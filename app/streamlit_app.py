import streamlit as st
from snowflake.snowpark.context import get_active_session
import json

session = get_active_session()

st.set_page_config(page_title="ReadinessOps", layout="wide")

st.markdown("""
<style>
    .block-container { padding-top: 2rem; }
    h1 { color: #1a2b4a; }
    h2, h3 { color: #2c3e6b; }
    .stMetric label { color: #4a5568; }
    .stMetric [data-testid="stMetricValue"] { color: #1a2b4a; }
</style>
""", unsafe_allow_html=True)

st.title("ReadinessOps")
st.caption("Enterprise AI Governance Operating Platform")

# -- Assessment Run Selector --
runs_df = session.sql("""
    SELECT r.RUN_ID, r.RUN_NAME, r.STATUS,
        (SELECT COUNT(*) FROM READINESS_GAPS g WHERE g.RUN_ID = r.RUN_ID AND g.SOURCE_PROPOSAL_ID IS NOT NULL) AS PUBLISHED_GAPS,
        (SELECT COUNT(*) FROM GOVERNANCE_AGENT_PROPOSAL p WHERE p.ASSESSMENT_RUN_ID = r.RUN_ID AND p.STATUS = 'REVIEW_REQUIRED') AS DRAFT_PROPOSALS
    FROM ASSESSMENT_RUNS r ORDER BY r.CREATED_AT DESC
""").to_pandas()

if runs_df.empty:
    st.warning("No assessment runs found.")
    st.stop()

run_options = {f"{row['RUN_ID']} — {row['RUN_NAME']} ({row['STATUS']})": row['RUN_ID'] for _, row in runs_df.iterrows()}
selected_label = st.selectbox("Assessment Run", options=list(run_options.keys()))
selected_run_id = run_options[selected_label]

selected_run = runs_df[runs_df['RUN_ID'] == selected_run_id].iloc[0]

# -- Summary Metrics --
col1, col2, col3, col4 = st.columns(4)
answers_count = session.sql(f"SELECT COUNT(*) AS N FROM ASSESSMENT_ANSWERS WHERE RUN_ID = '{selected_run_id}'").to_pandas()['N'][0]
col1.metric("Questions", int(answers_count))
col2.metric("Published Gaps", int(selected_run['PUBLISHED_GAPS']))
col3.metric("Draft Proposals", int(selected_run['DRAFT_PROPOSALS']))

latest_agent = session.sql(f"SELECT COALESCE((SELECT STATUS FROM GOVERNANCE_AGENT_RUN WHERE ASSESSMENT_RUN_ID = '{selected_run_id}' ORDER BY CREATED_AT DESC LIMIT 1), 'NONE') AS S").to_pandas()['S'][0]
col4.metric("Agent Status", latest_agent)

st.divider()

# ============================================================
# GOVERNANCE AGENT WORKSPACE
# ============================================================
st.header("Governance Agent Workspace")

# -- Standard Instruction --
st.markdown("**Standard Instruction** (applied to every review):")
st.info("Review the selected Assessment Run. Evaluate the sufficiency of available evidence, identify readiness gaps, assess the related governance and operational risks, and propose prioritized actions. Every proposal must be supported by the supplied Question, Answer, Evidence, and Rule context. Do not invent evidence.")

# -- Additional Instruction --
additional_instruction = st.text_area(
    "Additional instruction",
    placeholder="Optional. Add a business priority or time horizon. The standard governance review remains unchanged.",
    height=80
)

# -- Preview --
with st.expander("Preview: Assessment Context"):
    preview_df = session.sql(f"""
        SELECT q.QUESTION_ID, q.QUESTION_TEXT, a.ANSWER_STATUS,
            COALESCE(e.EVIDENCE_STATUS, 'MISSING') AS EVIDENCE_STATUS,
            q.EXPECTED_EVIDENCE AS RULE
        FROM ASSESSMENT_ANSWERS a
        JOIN READINESS_QUESTIONS q ON a.QUESTION_ID = q.QUESTION_ID
        LEFT JOIN EVIDENCE_ITEMS e ON a.RUN_ID = e.RUN_ID AND a.QUESTION_ID = e.QUESTION_ID
        WHERE a.RUN_ID = '{selected_run_id}'
        ORDER BY q.SORT_ORDER
    """).to_pandas()
    preview_display = preview_df.rename(columns={
        "QUESTION_ID": "ID", "QUESTION_TEXT": "Question",
        "ANSWER_STATUS": "Answer", "EVIDENCE_STATUS": "Evidence", "RULE": "Expected Evidence"
    })
    st.dataframe(preview_display, use_container_width=True)

# -- Run Button --
st.markdown("---")
st.markdown("**AI-generated results are saved as review drafts.** Dashboard and report results are not changed until approved proposals are published.")

if "gov_running" not in st.session_state:
    st.session_state.gov_running = False

