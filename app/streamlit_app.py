import streamlit as st
from snowflake.snowpark.context import get_active_session

# -- Session --
session = get_active_session()

# -- Page config --
st.set_page_config(page_title="ReadinessOps", layout="wide")

# -- Styling --
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
st.caption("AI-Powered Readiness Gap Agent — Snowflake Cortex")

# -- Assessment Run Selector --
runs_df = session.sql("SELECT RUN_ID, RUN_NAME, ORGANIZATION_NAME, STATUS FROM ASSESSMENT_RUNS ORDER BY CREATED_AT DESC").to_pandas()

if runs_df.empty:
    st.warning("No assessment runs found. Run sql/02_seed_data.sql to load sample data.")
    st.stop()

run_options = {f"{row['RUN_ID']} — {row['RUN_NAME']}": row['RUN_ID'] for _, row in runs_df.iterrows()}
selected_label = st.selectbox("Assessment Run", options=list(run_options.keys()))
selected_run_id = run_options[selected_label]

# -- Summary Metrics --
answers_count = session.sql(f"SELECT COUNT(*) AS N FROM ASSESSMENT_ANSWERS WHERE RUN_ID = '{selected_run_id}'").to_pandas()['N'][0]
gaps_count = session.sql(f"SELECT COUNT(*) AS N FROM READINESS_GAPS WHERE RUN_ID = '{selected_run_id}'").to_pandas()['N'][0]
actions_count = session.sql(f"SELECT COUNT(*) AS N FROM RECOMMENDED_ACTIONS WHERE RUN_ID = '{selected_run_id}'").to_pandas()['N'][0]
latest_status = session.sql(f"SELECT COALESCE((SELECT AGENT_STEP FROM AGENT_RUN_HISTORY WHERE RUN_ID = '{selected_run_id}' AND AGENT_RUN_ID LIKE 'AR_%' ORDER BY CREATED_AT DESC LIMIT 1), 'NO RUNS') AS S").to_pandas()['S'][0]

col1, col2, col3, col4 = st.columns(4)
col1.metric("Questions Answered", int(answers_count))
col2.metric("Open Gaps", int(gaps_count))
col3.metric("Actions", int(actions_count))
col4.metric("Agent Status", latest_status)

st.divider()

# -- Run Agent Button --
st.subheader("Run Agent")

with st.container():
    st.markdown(f"Execute `SP_RUN_READINESS_AGENT('{selected_run_id}')` to analyze gaps using Cortex AI.")
    st.warning("This will replace any previous AI-generated results for this run.")

    if "agent_running" not in st.session_state:
        st.session_state.agent_running = False

    run_col1, run_col2 = st.columns([1, 4])
    with run_col1:
        run_button = st.button(
            "Run Agent",
            disabled=st.session_state.agent_running,
            type="primary"
        )

    if run_button:
        st.session_state.agent_running = True
        with st.spinner("Agent running... calling Cortex AI"):
            try:
                result = session.sql(f"CALL SP_RUN_READINESS_AGENT('{selected_run_id}')").collect()
                result_msg = result[0][0]
                if result_msg.startswith("FAILED"):
                    st.error(f"Agent failed: {result_msg}")
                else:
                    st.success(result_msg)
            except Exception as e:
                st.error(f"Error: {str(e)}")
            finally:
                st.session_state.agent_running = False

st.divider()

# -- Gap Board --
st.subheader("Gap Board")

gaps_df = session.sql(f"""
    SELECT
        d.DOMAIN_NAME,
        g.GAP_TITLE,
        g.SEVERITY,
        g.PRIORITY_SCORE,
        g.GAP_DESCRIPTION AS RATIONALE,
        CASE WHEN g.GAP_ID LIKE 'AR_%' THEN 'AI Generated' ELSE 'Baseline' END AS SOURCE
    FROM READINESS_GAPS g
    JOIN READINESS_QUESTIONS q ON g.QUESTION_ID = q.QUESTION_ID
    JOIN READINESS_DOMAINS d ON q.DOMAIN_ID = d.DOMAIN_ID
    WHERE g.RUN_ID = '{selected_run_id}'
    ORDER BY g.PRIORITY_SCORE DESC
""").to_pandas()

if gaps_df.empty:
    st.info("No gaps found for this run. Run the agent to generate gaps.")
else:
    gaps_display = gaps_df.rename(columns={
        "DOMAIN_NAME": "Domain",
        "GAP_TITLE": "Gap",
        "SEVERITY": "Severity",
        "PRIORITY_SCORE": "Priority",
        "RATIONALE": "Rationale",
        "SOURCE": "Source",
    })
    st.dataframe(gaps_display, use_container_width=True)

st.divider()

# -- Recommended Actions --
st.subheader("Recommended Actions")

actions_df = session.sql(f"""
    SELECT
        act.ACTION_TITLE,
        g.PRIORITY_SCORE,
        act.OWNER_NAME AS OWNER_ROLE,
        act.DUE_IN_DAYS AS TARGET_DAYS,
        g.GAP_TITLE AS RELATED_GAP,
        act.ACTION_STATUS AS STATUS
    FROM RECOMMENDED_ACTIONS act
    JOIN READINESS_GAPS g ON act.GAP_ID = g.GAP_ID AND act.RUN_ID = g.RUN_ID
    WHERE act.RUN_ID = '{selected_run_id}'
    ORDER BY g.PRIORITY_SCORE DESC
""").to_pandas()

if actions_df.empty:
    st.info("No actions found for this run.")
else:
    actions_display = actions_df.rename(columns={
        "ACTION_TITLE": "Action",
        "PRIORITY_SCORE": "Priority",
        "OWNER_ROLE": "Owner",
        "TARGET_DAYS": "Due (days)",
        "RELATED_GAP": "Related Gap",
        "STATUS": "Status",
    })
    st.dataframe(actions_display, use_container_width=True)

st.divider()

# -- Agent Run History --
st.subheader("Agent Run History")

history_df = session.sql(f"""
    SELECT
        AGENT_STEP AS STEP,
        CASE
            WHEN AGENT_STEP = 'FAILED' THEN 'FAILED'
            ELSE 'OK'
        END AS STATUS,
        CREATED_AT AS TIMESTAMP,
        CASE
            WHEN AGENT_STEP = 'FAILED' THEN OUTPUT_SUMMARY
            ELSE NULL
        END AS FAILURE_MESSAGE
    FROM AGENT_RUN_HISTORY
    WHERE RUN_ID = '{selected_run_id}' AND AGENT_RUN_ID LIKE 'AR_%'
    ORDER BY CREATED_AT ASC
""").to_pandas()

if history_df.empty:
    st.info("No agent execution history. Run the agent to generate history.")
else:
    history_display = history_df.rename(columns={
        "STEP": "Step",
        "STATUS": "Status",
        "TIMESTAMP": "Timestamp",
        "FAILURE_MESSAGE": "Failure Message",
    })
    st.dataframe(history_display, use_container_width=True)

# -- Footer --
st.divider()
st.markdown("""
<div style="color: #6b7280; font-size: 0.85rem;">
<strong>Disclaimer</strong><br>
All data shown is synthetic and created for demonstration purposes.
AI-generated recommendations require human review before adoption.
Cortex AI model availability (mistral-large2) varies by Snowflake region.
</div>
""", unsafe_allow_html=True)
