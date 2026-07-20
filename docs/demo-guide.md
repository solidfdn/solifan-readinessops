# Demo Guide

## Prerequisites

- Snowflake account with Cortex AI enabled
- ACCOUNTADMIN or role with CREATE DATABASE, CREATE PROCEDURE privileges
- Access to `mistral-large2` model via Snowflake Cortex

## Demo Script (3-5 minutes)

### 1. Set Context (30 seconds)

```sql
USE SCHEMA READINESSOPS.APP;
```

Explain: "This is an AI readiness assessment system. Organizations answer readiness
questions and provide evidence. The AI agent evaluates gaps and recommends actions."

### 2. Show the Assessment Data (60 seconds)

```sql
SELECT q.QUESTION_TEXT, a.ANSWER_STATUS, e.EVIDENCE_STATUS
FROM ASSESSMENT_ANSWERS a
JOIN READINESS_QUESTIONS q ON a.QUESTION_ID = q.QUESTION_ID
LEFT JOIN EVIDENCE_ITEMS e ON a.RUN_ID = e.RUN_ID AND a.QUESTION_ID = e.QUESTION_ID
WHERE a.RUN_ID = 'RUN_001';
```

Point out: mixed answer statuses (ANSWERED, UNCONFIRMED, UNKNOWN, NOT_PREPARED)
and evidence gaps (PARTIAL, INSUFFICIENT).

### 3. Run the AI Agent (60 seconds)

```sql
CALL SP_RUN_READINESS_AGENT('RUN_001');
```

Expected result: `Agent complete. Generated 5 gaps and 5 actions for run RUN_001`

### 4. Show Generated Results (60 seconds)

```sql
SELECT GAP_TITLE, SEVERITY, PRIORITY_SCORE
FROM READINESS_GAPS WHERE GAP_ID LIKE 'AR_%'
ORDER BY PRIORITY_SCORE DESC;
```

```sql
SELECT ACTION_TITLE, OWNER_NAME, DUE_IN_DAYS
FROM RECOMMENDED_ACTIONS WHERE ACTION_ID LIKE 'AR_%'
ORDER BY DUE_IN_DAYS;
```

Highlight: The AI correctly identified HIGH severity gaps for the two questions
with INSUFFICIENT evidence and NOT_PREPARED status.

### 5. Show the Audit Trail (30 seconds)

```sql
SELECT AGENT_STEP, INPUT_SUMMARY, OUTPUT_SUMMARY, CREATED_AT
FROM AGENT_RUN_HISTORY WHERE AGENT_RUN_ID LIKE 'AR_%'
ORDER BY CREATED_AT;
```

Point out: 4 distinct steps with real timestamps showing the agent pipeline executed
in sequence (LOAD -> VALIDATE -> DETECT -> GENERATE).

### 6. Show the Action Board View (30 seconds)

```sql
SELECT DOMAIN_NAME, QUESTION_TEXT, SEVERITY, ACTION_TITLE, OWNER_NAME
FROM V_READINESSOPS_ACTION_BOARD
WHERE GAP_ID LIKE 'AR_%'
ORDER BY PRIORITY_SCORE DESC;
```

Explain: "This denormalized view powers the dashboard. Each row connects the
original question through to the AI-recommended action with an assigned owner."

## Key Talking Points

- Entire agent runs inside Snowflake (no external services)
- Cortex AI provides LLM inference without data leaving the platform
- Transaction safety: partial failures roll back cleanly
- Idempotent: re-running replaces previous output
- Audit trail captures every step for governance

## Alternative: Streamlit Demo (2 minutes)

1. Open the ReadinessOps Streamlit app in Snowsight
2. Select "RUN_001 — AI Readiness Baseline Assessment"
3. Show the summary metrics
4. Click "Run Agent" — wait for success message
5. Scroll down to see Gap Board and Recommended Actions populated
6. Show Agent Run History timeline

## Reset Between Demos

```sql
-- Remove AI output, keep sample data
DELETE FROM RECOMMENDED_ACTIONS WHERE ACTION_ID LIKE 'AR_%';
DELETE FROM READINESS_GAPS WHERE GAP_ID LIKE 'AR_%';
DELETE FROM AGENT_RUN_HISTORY WHERE AGENT_RUN_ID LIKE 'AR_%';
```
