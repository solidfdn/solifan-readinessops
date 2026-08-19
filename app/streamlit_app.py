import html
import json
from datetime import datetime

import pandas as pd
import streamlit as st
from snowflake.snowpark.context import get_active_session
import importlib
import value_control_plane
value_control_plane = importlib.reload(value_control_plane)
render_value_control_plane = value_control_plane.render_value_control_plane


# ============================================================
# Page and helpers
# ============================================================
st.set_page_config(
    page_title="ReadinessOps Governance Review",
    page_icon="✓",
    layout="wide",
)


# ============================================================
# Theme toggle (dark/light)
# ============================================================
if "app_theme" not in st.session_state:
    st.session_state.app_theme = "dark"

_tcol1, _tcol2 = st.columns([10, 1])
with _tcol2:
    _icon = "\u2600\ufe0f" if st.session_state.app_theme == "dark" else "\U0001f319"
    if st.button(_icon, key="theme_toggle", help="Light / Dark"):
        st.session_state.app_theme = (
            "light" if st.session_state.app_theme == "dark" else "dark"
        )
        if hasattr(st, "rerun"):
            st.rerun()
        else:
            st.experimental_rerun()

_is_dark = st.session_state.app_theme == "dark"

session = get_active_session()


def rerun_app():
    if hasattr(st, "rerun"):
        st.rerun()
    else:
        st.experimental_rerun()



def show_dataframe(dataframe):
    """Render every list with a consistent one-based row number."""
    display_df = dataframe.copy()
    display_df.index = range(1, len(display_df) + 1)
    display_df.index.name = "No."
    st.dataframe(
        display_df,
        use_container_width=True,
    )


def sql_literal(value):
    if value is None:
        return "NULL"
    return "'" + str(value).replace("'", "''") + "'"


def text(value, fallback="—"):
    if value is None:
        return fallback
    rendered = str(value).strip()
    if not rendered or rendered.lower() in {"nan", "none", "null", "nat"}:
        return fallback
    return rendered


def escaped(value, fallback="—"):
    return html.escape(text(value, fallback))


def integer(value, fallback=0):
    try:
        return int(value)
    except (TypeError, ValueError):
        return fallback


def timestamp_text(value):
    if value is None:
        return "—"
    if isinstance(value, datetime):
        return value.strftime("%Y-%m-%d %H:%M")
    return text(value)[:16]


def query_df(sql):
    return session.sql(sql).to_pandas()


def call_json(sql):
    result = session.sql(sql).collect()
    if not result:
        return {"status": "FAILED", "error": "Procedure returned no result."}
    raw = result[0][0]
    if isinstance(raw, dict):
        return raw
    try:
        return json.loads(raw)
    except (TypeError, json.JSONDecodeError):
        return {"status": "FAILED", "error": f"Unexpected procedure response: {raw}"}


def badge(label, tone="neutral"):
    css_class = {
        "high": "badge badge-high",
        "medium": "badge badge-medium",
        "low": "badge badge-low",
        "success": "badge badge-success",
        "warning": "badge badge-warning",
        "danger": "badge badge-danger",
        "info": "badge badge-info",
        "neutral": "badge badge-neutral",
    }.get(tone, "badge badge-neutral")
    return f'<span class="{css_class}">{html.escape(str(label))}</span>'


def severity_tone(value):
    severity = text(value, "").upper()
    return {"HIGH": "high", "MEDIUM": "medium", "LOW": "low"}.get(
        severity, "neutral"
    )


def status_tone(value):
    status = text(value, "").upper()
    return {
        "REVIEW_REQUIRED": "warning",
        "APPROVED": "success",
        "REJECTED": "danger",
        "PUBLISHED": "info",
    }.get(status, "neutral")


def status_label(value):
    return {
        "REVIEW_REQUIRED": "Needs human decision",
        "APPROVED": "Approved — ready to publish",
        "REJECTED": "Rejected",
        "PUBLISHED": "Published",
    }.get(text(value, "").upper(), text(value))


def evidence_needs_attention(value):
    status = text(value, "MISSING").upper()
    verified = {
        "VERIFIED",
        "VALIDATED",
        "APPROVED",
        "ACCEPTED",
        "COMPLETE",
        "COMPLETED",
    }
    return status not in verified


# Theme-aware CSS
# ============================================================
_dark_root = (
    ":root {"
    "  --ink: #e8ecf0;"
    "  --muted: #a0aec0;"
    "  --line: #3a4a5e;"
    "  --soft: #1e2a3a;"
    "  --card-bg: #1a2736;"
    "  --blue: #5b9bf5;"
    "  --navy: #a8c8f0;"
    "  --green: #4fd1c5;"
    "  --amber: #f6c144;"
    "  --red: #fc8181;"
    "}"
)

_light_root = (
    ":root {"
    "  --ink: #14213d;"
    "  --muted: #667085;"
    "  --line: #dfe5ee;"
    "  --soft: #f6f8fc;"
    "  --card-bg: #ffffff;"
    "  --blue: #2457c5;"
    "  --navy: #182a4d;"
    "  --green: #18794e;"
    "  --amber: #9a6700;"
    "  --red: #b42318;"
    "}"
)

_root_vars = _dark_root if _is_dark else _light_root

_badge_css = (
    ".badge-high, .badge-danger {background:#3b1c1c; color:var(--red); border:1px solid #5c2a2a;}"
    ".badge-medium, .badge-warning {background:#3b3315; color:var(--amber); border:1px solid #5c4d1a;}"
    ".badge-low, .badge-success {background:#1a3a2a; color:var(--green); border:1px solid #2a5c40;}"
    ".badge-info {background:#1a2744; color:#8ab4f8; border:1px solid #2a3d66;}"
    ".badge-neutral {background:#1e2a3a; color:#a0aec0; border:1px solid #3a4a5e;}"
) if _is_dark else (
    ".badge-high, .badge-danger {background:#fff1f0; color:var(--red); border:1px solid #fecdca;}"
    ".badge-medium, .badge-warning {background:#fff8e6; color:var(--amber); border:1px solid #fedf89;}"
    ".badge-low, .badge-success {background:#ecfdf3; color:var(--green); border:1px solid #abefc6;}"
    ".badge-info {background:#eef4ff; color:#3538cd; border:1px solid #c7d7fe;}"
    ".badge-neutral {background:#f2f4f7; color:#475467; border:1px solid #e4e7ec;}"
)

_layout_css = """
.block-container {padding-top: 1.4rem; padding-bottom: 3rem; max-width: 1500px;}
h1, h2, h3 {color: var(--ink); letter-spacing: -0.02em;}
h1 {margin-bottom: 0.2rem;}
[data-testid="stMetric"] {
  background: var(--card-bg);
  border: 1px solid var(--line);
  border-radius: 12px;
  padding: 0.9rem 1rem;
}
[data-testid="stMetricLabel"] {color: var(--muted);}
[data-testid="stMetricValue"] {color: var(--ink);}
.workflow {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  gap: 10px;
  margin: 0.8rem 0 1.2rem 0;
}
.workflow-step {
  border: 1px solid var(--line);
  border-radius: 12px;
  padding: 0.85rem 1rem;
  background: var(--card-bg);
}
.workflow-step strong {display:block; color: var(--ink); margin-bottom: 0.2rem;}
.workflow-step span {color: var(--muted); font-size: 0.88rem;}
.section-note {
  border-left: 4px solid var(--blue);
  background: var(--soft);
  padding: 0.8rem 1rem;
  border-radius: 0 10px 10px 0;
  color: var(--ink);
  margin: 0.35rem 0 1rem 0;
}
.proposal-card {
  border: 1px solid var(--line);
  border-radius: 14px;
  background: var(--card-bg);
  padding: 1.05rem 1.1rem 0.8rem 1.1rem;
  margin: 0.65rem 0 0.25rem 0;
}
.proposal-title {font-size: 1.08rem; font-weight: 700; color: var(--ink); margin: 0.35rem 0;}
.proposal-copy {color: var(--muted); line-height: 1.55; margin: 0.35rem 0;}
.context-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 10px;
  margin-top: 0.6rem;
}
.context-box {
  background: var(--soft);
  border: 1px solid var(--line);
  border-radius: 10px;
  padding: 0.7rem 0.8rem;
}
.context-box b {display:block; color: var(--muted); font-size: 0.78rem; text-transform: uppercase; letter-spacing: .04em; margin-bottom: .25rem;}
.context-box span {color: var(--ink); line-height: 1.45;}
.badge {display:inline-block; padding: .2rem .48rem; border-radius: 999px; font-size: .76rem; font-weight: 700; margin-right: .3rem;}
.published-card {
  border: 1px solid var(--line);
  border-radius: 12px;
  padding: .85rem 1rem;
  margin: .45rem 0;
  background: var(--card-bg);
}
.small-muted {color: var(--muted); font-size: .84rem;}
.audit-row {border-bottom:1px solid var(--line); padding:.65rem 0;}
@media (max-width: 900px) {
  .workflow, .context-grid {grid-template-columns: 1fr;}
}
"""