run_btn = st.button("Run Full Governance Review", disabled=st.session_state.gov_running, type="primary")

if run_btn:
    st.session_state.gov_running = True
    with st.spinner("Running Governance Review via Cortex AI..."):
        try:
            add_instr = additional_instruction if additional_instruction.strip() else None
            if add_instr:
                result = session.sql(f"CALL SP_RUN_FULL_GOVERNANCE_REVIEW('{selected_run_id}', '{add_instr}')").collect()
            else:
                result = session.sql(f"CALL SP_RUN_FULL_GOVERNANCE_REVIEW('{selected_run_id}', NULL)").collect()
            result_json = json.loads(result[0][0])
            if result_json.get('status') == 'COMPLETED':
                st.success(f"Review complete: {result_json.get('gaps',0)} gaps, {result_json.get('risks',0)} risks, {result_json.get('actions',0)} actions generated as drafts.")
                st.markdown(f"Agent Run ID: `{result_json.get('agent_run_id')}`")
            else:
                st.error(f"Review failed: {result_json.get('error','Unknown error')}")
        except Exception as e:
            st.error(f"Error: {str(e)}")
        finally:
            st.session_state.gov_running = False

st.divider()

# ============================================================
# PROPOSAL REVIEW
# ============================================================
st.header("Proposal Review")

proposals_df = session.sql(f"""
    SELECT PROPOSAL_ID, PROPOSAL_TYPE, TITLE, DESCRIPTION, SEVERITY, PRIORITY, RATIONALE, STATUS, QUESTION_ID, RECOMMENDED_OWNER, RECOMMENDED_DUE_DATE
    FROM GOVERNANCE_AGENT_PROPOSAL
    WHERE ASSESSMENT_RUN_ID = '{selected_run_id}'
    ORDER BY PROPOSAL_TYPE, PRIORITY DESC
""").to_pandas()

if proposals_df.empty:
    st.info("No proposals for this run. Run a Full Governance Review to generate proposals.")
else:
    tab_gaps, tab_risks, tab_actions = st.tabs(["Gap Proposals", "Risk Proposals", "Action Proposals"])

    for tab, ptype in [(tab_gaps, 'GAP'), (tab_risks, 'RISK'), (tab_actions, 'ACTION')]:
        with tab:
            type_df = proposals_df[proposals_df['PROPOSAL_TYPE'] == ptype]
            if type_df.empty:
                st.info(f"No {ptype.lower()} proposals.")
                continue

            for _, row in type_df.iterrows():
                with st.container():
                    status_icon = {"REVIEW_REQUIRED": "🔶", "APPROVED": "✅", "REJECTED": "❌", "PUBLISHED": "📋"}.get(row['STATUS'], "⬜")
                    st.markdown(f"**{status_icon} {row['TITLE']}** — {row['SEVERITY']} (Priority: {row['PRIORITY']})")
                    st.markdown(f"_{row['DESCRIPTION']}_")

                    if row['RATIONALE']:
                        st.caption(f"Rationale: {row['RATIONALE']}")

                    if ptype == 'ACTION' and row['RECOMMENDED_OWNER']:
                        st.caption(f"Owner: {row['RECOMMENDED_OWNER']} | Due: {row['RECOMMENDED_DUE_DATE']} days")

                    # Source details
                    sources = session.sql(f"SELECT QUESTION_ID, ANSWER_TEXT, EVIDENCE_ITEM_ID, SOURCE_SUMMARY FROM GOVERNANCE_AGENT_PROPOSAL_SOURCE WHERE PROPOSAL_ID = '{row['PROPOSAL_ID']}'").to_pandas()
                    if not sources.empty:
                        with st.expander(f"Sources ({len(sources)})"):
                            for _, src in sources.iterrows():
                                st.text(src['SOURCE_SUMMARY'])

                    # Review actions
                    if row['STATUS'] == 'REVIEW_REQUIRED':
                        rcol1, rcol2, rcol3 = st.columns([2, 1, 1])
                        comment_key = f"comment_{row['PROPOSAL_ID']}"
                        with rcol1:
                            comment = st.text_input("Comment", key=comment_key, placeholder="Optional review comment")
                        with rcol2:
                            if st.button("Approve", key=f"approve_{row['PROPOSAL_ID']}"):
                                session.sql(f"CALL SP_REVIEW_AGENT_PROPOSAL('{row['PROPOSAL_ID']}', 'APPROVE', '{comment}')").collect()
                                st.rerun()
                        with rcol3:
                            if st.button("Reject", key=f"reject_{row['PROPOSAL_ID']}"):
                                session.sql(f"CALL SP_REVIEW_AGENT_PROPOSAL('{row['PROPOSAL_ID']}', 'REJECT', '{comment}')").collect()
                                st.rerun()

                    st.markdown("---")

st.divider()

# ============================================================
# PUBLISH
# ============================================================
st.header("Publish Approved Proposals")

