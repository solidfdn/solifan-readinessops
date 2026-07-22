# Implementation Notes

## Scope

This document records the implementation decisions and validated behavior of the governed ReadinessOps workflow. The earlier direct-write prototype remains in files `04`–`07` for historical comparison only.

## Governed Data Flow

```text
Assessment context
→ Cortex draft generation
→ REVIEW_REQUIRED proposal
→ Human APPROVED or REJECTED
→ Explicit publication
→ Governed record
```

## Model Output Handling

### Markdown fences

Cortex can return markdown fences even when JSON-only output is requested.

**Resolution:** remove optional fences before `TRY_PARSE_JSON`.

### Defensive casting

Direct `VARIANT`-to-number conversion is not reliable for every model response.

**Resolution:** convert candidate values to `VARCHAR`, then apply numeric conversion and bounds.

### Priority normalization

The model may return a 1–5 scale even when a 1–100 range is requested.

**Resolution:**

- Prompt values are constrained to `60`, `70`, `80`, `90`, or `95`
- Procedure logic maps 1–5 to the governed range
- Other values are bounded defensively

### Failure behavior

Invalid model output must not create partial governed records.

**Resolution:** mark the Agent Run `FAILED`, retain the error, and keep the latest completed review visible in the app.

## Proposal Isolation and Traceability

### Proposal isolation

All AI results enter `GOVERNANCE_AGENT_PROPOSAL` as `REVIEW_REQUIRED`. Proposal generation does not write new rows to `READINESS_GAPS` or `RECOMMENDED_ACTIONS`.

### Source traceability

`GOVERNANCE_AGENT_PROPOSAL_SOURCE` preserves:

- Question
- Answer
- Evidence item
- Requirement / Rule Context
- Source summary
- Agent Run

## Human Decision

`SP_REVIEW_AGENT_PROPOSAL`:

- Accepts `APPROVE` or `REJECT`
- Updates exactly one proposal
- Records reviewer, time, and optional comment
- Appends a decision event
- Does not publish the proposal

## Controlled Publication

`SP_PUBLISH_AGENT_RUN`:

- Freezes approved proposals at the beginning of the call
- Publishes only `APPROVED` proposals
- Writes Gap and normalized Risk records to `READINESS_GAPS`
- Writes Actions to `RECOMMENDED_ACTIONS`
- Preserves Source Proposal and Agent Run identifiers
- Changes proposal state to `PUBLISHED`
- Appends one publication event per proposal
- Prevents duplicate governed writes and duplicate publication history

## Risk Normalization

The current canonical schema has no dedicated Risk table. Approved Risks are published to `READINESS_GAPS` with a `[RISK]` prefix. The application derives the displayed record type from the source proposal.

This is an explicit demonstration constraint, not a claim that Gap and Risk are the same enterprise object.

## Streamlit Decisions

### Issue-based review

The first review UI repeated evidence context for every proposal and produced an excessively long page.

**Resolution:**

- Add a proposal Summary
- Select one Assessment issue
- Show Question, Answer, Evidence, and Rule Context once
- Show only proposal types that exist for the selected issue
- Use compact list-plus-detail patterns for Published records and Audit trail

### Navigation state

An empty publication queue initially left the reviewer without an obvious next action.

**Resolution:** add **Back to review queue** and preserve the review subview in session state.

### Runtime compatibility

The target Snowflake Streamlit runtime did not support every current Streamlit argument.

**Resolution:**

- Avoid `hide_index`
- Render one-based row numbers explicitly
- Use native Python `bool` values for Streamlit boolean parameters
- Use `st.rerun` with `st.experimental_rerun` fallback

### Status language

The application uses plain state descriptions:

- Needs human decision
- Approved — ready to publish
- Rejected
- Published

## Deployment Decisions

The verified production app is `READINESSOPS_DASHBOARD`.

The deployment script:

- Resolves the repository path dynamically
- Uses parameters for connection, database, schema, warehouse, role, app, and stage
- Uploads the Git-tracked app to a dedicated production stage
- Leaves the legacy stage unchanged for rollback
- Avoids hardcoded local user paths and account URLs

## Final Validation

### AI generation

A completed review generated:

| Proposal type | Count |
|---|---:|
| Gap | 5 |
| Risk | 2 |
| Action | 5 |
| Total | 12 |

### Human-governance lifecycle

Validated behavior:

- Gap approved and published
- Risk rejected and not published
- Action approved and published
- A second Action approved and published during UI verification
- Approval did not change governed-record counts
- Publication changed governed-record counts
- Approval and publication created separate history events
- Repeat publication did not create duplicates
- Published records retained Source Proposal and Agent Run identifiers

### UI

Validated behavior:

- Summary defaults to proposals needing a human decision
- Review by issue shows only relevant proposal-type tabs
- Published records use list plus selected detail
- Audit trail uses latest events plus selected detail
- Visible list numbering starts at 1
- Empty publication queue includes **Back to review queue**
- Production dashboard loaded without a Python Interpreter Error

## Environment Used for Demonstration

- Database: `READINESSOPS_VALIDATION`
- Schema: `APP`
- Streamlit app: `READINESSOPS_DASHBOARD`
- Model: `mistral-large2`
- Synthetic Assessment Run: `RUN_001`

Counts in the live application change after each demo. Documents describe state transitions and verified behavior rather than treating one screenshot count as a permanent invariant.
