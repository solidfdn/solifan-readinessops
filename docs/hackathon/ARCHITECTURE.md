# Architecture and control boundary

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
     (Gap / Risk / Action)
     STATUS = REVIEW_REQUIRED
              │
              ▼
       Human Decision
       APPROVE / REJECT
              │
              ▼
     Controlled Publication
              │
       ┌──────┴────────┐
       ▼               ▼
READINESS_GAPS   RECOMMENDED_ACTIONS
       │               │
       └──────┬────────┘
              ▼
   Dashboard / BI / Agent / Report

Every decision:
GOVERNANCE_APPROVAL_HISTORY
```

## Control boundary

`Requirement / Rule Context → AI Proposed → Human Approved → Published`

## Traceability

`Question → Answer → Evidence → Rule Context → Agent Run → Proposal → Human Decision → Published Record`