st.markdown(
    "<style>" + _root_vars + _layout_css + _badge_css + "</style>",
    unsafe_allow_html=True,
)


# ============================================================
# Load the governed assessment context
# ============================================================
try:
    assessment_context_df = query_df(
        """
        WITH case_catalog AS (
            SELECT
                case_record.CASE_ID,
                current_revision.REVISION_NO AS CURRENT_REVISION_NO,
                current_revision.STATUS AS CURRENT_REVISION_STATUS,
                current_run.RUN_ID AS CURRENT_RUN_ID,
                current_run.RUN_NAME AS CURRENT_RUN_NAME,
                current_run.ORGANIZATION_NAME AS CURRENT_ORGANIZATION_NAME,
                current_run.CREATED_AT AS CURRENT_CREATED_AT,
                draft_revision.REVISION_NO AS DRAFT_REVISION_NO,
                draft_revision.STATUS AS DRAFT_REVISION_STATUS,
                draft_run.RUN_ID AS DRAFT_RUN_ID,
                draft_run.RUN_NAME AS DRAFT_RUN_NAME,
                draft_run.ORGANIZATION_NAME AS DRAFT_ORGANIZATION_NAME,
                draft_run.STATUS AS DRAFT_RUN_STATUS,
                draft_run.CREATED_AT AS DRAFT_CREATED_AT
            FROM ASSESSMENT_CASE case_record
            LEFT JOIN ASSESSMENT_REVISION current_revision
              ON current_revision.REVISION_ID = case_record.CURRENT_REVISION_ID
            LEFT JOIN ASSESSMENT_RUNS current_run
              ON current_run.RUN_ID = current_revision.RUN_ID
            LEFT JOIN ASSESSMENT_REVISION draft_revision
              ON draft_revision.REVISION_ID = case_record.ACTIVE_DRAFT_REVISION_ID
            LEFT JOIN ASSESSMENT_RUNS draft_run
              ON draft_run.RUN_ID = draft_revision.RUN_ID
        )
        SELECT
            CASE_ID,
            COALESCE(DRAFT_RUN_ID, CURRENT_RUN_ID) AS SELECTED_RUN_ID,
            REGEXP_REPLACE(
                COALESCE(DRAFT_RUN_NAME, CURRENT_RUN_NAME),
                ' - Revision [0-9]+$',
                ''
            ) AS ASSESSMENT_NAME,
            COALESCE(
                DRAFT_ORGANIZATION_NAME,
                CURRENT_ORGANIZATION_NAME
            ) AS ORGANIZATION_NAME,
            CURRENT_REVISION_NO,
            CURRENT_REVISION_STATUS,
            CURRENT_RUN_ID,
            DRAFT_REVISION_NO,
            DRAFT_REVISION_STATUS,
            DRAFT_RUN_STATUS,
            DRAFT_RUN_ID
        FROM case_catalog
        WHERE COALESCE(DRAFT_RUN_ID, CURRENT_RUN_ID) IS NOT NULL
        ORDER BY
            IFF(DRAFT_RUN_ID IS NOT NULL, 1, 2),
            COALESCE(DRAFT_CREATED_AT, CURRENT_CREATED_AT) DESC
        LIMIT 1
        """
    )
except Exception as exc:
    st.error(f"Could not load the governed assessment: {exc}")
    st.stop()

if assessment_context_df.empty:
    st.warning("No governed assessment is available.")
    st.stop()

assessment_context = assessment_context_df.iloc[0]
selected_run_id = text(assessment_context["SELECTED_RUN_ID"])
run_id_sql = sql_literal(selected_run_id)

assessment_name = text(
    assessment_context["ASSESSMENT_NAME"],
    "Governed AI assessment",
)
organization_name = text(
    assessment_context["ORGANIZATION_NAME"],
    "Organization not set",
)
current_revision_no = assessment_context.get("CURRENT_REVISION_NO")
draft_revision_no = assessment_context.get("DRAFT_REVISION_NO")
has_active_draft = (
    draft_revision_no is not None
    and pd.notna(draft_revision_no)
    and text(assessment_context.get("DRAFT_RUN_ID"), "") != ""
)

st.caption("Assessment")
st.markdown(f"**{assessment_name}**")
st.caption(f"Organization: {organization_name}")

if has_active_draft:
    st.info(
        f"Reviewing Revision {integer(draft_revision_no)} (Draft). "
        f"Revision {integer(current_revision_no)} remains the published "
        "current state."
    )
else:
    st.success(
        f"Revision {integer(current_revision_no)} is the published current "
        "state. No Draft Revision is active."
    )

try:
    latest_attempt_df = query_df(
        f"""
        SELECT AGENT_RUN_ID, STATUS, STARTED_AT, COMPLETED_AT,
               COALESCE(ADDITIONAL_INSTRUCTION, '') AS ADDITIONAL_INSTRUCTION,
               COALESCE(MODEL_NAME, '') AS MODEL_NAME,
               COALESCE(SUMMARY, '') AS SUMMARY,
               COALESCE(ERROR_MESSAGE, '') AS ERROR_MESSAGE,
               CREATED_AT
        FROM GOVERNANCE_AGENT_RUN
        WHERE ASSESSMENT_RUN_ID = {run_id_sql}
        ORDER BY CREATED_AT DESC
        LIMIT 1
        """
    )
    latest_completed_df = query_df(
        f"""
        SELECT AGENT_RUN_ID, STATUS, STARTED_AT, COMPLETED_AT,
               COALESCE(ADDITIONAL_INSTRUCTION, '') AS ADDITIONAL_INSTRUCTION,
               COALESCE(MODEL_NAME, '') AS MODEL_NAME,
               COALESCE(SUMMARY, '') AS SUMMARY,
               COALESCE(ERROR_MESSAGE, '') AS ERROR_MESSAGE,
               CREATED_AT
        FROM GOVERNANCE_AGENT_RUN
        WHERE ASSESSMENT_RUN_ID = {run_id_sql}
          AND STATUS = 'COMPLETED'
        ORDER BY CREATED_AT DESC
        LIMIT 1
        """
    )
except Exception as exc:
    st.error(f"Could not load governance review state: {exc}")
    st.stop()

latest_attempt = latest_attempt_df.iloc[0] if not latest_attempt_df.empty else None
latest_completed = latest_completed_df.iloc[0] if not latest_completed_df.empty else None
latest_agent_run_id = (
    text(latest_completed["AGENT_RUN_ID"], "") if latest_completed is not None else ""
)
agent_run_sql = sql_literal(latest_agent_run_id) if latest_agent_run_id else "NULL"

