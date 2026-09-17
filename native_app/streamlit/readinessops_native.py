"""ReadinessOps Marketplace Native App.

The Native App keeps the evaluated ReadinessOps workflow: existing Evidence,
four-section Decision Pack, human editing and review, explicit publication,
published records, Portfolio, and execution trace. AI output always begins as
REVIEW_REQUIRED and never invokes a human-governed transition itself.
"""

import json

import pandas as pd
import streamlit as st
from snowflake.snowpark.context import get_active_session

try:
    import snowflake.permissions as permissions
except ImportError:
    permissions = None


session = get_active_session()


def query(sql, params=None):
    return session.sql(sql, params=params).to_pandas()


def call_json(sql, params=None):
    rows = session.sql(sql, params=params).collect()
    if not rows:
        return {"status": "FAILED", "error": "Procedure returned no result."}
    value = rows[0][0]
    if isinstance(value, dict):
        return value
    try:
        return json.loads(value)
    except (TypeError, json.JSONDecodeError):
        return {"status": "FAILED", "error": f"Unexpected response: {value}"}


def reference_associations(reference_name):
    if permissions is None:
        return []
    try:
        return permissions.get_detailed_reference_associations(reference_name)
    except Exception:
        return []


def load_runs():
    try:
        return query(
            "SELECT RUN_ID, RUN_NAME, ORGANIZATION_NAME, INITIATIVE_NAME, "
            "STATUS, CREATED_AT FROM APP_CODE.V_ASSESSMENT_CONTEXT "
            "ORDER BY CREATED_AT DESC"
        )
    except Exception as exc:
        st.error(f"Could not load Assessment Runs: {exc}")
        return pd.DataFrame()


def select_run(runs, key):
    if runs.empty:
        st.info("Register Evidence to create the first Assessment Run.")
        return None
    records = runs.to_dict("records")
    labels = {
        row["RUN_ID"]: (
            f"{row['RUN_NAME']} · {row['ORGANIZATION_NAME']} · "
            f"{row['INITIATIVE_NAME']}"
        )
        for row in records
    }
    run_ids = list(labels)
    preferred = st.session_state.get("active_run_id")
    default_index = run_ids.index(preferred) if preferred in run_ids else 0
    return st.selectbox(
        "Assessment Run",
        run_ids,
        index=default_index,
        format_func=lambda value: labels[value],
        key=key,
    )


def show_result(result, success_statuses):
    if result.get("status") in success_statuses:
        st.success(result.get("status"))
    else:
        st.error(result.get("error", "Operation failed."))
    st.json(result)


