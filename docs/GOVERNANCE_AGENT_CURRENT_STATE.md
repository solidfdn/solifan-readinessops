# Governance Agent — Current State Analysis

## Existing Objects in READINESSOPS_VALIDATION.APP

### Tables

| Table | Rows | Purpose |
|-------|------|---------|
| ASSESSMENT_RUNS | 1 | Top-level assessment container |
| READINESS_DOMAINS | 4 | Question categories |
| READINESS_QUESTIONS | 5 | Assessment questions with expected evidence |
| ASSESSMENT_ANSWERS | 5 | Answers per run/question |
| EVIDENCE_ITEMS | 5 | Evidence per run/question |
| READINESS_GAPS | 10 | Canonical gaps (GAP_%) + AI-generated (AR_%) |
| RECOMMENDED_ACTIONS | 10 | Canonical actions (ACT_%) + AI-generated (AR_%) |
| AGENT_RUN_HISTORY | 8 | Step-level audit log |

### Views

| View | Source |
|------|--------|
| V_READINESSOPS_ACTION_BOARD | Joins all tables, shows ALL gaps/actions unfiltered |

### Procedures

| Procedure | Behavior |
|-----------|----------|
| SP_RUN_READINESS_AGENT(VARCHAR) | DESTRUCTIVE: Deletes AR_% rows, then re-inserts from Cortex AI |

## Key Relationships

```
ASSESSMENT_RUNS (RUN_ID)
├── ASSESSMENT_ANSWERS (RUN_ID, QUESTION_ID)
├── EVIDENCE_ITEMS (RUN_ID, QUESTION_ID)
├── READINESS_GAPS (RUN_ID, QUESTION_ID)
│   └── RECOMMENDED_ACTIONS (RUN_ID, GAP_ID)
└── AGENT_RUN_HISTORY (RUN_ID)

READINESS_QUESTIONS (QUESTION_ID)
├── ASSESSMENT_ANSWERS (QUESTION_ID)
├── EVIDENCE_ITEMS (QUESTION_ID)
└── READINESS_GAPS (QUESTION_ID)

READINESS_DOMAINS (DOMAIN_ID)
└── READINESS_QUESTIONS (DOMAIN_ID)
```

## How Current Effective Answers Are Resolved

- One row per (RUN_ID, QUESTION_ID) in ASSESSMENT_ANSWERS
- No versioning; latest row IS the effective answer
- ANSWER_STATUS: ANSWERED, UNCONFIRMED, UNKNOWN, NOT_PREPARED
- No composite primary key enforced

## How Evidence Links to Questions

- One row per (RUN_ID, QUESTION_ID) in EVIDENCE_ITEMS via EVIDENCE_ID
- EVIDENCE_STATUS: SUFFICIENT, PARTIAL, INSUFFICIENT, MISSING
- Joined by (RUN_ID, QUESTION_ID) — 1:1 in current data

## How Rules Are Represented

- **No dedicated Rules table exists**
- READINESS_QUESTIONS.EXPECTED_EVIDENCE serves as the evaluation criterion
- No versioning of rules
- Decision: Use EXPECTED_EVIDENCE as the rule source; add RULE_VERSION = '1.0' as a constant

## Gap, Risk, and Action Status

- READINESS_GAPS: No status field; no history tracking
- RECOMMENDED_ACTIONS: Has ACTION_STATUS (currently always 'PROPOSED')
- **No published/draft distinction** — all records are treated as canonical
- **No Risk entity exists** — only Gaps and Actions

## AI-Generated vs Manual Records

- GAP_% prefix = manually seeded baseline gaps
- ACT_% prefix = manually seeded baseline actions
- AR_% prefix = AI-generated records
- Currently co-mingled in the same tables with no status differentiation

## Current SP_RUN_READINESS_AGENT Behavior

1. DELETES all AR_% RECOMMENDED_ACTIONS for the RUN_ID
2. DELETES all AR_% READINESS_GAPS for the RUN_ID
3. DELETES all AR_% AGENT_RUN_HISTORY for the RUN_ID
4. Calls Cortex AI
5. INSERTS new AR_% gaps directly into READINESS_GAPS
6. INSERTS new AR_% actions directly into RECOMMENDED_ACTIONS
7. INSERTS step logs into AGENT_RUN_HISTORY

**This is destructive and ungoverned** — AI output directly becomes the system of record.

## Dashboard Source of Truth

V_READINESSOPS_ACTION_BOARD joins:
- ASSESSMENT_RUNS → ASSESSMENT_ANSWERS → READINESS_QUESTIONS → READINESS_DOMAINS
- LEFT JOIN EVIDENCE_ITEMS
- LEFT JOIN READINESS_GAPS
- LEFT JOIN RECOMMENDED_ACTIONS

**No filtering** — all gaps and actions appear regardless of source or status.

## Reuse Decisions

| Object | Decision |
|--------|----------|
| ASSESSMENT_RUNS | Reuse as-is |
| READINESS_DOMAINS | Reuse as-is |
| READINESS_QUESTIONS | Reuse; EXPECTED_EVIDENCE = rule |
| ASSESSMENT_ANSWERS | Reuse as-is |
| EVIDENCE_ITEMS | Reuse as-is |
| READINESS_GAPS | Reuse for published canonical records only |
| RECOMMENDED_ACTIONS | Reuse for published canonical records only |
| AGENT_RUN_HISTORY | Replace with new GOVERNANCE_AGENT_RUN table |
| V_READINESSOPS_ACTION_BOARD | Modify to filter only published records |
| SP_RUN_READINESS_AGENT | Preserve for backward compatibility; add new governed procedure |

## Required New Objects

| Object | Purpose |
|--------|---------|
| GOVERNANCE_AGENT_RUN | Full governance review execution records |
| GOVERNANCE_AGENT_PROPOSAL | Draft Gap/Risk/Action proposals |
| GOVERNANCE_AGENT_PROPOSAL_SOURCE | Traceability to Question/Answer/Evidence/Rule |
| GOVERNANCE_APPROVAL_HISTORY | Immutable review and publication log |

## Required Changes to Existing Objects

| Object | Change |
|--------|--------|
| READINESS_GAPS | Add SOURCE_PROPOSAL_ID and SOURCE_AGENT_RUN_ID columns |
| RECOMMENDED_ACTIONS | Add SOURCE_PROPOSAL_ID and SOURCE_AGENT_RUN_ID columns |
| V_READINESSOPS_ACTION_BOARD | Filter to exclude AR_% rows OR add published-only filter |

## Risks and Ambiguities

1. No Risk entity exists — will create as PROPOSAL_TYPE='RISK' in proposals; canonical Risk records will be stored in READINESS_GAPS with a RISK severity marker or a new column
2. No ANSWER_ID — use composite (RUN_ID, QUESTION_ID) as answer identifier
3. No Rule versioning — use constant RULE_VERSION='1.0' with EXPECTED_EVIDENCE as rule text
4. READINESS_GAPS has no status field — published records are distinguished by existence (GAP_% prefix for manual, published AR_% for AI-generated with SOURCE_PROPOSAL_ID set)