try:
    evidence_df = query_df(
        f"""
        SELECT
            q.QUESTION_ID,
            d.DOMAIN_NAME,
            q.QUESTION_TEXT,
            q.EXPECTED_EVIDENCE,
            a.ANSWER_STATUS,
            COALESCE(a.ANSWER_TEXT, '') AS ANSWER_TEXT,
            COALESCE(e.EVIDENCE_TITLE, '') AS EVIDENCE_TITLE,
            COALESCE(e.EVIDENCE_TEXT, '') AS EVIDENCE_TEXT,
            COALESCE(e.EVIDENCE_STATUS, 'MISSING') AS EVIDENCE_STATUS,
            q.SORT_ORDER
        FROM ASSESSMENT_ANSWERS a
        JOIN READINESS_QUESTIONS q
          ON a.QUESTION_ID = q.QUESTION_ID
        JOIN READINESS_DOMAINS d
          ON q.DOMAIN_ID = d.DOMAIN_ID
        LEFT JOIN EVIDENCE_ITEMS e
          ON a.RUN_ID = e.RUN_ID
         AND a.QUESTION_ID = e.QUESTION_ID
        WHERE a.RUN_ID = {run_id_sql}
        QUALIFY ROW_NUMBER() OVER (
            PARTITION BY a.RUN_ID, a.QUESTION_ID
            ORDER BY e.EVIDENCE_ID DESC NULLS LAST
        ) = 1
        ORDER BY q.SORT_ORDER
        """
    )
except Exception as exc:
    st.error(f"Could not load evidence context: {exc}")
    st.stop()

if latest_agent_run_id:
    try:
        proposals_df = query_df(
            f"""
            SELECT
                p.PROPOSAL_ID,
                p.AGENT_RUN_ID,
                p.PROPOSAL_TYPE,
                p.TITLE,
                p.DESCRIPTION,
                p.SEVERITY,
                p.PRIORITY,
                p.RATIONALE,
                p.STATUS,
                p.QUESTION_ID,
                p.REVIEW_COMMENT,
                p.REVIEWED_BY,
                p.REVIEWED_AT,
                p.RECOMMENDED_OWNER,
                p.RECOMMENDED_DUE_DATE,
                p.PUBLISHED_ENTITY_ID,
                q.QUESTION_TEXT,
                q.EXPECTED_EVIDENCE,
                d.DOMAIN_NAME,
                a.ANSWER_STATUS,
                COALESCE(a.ANSWER_TEXT, '') AS ANSWER_TEXT,
                COALESCE(e.EVIDENCE_TITLE, '') AS EVIDENCE_TITLE,
                COALESCE(e.EVIDENCE_TEXT, '') AS EVIDENCE_TEXT,
                COALESCE(e.EVIDENCE_STATUS, 'MISSING') AS EVIDENCE_STATUS,
                COALESCE(src.SOURCE_SUMMARY, '') AS SOURCE_SUMMARY,
                COALESCE(src.RULE_ID, '') AS RULE_ID,
                COALESCE(src.RULE_VERSION, '') AS RULE_VERSION
            FROM GOVERNANCE_AGENT_PROPOSAL p
            LEFT JOIN READINESS_QUESTIONS q
              ON p.QUESTION_ID = q.QUESTION_ID
            LEFT JOIN READINESS_DOMAINS d
              ON q.DOMAIN_ID = d.DOMAIN_ID
            LEFT JOIN ASSESSMENT_ANSWERS a
              ON p.ASSESSMENT_RUN_ID = a.RUN_ID
             AND p.QUESTION_ID = a.QUESTION_ID
            LEFT JOIN (
                SELECT RUN_ID, QUESTION_ID, EVIDENCE_TITLE, EVIDENCE_TEXT, EVIDENCE_STATUS
                FROM EVIDENCE_ITEMS
                QUALIFY ROW_NUMBER() OVER (
                    PARTITION BY RUN_ID, QUESTION_ID
                    ORDER BY EVIDENCE_ID DESC NULLS LAST
                ) = 1
            ) e
              ON p.ASSESSMENT_RUN_ID = e.RUN_ID
             AND p.QUESTION_ID = e.QUESTION_ID
            LEFT JOIN (
                SELECT
                    PROPOSAL_ID,
                    LISTAGG(SOURCE_SUMMARY, '\n') WITHIN GROUP (ORDER BY CREATED_AT) AS SOURCE_SUMMARY,
                    MAX(RULE_ID) AS RULE_ID,
                    MAX(RULE_VERSION) AS RULE_VERSION
                FROM GOVERNANCE_AGENT_PROPOSAL_SOURCE
                GROUP BY PROPOSAL_ID
            ) src
              ON p.PROPOSAL_ID = src.PROPOSAL_ID
            WHERE p.AGENT_RUN_ID = {agent_run_sql}
            ORDER BY
                CASE p.STATUS
                    WHEN 'REVIEW_REQUIRED' THEN 1
                    WHEN 'APPROVED' THEN 2
                    WHEN 'REJECTED' THEN 3
                    WHEN 'PUBLISHED' THEN 4
                    ELSE 5
                END,
                p.PRIORITY DESC,
                p.PROPOSAL_TYPE,
                p.PROPOSAL_ID
            """
        )
    except Exception as exc:
        st.error(f"Could not load AI proposals: {exc}")
        st.stop()
else:
    proposals_df = query_df(
        """
        SELECT
            NULL::VARCHAR AS PROPOSAL_ID,
            NULL::VARCHAR AS AGENT_RUN_ID,
            NULL::VARCHAR AS PROPOSAL_TYPE,
            NULL::VARCHAR AS TITLE,
            NULL::VARCHAR AS DESCRIPTION,
            NULL::VARCHAR AS SEVERITY,
            NULL::NUMBER AS PRIORITY,
            NULL::VARCHAR AS RATIONALE,
            NULL::VARCHAR AS STATUS,
            NULL::VARCHAR AS QUESTION_ID,
            NULL::VARCHAR AS REVIEW_COMMENT,
            NULL::VARCHAR AS REVIEWED_BY,
            NULL::TIMESTAMP_NTZ AS REVIEWED_AT,
            NULL::VARCHAR AS RECOMMENDED_OWNER,
            NULL::NUMBER AS RECOMMENDED_DUE_DATE,
            NULL::VARCHAR AS PUBLISHED_ENTITY_ID,
            NULL::VARCHAR AS QUESTION_TEXT,
            NULL::VARCHAR AS EXPECTED_EVIDENCE,
            NULL::VARCHAR AS DOMAIN_NAME,
            NULL::VARCHAR AS ANSWER_STATUS,
            NULL::VARCHAR AS ANSWER_TEXT,
            NULL::VARCHAR AS EVIDENCE_TITLE,
            NULL::VARCHAR AS EVIDENCE_TEXT,
            NULL::VARCHAR AS EVIDENCE_STATUS,
            NULL::VARCHAR AS SOURCE_SUMMARY,
            NULL::VARCHAR AS RULE_ID,
            NULL::VARCHAR AS RULE_VERSION
        WHERE 1 = 0
        """
    )

