# Architecture and Control Boundary

```text
Assessment Run
  └─ Question
      ├─ Answer
      ├─ Evidence
      └─ Requirement / Rule Context
              │
              ▼
     Cortex Governance Review
              │
              ▼
     Draft Proposals
     GAP / RISK / ACTION
     STATUS = REVIEW_REQUIRED
              │
              ▼
       Human Decision
       APPROVE / REJECT
              │
              ▼
     Controlled Publication
              │
       ┌──────┴─────────────┐
       ▼                    ▼
READINESS_GAPS      RECOMMENDED_ACTIONS
Gap + normalized Risk         Action
       │                    │
       └─────────┬──────────┘
                 ▼
     Dashboard / BI / Agent / Report

Every decision and publication:
GOVERNANCE_APPROVAL_HISTORY
```

## Control Boundary

```text
Requirement / Rule Context
→ AI Proposed
→ Human Approved
→ Explicitly Published
```

## Risk Normalization

The demonstration has no dedicated canonical Risk table. Approved Risks publish to `READINESS_GAPS` with a `[RISK]` prefix and retain their Risk identity through the source proposal.

## Traceability

```text
Question
→ Answer
→ Evidence
→ Rule Context
→ Agent Run
→ Proposal
→ Human Decision
→ Published Record
```
