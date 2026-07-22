# Demo Guide

## Goal

Demonstrate a governed operating workflow rather than an autonomous direct-write agent:

```text
Assessment evidence
→ natural-language review priority
→ AI-generated drafts
→ human approval or rejection
→ controlled publication
→ governed record and audit trail
```

## Prerequisites

- Snowflake account with Cortex AI enabled
- Access to `mistral-large2`
- Governed SQL path `01`–`03` and `10`–`14` deployed
- Streamlit app deployed as `READINESSOPS_DASHBOARD`
- Synthetic Assessment Run `RUN_001`
- No approved-but-unpublished proposal left from a previous rehearsal

## Four-Minute Demo

### 0:00–0:30 — Establish the control boundary

Show the four steps at the top of the application.

Say:

> ReadinessOps starts with assessment evidence. Cortex proposes Gap, Risk, and Action drafts, but the model cannot approve or publish its own output. A person decides, and a separate publication step creates the governed record.

Show the four metrics:

- Evidence not yet verified
- Needs human decision
- Approved, not published
- Published governance records

Counts vary as the demo is repeated. Explain the meaning of the metrics rather than relying on fixed numbers.

### 0:30–1:10 — Use natural language at the governed entry point

Open **Review setup**.

Enter:

```text
Prioritize governance issues that could block executive approval within the next 90 days. Do not propose any gap, risk, or action that is not supported by the supplied assessment evidence.
```

Select **Generate AI draft proposals**.

Show:

- Agent Run ID
- Model
- Completion time
- Additional instruction
- Generated Gap, Risk, and Action counts

Explain:

> The additional instruction changes business priority, not the control boundary. The fixed instruction still requires every proposal to be supported by Question, Answer, Evidence, and Rule Context.

### 1:10–2:15 — Inspect one issue and make a human decision

Open **Review queue** and then **Review by issue**.

The first issue may already be displayed. Use it directly unless a different demo issue is needed.

Show:

- Current Answer
- Evidence
- Requirement / Rule Context
- Related Gap, Risk, and Action tabs
- **Why the AI raised this proposal**
- Source traceability

Open an Action proposal.

Enter a Decision comment:

```text
DEMO_APPROVE — reviewed against the supplied evidence and current governance requirement.
```

Select **Approve**.

Show the metric change:

- Needs human decision decreases by 1
- Approved, not published increases by 1
- Published governance records does not change

Explain:

> Approval records the human decision, but it still does not create the governed record.

### 2:15–3:00 — Publish explicitly

Open **Approved & publish**.

Review the approved proposal list, select the confirmation checkbox, and choose **Publish approved proposals**.

Show the metric change:

- Approved, not published returns to 0
- Published governance records increases
- The published Action count increases for an Action proposal

Explain:

> Publication is a separate authority boundary. The procedure publishes only proposals that were already approved and uses the Source Proposal ID to prevent duplicate canonical writes.

### 3:00–3:35 — Inspect the governed record

Open **Published records**.

Select the newly published item and show:

- Record type
- Description
- Owner and target, when applicable
- Assessment Question
- Source Proposal
- Agent Run

Explain:

> A published record remains traceable to the evidence context and the AI proposal that produced it.

### 3:35–4:00 — Verify the decision history

Open **Audit trail**.

Show the two latest events:

1. `PUBLISH`
2. `APPROVE`

Show the actor, time, previous and new state, and comment.

Close with:

> AI proposes, people decide, and the system preserves the basis and history of the decision. ReadinessOps is an operating layer for Enterprise AI Governance, not a one-time diagnosis.

## Empty Publication State

When there are no approved proposals waiting for publication, the page displays:

```text
No approved proposals are waiting to be published.
← Back to review queue
```

Use **Back to review queue** rather than navigating through the top-level Workspace selector.

## SQL Verification

Run the read-only final validation:

```powershell
snow sql `
  -c "<SNOWFLAKE_CLI_CONNECTION>" `
  -f "sql/18_hackathon_final_validation.sql"
```

The validation checks:

- Required procedures
- Latest-run source traceability
- Proposal states
- Audit actor and timestamp completeness
- Duplicate canonical records
- Duplicate publication history
- Published-record traceability
- Production Streamlit object
- Absence of hackathon-only Streamlit objects

## Demonstrated Result

The verified lifecycle includes:

- 5 Gap, 2 Risk, and 5 Action drafts in a completed review
- Gap approval and publication
- Risk rejection without publication
- Action approval and publication
- Separate approval and publication events
- Duplicate publication prevention
- One-based list numbering
- Production dashboard verification