try:
    published_gap_df = query_df(
        f"""
        SELECT
            g.GAP_ID AS ENTITY_ID,
            COALESCE(p.PROPOSAL_TYPE, 'GAP') AS RECORD_TYPE,
            g.GAP_TITLE AS TITLE,
            g.GAP_DESCRIPTION AS DESCRIPTION,
            g.SEVERITY,
            g.PRIORITY_SCORE AS PRIORITY,
            g.QUESTION_ID,
            q.QUESTION_TEXT,
            d.DOMAIN_NAME,
            g.SOURCE_PROPOSAL_ID,
            g.SOURCE_AGENT_RUN_ID
        FROM READINESS_GAPS g
        LEFT JOIN GOVERNANCE_AGENT_PROPOSAL p
          ON g.SOURCE_PROPOSAL_ID = p.PROPOSAL_ID
        LEFT JOIN READINESS_QUESTIONS q
          ON g.QUESTION_ID = q.QUESTION_ID
        LEFT JOIN READINESS_DOMAINS d
          ON g.DOMAIN_ID = d.DOMAIN_ID
        WHERE g.RUN_ID = {run_id_sql}
          AND g.SOURCE_PROPOSAL_ID IS NOT NULL
        ORDER BY g.PRIORITY_SCORE DESC, g.GAP_ID
        """
    )
    published_action_df = query_df(
        f"""
        SELECT
            a.ACTION_ID AS ENTITY_ID,
            'ACTION' AS RECORD_TYPE,
            a.ACTION_TITLE AS TITLE,
            a.ACTION_DESCRIPTION AS DESCRIPTION,
            NULL::VARCHAR AS SEVERITY,
            NULL::NUMBER AS PRIORITY,
            p.QUESTION_ID,
            q.QUESTION_TEXT,
            d.DOMAIN_NAME,
            a.OWNER_NAME,
            a.DUE_IN_DAYS,
            a.ACTION_STATUS,
            a.SOURCE_PROPOSAL_ID,
            a.SOURCE_AGENT_RUN_ID
        FROM RECOMMENDED_ACTIONS a
        LEFT JOIN GOVERNANCE_AGENT_PROPOSAL p
          ON a.SOURCE_PROPOSAL_ID = p.PROPOSAL_ID
        LEFT JOIN READINESS_QUESTIONS q
          ON p.QUESTION_ID = q.QUESTION_ID
        LEFT JOIN READINESS_DOMAINS d
          ON q.DOMAIN_ID = d.DOMAIN_ID
        WHERE a.RUN_ID = {run_id_sql}
          AND a.SOURCE_PROPOSAL_ID IS NOT NULL
        ORDER BY a.CREATED_AT DESC, a.ACTION_ID
        """
    )
    published_decision_df = query_df(
        f"""
        SELECT
            d.DECISION_RECORD_ID AS ENTITY_ID,
            d.DECISION_TYPE AS RECORD_TYPE,
            d.TITLE,
            d.DESCRIPTION,
            d.PUBLISHED_BY,
            d.PUBLISHED_AT,
            d.SOURCE_PROPOSAL_ID,
            d.SOURCE_AGENT_RUN_ID
        FROM GOVERNED_DECISION_RECORD d
        WHERE d.ASSESSMENT_RUN_ID = {run_id_sql}
        ORDER BY d.PUBLISHED_AT DESC, d.DECISION_RECORD_ID
        """
    )
except Exception as exc:
    st.error(f"Could not load published records: {exc}")
    st.stop()

pending_count = 0
approved_count = 0
rejected_count = 0
published_proposal_count = 0
if not proposals_df.empty:
    status_series = proposals_df["STATUS"].astype(str)
    pending_count = integer((status_series == "REVIEW_REQUIRED").sum())
    approved_count = integer((status_series == "APPROVED").sum())
    rejected_count = integer((status_series == "REJECTED").sum())
    published_proposal_count = integer((status_series == "PUBLISHED").sum())

evidence_attention_count = 0
if not evidence_df.empty:
    evidence_attention_count = sum(
        1 for value in evidence_df["EVIDENCE_STATUS"].tolist() if evidence_needs_attention(value)
    )

published_gap_count = 0
published_risk_count = 0
if not published_gap_df.empty:
    record_types = published_gap_df["RECORD_TYPE"].astype(str)
    published_gap_count = integer((record_types == "GAP").sum())
    published_risk_count = integer((record_types == "RISK").sum())
published_action_count = len(published_action_df)
published_decision_count = len(published_decision_df)
published_total = (
    published_gap_count
    + published_risk_count
    + published_action_count
    + published_decision_count
)


# ============================================================
# Header and workflow summary
# ============================================================
st.title("ReadinessOps Governance Review")
st.caption(
    "Turn evidence gaps into governed actions without allowing AI output to bypass human accountability."
)

st.markdown(
    """
<div class="workflow">
  <div class="workflow-step"><strong>1. Evidence context</strong><span>What exists, what is missing, and what the requirement expects.</span></div>
  <div class="workflow-step"><strong>2. AI proposal</strong><span>Evidence-grounded decision, gap, risk, and action drafts.</span></div>
  <div class="workflow-step"><strong>3. Human decision</strong><span>Approve or reject every proposal with an audit record.</span></div>
  <div class="workflow-step"><strong>4. Published record</strong><span>Only approved proposals become governed records.</span></div>
</div>
""",
    unsafe_allow_html=True,
)

metric1, metric2, metric3, metric4 = st.columns(4)
metric1.metric("Evidence not yet verified", evidence_attention_count)
metric2.metric("Needs human decision", pending_count)
metric3.metric("Approved, not published", approved_count)
metric4.metric("Published governance records", published_total)

if latest_attempt is not None and text(latest_attempt["STATUS"], "") == "FAILED":
    st.error(
        "The latest AI review attempt failed. The workspace is showing the most recent completed review. "
        f"Error: {text(latest_attempt['ERROR_MESSAGE'])}"
    )
elif latest_completed is not None:
    st.markdown(
        f"<div class='section-note'><b>Current review:</b> {escaped(latest_agent_run_id)} · "
        f"Completed {escaped(timestamp_text(latest_completed['COMPLETED_AT']))} · "
        f"{escaped(latest_completed['SUMMARY'], 'No summary returned')}</div>",
        unsafe_allow_html=True,
    )

last_action_message = st.session_state.pop("last_action_message", None)
if last_action_message:
    st.success(last_action_message)

last_error_message = st.session_state.pop("last_error_message", None)
if last_error_message:
    st.error(last_error_message)

assessment_navigation_context = (
    f"{selected_run_id}:{integer(current_revision_no)}:"
    f"{integer(draft_revision_no) if has_active_draft else 'none'}"
)
if (
    st.session_state.get("assessment_navigation_context")
    != assessment_navigation_context
):
    st.session_state["workspace_navigation"] = (
        "Value Control Plane" if has_active_draft else "Review queue"
    )
    st.session_state["vcp_section_nav"] = (
        "Revisions" if has_active_draft else "Initiative"
    )
    st.session_state["assessment_navigation_context"] = (
        assessment_navigation_context
    )

workspace = st.radio(
    "Workspace",
    options=["Review queue", "Value Control Plane", "Published records", "Audit trail", "Review setup"],
    horizontal=True,
    key="workspace_navigation",
)