def render_evidence_workspace(read_session_granted):
    st.header("Evidence & Decision Pack")
    st.caption(
        "Connect existing Snowflake Evidence with SELECT only, register it in "
        "the ReadinessOps model, and generate the evaluated four-section pack."
    )

    if read_session_granted:
        st.success("Operator attribution is enabled.")
    elif permissions is None:
        st.error("Snowflake Permission SDK is unavailable.")
    elif st.button("Grant operator attribution", key="request_read_session"):
        permissions.request_account_privileges(["READ SESSION"])

    table_refs = reference_associations("EVIDENCE_SOURCE_TABLE")
    view_refs = reference_associations("EVIDENCE_SOURCE_VIEW")

    st.subheader("1. Connect existing Snowflake Evidence")
    left, right = st.columns(2)
    with left:
        st.markdown("**Existing table**")
        if table_refs:
            st.success("Table reference is bound.")
            st.dataframe(pd.DataFrame(table_refs), use_container_width=True)
        elif permissions is not None and st.button(
            "Choose table",
            key="request_table_reference",
            disabled=not read_session_granted,
        ):
            permissions.request_reference("EVIDENCE_SOURCE_TABLE")
    with right:
        st.markdown("**Existing view**")
        if view_refs:
            st.success("View reference is bound.")
            st.dataframe(pd.DataFrame(view_refs), use_container_width=True)
        elif permissions is not None and st.button(
            "Choose view",
            key="request_view_reference",
            disabled=not read_session_granted,
        ):
            permissions.request_reference("EVIDENCE_SOURCE_VIEW")

    st.caption(
        "Decision Pack generation also requires the declared "
        "SNOWFLAKE.CORTEX_USER database role."
    )

    st.subheader("2. Register Evidence in the existing ReadinessOps model")
    context_left, context_right = st.columns(2)
    with context_left:
        assessment_run_id = st.text_input(
            "Assessment ID",
            placeholder="RUN_CUSTOMER_001",
            help="Use the same stable ID when adding Evidence to this assessment.",
        )
        run_name = st.text_input("Assessment name", placeholder="AI initiative assessment")
        organization_name = st.text_input(
            "Organization name", placeholder="Customer organization"
        )
        assessment_scope = st.text_area(
            "Assessment scope", placeholder="Decision scope and operating boundary"
        )
    with context_right:
        initiative_id = st.text_input(
            "AI initiative ID",
            placeholder="INIT_CUSTOMER_001",
            help="Use the stable ReadinessOps Initiative ID.",
        )
        initiative_name = st.text_input(
            "AI initiative name", placeholder="Customer AI initiative"
        )
        initiative_description = st.text_area(
            "Initiative description",
            placeholder="What the initiative is intended to do",
        )
        business_outcome = st.text_area(
            "Business outcome", placeholder="Expected measurable outcome"
        )

    mapping_left, mapping_right = st.columns(2)
    with mapping_left:
        source_kind = st.radio(
            "Bound source type", ["TABLE", "VIEW"], horizontal=True
        )
        source_key_column = st.text_input(
            "Unique row key column", placeholder="EVIDENCE_ID"
        )
        source_key_value = st.text_input("Row key value", placeholder="EV-001")
    with mapping_right:
        title_column = st.text_input(
            "Evidence title column", placeholder="EVIDENCE_TITLE"
        )
        text_column = st.text_input(
            "Evidence text column", placeholder="EVIDENCE_TEXT"
        )

    if st.button("Register Evidence", type="primary"):
        expected_reference = table_refs if source_kind == "TABLE" else view_refs
        required_values = (
            source_key_column,
            source_key_value,
            title_column,
            text_column,
            assessment_run_id,
            initiative_id,
            run_name,
            organization_name,
            assessment_scope,
            initiative_name,
        )
        if not read_session_granted:
            st.error("Grant READ SESSION before registering Evidence.")
        elif not expected_reference:
            st.error(f"Bind an existing {source_kind.lower()} first.")
        elif not all(value.strip() for value in required_values):
            st.error("Complete the source mapping and assessment context.")
        else:
            result = call_json(
                "CALL APP_CODE.SP_IMPORT_REFERENCE_EVIDENCE("
                "?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                [
                    source_kind,
                    source_key_column,
                    source_key_value,
                    title_column,
                    text_column,
                    assessment_run_id,
                    initiative_id,
                    run_name,
                    organization_name,
                    assessment_scope,
                    initiative_name,
                    initiative_description,
                    business_outcome,
                ],
            )
            if result.get("status") in {"IMPORTED", "SKIPPED"}:
                st.session_state["active_run_id"] = result.get("assessment_run_id")
            show_result(result, {"IMPORTED", "SKIPPED"})

    st.subheader("3. Generate the existing four-section Decision Pack")
    selected_run_id = select_run(load_runs(), "evidence_run")
    if selected_run_id:
        additional_instruction = st.text_area(
            "Additional instruction (optional)",
            placeholder="Keep blank unless a human reviewer adds an instruction.",
        )
        if st.button(
            "Generate Decision Pack",
            type="primary",
            disabled=not read_session_granted,
        ):
            result = call_json(
                "CALL APP_CODE.SP_GENERATE_DECISION_PACK(?, ?)",
                [selected_run_id, additional_instruction or None],
            )
            show_result(result, {"COMPLETED", "SKIPPED"})

        st.subheader("4. Human review queue")
        proposals = query(
            "SELECT PROPOSAL_ID, AGENT_RUN_ID, PROPOSAL_TYPE, TITLE, "
            "DESCRIPTION, STATUS, CONTENT_VERSION, CONTENT_HASH, CREATED_AT "
            "FROM APP_CODE.V_DECISION_PACK_REVIEW WHERE ASSESSMENT_RUN_ID = ? "
            "ORDER BY CREATED_AT DESC, PROPOSAL_TYPE",
            [selected_run_id],
        )
        if proposals.empty:
            st.info("No Decision Pack has been generated for this Assessment Run.")
        else:
            st.dataframe(proposals, use_container_width=True)

        with st.expander("Evidence and execution trace"):
            evidence = query(
                "SELECT EVIDENCE_ID, EVIDENCE_TITLE, EVIDENCE_STATUS, "
                "SOURCE_TYPE, CONTENT_SHA256, UPLOADED_BY, CREATED_AT "
                "FROM APP_CODE.V_EVIDENCE_ITEMS WHERE RUN_ID = ? "
                "ORDER BY CREATED_AT DESC",
                [selected_run_id],
            )
            st.markdown("**Evidence**")
            st.dataframe(evidence, use_container_width=True)
            steps = query(
                "SELECT s.AGENT_RUN_ID, s.RUN_CREATED_BY, s.STEP_SEQUENCE, "
                "s.STEP_CODE, s.STEP_NAME, s.STATUS, s.DURATION_MS, "
                "s.ERROR_MESSAGE FROM APP_CODE.V_AGENT_RUN_STEP s "
                "WHERE s.ASSESSMENT_RUN_ID = ? "
                "ORDER BY s.AGENT_RUN_ID DESC, s.STEP_SEQUENCE",
                [selected_run_id],
            )
            st.markdown("**Execution trace**")
            st.dataframe(steps, use_container_width=True)


