"""ReadinessOps Marketplace R1 Native App proof UI.

The R1 surface proves read-only consumer data access and proposal generation.
It deliberately exposes no approve or publish action.
"""

import json

import pandas as pd
import streamlit as st
from snowflake.snowpark.context import get_active_session

try:
    import snowflake.permissions as permissions
except ImportError:  # Visible failure is safer than silently bypassing consent.
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


st.title("ReadinessOps")
st.caption("Marketplace R1 · Consumer data reference and Cortex proof")
st.info(
    "AI output is saved only as REVIEW_REQUIRED. This R1 build cannot approve, "
    "publish, or update a governed Current state."
)

st.subheader("1. Grant minimum access")
st.write(
    "Bind either an existing table or an existing view that is already populated "
    "by your normal Snowflake workflow. ReadinessOps requests SELECT only."
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
    st.success("READ SESSION is granted for accountable operator attribution.")
elif permissions is None:
    st.error("Snowflake Permission SDK is unavailable.")
elif st.button("Grant operator attribution", key="request_read_session"):
    permissions.request_account_privileges(["READ SESSION"])

st.caption(
    "READ SESSION is used only to record the signed-in Snowflake user on evidence "
    "and proposal events. The app does not grant this permission automatically."
)

table_refs = reference_associations("EVIDENCE_SOURCE_TABLE")
view_refs = reference_associations("EVIDENCE_SOURCE_VIEW")

left, right = st.columns(2)
with left:
    st.markdown("**Existing table**")
    if table_refs:
        st.success("Table reference is bound.")
        st.dataframe(pd.DataFrame(table_refs), use_container_width=True)
    elif permissions is None:
        st.error("Snowflake Permission SDK is unavailable.")
    elif st.button(
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
    elif permissions is None:
        st.error("Snowflake Permission SDK is unavailable.")
    elif st.button(
        "Choose view",
        key="request_view_reference",
        disabled=not read_session_granted,
    ):
        permissions.request_reference("EVIDENCE_SOURCE_VIEW")

st.caption(
    "Cortex also requires the SNOWFLAKE.CORTEX_USER role declared by this app. "
    "Review and grant it from the installed app's Security tab."
)

st.subheader("2. Map one existing evidence row")
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
title_column = st.text_input(
    "Title column",
    placeholder="EVIDENCE_TITLE",
)
text_column = st.text_input(
    "Evidence text column",
    placeholder="EVIDENCE_TEXT",
)

if st.button("Create review-required proposal", type="primary"):
    expected_reference = table_refs if source_kind == "TABLE" else view_refs
    if not read_session_granted:
        st.error("Grant READ SESSION before processing data so the actor is recorded.")
    elif not expected_reference:
        st.error(f"Bind an existing {source_kind.lower()} before processing data.")
    elif not all(
        value.strip()
        for value in (
            source_key_column,
            source_key_value,
            title_column,
            text_column,
        )
    ):
        st.error("Complete the row key and column mapping fields.")
    else:
        with st.spinner("Reading one row and generating a proposal..."):
            try:
                result = call_json(
                    "CALL APP_CODE.SP_IMPORT_AND_PROPOSE_ONE(?, ?, ?, ?, ?)",
                    [
                        source_kind,
                        source_key_column,
                        source_key_value,
                        title_column,
                        text_column,
                    ],
                )
            except Exception as exc:
                st.error(f"Processing failed: {exc}")
            else:
                if result.get("status") in {"REVIEW_REQUIRED", "SKIPPED"}:
                    st.success(result.get("status"))
                else:
                    st.error(result.get("error", "Processing failed."))
                st.json(result)

st.subheader("3. Review queue")
try:
    proposals = query(
        "SELECT PROPOSAL_ID, EVIDENCE_ID, PROPOSAL_TYPE, PROPOSAL_TEXT, "
        "STATUS, MODEL_NAME, PROMPT_VERSION, CREATED_AT, CREATED_BY "
        "FROM APP_CODE.V_REVIEW_REQUIRED_PROPOSAL ORDER BY CREATED_AT DESC"
    )
except Exception as exc:
    st.error(f"Could not load review-required proposals: {exc}")
else:
    if proposals.empty:
        st.info("No review-required proposal has been created in this app installation.")
    else:
        st.dataframe(proposals, use_container_width=True)

st.caption(
    "Approval, rejection, explicit publication, Revision reassessment, and Current "
    "updates remain outside the R1 proof and will be added only through governed "
    "human actions in the next release stage."
)