# ============================================================
# Review queue
# ============================================================
if workspace == "Review queue":
    st.header("Human review workspace")
    st.markdown(
        "<div class='section-note'>Review the assessment by issue. Evidence context is shown once, and related Gap, Risk, and Action proposals are separated into focused tabs.</div>",
        unsafe_allow_html=True,
    )

    if proposals_df.empty:
        if has_active_draft:
            st.info(
                "This Draft Revision does not yet have a completed governance "
                "review. Open Review setup to generate one."
            )
        else:
            st.info(
                "No proposals are available. Open Review setup to generate an "
                "AI review."
            )
    else:
        def render_proposal_detail(row, key_prefix):
            proposal_id = text(row["PROPOSAL_ID"], "")
            proposal_type = text(row["PROPOSAL_TYPE"], "Proposal")
            proposal_status = text(row["STATUS"], "")
            title = text(row["TITLE"], "Untitled proposal")
            severity = text(row["SEVERITY"], "Not rated")
            priority = text(row["PRIORITY"], "—")

            st.markdown(
                "<div class='proposal-card'>"
                f"{badge(proposal_type, 'info')}"
                f"{badge(severity, severity_tone(severity))}"
                f"{badge(status_label(proposal_status), status_tone(proposal_status))}"
                f"<div class='proposal-title'>{escaped(title)}</div>"
                f"<div class='small-muted'>Priority {escaped(priority)} · {escaped(row['DOMAIN_NAME'])}</div>"
                f"<div class='proposal-copy'>{escaped(row['DESCRIPTION'])}</div>"
                "</div>",
                unsafe_allow_html=True,
            )

            with st.expander("Why the AI raised this proposal"):
                st.write(text(row["RATIONALE"], "No rationale was returned."))
                source_summary = text(row["SOURCE_SUMMARY"], "")
                if source_summary:
                    st.markdown("**Source traceability**")
                    st.text(source_summary)
                rule_id = text(row["RULE_ID"], "")
                rule_version = text(row["RULE_VERSION"], "")
                if rule_id or rule_version:
                    st.caption(
                        f"Rule context: {rule_id or 'Not set'} · version {rule_version or 'Not set'}"
                    )

            if proposal_type == "ACTION":
                st.caption(
                    f"Recommended owner: {text(row['RECOMMENDED_OWNER'])} · "
                    f"Target: {text(row['RECOMMENDED_DUE_DATE'])} days"
                )

            if proposal_status == "REVIEW_REQUIRED":
                comment_key = f"{key_prefix}_review_comment_{proposal_id}"
                comment = st.text_input(
                    "Decision comment",
                    key=comment_key,
                    placeholder="Optional: record the reason for the decision.",
                )
                action_col1, action_col2, action_col3 = st.columns([1, 1, 4])
                with action_col1:
                    approve_clicked = st.button(
                        "Approve",
                        key=f"{key_prefix}_approve_{proposal_id}",
                        type="primary",
                    )
                with action_col2:
                    reject_clicked = st.button(
                        "Reject",
                        key=f"{key_prefix}_reject_{proposal_id}",
                    )

                if approve_clicked or reject_clicked:
                    decision = "APPROVE" if approve_clicked else "REJECT"
                    try:
                        result = call_json(
                            "CALL SP_REVIEW_AGENT_PROPOSAL("
                            f"{sql_literal(proposal_id)}, "
                            f"{sql_literal(decision)}, "
                            f"{sql_literal(comment.strip())})"
                        )
                        if result.get("status") == "OK":
                            verb = "Approved" if decision == "APPROVE" else "Rejected"
                            st.session_state["last_action_message"] = (
                                f"{verb}: {title}. The decision was written to the approval history."
                            )
                        else:
                            st.session_state["last_error_message"] = (
                                f"Decision failed: {result.get('error', 'Unknown error')}"
                            )
                    except Exception as exc:
                        st.session_state["last_error_message"] = f"Decision failed: {exc}"
                    rerun_app()
            else:
                review_comment = text(row["REVIEW_COMMENT"], "")
                reviewed_by = text(row["REVIEWED_BY"], "")
                if review_comment or reviewed_by:
                    st.caption(
                        f"Decision record: {reviewed_by or 'Unknown reviewer'} · "
                        f"{timestamp_text(row['REVIEWED_AT'])}"
                        + (f" · {review_comment}" if review_comment else "")
                    )

        decision_status_options = [
            "Needs human decision",
            "Approved — ready to publish",
            "Rejected",
            "Published",
            "All",
        ]
        decision_status_map = {
            "Needs human decision": "REVIEW_REQUIRED",
            "Approved — ready to publish": "APPROVED",
            "Rejected": "REJECTED",
            "Published": "PUBLISHED",
        }

        if "review_subview" not in st.session_state:
            st.session_state["review_subview"] = "Summary"

        current_review_subview = st.session_state["review_subview"]
        review_nav_col1, review_nav_col2, review_nav_col3 = st.columns(3)

        with review_nav_col1:
            summary_button_kwargs = (
                {"type": "primary"} if current_review_subview == "Summary" else {}
            )
            if st.button(
                "Summary",
                key="review_nav_summary",
                **summary_button_kwargs,
            ):
                st.session_state["review_subview"] = "Summary"
                rerun_app()

        with review_nav_col2:
            issue_button_kwargs = (
                {"type": "primary"}
                if current_review_subview == "Review by issue"
                else {}
            )
            if st.button(
                "Review by issue",
                key="review_nav_issue",
                **issue_button_kwargs,
            ):
                st.session_state["review_subview"] = "Review by issue"
                rerun_app()

        with review_nav_col3:
            publish_button_kwargs = (
                {"type": "primary"}
                if current_review_subview == "Approved & publish"
                else {}
            )
            if st.button(
                "Approved & publish",
                key="review_nav_publish",
                **publish_button_kwargs,
            ):
                st.session_state["review_subview"] = "Approved & publish"
                rerun_app()

        if current_review_subview == "Summary":
            pending_df = proposals_df[
                proposals_df["STATUS"].astype(str) == "REVIEW_REQUIRED"
            ].copy()
            pending_issue_count = 0
            if not pending_df.empty:
                pending_issue_keys = pending_df["QUESTION_ID"].fillna(
                    pending_df["PROPOSAL_ID"]
                )
                pending_issue_count = integer(pending_issue_keys.nunique())

            s1, s2, s3, s4 = st.columns(4)
            s1.metric("Issues requiring review", pending_issue_count)
            s2.metric(
                "Gap proposals",
                integer(
                    (
                        (proposals_df["PROPOSAL_TYPE"].astype(str) == "GAP")
                        & (proposals_df["STATUS"].astype(str) == "REVIEW_REQUIRED")
                    ).sum()
                ),
            )
            s3.metric(
                "Risk proposals",
                integer(
                    (
                        (proposals_df["PROPOSAL_TYPE"].astype(str) == "RISK")
                        & (proposals_df["STATUS"].astype(str) == "REVIEW_REQUIRED")
                    ).sum()
                ),
            )
            s4.metric(
                "Action proposals",
                integer(
                    (
                        (proposals_df["PROPOSAL_TYPE"].astype(str) == "ACTION")
                        & (proposals_df["STATUS"].astype(str) == "REVIEW_REQUIRED")
                    ).sum()
                ),
            )

            st.subheader("Current proposal summary")
            summary_status_filter = st.selectbox(
                "Decision status",
                options=decision_status_options,
                index=0,
                key="summary_status_filter",
            )
            summary_source_df = proposals_df.copy()
            if summary_status_filter != "All":
                summary_source_df = summary_source_df[
                    summary_source_df["STATUS"].astype(str)
                    == decision_status_map[summary_status_filter]
                ]

            if summary_source_df.empty:
                st.info("No proposals match the selected decision status.")
            else:
                summary_df = summary_source_df[
                    [
                        "TITLE",
                        "PROPOSAL_TYPE",
                        "SEVERITY",
                        "PRIORITY",
                        "DOMAIN_NAME",
                        "STATUS",
                    ]
                ].copy()
                summary_df["STATUS"] = summary_df["STATUS"].map(status_label)
                summary_df = summary_df.rename(
                    columns={
                        "TITLE": "Proposal",
                        "PROPOSAL_TYPE": "Type",
                        "SEVERITY": "Severity",
                        "PRIORITY": "Priority",
                        "DOMAIN_NAME": "Domain",
                        "STATUS": "Decision status",
                    }
                )
                show_dataframe(summary_df.reset_index(drop=True))
                st.caption(
                    f"{len(summary_df)} proposal(s) shown. Open Review by issue to inspect one assessment issue at a time."
                )

        elif current_review_subview == "Review by issue":
            filter_col1, filter_col2, filter_col3 = st.columns([1, 1, 1])
            with filter_col1:
                status_filter = st.selectbox(
                    "Decision status",
                    options=decision_status_options,
                    key="issue_status_filter",
                )
            with filter_col2:
                domain_options = ["All"] + sorted(
                    {
                        text(value)
                        for value in proposals_df["DOMAIN_NAME"].tolist()
                        if text(value, "") != ""
                    }
                )
                domain_filter = st.selectbox(
                    "Domain",
                    options=domain_options,
                    key="issue_domain_filter",
                )
            with filter_col3:
                severity_options = ["All", "High", "Medium", "Low", "Not rated"]
                severity_filter = st.selectbox(
                    "Severity",
                    options=severity_options,
                    key="issue_severity_filter",
                )

            filtered_df = proposals_df.copy()
            if status_filter != "All":
                filtered_df = filtered_df[
                    filtered_df["STATUS"].astype(str) == decision_status_map[status_filter]
                ]
            if domain_filter != "All":
                filtered_df = filtered_df[
                    filtered_df["DOMAIN_NAME"].astype(str) == domain_filter
                ]
            if severity_filter != "All":
                severity_value = "" if severity_filter == "Not rated" else severity_filter.upper()
                if severity_filter == "Not rated":
                    filtered_df = filtered_df[
                        filtered_df["SEVERITY"].fillna("").astype(str).str.strip() == ""
                    ]
                else:
                    filtered_df = filtered_df[
                        filtered_df["SEVERITY"].astype(str).str.upper() == severity_value
                    ]

            if filtered_df.empty:
                st.info("No assessment issues match the selected filters.")
            else:
                issue_options = {}
                issue_order = []
                for _, issue_row in filtered_df.iterrows():
                    question_id = text(issue_row["QUESTION_ID"], "")
                    proposal_id = text(issue_row["PROPOSAL_ID"], "")
                    issue_key = question_id if question_id else f"UNLINKED::{proposal_id}"
                    if issue_key in issue_order:
                        continue
                    issue_order.append(issue_key)
                    question_label = text(
                        issue_row["QUESTION_TEXT"],
                        text(issue_row["TITLE"], "Unlinked proposal"),
                    )
                    label = (
                        f"{text(issue_row['DOMAIN_NAME'], 'No domain')} · "
                        f"{question_label[:100]}"
                    )
                    if label in issue_options:
                        label = f"{label} · {issue_key}"
                    issue_options[label] = issue_key

                selected_issue_label = st.selectbox(
                    "Assessment issue",
                    options=list(issue_options.keys()),
                    key="selected_assessment_issue",
                    help="Select one evidence issue. Its related Gap, Risk, and Action proposals are shown below.",
                )
                selected_issue_key = issue_options[selected_issue_label]
                if selected_issue_key.startswith("UNLINKED::"):
                    selected_proposal_id = selected_issue_key.split("::", 1)[1]
                    issue_df = filtered_df[
                        filtered_df["PROPOSAL_ID"].astype(str) == selected_proposal_id
                    ].copy()
                else:
                    issue_df = filtered_df[
                        filtered_df["QUESTION_ID"].astype(str) == selected_issue_key
                    ].copy()

                issue_df = issue_df.sort_values(
                    by=["PRIORITY", "PROPOSAL_TYPE", "PROPOSAL_ID"],
                    ascending=[False, True, True],
                )
                context_row = issue_df.iloc[0]

                st.markdown(
                    "<div class='proposal-card'>"
                    f"<div class='proposal-title'>{escaped(context_row['QUESTION_TEXT'], 'Assessment context')}</div>"
                    f"<div class='small-muted'>{escaped(context_row['DOMAIN_NAME'])}</div>"
                    "<div class='context-grid'>"
                    "<div class='context-box'><b>Current answer</b>"
                    f"<span>{escaped(context_row['ANSWER_STATUS'])}: "
                    f"{escaped(context_row['ANSWER_TEXT'], 'No answer text')}</span></div>"
                    "<div class='context-box'><b>Evidence</b>"
                    f"<span>{escaped(context_row['EVIDENCE_STATUS'])}: "
                    f"{escaped(context_row['EVIDENCE_TITLE'], 'No evidence item')}"
                    f"<br>{escaped(context_row['EVIDENCE_TEXT'], '')}</span></div>"
                    "<div class='context-box'><b>Requirement / rule context</b>"
                    f"<span>{escaped(context_row['EXPECTED_EVIDENCE'])}</span></div>"
                    "<div class='context-box'><b>Related AI proposals</b>"
                    f"<span>{len(issue_df)} proposal(s): "
                    f"{integer((issue_df['PROPOSAL_TYPE'].astype(str) == 'GAP').sum())} gap, "
                    f"{integer((issue_df['PROPOSAL_TYPE'].astype(str) == 'RISK').sum())} risk, "
                    f"{integer((issue_df['PROPOSAL_TYPE'].astype(str) == 'ACTION').sum())} action</span></div>"
                    "</div>"
                    "</div>",
                    unsafe_allow_html=True,
                )

                available_proposal_types = [
                    proposal_type
                    for proposal_type in ["GAP", "RISK", "ACTION"]
                    if integer(
                        (issue_df["PROPOSAL_TYPE"].astype(str) == proposal_type).sum()
                    )
                    > 0
                ]
                proposal_type_labels = {
                    "GAP": "Gap",
                    "RISK": "Risk",
                    "ACTION": "Action",
                }

                if not available_proposal_types:
                    st.info("No AI proposal is linked to this assessment issue.")
                else:
                    proposal_tabs = st.tabs(
                        [proposal_type_labels[value] for value in available_proposal_types]
                    )
                    for proposal_tab, proposal_type in zip(
                        proposal_tabs, available_proposal_types
                    ):
                        with proposal_tab:
                            type_rows = issue_df[
                                issue_df["PROPOSAL_TYPE"].astype(str) == proposal_type
                            ].copy()
                            if len(type_rows) > 1:
                                type_options = {}
                                for _, type_row in type_rows.iterrows():
                                    type_label = (
                                        f"Priority {text(type_row['PRIORITY'])} · "
                                        f"{text(type_row['TITLE'])}"
                                    )
                                    if type_label in type_options:
                                        type_label = (
                                            f"{type_label} · {text(type_row['PROPOSAL_ID'])}"
                                        )
                                    type_options[type_label] = text(type_row["PROPOSAL_ID"])
                                selected_type_label = st.selectbox(
                                    f"Select {proposal_type.lower()} proposal",
                                    options=list(type_options.keys()),
                                    key=f"selected_{proposal_type.lower()}_{selected_issue_key}",
                                )
                                selected_type_id = type_options[selected_type_label]
                                selected_type_row = type_rows[
                                    type_rows["PROPOSAL_ID"].astype(str) == selected_type_id
                                ].iloc[0]
                            else:
                                selected_type_row = type_rows.iloc[0]

                            render_proposal_detail(
                                selected_type_row,
                                f"issue_{selected_issue_key}_{proposal_type}",
                            )

        else:
            st.subheader("Approved proposals waiting for publication")
            if not latest_agent_run_id:
                st.info("A completed review is required before proposals can be published.")
                if st.button(
                    "← Back to review queue",
                    key="back_to_review_queue_no_run",
                    type="primary",
                ):
                    st.session_state["review_subview"] = "Review by issue"
                    rerun_app()
            elif approved_count == 0:
                st.info("No approved proposals are waiting to be published.")
                if st.button(
                    "← Back to review queue",
                    key="back_to_review_queue_empty",
                    type="primary",
                ):
                    st.session_state["review_subview"] = "Review by issue"
                    rerun_app()
            else:
                approved_df = proposals_df[
                    proposals_df["STATUS"].astype(str) == "APPROVED"
                ].copy()
                approved_type_counts = (
                    approved_df.groupby("PROPOSAL_TYPE").size().to_dict()
                )
                pub1, pub2, pub3 = st.columns(3)
                pub1.metric("Approved gaps", integer(approved_type_counts.get("GAP", 0)))
                pub2.metric("Approved risks", integer(approved_type_counts.get("RISK", 0)))
                pub3.metric("Approved actions", integer(approved_type_counts.get("ACTION", 0)))

                approved_display = approved_df[
                    [
                        "TITLE",
                        "PROPOSAL_TYPE",
                        "SEVERITY",
                        "PRIORITY",
                        "DOMAIN_NAME",
                        "REVIEWED_BY",
                    ]
                ].rename(
                    columns={
                        "TITLE": "Approved proposal",
                        "PROPOSAL_TYPE": "Type",
                        "SEVERITY": "Severity",
                        "PRIORITY": "Priority",
                        "DOMAIN_NAME": "Domain",
                        "REVIEWED_BY": "Approved by",
                    }
                )
                show_dataframe(approved_display)

                confirm_publish = st.checkbox(
                    "I confirm that these human-approved proposals may become governed records.",
                    key="confirm_publish",
                )
                publish_clicked = st.button(
                    "Publish approved proposals",
                    type="primary",
                    disabled=bool(not confirm_publish),
                    key="publish_approved_proposals",
                )
                if publish_clicked:
                    try:
                        result = call_json(
                            f"CALL SP_PUBLISH_AGENT_RUN({sql_literal(latest_agent_run_id)})"
                        )
                        if result.get("status") == "OK":
                            st.session_state["last_action_message"] = (
                                "Published governed records: "
                                f"{result.get('published_gaps', 0)} gap(s), "
                                f"{result.get('published_risks', 0)} risk(s), "
                                f"{result.get('published_actions', 0)} action(s)."
                            )
                        else:
                            st.session_state["last_error_message"] = (
                                f"Publish failed: {result.get('error', 'Unknown error')}"
                            )
                    except Exception as exc:
                        st.session_state["last_error_message"] = f"Publish failed: {exc}"
                    rerun_app()