def render_human_review(read_session_granted):
    st.header("Human review & explicit publication")
    st.info(
        "Editing, approval, and publication are separate human actions. "
        "Every action is bound to the displayed content version and hash."
    )
    selected_run_id = select_run(load_runs(), "review_run")
    if not selected_run_id:
        return

    proposals = query(
        "SELECT * FROM APP_CODE.V_DECISION_PACK_REVIEW "
        "WHERE ASSESSMENT_RUN_ID = ? ORDER BY CREATED_AT DESC, PROPOSAL_TYPE",
        [selected_run_id],
    )
    if proposals.empty:
        st.info("Generate a Decision Pack before human review.")
        return

    run_ids = proposals["AGENT_RUN_ID"].drop_duplicates().tolist()
    selected_agent_run_id = st.selectbox("Decision Pack run", run_ids)
    pack = proposals[proposals["AGENT_RUN_ID"] == selected_agent_run_id].copy()

    counts = pack["STATUS"].value_counts().to_dict()
    m1, m2, m3, m4 = st.columns(4)
    m1.metric("Review required", int(counts.get("REVIEW_REQUIRED", 0)))
    m2.metric("Approved", int(counts.get("APPROVED", 0)))
    m3.metric("Rejected", int(counts.get("REJECTED", 0)))
    m4.metric("Published", int(counts.get("PUBLISHED", 0)))

    records = pack.to_dict("records")
    by_id = {row["PROPOSAL_ID"]: row for row in records}
    proposal_id = st.selectbox(
        "Decision Pack section",
        list(by_id),
        format_func=lambda value: (
            f"{by_id[value]['PROPOSAL_TYPE']} · {by_id[value]['STATUS']} · "
            f"v{int(by_id[value]['CONTENT_VERSION'])}"
        ),
    )
    proposal = by_id[proposal_id]
    snapshot_key = f"review_snapshot_{proposal_id}"
    current_snapshot = {
        "content_version": int(proposal["CONTENT_VERSION"]),
        "content_hash": str(proposal["CONTENT_HASH"]),
        "title": proposal["TITLE"] or "",
        "description": proposal["DESCRIPTION"] or "",
        "payload": proposal["PROPOSAL_PAYLOAD"],
    }
    if snapshot_key not in st.session_state:
        st.session_state[snapshot_key] = current_snapshot
    displayed_snapshot = st.session_state[snapshot_key]
    expected_version = int(displayed_snapshot["content_version"])
    expected_hash = str(displayed_snapshot["content_hash"])

    current_changed = (
        current_snapshot["content_version"] != expected_version
        or current_snapshot["content_hash"] != expected_hash
    )
    if current_changed:
        st.warning(
            "This proposal changed after the displayed version was loaded. "
            "Review the new content before deciding."
        )
        if st.button("Reload displayed version"):
            st.session_state[snapshot_key] = current_snapshot
            st.rerun()

    st.caption(f"Content v{expected_version} · SHA-256 {expected_hash}")
    st.json(displayed_snapshot["payload"])

    if proposal["STATUS"] == "REVIEW_REQUIRED":
        with st.form("edit_proposal"):
            new_title = st.text_input("Title", value=displayed_snapshot["title"])
            new_description = st.text_area(
                "Description", value=displayed_snapshot["description"]
            )
            edit_reason = st.text_input("Edit reason")
            save_edit = st.form_submit_button("Save reviewed draft")
        if save_edit:
            result = call_json(
                "CALL APP_CODE.SP_EDIT_DECISION_PROPOSAL(?, ?, ?, ?, ?, ?)",
                [
                    proposal_id,
                    expected_version,
                    expected_hash,
                    new_title,
                    new_description,
                    edit_reason or None,
                ],
            )
            show_result(result, {"OK"})

        review_comment = st.text_area("Review comment")
        approve_col, reject_col = st.columns(2)
        if approve_col.button(
            "Approve displayed version",
            type="primary",
            disabled=(not read_session_granted or current_changed),
        ):
            result = call_json(
                "CALL APP_CODE.SP_REVIEW_DECISION_PROPOSAL(?, 'APPROVE', ?, ?, ?)",
                [proposal_id, expected_version, expected_hash, review_comment or None],
            )
            show_result(result, {"OK"})
        if reject_col.button(
            "Reject displayed version",
            disabled=(not read_session_granted or current_changed),
        ):
            result = call_json(
                "CALL APP_CODE.SP_REVIEW_DECISION_PROPOSAL(?, 'REJECT', ?, ?, ?)",
                [proposal_id, expected_version, expected_hash, review_comment or None],
            )
            show_result(result, {"OK"})
    else:
        st.warning("This proposal is immutable after review. Generate a new pack to revise it.")

    st.subheader("Explicit publication")
    st.caption(
        "Publication becomes available only when all four current content "
        "versions have been approved."
    )
    all_approved = len(pack) == 4 and (pack["STATUS"] == "APPROVED").all()
    already_published = len(pack) == 4 and (pack["STATUS"] == "PUBLISHED").all()
    publication_target_key = "publication_target_run"
    confirmation_key = f"publish_confirm_{selected_agent_run_id}"
    if st.session_state.get(publication_target_key) != selected_agent_run_id:
        st.session_state[publication_target_key] = selected_agent_run_id
        st.session_state[confirmation_key] = False
    confirm = False
    if all_approved:
        confirm = st.checkbox(
            "I confirm that these four approved sections are the intended governed record.",
            key=confirmation_key,
        )
    if st.button(
        "Explicitly publish approved Decision Pack",
        type="primary",
        disabled=(not read_session_granted or not all_approved or not confirm),
    ):
        result = call_json(
            "CALL APP_CODE.SP_PUBLISH_DECISION_PACK(?)", [selected_agent_run_id]
        )
        show_result(result, {"OK", "SKIPPED"})
    if already_published:
        st.success("This Decision Pack is already published as governed records.")


