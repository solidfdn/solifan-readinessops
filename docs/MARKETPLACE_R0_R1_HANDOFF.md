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

- Earlier R1 shell was installed in account `JD45494` as package
  `READINESSOPS_MARKETPLACE_PACKAGE` and application
  `READINESSOPS_MARKETPLACE_DEV`.
- That installation verified application creation, both application roles,
  both reference declarations, callback/procedure grants, and the declared
  `READ SESSION` privilege. References were unbound and no runtime data existed.
- Corrected port: repository tests **33/33 passed**, Native Streamlit compiled,
  `git diff --check` passed, and Snowflake CLI 3.27.0 generated a bundle
  containing both modular SQL files.
- Corrected port is **not yet upgraded or runtime-validated in Snowflake**.

## Remaining issues

- Upgrade the existing development application and validate setup-script SQL on
  Snowflake.
- Bind an existing ReadinessOps Evidence Table/View; verify one-row import,
  exact four-section generation, attribution, idempotency, revoked-access
  behavior, and upgrade persistence.
- R2 still covers the remaining governed lifecycle and consistency fixes before
  Marketplace submission.

## Next work

1. Push the corrected R1 port to the current feature branch.
2. Upgrade `READINESSOPS_MARKETPLACE_DEV` from that branch.
3. Run `scripts/native_app_r1_validation.sql` and retain actual runtime results.