# ============================================================
# Published records
# ============================================================
elif workspace == "Published records":
    st.header("Published governance records")
    st.markdown(
        "<div class='section-note'>These records passed human review. Use the list to select one governed record and inspect its traceability.</div>",
        unsafe_allow_html=True,
    )

    p1, p2, p3, p4 = st.columns(4)
    p1.metric("Published gaps", published_gap_count)
    p2.metric("Published risks", published_risk_count)
    p3.metric("Published actions", published_action_count)
    p4.metric("Published decisions", published_decision_count)

    record_filter = st.radio(
        "Record type",
        options=["All", "Decision", "Gap", "Risk", "Action"],
        horizontal=True,
    )

    published_records = []
    if not published_gap_df.empty:
        for row_index, row in published_gap_df.iterrows():
            record_type = text(row["RECORD_TYPE"], "GAP")
            published_records.append(
                {
                    "Record": text(row["TITLE"]),
                    "Type": record_type,
                    "Severity / status": text(row["SEVERITY"], "Not rated"),
                    "Domain": text(row["DOMAIN_NAME"]),
                    "Owner / target": "—",
                    "_source": "gap",
                    "_row_index": row_index,
                    "_entity_id": text(row["ENTITY_ID"]),
                }
            )
    if not published_action_df.empty:
        for row_index, row in published_action_df.iterrows():
            published_records.append(
                {
                    "Record": text(row["TITLE"]),
                    "Type": "ACTION",
                    "Severity / status": text(row["ACTION_STATUS"]),
                    "Domain": text(row["DOMAIN_NAME"]),
                    "Owner / target": (
                        f"{text(row['OWNER_NAME'])} · {text(row['DUE_IN_DAYS'])} days"
                    ),
                    "_source": "action",
                    "_row_index": row_index,
                    "_entity_id": text(row["ENTITY_ID"]),
                }
            )
    if not published_decision_df.empty:
        for row_index, row in published_decision_df.iterrows():
            published_records.append(
                {
                    "Record": text(row["TITLE"]),
                    "Type": "DECISION",
                    "Severity / status": text(row["RECORD_TYPE"]),
                    "Domain": "Value Control Plane",
                    "Owner / target": text(row["PUBLISHED_BY"]),
                    "_source": "decision",
                    "_row_index": row_index,
                    "_entity_id": text(row["ENTITY_ID"]),
                }
            )

    if record_filter != "All":
        published_records = [
            record
            for record in published_records
            if record["Type"] == record_filter.upper()
        ]

    if not published_records:
        st.info("No published records match the selected filter.")
    else:
        records_summary_df = pd.DataFrame(published_records)[
            ["Record", "Type", "Severity / status", "Domain", "Owner / target"]
        ]
        st.subheader("Published record list")
        show_dataframe(records_summary_df.reset_index(drop=True))

        record_options = {}
        for record in published_records:
            option_label = (
                f"{record['Type']} · {record['Record']} · {record['Domain']}"
            )
            if option_label in record_options:
                option_label = f"{option_label} · {record['_entity_id']}"
            record_options[option_label] = record

        selected_record_label = st.selectbox(
            "Record detail",
            options=list(record_options.keys()),
            key="selected_published_record",
        )
        selected_record = record_options[selected_record_label]

        if selected_record["_source"] == "gap":
            row = published_gap_df.loc[selected_record["_row_index"]]
            record_type = text(row["RECORD_TYPE"], "GAP")
            st.markdown(
                "<div class='published-card'>"
                f"{badge(record_type, 'info')}"
                f"{badge(text(row['SEVERITY'], 'Not rated'), severity_tone(row['SEVERITY']))}"
                f"<div class='proposal-title'>{escaped(row['TITLE'])}</div>"
                f"<div class='proposal-copy'>{escaped(row['DESCRIPTION'])}</div>"
                f"<div class='small-muted'>{escaped(row['DOMAIN_NAME'])}</div>"
                "</div>",
                unsafe_allow_html=True,
            )
        elif selected_record["_source"] == "action":
            row = published_action_df.loc[selected_record["_row_index"]]
            st.markdown(
                "<div class='published-card'>"
                f"{badge('ACTION', 'success')}"
                f"{badge(text(row['ACTION_STATUS']), 'neutral')}"
                f"<div class='proposal-title'>{escaped(row['TITLE'])}</div>"
                f"<div class='proposal-copy'>{escaped(row['DESCRIPTION'])}</div>"
                f"<div class='small-muted'>Owner: {escaped(row['OWNER_NAME'])} · "
                f"Target: {escaped(row['DUE_IN_DAYS'])} days · {escaped(row['DOMAIN_NAME'])}</div>"
                "</div>",
                unsafe_allow_html=True,
            )
        else:
            row = published_decision_df.loc[selected_record["_row_index"]]
            st.markdown(
                "<div class='published-card'>"
                f"{badge(text(row['RECORD_TYPE']), 'info')}"
                f"{badge('Published governed record', 'success')}"
                f"<div class='proposal-title'>{escaped(row['TITLE'])}</div>"
                f"<div class='proposal-copy'>{escaped(row['DESCRIPTION'])}</div>"
                f"<div class='small-muted'>Published by {escaped(row['PUBLISHED_BY'])} · "
                f"{escaped(timestamp_text(row['PUBLISHED_AT']))}</div>"
                "</div>",
                unsafe_allow_html=True,
            )

        trace_col1, trace_col2 = st.columns(2)
        with trace_col1:
            if selected_record["_source"] == "decision":
                st.markdown("**Governed decision type**")
                st.write(text(row["RECORD_TYPE"]))
            else:
                st.markdown("**Assessment question**")
                st.write(text(row["QUESTION_TEXT"]))
        with trace_col2:
            st.markdown("**Publication source**")
            st.write(f"Proposal: {text(row['SOURCE_PROPOSAL_ID'])}")
            st.write(f"Agent run: {text(row['SOURCE_AGENT_RUN_ID'])}")


