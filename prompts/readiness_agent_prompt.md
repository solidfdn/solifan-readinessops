# LLM Prompt Template — Readiness Gap Analyst

## Overview

This prompt is sent to `SNOWFLAKE.CORTEX.COMPLETE('mistral-large2', ...)` by the
`SP_RUN_READINESS_AGENT` stored procedure. It instructs the LLM to analyze
assessment data and return structured JSON identifying gaps and recommended actions.

## System Role

> You are an AI readiness gap analyst. Analyze the following assessment data and produce a JSON response.

## Input Format

The procedure constructs the input dynamically from table data. Each question block follows this structure (repeated per question):

```
---
Question ID: Q001
Domain: Strategy and Ownership
Question: Is there a named executive owner for the AI and data program?
Expected Evidence: Executive sponsor memo or governance charter
Answer Status: ANSWERED
Answer Text: The CIO is the executive sponsor, but the role is not yet reflected in the formal governance charter.
Evidence Title: Draft AI Governance Charter
Evidence Text: The CIO is mentioned as sponsor. However, operating responsibilities and escalation rules are still marked as draft.
Evidence Status: PARTIAL
```

### Field Meanings

| Field | Source Table | Description |
|-------|-------------|-------------|
| Question ID | READINESS_QUESTIONS | Unique identifier |
| Domain | READINESS_DOMAINS | Readiness domain name |
| Question | READINESS_QUESTIONS | The readiness question text |
| Expected Evidence | READINESS_QUESTIONS | What evidence should exist |
| Answer Status | ASSESSMENT_ANSWERS | ANSWERED, UNCONFIRMED, UNKNOWN, NOT_PREPARED |
| Answer Text | ASSESSMENT_ANSWERS | Free-text response |
| Evidence Title | EVIDENCE_ITEMS | Name of supporting evidence |
| Evidence Text | EVIDENCE_ITEMS | Description of evidence content |
| Evidence Status | EVIDENCE_ITEMS | SUFFICIENT, PARTIAL, INSUFFICIENT, MISSING |

## Instructions Block

```
For each question where the answer is not fully confirmed with sufficient evidence, identify a gap.
Then for each gap, recommend one concrete action.
```

## Rules

- `severity` must be HIGH, MEDIUM, or LOW
- `priority_score` must be an integer 1-100 (higher = more urgent)
- `suggested_owner` must be one of: Risk Manager, Data Governance Lead, Program Lead, PMO Lead, Security Lead
- `due_in_days` must be 14, 30, 60, or 90

## Expected Output Schema

The LLM must return **only valid JSON** with no markdown wrapping:

```json
{
  "gaps": [
    {
      "question_id": "Q001",
      "severity": "MEDIUM",
      "priority_score": 70,
      "gap_title": "Short title describing the gap",
      "gap_description": "Explanation of why this is a gap."
    }
  ],
  "actions": [
    {
      "question_id": "Q001",
      "action_title": "Short action title",
      "action_description": "Concrete steps to close the gap.",
      "suggested_owner": "Program Lead",
      "due_in_days": 60
    }
  ]
}
```

### Output Field Definitions

| Field | Maps To | Description |
|-------|---------|-------------|
| gaps[].question_id | READINESS_GAPS.QUESTION_ID | Links gap to source question |
| gaps[].severity | READINESS_GAPS.SEVERITY | HIGH / MEDIUM / LOW |
| gaps[].priority_score | READINESS_GAPS.PRIORITY_SCORE | 1-100, higher = more urgent |
| gaps[].gap_title | READINESS_GAPS.GAP_TITLE | Brief title |
| gaps[].gap_description | READINESS_GAPS.GAP_DESCRIPTION | Detailed explanation |
| actions[].question_id | (join key) | Links action to its gap via question_id |
| actions[].action_title | RECOMMENDED_ACTIONS.ACTION_TITLE | Brief title |
| actions[].action_description | RECOMMENDED_ACTIONS.ACTION_DESCRIPTION | Steps to resolve |
| actions[].suggested_owner | RECOMMENDED_ACTIONS.OWNER_NAME | Responsible role |
| actions[].due_in_days | RECOMMENDED_ACTIONS.DUE_IN_DAYS | Deadline in days |

## Post-Processing Notes

1. **Markdown fences**: The procedure strips ` ```json ` / ` ``` ` wrappers via REGEXP_REPLACE
2. **Validation**: TRY_PARSE_JSON is used; NULL result triggers FAILED audit row
3. **Type safety**: `priority_score` and `due_in_days` use `TRY_CAST(::VARCHAR AS INTEGER)` with defaults
4. **Model**: `mistral-large2` selected for structured JSON output reliability
5. **Token limits**: For assessments with 20+ questions, consider batching into groups of 10
