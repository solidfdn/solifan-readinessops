# ReadinessOps — Marketplace Native App (R1 validated / R2 in progress)

This package ports the existing ReadinessOps governed workflow into the
Snowflake Native App boundary. It maps existing consumer Evidence into the
existing ReadinessOps model and generates the same four-section Decision Pack.
It is the Native App distribution of the existing product, not a separate
application or data model.

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
- Human editing, approval/rejection, and explicit publication use one normalized
  proposal payload, content version, and SHA-256 hash.
- Stale edit/review requests are rejected; approved content is verified again
  before an atomic four-section publication.
- Published records and AI Portfolio use one complete Decision Pack run and do
  not mix sections from different runs.
- Native App Streamlit without `st.file_uploader`.

## Human control boundary

AI generation and Evidence processing cannot approve their own output, publish
a governed record, or update Current state. Editing, approval/rejection, and
publication are separate explicit human actions. Publication is disabled until
all four displayed content versions have been approved.

## Consumer setup

1. Install the application package or listing.
2. Grant the application roles:
   - `READINESSOPS_USER` for read-only Evidence, Decision Pack, and trace views.
   - `READINESSOPS_REVIEWER` for version-bound edit and review procedures.
   - `READINESSOPS_PUBLISHER` for explicit publication only.
   - `READINESSOPS_ADMIN` for the current Streamlit UI, reference binding, and
     Decision Pack generation. The Admin role inherits the other app roles.
3. Open the app Security tab and explicitly grant `READ SESSION` and
   `SNOWFLAKE.CORTEX_USER`. Neither is granted automatically.
4. In the Admin-only Streamlit app, bind either an existing table or existing
   view. The requested object privilege is `SELECT` only.
5. Enter the source mapping and assessment/initiative context, register the
   Evidence, and generate the four-section Decision Pack.
6. In Human review, edit and approve/reject the displayed content version.
7. After all four sections are approved, use the separate confirmation and
   explicit publication action.

The selected evidence text must be non-empty and no more than 50,000 characters.
The fixed R1 model is `llama3.1-8b`; availability must be confirmed in the
consumer's selected region before this build is treated as operational.

## Remaining release work

- A clean consumer-style install and the remaining negative-path checks are
  still required before Marketplace submission.
- Only one evidence row is imported at a time.
- Table and view references are separate because Native App reference object
  types are explicit.
- No file upload is included because `st.file_uploader` is unsupported in a
  Snowflake Native App Streamlit app.
- Revision reassessment and atomic Current advancement, recovery, export, and
  deletion remain in later release stages. No screen should imply these are
  complete before runtime evidence exists.
- The current Streamlit is Admin-only because Native App Streamlit executes with
  owner's rights. Read-only users can query the granted views but cannot open
  the mutation-capable UI. Review and publish procedures still have separate
  application-role grants.
