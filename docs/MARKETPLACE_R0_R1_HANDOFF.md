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
- Kept approval, rejection, publication, Revision reassessment, and Current
  updates outside the R1 surface. Evidence changes cannot trigger them.

## Verification result

- Corrected R1 was upgraded successfully in account `JD45494` as package
  `READINESSOPS_MARKETPLACE_PACKAGE` and application
  `READINESSOPS_MARKETPLACE_DEV`.
- Snowflake setup-script validation passed during `snow app run`. The application
  exposes both application roles, both read-only reference declarations, and
  the four ported read views.
- `READ SESSION` is granted. Both references remain unbound, and the assessment,
  Evidence, Decision Pack, and run-step views correctly return no data before
  the first existing-data import.
- Corrected port: repository tests **33/33 passed**, Native Streamlit compiled,
  `git diff --check` passed, and Snowflake CLI 3.27.0 generated a bundle
  containing both modular SQL files.
- Corrected port is **installed and structurally validated in Snowflake**.
  Existing-data import and Cortex generation are not yet runtime-validated.

## Remaining issues

- Bind an existing ReadinessOps Evidence Table/View; verify one-row import,
  exact four-section generation, attribution, idempotency, revoked-access
  behavior, and upgrade persistence.
- R2 still covers the remaining governed lifecycle and consistency fixes before
  Marketplace submission.

## Next work

1. Confirm which existing ReadinessOps database/table is available in account
   `JD45494`; do not create a synthetic test database.
2. Bind that existing Evidence Table/View and validate one-row import.
3. Generate the exact four-section Decision Pack and retain actual runtime
   results.