approved_counts = session.sql(f"""
    SELECT PROPOSAL_TYPE, COUNT(*) AS N
    FROM GOVERNANCE_AGENT_PROPOSAL
    WHERE ASSESSMENT_RUN_ID = '{selected_run_id}' AND STATUS = 'APPROVED'
    GROUP BY PROPOSAL_TYPE
""").to_pandas()

if approved_counts.empty:
    st.info("No approved proposals to publish.")
else:
    pcol1, pcol2, pcol3 = st.columns(3)
    gap_approved = int(approved_counts[approved_counts['PROPOSAL_TYPE'] == 'GAP']['N'].sum()) if 'GAP' in approved_counts['PROPOSAL_TYPE'].values else 0
    risk_approved = int(approved_counts[approved_counts['PROPOSAL_TYPE'] == 'RISK']['N'].sum()) if 'RISK' in approved_counts['PROPOSAL_TYPE'].values else 0
    action_approved = int(approved_counts[approved_counts['PROPOSAL_TYPE'] == 'ACTION']['N'].sum()) if 'ACTION' in approved_counts['PROPOSAL_TYPE'].values else 0

    pcol1.metric("Approved Gaps", gap_approved)
    pcol2.metric("Approved Risks", risk_approved)
    pcol3.metric("Approved Actions", action_approved)

    confirm_publish = st.checkbox("I understand that approved proposals will become published governance records.")

    # Get latest agent run for this assessment
    latest_run_id = session.sql(f"SELECT AGENT_RUN_ID FROM GOVERNANCE_AGENT_RUN WHERE ASSESSMENT_RUN_ID = '{selected_run_id}' ORDER BY CREATED_AT DESC LIMIT 1").to_pandas()['AGENT_RUN_ID'][0]

    if st.button("Publish approved proposals", disabled=not confirm_publish, type="primary"):
        try:
            pub_result = session.sql(f"CALL SP_PUBLISH_AGENT_RUN('{latest_run_id}')").collect()
            pub_json = json.loads(pub_result[0][0])
            if pub_json.get('status') == 'OK':
                st.success(f"Published: {pub_json.get('published_gaps',0)} gaps, {pub_json.get('published_risks',0)} risks, {pub_json.get('published_actions',0)} actions")
            else:
                st.error(f"Publish failed: {pub_json.get('error','Unknown')}")
        except Exception as e:
            st.error(f"Error: {str(e)}")

st.divider()

# ============================================================
# AGENT RUN HISTORY
# ============================================================
st.header("Agent Run History")

history_df = session.sql(f"""
    SELECT AGENT_RUN_ID, ASSESSMENT_RUN_ID, STATUS, STARTED_AT, COMPLETED_AT,
        ADDITIONAL_INSTRUCTION, MODEL_NAME, SUMMARY, ERROR_MESSAGE
    FROM GOVERNANCE_AGENT_RUN
    WHERE ASSESSMENT_RUN_ID = '{selected_run_id}'
    ORDER BY CREATED_AT DESC
""").to_pandas()

if history_df.empty:
    st.info("No agent runs yet.")
else:
    history_display = history_df.rename(columns={
        "AGENT_RUN_ID": "Run ID", "STATUS": "Status", "STARTED_AT": "Started",
        "COMPLETED_AT": "Completed", "MODEL_NAME": "Model", "SUMMARY": "Summary",
        "ERROR_MESSAGE": "Error", "ADDITIONAL_INSTRUCTION": "Additional Instruction"
    })
    st.dataframe(history_display[["Run ID", "Status", "Started", "Completed", "Model", "Summary", "Additional Instruction", "Error"]], use_container_width=True)

    # Select a previous run to view its proposals
    run_ids = history_df['AGENT_RUN_ID'].tolist()
    if len(run_ids) > 1:
        selected_hist_run = st.selectbox("View proposals from a previous run:", run_ids)
        if selected_hist_run:
            hist_proposals = session.sql(f"SELECT PROPOSAL_TYPE, TITLE, SEVERITY, PRIORITY, STATUS FROM GOVERNANCE_AGENT_PROPOSAL WHERE AGENT_RUN_ID = '{selected_hist_run}' ORDER BY PROPOSAL_TYPE, PRIORITY DESC").to_pandas()
            if not hist_proposals.empty:
                st.dataframe(hist_proposals.rename(columns={"PROPOSAL_TYPE": "Type", "TITLE": "Title", "SEVERITY": "Severity", "PRIORITY": "Priority", "STATUS": "Status"}), use_container_width=True)

# -- Footer --
st.divider()
st.markdown("""
<div style="color: #6b7280; font-size: 0.85rem;">
<strong>Governance Notice</strong><br>
All data shown is synthetic and created for demonstration purposes.
AI-generated recommendations are saved as drafts requiring human review.
Only approved and published records appear in Dashboard results.
Cortex AI model availability (mistral-large2) varies by Snowflake region.
</div>
""", unsafe_allow_html=True)
