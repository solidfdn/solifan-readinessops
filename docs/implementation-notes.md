# Implementation Notes

## Scope

This document records the principal implementation and validation decisions for both the original readiness-gap prototype and the governed Governance Agent Workspace.

## Original Prototype Findings

### Cortex COMPLETE May Return Markdown Fences

Even when instructed to return raw JSON, model output can contain markdown fences.

**Resolution:** Strip optional fences before parsing and use `TRY_PARSE_JSON`.

### Safe Casting from VARIANT

`TRY_CAST` does not accept every direct VARIANT-to-number conversion.

**Resolution:** Convert JSON values to `VARCHAR` before numeric `TRY_CAST`.

### Transaction Boundaries

Cleanup performed before a transaction cannot be restored by rollback.

**Resolution:** Keep destructive legacy-prototype cleanup inside a transaction. The governed flow avoids deleting prior canonical output during proposal generation.

### Action-to-Gap Integrity

A loose join can create an action with no valid linked gap.

**Resolution:** Use validated join conditions and publish source identifiers.

## Governance Workspace Implementation

### Proposal Isolation

AI-generated results are written to `GOVERNANCE_AGENT_PROPOSAL` as `REVIEW_REQUIRED`, not to canonical tables.

### Evidence Traceability

`GOVERNANCE_AGENT_PROPOSAL_SOURCE` stores the source Question, Answer, Evidence, and Rule context used to support each proposal.

### Human Review Procedure

`SP_REVIEW_AGENT_PROPOSAL`:

- Updates one proposal
- Accepts `APPROVE` or `REJECT`
- Stores review comment, reviewer, and time
- Appends a decision event to `GOVERNANCE_APPROVAL_HISTORY`

### Controlled Publication

`SP_PUBLISH_AGENT_RUN`:

- Selects approved proposals only
- Publishes canonical Gap and Action records
- Sets source proposal and agent-run IDs
- Changes proposal state to `PUBLISHED`
- Records publication history
- Prevents duplicate publication

### Priority Normalization

The model occasionally returned a 1–5 priority scale despite the requested 1–100 format.

**Resolution:**

- Prompt output values were constrained to `60|70|80|90|95`
- Procedure logic maps 1–5 to 60–95 when needed
- Other numeric output is bounded safely

### Stored Procedure Portability

`USE SCHEMA` inside the SQL stored procedures caused an unsupported-statement error in execution.

**Resolution:** Remove session-context statements from procedure bodies and deploy procedures in the target schema.

### Streamlit Rerun Compatibility

The deployed Streamlit runtime did not expose `st.rerun`.

**Resolution:** Add a compatibility helper that uses `st.rerun` when available and otherwise calls `st.experimental_rerun`.

### Encoding and Status Labels

A Windows edit introduced malformed characters into the status-label mapping.

**Resolution:** Replace decorative symbols with ASCII status labels:

- `[DRAFT]`
- `[APPROVED]`
- `[REJECTED]`
- `[PUBLISHED]`

### Proposal-Type Review Safety

The original tab interface returned to the Gap tab after Streamlit reruns. This created a risk that a reviewer could believe they were acting on a Risk while actually submitting an action against a Gap.

**Resolution:**

- Replace tabs with a stateful radio selector
- Use one explicit proposal type at a time
- Preserve selection through reruns
- Show a completion message after review
- Validate comments and status by proposal type

## Final Validation

A controlled UI and SQL test validated the complete lifecycle:

| Proposal Type | Decision | Final State | Canonical Result | History |
|---|---|---|---:|---:|
| Gap | Approve, then publish | `PUBLISHED` | 1 Gap | 2 |
| Risk | Reject | `REJECTED` | 0 | 1 |
| Action | Approve, then publish | `PUBLISHED` | 1 Action | 2 |

Additional validation:

- Latest Draft Proposals changed 12 → 11 → 10 → 9
- Proposal-type selection remained stable after each rerun
- Success messages appeared after review actions
- Review comments stayed attached to the correct proposal
- Published Gap and Action carried source agent-run and proposal IDs
- Rejected Risk had no published entity ID
- Repeat publication did not create duplicate canonical records
- Dashboard view excluded legacy `AR_%` records

## Environment

- Database: `READINESSOPS_VALIDATION`
- Schema: `APP`
- Streamlit app: `READINESSOPS_DASHBOARD`
- Model: `mistral-large2`
- Demonstrated agent run: `GR_20260720_235320_879`