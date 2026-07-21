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
        (SELECT COUNT(*)
         FROM READINESS_GAPS g
         WHERE g.RUN_ID = r.RUN_ID
           AND g.SOURCE_PROPOSAL_ID IS NOT NULL) AS PUBLISHED_GAPS
    FROM ASSESSMENT_RUNS r
    ORDER BY r.CREATED_AT DESC
""").to_pandas()

if runs_df.empty:
    st.warning("No assessment runs found.")
    st.stop()

run_options = {
    f"{row['RUN_ID']} - {row['RUN_NAME']} ({row['STATUS']})": row['RUN_ID']
    for _, row in runs_df.iterrows()
}
selected_label = st.selectbox("Assessment Run", options=list(run_options.keys()))
selected_run_id = run_options[selected_label]
selected_run = runs_df[runs_df["RUN_ID"] == selected_run_id].iloc[0]

safe_selected_run_id = selected_run_id.replace("'", "''")

latest_agent_df = session.sql(f"""
    SELECT
        AGENT_RUN_ID,
        STATUS,
        STARTED_AT,
        COMPLETED_AT,
        COALESCE(ADDITIONAL_INSTRUCTION, '') AS ADDITIONAL_INSTRUCTION,
        COALESCE(MODEL_NAME, '') AS MODEL_NAME,
        COALESCE(SUMMARY, '') AS SUMMARY,
        COALESCE(ERROR_MESSAGE, '') AS ERROR_MESSAGE
    FROM GOVERNANCE_AGENT_RUN
    WHERE ASSESSMENT_RUN_ID = '{safe_selected_run_id}'
    ORDER BY CREATED_AT DESC
    LIMIT 1
""").to_pandas()

if latest_agent_df.empty:
    latest_agent_run_id = None
    latest_agent_status = "NONE"
    latest_agent_completed_at = None
    latest_agent_instruction = ""
    latest_agent_model = ""
    latest_agent_summary = ""
    latest_agent_error = ""
    draft_proposals = 0
else:
    latest_agent_row = latest_agent_df.iloc[0]
    latest_agent_run_id = str(latest_agent_row["AGENT_RUN_ID"])
    latest_agent_status = str(latest_agent_row["STATUS"])
    latest_agent_completed_at = latest_agent_row["COMPLETED_AT"]
    latest_agent_instruction = str(latest_agent_row["ADDITIONAL_INSTRUCTION"])
    latest_agent_model = str(latest_agent_row["MODEL_NAME"])
    latest_agent_summary = str(latest_agent_row["SUMMARY"])
    latest_agent_error = str(latest_agent_row["ERROR_MESSAGE"])

    safe_latest_agent_run_id = latest_agent_run_id.replace("'", "''")

    draft_proposals = int(session.sql(f"""
        SELECT COUNT(*) AS N
        FROM GOVERNANCE_AGENT_PROPOSAL
        WHERE AGENT_RUN_ID = '{safe_latest_agent_run_id}'
          AND STATUS = 'REVIEW_REQUIRED'
    """).to_pandas()["N"][0])

# -- Summary Metrics --
col1, col2, col3, col4 = st.columns(4)

answers_count = int(session.sql(f"""
    SELECT COUNT(*) AS N
    FROM ASSESSMENT_ANSWERS
    WHERE RUN_ID = '{safe_selected_run_id}'