# ============================================================
# Audit trail
# ============================================================
elif workspace == "Audit trail":
    st.header("Human decision and publication history")
    st.markdown(
        "<div class='section-note'>Every approval, rejection, and publication remains attributable to a person and a timestamp.</div>",
        unsafe_allow_html=True,
    )

    try:
        history_df = query_df(
            f"""
            SELECT
                h.APPROVAL_HISTORY_ID,
                h.PROPOSAL_ID,
                p.PROPOSAL_TYPE,
                p.TITLE,
                h.ACTION_TYPE,
                h.PREVIOUS_STATUS,
                h.NEW_STATUS,
                COALESCE(h.COMMENT, '') AS COMMENT,
                h.ACTED_BY,
                h.ACTED_AT
            FROM GOVERNANCE_APPROVAL_HISTORY h
            JOIN GOVERNANCE_AGENT_PROPOSAL p
              ON h.PROPOSAL_ID = p.PROPOSAL_ID
            WHERE p.ASSESSMENT_RUN_ID = {run_id_sql}
            ORDER BY h.ACTED_AT DESC, h.APPROVAL_HISTORY_ID DESC
            """
        )
    except Exception as exc:
        st.error(f"Could not load audit history: {exc}")
        history_df = None

    if history_df is not None:
        if history_df.empty:
            st.info("No human decisions have been recorded for this Assessment Run.")
        else:
            history_filter_col, history_limit_col = st.columns([2, 1])
            with history_filter_col:
                action_filter = st.selectbox(
                    "History event",
                    options=["All", "APPROVE", "REJECT", "PUBLISH"],
                )
            with history_limit_col:
                history_limit = st.selectbox(
                    "Rows to show",
                    options=[10, 25, 50, "All"],
                    index=0,
                )

            filtered_history = history_df.copy()
            if action_filter != "All":
                filtered_history = filtered_history[
                    filtered_history["ACTION_TYPE"].astype(str) == action_filter
                ]
            if history_limit != "All":
                filtered_history = filtered_history.head(integer(history_limit, 10))

            if filtered_history.empty:
                st.info("No history events match the selected filter.")
            else:
                history_summary_df = filtered_history[
                    [
                        "ACTION_TYPE",
                        "PROPOSAL_TYPE",
                        "TITLE",
                        "ACTED_BY",
                        "ACTED_AT",
                    ]
                ].copy()
                history_summary_df["ACTED_AT"] = history_summary_df["ACTED_AT"].map(
                    timestamp_text
                )
                history_summary_df = history_summary_df.rename(
                    columns={
                        "ACTION_TYPE": "Event",
                        "PROPOSAL_TYPE": "Type",
                        "TITLE": "Proposal",
                        "ACTED_BY": "Actor",
                        "ACTED_AT": "Timestamp",
                    }
                )
                st.subheader("Recent history")
                show_dataframe(history_summary_df.reset_index(drop=True))

                history_options = {}
                for row_index, row in filtered_history.iterrows():
                    option_label = (
                        f"{text(row['ACTION_TYPE'])} · {text(row['TITLE'])} · "
                        f"{timestamp_text(row['ACTED_AT'])}"
                    )
                    if option_label in history_options:
                        option_label = (
                            f"{option_label} · {text(row['APPROVAL_HISTORY_ID'])}"
                        )
                    history_options[option_label] = row_index

                selected_history_label = st.selectbox(
                    "History detail",
                    options=list(history_options.keys()),
                    key="selected_history_event",
                )
                row = filtered_history.loc[history_options[selected_history_label]]
                action_type = text(row["ACTION_TYPE"])
                tone = {
                    "APPROVE": "success",
                    "REJECT": "danger",
                    "PUBLISH": "info",
                }.get(action_type, "neutral")
                st.markdown(
                    "<div class='proposal-card'>"
                    f"{badge(action_type, tone)} {badge(text(row['PROPOSAL_TYPE']), 'neutral')}"
                    f"<div class='proposal-title'>{escaped(row['TITLE'])}</div>"
                    f"<div class='small-muted'>{escaped(row['ACTED_BY'])} · "
                    f"{escaped(timestamp_text(row['ACTED_AT']))}</div>"
                    f"<div class='proposal-copy'>{escaped(row['PREVIOUS_STATUS'])} → "
                    f"{escaped(row['NEW_STATUS'])}</div>"
                    f"<div class='proposal-copy'>{escaped(row['COMMENT'], 'No comment recorded.')}</div>"
                    "</div>",
                    unsafe_allow_html=True,
                )
                st.caption(
                    f"Proposal ID: {text(row['PROPOSAL_ID'])} · "
                    f"History ID: {text(row['APPROVAL_HISTORY_ID'])}"
                )


