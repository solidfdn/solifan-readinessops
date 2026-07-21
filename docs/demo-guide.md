# Demo Guide

## Goal

Demonstrate that ReadinessOps is not an autonomous direct-write agent. It is a governed operating workflow:

```text
Assessment evidence
→ AI-generated drafts
→ Human approval or rejection
→ Controlled publication
→ Canonical dashboard records
```

## Prerequisites

- Snowflake account with Cortex AI enabled
- Access to `mistral-large2`
- Governance SQL files `10`–`15` deployed
- Streamlit app deployed
- Synthetic Assessment Run `RUN_001`

## Demo Script — 4 to 6 Minutes

### 1. Establish the Governance Problem

Explain:

> Enterprise AI governance cannot rely on an AI model writing directly into the system of record. ReadinessOps uses AI to generate evidence-grounded proposals, then requires a human decision before publication.

### 2. Show the Assessment Context

```sql
SELECT
  q.QUESTION_ID,
  q.QUESTION_TEXT,
  q.EXPECTED_EVIDENCE,
  a.ANSWER_STATUS,
  a.ANSWER_TEXT,
  e.EVIDENCE_STATUS,
  e.EVIDENCE_TEXT
FROM ASSESSMENT_ANSWERS a
JOIN READINESS_QUESTIONS q
  ON a.QUESTION_ID = q.QUESTION_ID
LEFT JOIN EVIDENCE_ITEMS e
  ON a.RUN_ID = e.RUN_ID
 AND a.QUESTION_ID = e.QUESTION_ID
WHERE a.RUN_ID = 'RUN_001'
ORDER BY q.SORT_ORDER;
```

Point out that proposals must be supported by the supplied Question, Answer, Evidence, and Rule context.

### 3. Run a Full Governance Review

In Streamlit, enter an optional instruction such as:

```text
Prioritize governance issues that could block executive approval within the next 90 days. Do not propose any gap, risk, or action that is not supported by the supplied assessment evidence.
```

Click **Run Full Governance Review**.

SQL equivalent:

```sql
CALL SP_RUN_FULL_GOVERNANCE_REVIEW(
  'RUN_001',
  'Prioritize governance issues that could block executive approval within the next 90 days. Do not propose any gap, risk, or action that is not supported by the supplied assessment evidence.'
);
```

Show:

- Agent status
- Model
- Completed timestamp
- Additional instruction used
- Generated Gap, Risk, and Action counts

### 4. Review the Drafts

Open **Proposal Review**.

Demonstrate that:

- Gap, Risk, and Action are selected explicitly
- Each item starts as `[DRAFT]`
- Source context is expandable
- A comment can be entered
- Approve and Reject are separate decisions
- The selected proposal type remains stable after the app reruns

Approve one Gap, reject one Risk, and approve one Action.

### 5. Show Controlled Publication

Scroll to **Publish Approved Proposals**.

Confirm that the counters show only approved items. Check the confirmation box and publish once.

Expected demonstration:

- Approved Gap becomes `PUBLISHED`
- Approved Action becomes `PUBLISHED`
- Rejected Risk remains `REJECTED`
- No canonical Risk record is created from the rejected proposal

### 6. Verify in SQL

```sql
SELECT
  PROPOSAL_TYPE,
  TITLE,
  STATUS,
  REVIEW_COMMENT,
  PUBLISHED_ENTITY_ID
FROM GOVERNANCE_AGENT_PROPOSAL
WHERE AGENT_RUN_ID = '<AGENT_RUN_ID>'
ORDER BY PROPOSAL_TYPE, PRIORITY DESC;
```

```sql
SELECT COUNT(*) AS PUBLISHED_GAPS
FROM READINESS_GAPS
WHERE SOURCE_AGENT_RUN_ID = '<AGENT_RUN_ID>';
```

```sql
SELECT COUNT(*) AS PUBLISHED_ACTIONS
FROM RECOMMENDED_ACTIONS
WHERE SOURCE_AGENT_RUN_ID = '<AGENT_RUN_ID>';
```

```sql
SELECT
  p.PROPOSAL_TYPE,
  p.STATUS,
  COUNT(h.PROPOSAL_ID) AS HISTORY_RECORDS
FROM GOVERNANCE_AGENT_PROPOSAL p
LEFT JOIN GOVERNANCE_APPROVAL_HISTORY h
  ON h.PROPOSAL_ID = p.PROPOSAL_ID
WHERE p.AGENT_RUN_ID = '<AGENT_RUN_ID>'
GROUP BY p.PROPOSAL_TYPE, p.STATUS
ORDER BY p.PROPOSAL_TYPE;
```

### 7. Show the Dashboard Boundary

Explain:

> Draft, approved-but-unpublished, and rejected proposals do not appear as new canonical dashboard records. The dashboard reads the governed presentation view and excludes legacy `AR_%` direct-write records.

## Verified Demonstration Result

The final UI and database validation produced:

| Item | Result |
|---|---|
| Gap review | Approved, then published |
| Risk review | Rejected |
| Action review | Approved, then published |
| Published Gap count | 1 |
| Published Action count | 1 |
| Rejected Risk canonical count | 0 |
| Gap history | Approval + publication |
| Action history | Approval + publication |
| Risk history | Rejection |
| Duplicate publication | Prevented |

## Talking Points

- Snowflake-native end to end
- Cortex AI does analysis, not final governance decision-making
- Human review is explicit and traceable
- Publication is separate from approval
- Evidence grounding is visible before approval
- Assessment and agent-run history support repeatable governance operations
- The workflow maps directly to `Question → Evidence → Gap → Risk → Action`