""").to_pandas()["N"][0])

col1.metric("Questions", answers_count)
col2.metric("Published Gaps", int(selected_run["PUBLISHED_GAPS"]))
col3.metric("Latest Draft Proposals", draft_proposals)
col4.metric("Agent Status", latest_agent_status)
st.divider()

# ============================================================
# GOVERNANCE AGENT WORKSPACE
# ============================================================
st.header("Governance Agent Workspace")

if latest_agent_run_id:
    st.markdown("#### Latest Governance Review")

    meta1, meta2, meta3 = st.columns(3)
    meta1.metric("Status", latest_agent_status)
    meta2.metric("Model", latest_agent_model or "-")

    completed_text = (
        str(latest_agent_completed_at)[:19]
        if latest_agent_completed_at is not None
        else "-"
    )
    meta3.metric("Completed", completed_text)

    st.caption(f"Agent Run ID: `{latest_agent_run_id}`")

    if latest_agent_instruction:
        st.info(f"Instruction used: {latest_agent_instruction}")

    if latest_agent_summary:
        st.success(f"Generated result: {latest_agent_summary}")

    if latest_agent_error:
        st.error(f"Latest run error: {latest_agent_error}")
else:
    st.info("No governance review has been run for this Assessment Run.")

last_review_result = st.session_state.get("last_review_result")

if (
    last_review_result
    and last_review_result.get("assessment_run_id") == selected_run_id
    and last_review_result.get("agent_run_id") == latest_agent_run_id
):
    st.success(last_review_result["message"])

# -- Standard Instruction --
st.markdown("**Standard Instruction** (applied to every review):")
st.info("Review the selected Assessment Run. Evaluate the sufficiency of available evidence, identify readiness gaps, assess the related governance and operational risks, and propose prioritized actions. Every proposal must be supported by the supplied Question, Answer, Evidence, and Rule context. Do not invent evidence.")

# -- Additional Instruction --
additional_instruction = st.text_area(
    "Additional instruction",
    placeholder="Optional. Add a business priority or time horizon. The standard governance review remains unchanged.",
    height=80,
    key="additional_instruction",
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

run_btn = st.button(
    "Run Full Governance Review",
    disabled=st.session_state.gov_running,
    type="primary",
)

if run_btn:
    st.session_state.gov_running = True

    with st.spinner("Running Governance Review via Cortex AI..."):
        try:
            add_instr = additional_instruction.strip() or None

            if add_instr:
                safe_add_instr = add_instr.replace("'", "''")
                result = session.sql(
                    f"CALL SP_RUN_FULL_GOVERNANCE_REVIEW('{safe_selected_run_id}', '{safe_add_instr}')"
                ).collect()
            else:
                result = session.sql(
                    f"CALL SP_RUN_FULL_GOVERNANCE_REVIEW('{safe_selected_run_id}', NULL)"
                ).collect()

            result_json = json.loads(result[0][0])

            if result_json.get("status") == "COMPLETED":
                agent_run_id = result_json.get("agent_run_id")

                message = (
                    "New governance review completed: "
                    f"{result_json.get('gaps', 0)} gaps, "
                    f"{result_json.get('risks', 0)} risks, "
                    f"{result_json.get('actions', 0)} actions generated as drafts. "
                    f"Agent Run ID: {agent_run_id}"
                )

                st.session_state["last_review_result"] = {
                    "assessment_run_id": selected_run_id,
                    "agent_run_id": agent_run_id,
                    "message": message,
                }

                st.session_state.gov_running = False
                st.rerun()
            else:
                st.error(
                    f"Review failed: {result_json.get('error', 'Unknown error')}"
                )

        except Exception as e:
            st.error(f"Error: {str(e)}")

        finally:
            st.session_state.gov_running = False

st.divider()
# ============================================================
# PROPOSAL REVIEW
# ============================================================
st.header("Proposal Review")

if latest_agent_run_id:
    st.info(
        f"Displaying {draft_proposals} draft proposals generated by the latest completed review."
    )
    with st.expander("Technical details"):
        st.code(latest_agent_run_id)
    proposal_filter = f"AGENT_RUN_ID = '{safe_latest_agent_run_id}'"
else:
    proposal_filter = "1 = 0"

proposals_df = session.sql(f"""
    SELECT
        PROPOSAL_ID,
        AGENT_RUN_ID,
        PROPOSAL_TYPE,
        TITLE,
        DESCRIPTION,
        SEVERITY,
        PRIORITY,
        RATIONALE,
        STATUS,
        QUESTION_ID,
        RECOMMENDED_OWNER,
        RECOMMENDED_DUE_DATE
    FROM GOVERNANCE_AGENT_PROPOSAL
    WHERE {proposal_filter}
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
    WHERE AGENT_RUN_ID = '{safe_latest_agent_run_id if latest_agent_run_id else ""}'
      AND STATUS = 'APPROVED'
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

    latest_run_id = latest_agent_run_id

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
