# Marketplace release handoff — R0 / R1

Updated: 2026-09-17
Baseline: `a818f954b2f54cb4b86fc6c3fd8d5a6e01d7e51b`

## Complete

- R0: confirmed the agreed baseline and found no newer `main` difference at
  implementation start.
- R1 package/install shell: added `snowflake.yml`, manifest, setup, application
  roles, Table/View references, and an Admin-only Native App Streamlit.
- Corrected the initial generic proof so R1 now uses the existing ReadinessOps
  `AI_INITIATIVE`, `ASSESSMENT_RUNS`, `EVIDENCE_ITEMS`, and
  `GOVERNANCE_AGENT_*` model. It does not create a second proposal model.
- Ported the existing `SP_GENERATE_DECISION_PACK` contract: one Cortex call,
  exact Governance/Value/Model Routing/Portfolio sections, evidence citations,
  five run steps, idempotency, and four `REVIEW_REQUIRED` proposals.
- Added a Native App reference adapter that imports one existing consumer row
  into the existing Evidence model. No synthetic customer database or fixture
  is included.
- Fixed two Snowflake runtime differences found by the real reference import:
  reference rows are materialized before filtering, and computed Evidence
  values are materialized before the `VALUES` clause.
- Replaced legacy `mistral-large2` in the Native App Decision Pack path with
  Tokyo-native, non-legacy `llama3.1-8b`; the model name is defined once and
  reused by inference and trace records.
- Kept approval, rejection, publication, Revision reassessment, and Current
  updates outside the R1 surface. Evidence changes cannot trigger them.

## Verification result

- Corrected R1 was upgraded successfully in account `JD45494` as package
  `READINESSOPS_MARKETPLACE_PACKAGE` and application
  `READINESSOPS_MARKETPLACE_DEV`.
- Snowflake setup-script validation passed during `snow app run`. The application
  exposes both application roles, both read-only reference declarations, and
  the four ported read views.
- `READ SESSION` and `SNOWFLAKE.CORTEX_USER` are granted. The Table reference is
  bound read-only to the existing
  `READINESSOPS_REVISION_DEV.APP.EVIDENCE_ITEMS`; the View reference remains
  unbound.
- Existing Evidence `EV_TXT_20260819_011009_8d13365a` was imported successfully
  as `EV_148c4baa80542cac1ecfea272d9ba415` for Assessment
  `RUN_REV_7ed6c4d12bb44e5eab0629f6108c44c3` and Initiative
  `INIT_AA5523768A0F49D5`. The source was only read with `SELECT`.
- Decision Pack run `DP_20260917_051714_215` completed with one Cortex call,
  four proposals, and five run steps. All four proposals are
  `REVIEW_REQUIRED`; all five steps are `COMPLETED` with no error.
- Evidence persisted through a subsequent Native App upgrade and was then used
  by the successful Decision Pack run.
- Repository tests **35/35 passed** and `git diff --check` passed after the
  runtime fixes.
- Corrected R1 is **installed and core-runtime validated in Snowflake**. No
  approval, publication, governed Current update, or Marketplace publication
  was performed.

## Remaining issues

- Verify operator attribution values, repeated-import and repeated-generation
  idempotency, revoked-reference behavior, and the Admin-only Streamlit flow.
- Validate a clean consumer-style install and role assignment before the
  Marketplace submission gate.
- R2 still covers the remaining governed lifecycle and consistency fixes before
  Marketplace submission.

## Next work

1. Verify attribution and idempotency against the successful R1 records.
2. Verify revoked-reference failure and the Admin-only Streamlit workflow.
3. Proceed to the next agreed release-plan gate without publishing or changing
   governed state automatically.
