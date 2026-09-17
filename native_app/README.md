# ReadinessOps — Marketplace R1 Native App

This package ports the existing ReadinessOps governed workflow into the
Snowflake Native App boundary. It maps existing consumer Evidence into the
existing ReadinessOps model and generates the same four-section Decision Pack.
It is an R1 technical milestone, not a separate application or data model.

## What this build proves

- Installation under a consumer-selected application name, without a fixed
  database name in the package.
- Read-only access to one existing consumer table or view through a declared
  Snowflake Native App reference.
- Explicit, minimum access: `SELECT` on the selected object and
  `SNOWFLAKE.CORTEX_USER` for the Cortex call. `READ SESSION` is separately
  requested so the signed-in consumer user can be recorded.
- Registration of the selected row in the existing `AI_INITIATIVE`,
  `ASSESSMENT_RUNS`, and `EVIDENCE_ITEMS` model, with source identity, actor,
  and SHA-256 content hash.
- One Cortex call producing the existing Governance, Value Realization, Model
  Routing, and Portfolio Decision Pack sections.
- Four proposals stored in `GOVERNANCE_AGENT_PROPOSAL` as `REVIEW_REQUIRED`,
  with evidence citations and run-step history.
- Native App Streamlit without `st.file_uploader`.

## Human control boundary

This R1 package does not expose approval or publication actions. Evidence
processing cannot approve its own output, publish a governed record, or update
Current state. The generated Decision Pack remains in the existing human review
queue for later governed workflow stages.

## Consumer setup

1. Install the application package or listing.
2. Grant the application roles:
   - `READINESSOPS_USER` for read-only Evidence, Decision Pack, and trace views.
   - `READINESSOPS_ADMIN` for the R1 Streamlit UI, reference binding, and
     Decision Pack generation. The Admin role inherits the User role.
3. Open the app Security tab and explicitly grant `READ SESSION` and
   `SNOWFLAKE.CORTEX_USER`. Neither is granted automatically.
4. In the Admin-only Streamlit app, bind either an existing table or existing
   view. The requested object privilege is `SELECT` only.
5. Enter the source mapping and assessment/initiative context, register the
   Evidence, then generate the four-section Decision Pack.

The selected evidence text must be non-empty and no more than 50,000 characters.
The fixed R1 model is `mistral-large2`; availability must be confirmed in the
consumer's selected region before this build is treated as operational.

## R1 limitations

- Snowflake upgrade and runtime verification are still required for this port.
- Only one evidence row is imported at a time.
- Table and view references are separate because Native App reference object
  types are explicit.
- No file upload is included because `st.file_uploader` is unsupported in a
  Snowflake Native App Streamlit app.
- Approval, rejection, explicit publication, Revision reassessment, Current and
  Portfolio consistency, concurrency protection, recovery, export, and deletion
  remain outside the R1 Native App surface and are addressed in later release
  stages.
- The R1 Streamlit is Admin-only because Native App Streamlit executes with
  owner's rights. Read-only users can query the granted views but cannot open
  the mutation-capable R1 UI or call its procedures.
