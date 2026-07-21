# Governance Agent — Implemented State

## Status

The governed Governance Agent Workspace is implemented and validated in `READINESSOPS_VALIDATION.APP`.

The earlier `SP_RUN_READINESS_AGENT` direct-write prototype remains in the repository for historical comparison. The governed implementation uses separate proposal, review, and publication procedures.

## Implemented Governance Objects

| Object | Purpose |
|---|---|
| `GOVERNANCE_AGENT_RUN` | Full governance-review execution record |
| `GOVERNANCE_AGENT_PROPOSAL` | Gap, Risk, and Action proposal lifecycle |
| `GOVERNANCE_AGENT_PROPOSAL_SOURCE` | Source traceability to assessment context |
| `GOVERNANCE_APPROVAL_HISTORY` | Human decision and publication history |
| `SP_RUN_FULL_GOVERNANCE_REVIEW` | Evidence-grounded proposal generation |
| `SP_REVIEW_AGENT_PROPOSAL` | Individual approval or rejection |
| `SP_PUBLISH_AGENT_RUN` | Controlled publication of approved proposals |
| `V_READINESSOPS_ACTION_BOARD` | Canonical dashboard presentation |

## Current Operating Flow

```text
ASSESSMENT_RUNS
  + READINESS_QUESTIONS
  + ASSESSMENT_ANSWERS
  + EVIDENCE_ITEMS
        ↓
SP_RUN_FULL_GOVERNANCE_REVIEW
        ↓
GOVERNANCE_AGENT_RUN
GOVERNANCE_AGENT_PROPOSAL
GOVERNANCE_AGENT_PROPOSAL_SOURCE
        ↓
Human review in Streamlit
        ↓
APPROVED or REJECTED
        ↓
SP_PUBLISH_AGENT_RUN
        ↓
READINESS_GAPS / RECOMMENDED_ACTIONS
        ↓
V_READINESSOPS_ACTION_BOARD
```

## Proposal Types and States

### Types

- `GAP`
- `RISK`
- `ACTION`

### States

- `REVIEW_REQUIRED`
- `APPROVED`
- `REJECTED`
- `PUBLISHED`

## Effective Assessment Context

The current sample model resolves one answer per `(RUN_ID, QUESTION_ID)`. Evidence is joined through the same run and question keys. `READINESS_QUESTIONS.EXPECTED_EVIDENCE` is used as the rule context supplied to the model.

## AI and Human Responsibilities

### Cortex AI

- Evaluates supplied assessment context
- Produces Gap, Risk, and Action drafts
- Assigns severity, priority, rationale, owner, and due-date recommendations
- Does not write directly to canonical governance records in the governed flow

### Human Reviewer

- Inspects source context
- Approves or rejects each proposal
- Adds a review comment
- Controls which approved proposals are published

## Canonical Publication

Approved Gap and Action proposals are published with:

- `SOURCE_PROPOSAL_ID`
- `SOURCE_AGENT_RUN_ID`

Rejected and unreviewed proposals remain outside canonical tables. The current dashboard view excludes legacy `AR_%` direct-write records.

## Streamlit Workspace

The deployed application includes:

- Assessment Run selection
- Questions, Published Gaps, Latest Draft Proposals, and Agent Status metrics
- Latest Governance Review summary
- Standard and additional instruction display
- Full governance review execution
- Explicit Gap/Risk/Action selector
- Source expansion
- Review comments
- Approve and Reject actions
- Approved-item counters
- Controlled publish confirmation
- Agent Run History

The explicit proposal-type selector replaces the earlier tab implementation so the selected type remains stable after Streamlit reruns.

## Validated Result

For agent run `GR_20260720_235320_879`:

- 5 Gap proposals generated
- 2 Risk proposals generated
- 5 Action proposals generated
- 1 Gap approved and published
- 1 Risk rejected
- 1 Action approved and published
- 1 canonical Gap created
- 1 canonical Action created
- Gap and Action each recorded approval and publication events
- Risk recorded one rejection event
- No rejected Risk was published
- No duplicate canonical record was created

## Known Constraints

- The sample data model does not version answers or rules
- Model choice is fixed to `mistral-large2`
- The sample Assessment Run is synthetic
- Production use requires environment-specific RBAC and security policies
- The legacy direct-write prototype remains for comparison but is not the governed path