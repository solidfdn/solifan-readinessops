# Governance Agent — Current Implemented State

## Status

The governed ReadinessOps workflow is implemented, committed to `main`, and
deployed for evaluator use as
`READINESSOPS_REVISION_DEV.APP.READINESSOPS_REVISION_DASHBOARD`.

The earlier baseline remains available as
`READINESSOPS_VALIDATION.APP.READINESSOPS_DASHBOARD`; it does not contain the
complete Revision and changed-Evidence evaluation path.

The earlier `SP_RUN_READINESS_AGENT` direct-write prototype remains in the repository for historical comparison. It is not the governed production path.

## Current Operating Flow

```text
ASSESSMENT_CASE + ASSESSMENT_REVISION
        ↓
ASSESSMENT_RUNS + Questions + Answers + Evidence
        ├─ SP_RUN_FULL_GOVERNANCE_REVIEW
        │      → Gap / Risk / Action drafts
        └─ SP_GENERATE_DECISION_PACK
               → Governance / Value / Routing / Portfolio drafts
                       ↓
               Human review in Streamlit
                       ↓
               APPROVED or REJECTED
                       ↓
               SP_PUBLISH_AGENT_RUN
                       ↓
               READINESS_GAPS / RECOMMENDED_ACTIONS
               / GOVERNED_DECISION_RECORD
                       ↓
               Published / Portfolio / Audit

Draft Revision + ADDED / REPLACED Evidence
        → SP_ANALYZE_REVISION_EVIDENCE_IMPACT
        → Advisory impact result
        → Human reassessment decision
```

## Proposal Types

- `GAP`
- `RISK`
- `ACTION`
- `DECISION_GOVERNANCE`
- `DECISION_VALUE`
- `DECISION_MODEL_ROUTING`
- `DECISION_PORTFOLIO`

## Proposal States

- `REVIEW_REQUIRED`
- `APPROVED`
- `REJECTED`
- `PUBLISHED`

## AI Responsibilities

Cortex:

- Evaluates supplied assessment context
- Generates Gap, Risk, and Action drafts
- Assigns severity, priority, rationale, owner, and target recommendations
- Cannot approve or publish a proposal
- Does not write directly to governed tables in the current flow
- Evaluates only `ADDED` or `REPLACED` Evidence against the four immutable
  published base decisions
- Cannot regenerate, approve, publish, or advance Current State from an impact
  result

## Human Responsibilities

The reviewer:

- Inspects Question, Answer, Evidence, and Rule Context
- Reviews the model rationale
- Approves or rejects each proposal
- Optionally records a Decision comment
- Explicitly publishes approved proposals
- Confirms whether a changed-Evidence impact requires Decision Pack
  reassessment

## Governed Publication

- Approved Gaps publish to `READINESS_GAPS`
- Approved Risks publish to `READINESS_GAPS` with a `[RISK]` title prefix
- Approved Actions publish to `RECOMMENDED_ACTIONS`
- Source Proposal and Agent Run identifiers are retained
- Unresolved and rejected proposals remain outside governed records
- Duplicate publication is prevented

## Streamlit Workspaces

### Value Control Plane

- Initiative and Assessment linkage
- TXT/PDF Evidence upload and original-byte retention
- Current, Draft, and historical Revision states
- Evidence lineage and frozen decision comparison
- changed-Evidence impact analysis with human-confirmation labeling
- four-section Decision Pack, Published records, and Portfolio

### Review queue

- Summary
- Review by issue
- Approved & publish
- Decision, domain, and severity filters
- Gap, Risk, and Action tabs only when relevant
- Back to review queue from an empty publication state

### Published records

- Governed record counts
- One-based list numbering
- One selected record detail
- Source Proposal and Agent Run traceability

### Audit trail

- Latest decision and publication events
- One selected event detail
- Actor, time, status transition, and comment

### Review setup

- Evidence context preview
- Fixed governance instruction
- Optional business instruction
- Cortex proposal generation
- Latest completed review summary

## Effective Assessment Context

The current sample resolves:

- One effective answer per `(RUN_ID, QUESTION_ID)`
- The latest evidence item per `(RUN_ID, QUESTION_ID)`
- `READINESS_QUESTIONS.EXPECTED_EVIDENCE` as Requirement / Rule Context

Production data models may require answer versioning, multiple evidence items, rule versioning, effective dates, and approval of evidence itself.

## Verified Lifecycle

- Full review completed
- 5 Gap, 2 Risk, and 5 Action drafts generated
- Gap approval and publication succeeded
- Risk rejection succeeded without publication
- Action approval and publication succeeded
- Approval and publication history were separate
- Repeated publication did not create duplicate records
- Production app loaded from the Git-tracked source
- Visible lists start at 1
- Empty publication state returns directly to the review queue
- Published Current State remained immutable while Revision 3 stayed Draft
- One changed Evidence item was isolated from inherited Evidence
- Four published decision sections were evaluated in one Cortex call
- Four sections returned `HIGH` impact and `REASSESS`
- Duplicate execution returned `SKIPPED`
- All seven Evidence-impact integrity checks returned zero failures

## Known Constraints

- Fixed model selection
- Synthetic sample assessment
- No dedicated canonical Risk table
- Persistent application history is not storage-level immutable
- No schedule or event trigger
- Production hardening requires RBAC, retention, monitoring, and change-control design