def render_published_records():
    st.header("Published governed decision records")
    records = query(
        "SELECT DECISION_TYPE, TITLE, DESCRIPTION, CONTENT_VERSION, CONTENT_HASH, "
        "PUBLISHED_BY, PUBLISHED_AT, SOURCE_AGENT_RUN_ID, ASSESSMENT_RUN_ID "
        "FROM APP_CODE.V_GOVERNED_DECISION_RECORDS "
        "ORDER BY PUBLISHED_AT DESC, DECISION_TYPE"
    )
    if records.empty:
        st.info("No governed Decision Pack has been explicitly published.")
    else:
        st.dataframe(records, use_container_width=True)


def render_portfolio():
    st.header("AI Portfolio")
    st.caption(
        "Each initiative uses one complete four-section published Decision Pack; "
        "sections from different runs are never mixed."
    )
    portfolio = query(
        "SELECT * FROM APP_CODE.V_AI_PORTFOLIO "
        "ORDER BY PORTFOLIO_PRIORITY DESC NULLS LAST, INITIATIVE_NAME"
    )
    if portfolio.empty:
        st.info("No active AI initiatives are available.")
    else:
        st.dataframe(portfolio, use_container_width=True)


st.set_page_config(layout="wide")
st.title("ReadinessOps")
st.caption("Snowflake Marketplace · Native App")
st.info(
    "Question → Evidence → governed Decision Pack → Human review → Explicit "
    "publication. Evidence changes and AI output cannot approve, publish, or "
    "replace Current state automatically."
)

read_session_granted = False
if permissions is not None:
    try:
        read_session_granted = "READ SESSION" in permissions.get_held_account_privileges(
            ["READ SESSION"]
        )
    except Exception:
        read_session_granted = False

workspace = st.radio(
    "Workspace",
    [
        "Evidence & Decision Pack",
        "Human review",
        "Published records",
        "AI Portfolio",
    ],
    horizontal=True,
)

if workspace == "Evidence & Decision Pack":
    render_evidence_workspace(read_session_granted)
elif workspace == "Human review":
    render_human_review(read_session_granted)
elif workspace == "Published records":
    render_published_records()
else:
    render_portfolio()

st.caption(
    "Approval, rejection, explicit publication, Revision reassessment, and "
    "Current updates remain governed human actions."
)