# ============================================================
# Value Control Plane
# ============================================================
elif workspace == "Value Control Plane":
    current_actor = session.sql("SELECT CURRENT_USER()").collect()[0][0]
    render_value_control_plane(session, selected_run_id, current_actor)


# ============================================================
# Review setup / technical details
# ============================================================
else:
    st.header("Review setup")
    st.markdown(
        "<div class='section-note'>Generate a new AI review only when the evidence or business instruction has changed. The output is always saved as draft proposals.</div>",
        unsafe_allow_html=True,
    )

    if latest_completed is not None:
        setup1, setup2, setup3 = st.columns(3)
        setup1.metric("Latest status", text(latest_completed["STATUS"]))
        setup2.metric("Model", text(latest_completed["MODEL_NAME"]))
        setup3.metric("Completed", timestamp_text(latest_completed["COMPLETED_AT"]))
        st.caption(f"Agent Run ID: {latest_agent_run_id}")

    st.subheader("Evidence context")
    evidence_display = evidence_df.rename(
        columns={
            "DOMAIN_NAME": "Domain",
            "QUESTION_TEXT": "Question",
            "ANSWER_STATUS": "Answer status",
            "ANSWER_TEXT": "Answer",
            "EVIDENCE_TITLE": "Evidence",
            "EVIDENCE_STATUS": "Evidence status",
            "EXPECTED_EVIDENCE": "Requirement / rule context",
        }
    )
    display_columns = [
        "Domain",
        "Question",
        "Answer status",
        "Answer",
        "Evidence",
        "Evidence status",
        "Requirement / rule context",
    ]
    show_dataframe(evidence_display[display_columns])

    st.subheader("Generate a new AI review")
    st.info(
        "Standard instruction: assess evidence sufficiency, identify gaps and risks, propose prioritized actions, and ground every proposal in the supplied Question, Answer, Evidence, and Rule context."
    )
    additional_instruction = st.text_area(
        "Additional business instruction",
        placeholder="Optional: focus on a deadline, risk appetite, or business priority.",
        height=90,
        key="additional_business_instruction",
    )

    if "governance_review_running" not in st.session_state:
        st.session_state.governance_review_running = False

    run_review_clicked = st.button(
        "Generate AI draft proposals",
        type="primary",
        disabled=bool(st.session_state.governance_review_running),
        key="generate_ai_review",
    )

    if run_review_clicked:
        st.session_state.governance_review_running = True
        with st.spinner("Reviewing evidence and generating governed draft proposals..."):
            try:
                result = call_json(
                    "CALL SP_RUN_FULL_GOVERNANCE_REVIEW("
                    f"{run_id_sql}, {sql_literal(additional_instruction.strip() or None)})"
                )
                if result.get("status") == "COMPLETED":
                    st.session_state["last_action_message"] = (
                        "AI review completed. Drafts created: "
                        f"{result.get('gaps', 0)} gap(s), "
                        f"{result.get('risks', 0)} risk(s), "
                        f"{result.get('actions', 0)} action(s). "
                        "Human review is required before publication."
                    )
                else:
                    st.session_state["last_error_message"] = (
                        f"AI review failed: {result.get('error', 'Unknown error')}"
                    )
            except Exception as exc:
                st.session_state["last_error_message"] = f"AI review failed: {exc}"
            finally:
                st.session_state.governance_review_running = False
            rerun_app()

    with st.expander("System details"):
        st.write(f"Assessment Run ID: {selected_run_id}")
        st.write(f"Latest completed Agent Run ID: {latest_agent_run_id or 'None'}")
        st.write(
            "Control boundary: Requirement / Rule Context → AI Proposed → Human Approved → Published"
        )
        st.write(
            "Traceability: Question → Answer → Evidence → Rule Context → Agent Run → Proposal → Human Decision → Published Record"
        )


st.divider()
st.caption(
    "Demo data is synthetic. AI output remains a proposal until a human decision is recorded and publication is explicitly confirmed."
)
