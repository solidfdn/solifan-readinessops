# Hackathon Submission

## Project

**SOLIFAN ReadinessOps — Human-Governed AI Value Control on Snowflake**

## One-Sentence Description

A Snowflake-native control plane that converts TXT/PDF evidence into a four-section AI Decision Pack, requires accountable human review and explicit publication, and preserves governed records, portfolio signals, and audit history.

## Problem

Organizations can generate AI recommendations quickly, but they still struggle to answer:

- What evidence supported the recommendation?
- Who approved it?
- Was value considered alongside governance and model routing?
- Which output became the official record?
- How does the initiative compare with the rest of the portfolio?

Without those controls, generated text can silently become operational truth.

## Solution

ReadinessOps separates analysis from authority:

1. Create or link an AI Initiative to an Assessment Run.
2. Upload TXT or PDF evidence.
3. Retain the original file in a Snowflake stage and parse PDF content with Cortex document intelligence.
4. Generate exactly four Decision Pack drafts: Governance, Value, Model Routing, and Portfolio.
5. Validate the output structure, priority, and source evidence IDs.
6. Let a person inspect, edit, approve, or reject each section.
7. Publish only approved sections after explicit confirmation.
8. Preserve Governed Decision Records and approval/publication history.
9. Present initiative-level recommendations in a portfolio view.

The existing Gap, Risk, and Action governance workflow remains available and unchanged in behavior.

## Application Screenshots

### Retained TXT/PDF Evidence

![Retained TXT and PDF evidence](../assets/screenshots/app_ss_01.png)

### Strict Four-Section Decision Pack

![Strict four-section Decision Pack](../assets/screenshots/app_ss_02.png)

### Human Decision and Publication Audit

![Human decision and publication audit history](../assets/screenshots/app_ss_03.png)

## Evaluation Criteria Mapping

### Technical Implementation — 40%

| Aspect | Implementation |
|---|---|
| Snowflake-native workflow | Data, stages, parsing, inference, procedures, Streamlit, views, and history remain in Snowflake |
| Cortex generation | `SNOWFLAKE.CORTEX.COMPLETE('mistral-large2', ...)` |
| PDF intelligence | `AI_PARSE_DOCUMENT` extracts PDF evidence text |
| Original-file retention | TXT and PDF files stored in `READINESSOPS_EVIDENCE_STAGE` |
| Strict structured output | Exactly four required Decision Pack objects with field and type validation |
| Evidence grounding | Every section must cite non-empty evidence IDs belonging to the selected Run |
| Proposal isolation | Every AI result begins as `REVIEW_REQUIRED` |
| Human decision | Per-section edit, approval/rejection, actor, time, and comment |
| Controlled publication | `SP_PUBLISH_AGENT_RUN` publishes only approved proposals |
| Idempotency | Duplicate canonical writes and publication history are prevented |
| Portfolio | `V_AI_PORTFOLIO` summarizes initiative governance, value, recommendation, and priority |
| Runtime | Streamlit pinned to `1.35.0`; deployment uploads all required source files |

### Real-World Relevance — 30%

- **Users:** CCoE teams, AI governance leads, risk managers, program owners, internal audit, and executive sponsors
- **Decision boundary:** AI proposes; accountable people decide
- **Evidence value:** Original artifacts, extracted text, hashes, and source links remain inspectable
- **Investment value:** Governance, value, routing, and portfolio implications are reviewed together
- **Operational value:** Approved decisions become governed records rather than disconnected reports
- **Portfolio value:** Initiatives can be compared by stage, risk posture, expected value, and recommendation
- **Integration value:** Snowflake records can feed BI, reporting, and downstream governed workflows

### Completeness — 30%

| Component | Status |
|---|---|
| AI Initiative model and Assessment link | Complete |
| TXT evidence upload | Complete |
| PDF upload and Cortex parsing | Complete |
| Original-file stage retention | Complete |
| Four-section Decision Pack | Complete |
| Strict schema and evidence-ID validation | Complete |
| Human edit, approval, and rejection | Complete |
| Explicit controlled publication | Complete |
| Governed Decision Records | Complete |
| Portfolio workspace | Complete |
| Audit history | Complete |
| Legacy Gap/Risk/Action preservation | Complete |
| Production Streamlit deployment | Complete |
| Isolated E2E validation | Complete |

## Technical Control Boundary

```text
Evidence Supplied
→ AI Drafted
→ Human Reviewed
→ Explicitly Published
→ Governed Record
```

The AI cannot approve its own proposal or bypass the publication confirmation.

## Verified Results

The isolated `RUN_FINALIST_E2E_001` test confirmed:

| Test | Result |
|---|---|
| TXT evidence upload and stage retention | Passed |
| PDF upload, stage retention, and parsing | Passed |
| Exactly four Decision Pack sections | Passed |
| Four human approvals | Passed |
| Four explicit publications | Passed |
| Eight approval/publication audit events | Passed |
| Four Governed Decision Records | Passed |
| Portfolio view | Passed |
| Evidence citation validation | Passed |
| Duplicate publication prevention | Passed |
| Proposal leakage into `RUN_001` | 0 |
| Existing `RUN_001` retained | Passed |
| Production dashboard deployment | Passed |

## Safety and Compatibility

The finalist migration extends the existing publication procedure only for `DECISION_*` proposal types. Existing Gap, Risk, and Action mappings and audit deduplication remain functionally unchanged. The E2E test used a dedicated Run and did not modify `RUN_001`.

## Built With CoCo CLI

The implementation workflow included live Snowflake inspection, SQL and Streamlit development, Cortex output testing, runtime diagnosis, isolated E2E validation, production deployment, Git review, and documentation synchronization.

## Why It Matters

ReadinessOps turns enterprise AI governance from a periodic assessment into an operating control plane. It makes evidence, value, model routing, human accountability, publication authority, portfolio context, and audit history part of one Snowflake-native workflow.
