# LLM Prompt Template — Governance Review

## Overview

This prompt is constructed by `SP_RUN_FULL_GOVERNANCE_REVIEW` and sent to:

```sql
SNOWFLAKE.CORTEX.COMPLETE('mistral-large2', <prompt>)
```

Its purpose is to generate evidence-grounded **Gap**, **Risk**, and **Action** proposals. The output is stored as review drafts and does not become a canonical governance record until human approval and controlled publication.

## Standard Instruction

```text
Review the selected Assessment Run. Evaluate the sufficiency of available evidence, identify readiness gaps, assess the related governance and operational risks, and propose prioritized actions. Every proposal must be supported by the supplied Question, Answer, Evidence, and Rule context. Do not invent evidence.
```

## Optional Additional Instruction

A user can add a business priority or time horizon, for example:

```text
Prioritize governance issues that could block executive approval within the next 90 days. Do not propose any gap, risk, or action that is not supported by the supplied assessment evidence.
```

The additional instruction supplements the standard instruction. It does not remove the evidence-grounding requirement.

## Input Format

Each assessment item contains:

```text
---
Question ID: Q001
Domain: Strategy and Ownership
Question: Is there a named executive owner for the AI and data program?
Rule: Executive sponsor memo or governance charter
Answer Status: ANSWERED
Answer: The CIO is the executive sponsor, but the role is not yet reflected in the formal governance charter.
Evidence ID: EV001
Evidence: The CIO is mentioned as sponsor. Operating responsibilities and escalation rules remain draft.
Evidence Status: PARTIAL
```

## Source Fields

| Prompt Field | Source |
|---|---|
| Question ID | `READINESS_QUESTIONS.QUESTION_ID` |
| Domain | `READINESS_DOMAINS.DOMAIN_NAME` |
| Question | `READINESS_QUESTIONS.QUESTION_TEXT` |
| Rule | `READINESS_QUESTIONS.EXPECTED_EVIDENCE` |
| Answer Status | `ASSESSMENT_ANSWERS.ANSWER_STATUS` |
| Answer | `ASSESSMENT_ANSWERS.ANSWER_TEXT` |
| Evidence ID | `EVIDENCE_ITEMS.EVIDENCE_ID` |
| Evidence | `EVIDENCE_ITEMS.EVIDENCE_TEXT` |
| Evidence Status | `EVIDENCE_ITEMS.EVIDENCE_STATUS` |

## Required Output

Return one JSON object with three arrays:

```json
{
  "gaps": [
    {
      "question_id": "Q001",
      "severity": "HIGH",
      "priority": 95,
      "title": "Short gap title",
      "description": "Why this is a readiness gap.",
      "rationale": "How the supplied assessment context supports the proposal."
    }
  ],
  "risks": [
    {
      "question_id": "Q001",
      "severity": "HIGH",
      "priority": 90,
      "title": "Short risk title",
      "description": "The governance or operational exposure.",
      "rationale": "How the supplied assessment context supports the proposal."
    }
  ],
  "actions": [
    {
      "question_id": "Q001",
      "severity": "HIGH",
      "priority": 95,
      "title": "Short action title",
      "description": "Concrete work required.",
      "rationale": "How the action addresses the supplied evidence gap.",
      "recommended_owner": "Program Lead",
      "due_in_days": 30
    }
  ]
}
```

## Output Rules

- Return JSON only
- Do not use markdown fences
- Do not invent evidence
- Every proposal must reference a supplied `question_id`
- `severity` must be `HIGH`, `MEDIUM`, or `LOW`
- `priority` should be one of `60`, `70`, `80`, `90`, or `95`
- `recommended_owner` must be one of:
  - `Risk Manager`
  - `Data Governance Lead`
  - `Program Lead`
  - `PMO Lead`
  - `Security Lead`
- `due_in_days` must be `14`, `30`, `60`, or `90`

## Post-Processing

The stored procedure:

1. Strips optional markdown fences
2. Parses with `TRY_PARSE_JSON`
3. Fails the agent run safely if JSON is invalid
4. Normalizes 1–5 priority output to 60–95
5. Bounds other priority values safely
6. Stores proposals as `REVIEW_REQUIRED`
7. Creates proposal-source traceability
8. Requires human review before publication