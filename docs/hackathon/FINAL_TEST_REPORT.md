# Final Test Report

Date: 2026-08-17

## Scope

Finalist Value Control Plane validation was performed with isolated Assessment Run `RUN_FINALIST_E2E_001`. Existing `RUN_001` data and legacy Gap, Risk, and Action publication behavior were protected.

## Deployment

| Check | Result |
|---|---|
| Production Streamlit object | `READINESSOPS_VALIDATION.APP.READINESSOPS_DASHBOARD` |
| Streamlit runtime | `1.35.0` |
| `environment.yml` uploaded | PASS |
| `value_control_plane.py` uploaded | PASS |
| `streamlit_app.py` uploaded | PASS |
| Production Streamlit recreation | PASS |

## Data Model and Procedures

| Component | Result |
|---|---|
| `AI_INITIATIVE` | PASS |
| `ASSESSMENT_RUNS.INITIATIVE_ID` | PASS |
| Extended `EVIDENCE_ITEMS` metadata | PASS |
| `READINESSOPS_EVIDENCE_STAGE` | PASS |
| `GOVERNED_DECISION_RECORD` | PASS |
| `SP_GENERATE_DECISION_PACK` | PASS |
| `SP_EDIT_AGENT_PROPOSAL` | PASS |
| Extended `SP_PUBLISH_AGENT_RUN` | PASS |
| `V_AI_PORTFOLIO` | PASS |

The idempotent finalist migration executed successfully. Existing Gap, Risk, and Action branches remained functionally unchanged.

## Evidence Tests

| Test | Result |
|---|---|
| TXT upload and UTF-8 validation | PASS |
| TXT original-file stage retention | PASS |
| PDF upload | PASS |
| PDF original-file stage retention | PASS |
| PDF parsing with `AI_PARSE_DOCUMENT` | PASS |
| SHA-256 and metadata persistence | PASS |
| Stage path persistence | PASS |
| Duplicate detection | PASS |

Verified PDF example:

- file: `readinessops_pdf_e2e.pdf`
- extracted text: 425 characters
- pages: 1
- parser: `AI_PARSE_DOCUMENT`

## Decision Pack Tests

| Test | Result |
|---|---|
| Cortex generation completed | PASS |
| Exactly four required sections | PASS |
| Required field/type validation | PASS |
| Priority range validation | PASS |
| Non-empty source evidence IDs | PASS |
| Evidence IDs belong to selected Run | PASS |
| Per-section source links | PASS |
| Draft state starts as `REVIEW_REQUIRED` | PASS |

Validated sections:

1. Governance
2. Value
3. Model Routing
4. Portfolio

## Human Decision and Publication

| Check | Result |
|---|---:|
| E2E proposals | 4 |
| Human approvals | 4 |
| Explicit publications | 4 |
| Governed Decision Records | 4 |
| APPROVE + PUBLISH audit events | 8 |

Confirmed:

- approval did not publish automatically
- publication required explicit confirmation
- published records retained proposal and Agent Run traceability
- duplicate publication was prevented
- approval and publication events recorded actor and timestamp separately

## Isolation and Regression Safety

| Check | Result |
|---|---:|
| `RUN_001` present | 1 |
| E2E proposal leakage into `RUN_001` | 0 |
| E2E proposals linked to `RUN_FINALIST_E2E_001` | 4 |
| E2E audit events | 8 |
| E2E evidence present | PASS |
| Existing Gap publication mapping | Preserved |
| Existing Risk publication mapping | Preserved |
| Existing Action publication mapping | Preserved |

## UI Tests

- Initiative create/select/link: PASS
- TXT/PDF Evidence list and metadata: PASS
- Decision Pack generation: PASS
- per-section review and approval: PASS
- explicit Publish gate: PASS
- Published Governed Decision Records: PASS
- Portfolio view: PASS
- Audit list and detail: PASS
- production display: PASS

## Acceptance Result

**PASS.** The finalist build completed the isolated path from AI Initiative and retained TXT/PDF evidence through strict Decision Pack generation, human approval, explicit publication, portfolio presentation, and audit history without proposal leakage into `RUN_001`.

## Operational Note

Live counts and Agent Run IDs change when the workflow is repeated. Stable acceptance criteria are the state transitions, evidence provenance, strict output contract, human authority boundary, idempotency, audit attribution, and Run isolation.
