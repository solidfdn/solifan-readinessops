# ReadinessOps — Marketplace R1 Native App proof

ReadinessOps turns existing Snowflake evidence into an AI proposal that remains
subject to human review. This package is the R1 technical proof for the
Marketplace release path; it is not the complete customer release.

## What this build proves

- Installation under a consumer-selected application name, without a fixed
  database name in the package.
- Read-only access to one existing consumer table or view through a declared
  Snowflake Native App reference.
- Explicit, minimum access: `SELECT` on the selected object and
  `SNOWFLAKE.CORTEX_USER` for the Cortex call. `READ SESSION` is separately
  requested so the signed-in consumer user can be recorded.
- Snapshot of the selected evidence row, including source key, capture time,
  actor, and SHA-256 content hash.
- One Cortex-generated proposal stored as `REVIEW_REQUIRED`.
- Native App Streamlit without `st.file_uploader`.

## Human control boundary

This R1 package does not contain an approval or publication procedure. Evidence
processing cannot approve its own output, publish a governed record, or update
Current state. The output remains a proposal until later governed workflow
stages add separate human review and explicit publication actions.

## Consumer setup

1. Install the application package or listing.
2. Grant the application roles:
   - `READINESSOPS_USER` for read-only evidence and proposal views.
   - `READINESSOPS_ADMIN` for the R1 Streamlit UI, reference binding, and
     proposal generation. The Admin role inherits the User role.
3. Open the app Security tab and explicitly grant `READ SESSION` and
   `SNOWFLAKE.CORTEX_USER`. Neither is granted automatically.
4. In the Admin-only Streamlit app, bind either an existing table or existing view. The
   requested object privilege is `SELECT` only.
5. Enter the source row key, title column, and evidence text column, then create
   one review-required proposal.

The selected evidence text must be non-empty and no more than 50,000 characters.
The fixed R1 model is `mistral-large2`; availability must be confirmed in the
consumer's selected region before this build is treated as operational.

## R1 limitations

- Snowflake installation and runtime verification are still required.
- Only one evidence row is processed at a time.
- Table and view references are separate because Native App reference object
  types are explicit.
- No file upload is included because `st.file_uploader` is unsupported in a
  Snowflake Native App Streamlit app.
- Approval, rejection, explicit publication, Revision reassessment, Current and
  Portfolio consistency, concurrency protection, recovery, export, and deletion
  are later release stages.
- The R1 Streamlit is Admin-only because Native App Streamlit executes with
  owner's rights. Read-only users can query the two granted views but cannot
  open the mutation-capable R1 UI or call its procedure.
