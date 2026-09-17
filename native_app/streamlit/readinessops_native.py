"""ReadinessOps Marketplace Native App.

This is the Native App surface for the existing ReadinessOps governed workflow.
R1 imports one consumer-owned Evidence row and runs the existing four-section
Decision Pack. AI output remains REVIEW_REQUIRED; approval and publication are
not exposed by this R1 surface.
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


st.set_page_config(layout="wide")
st.title("ReadinessOps")
st.caption("Snowflake Marketplace · Native App")
st.info(
    "Evidence is evaluated through the existing four-section Decision Pack. "
    "AI output is saved as REVIEW_REQUIRED and cannot approve or publish itself."
)

st.subheader("1. Connect existing Snowflake Evidence")
st.write(
    "Select an existing consumer Table or View that is already populated by the "
    "consumer's normal workflow. ReadinessOps requests SELECT only."
)

read_session_granted = False
if permissions is not None:
    try:
        read_session_granted = "READ SESSION" in permissions.get_held_account_privileges(
            ["READ SESSION"]
        )
    except Exception:
        read_session_granted = False

if read_session_granted:
    st.success("Operator attribution is enabled.")
elif permissions is None:
    st.error("Snowflake Permission SDK is unavailable.")
elif st.button("Grant operator attribution", key="request_read_session"):
    permissions.request_account_privileges(["READ SESSION"])

table_refs = reference_associations("EVIDENCE_SOURCE_TABLE")
view_refs = reference_associations("EVIDENCE_SOURCE_VIEW")

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
        help="Use the same stable ID when adding more Evidence to this assessment.",
    )
    run_name = st.text_input("Assessment name", placeholder="AI initiative assessment")
    organization_name = st.text_input(
        "Organization name",
        placeholder="Customer organization",
    )
    assessment_scope = st.text_area(
        "Assessment scope",
        placeholder="Decision scope and operating boundary",
    )
with context_right:
    initiative_id = st.text_input(
        "AI initiative ID",
        placeholder="INIT_CUSTOMER_001",
        help="Use the existing stable ReadinessOps Initiative ID.",
    )
    initiative_name = st.text_input(
        "AI initiative name",
        placeholder="Customer AI initiative",
    )
    initiative_description = st.text_area(
        "Initiative description",
        placeholder="What the initiative is intended to do",
    )
    business_outcome = st.text_area(
        "Business outcome",
        placeholder="Expected measurable outcome",
    )

mapping_left, mapping_right = st.columns(2)
with mapping_left:
    source_kind = st.radio(
        "Bound source type",
        ["TABLE", "VIEW"],
        horizontal=True,
        key="source_kind",
    )
    source_key_column = st.text_input(
        "Unique row key column",
        placeholder="EVIDENCE_ID",
    )
    source_key_value = st.text_input(
        "Row key value",
        placeholder="EV-001",
    )
with mapping_right:
    title_column = st.text_input(
        "Evidence title column",
        placeholder="EVIDENCE_TITLE",
    )
    text_column = st.text_input(
        "Evidence text column",
        placeholder="EVIDENCE_TEXT",
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
        st.error(f"Bind an existing {source_kind.lower()} before registering Evidence.")
    elif not all(value.strip() for value in required_values):
        st.error("Complete the source mapping and assessment context.")
    else:
        with st.spinner("Registering Evidence in ReadinessOps..."):
            try:
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
            except Exception as exc:
                st.error(f"Evidence registration failed: {exc}")
            else:
                if result.get("status") in {"IMPORTED", "SKIPPED"}:
                    st.session_state["active_run_id"] = result.get(
                        "assessment_run_id"
                    )
                    st.success(result.get("status"))
                else:
                    st.error(result.get("error", "Evidence registration failed."))
                st.json(result)

st.subheader("3. Generate the existing four-section Decision Pack")

try:
    runs = query(
        "SELECT RUN_ID, RUN_NAME, ORGANIZATION_NAME, INITIATIVE_NAME, STATUS, "
        "CREATED_AT FROM APP_CODE.V_ASSESSMENT_CONTEXT ORDER BY CREATED_AT DESC"
    )
except Exception as exc:
    st.error(f"Could not load Assessment Runs: {exc}")
    runs = pd.DataFrame()

selected_run_id = None
if runs.empty:
    st.info("Register Evidence to create the first Assessment Run.")
else:
    run_records = runs.to_dict("records")
    labels = {
        row["RUN_ID"]: (
            f"{row['RUN_NAME']} · {row['ORGANIZATION_NAME']} · "
            f"{row['INITIATIVE_NAME']}"
        )
        for row in run_records
    }
    run_ids = list(labels)
    preferred = st.session_state.get("active_run_id")
    default_index = run_ids.index(preferred) if preferred in run_ids else 0
    selected_run_id = st.selectbox(
        "Assessment Run",
        run_ids,
        index=default_index,
        format_func=lambda value: labels[value],
    )
    additional_instruction = st.text_area(
        "Additional instruction (optional)",
        placeholder="Keep blank unless a human reviewer adds a specific instruction.",
    )

    if st.button(
        "Generate Decision Pack",
        type="primary",
        disabled=not read_session_granted,
    ):
        if not read_session_granted:
            st.error("Grant READ SESSION before generating a Decision Pack.")
        else:
            with st.spinner(
                "Generating Governance, Value, Routing, and Portfolio drafts..."
            ):
                try:
                    result = call_json(
                        "CALL APP_CODE.SP_GENERATE_DECISION_PACK(?, ?)",
                        [selected_run_id, additional_instruction or None],
                    )
                except Exception as exc:
                    st.error(f"Decision Pack generation failed: {exc}")
                else:
                    if result.get("status") in {"COMPLETED", "SKIPPED"}:
                        st.success(result.get("status"))
                    else:
                        st.error(
                            result.get("error", "Decision Pack generation failed.")
                        )
                    st.json(result)

st.subheader("4. Human review queue")
if selected_run_id:
    try:
        proposals = query(
            "SELECT PROPOSAL_ID, AGENT_RUN_ID, PROPOSAL_TYPE, TITLE, "
            "DESCRIPTION, SEVERITY, PRIORITY, STATUS, PROPOSAL_PAYLOAD, "
            "CREATED_AT FROM APP_CODE.V_DECISION_PACK_REVIEW "
            "WHERE ASSESSMENT_RUN_ID = ? ORDER BY CREATED_AT DESC, PROPOSAL_TYPE",
            [selected_run_id],
        )
    except Exception as exc:
        st.error(f"Could not load Decision Pack proposals: {exc}")
    else:
        if proposals.empty:
            st.info("No Decision Pack has been generated for this Assessment Run.")
        else:
            st.dataframe(proposals, use_container_width=True)

    with st.expander("Evidence and execution trace"):
        try:
            evidence = query(
                "SELECT EVIDENCE_ID, EVIDENCE_TITLE, EVIDENCE_STATUS, "
                "SOURCE_TYPE, CONTENT_SHA256, CREATED_AT "
                "FROM APP_CODE.V_EVIDENCE_ITEMS WHERE RUN_ID = ? "
                "ORDER BY CREATED_AT DESC",
                [selected_run_id],
            )
            st.markdown("**Evidence**")
            st.dataframe(evidence, use_container_width=True)

            steps = query(
                "SELECT s.AGENT_RUN_ID, s.STEP_SEQUENCE, s.STEP_CODE, "
                "s.STEP_NAME, s.STATUS, s.DURATION_MS, s.ERROR_MESSAGE "
                "FROM APP_CODE.V_AGENT_RUN_STEP s "
                "WHERE s.ASSESSMENT_RUN_ID = ? "
                "ORDER BY s.AGENT_RUN_ID DESC, s.STEP_SEQUENCE",
                [selected_run_id],
            )
            st.markdown("**Execution trace**")
            st.dataframe(steps, use_container_width=True)
        except Exception as exc:
            st.error(f"Could not load Evidence or execution trace: {exc}")

st.caption(
    "Approval, rejection, explicit publication, Revision reassessment, and "
    "Current updates remain separate governed human actions. They are not "
    "performed automatically from Evidence changes or AI output."
)
