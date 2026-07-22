# LLM Prompt Template — Governance Review

## Purpose

`SP_RUN_FULL_GOVERNANCE_REVIEW` constructs this prompt and sends it to:

```sql
SNOWFLAKE.CORTEX.COMPLETE('mistral-large2', <prompt>)
```

The model generates evidence-grounded Gap, Risk, and Action proposals. Its output is stored as `REVIEW_REQUIRED` and cannot become a governed record without human approval and explicit publication.

## Fixed Standard Instruction

```text
Review the selected Assessment Run.
Evaluate the sufficiency of available evidence, identify readiness gaps, assess the related governance and operational risks, and propose prioritized actions.
Every proposal must be supported by the supplied Question, Answer, Evidence, and Rule context.
Do not invent evidence.
```

## Optional Additional Business Instruction

A reviewer can add a priority or time horizon:

```text
Prioritize governance issues that could block executive approval within the next 90 days.
Do not propose any gap, risk, or action that is not supported by the supplied assessment evidence.
```

The additional instruction:

- Supplements the fixed instruction
- Cannot remove the evidence-grounding requirement
- Cannot approve a proposal
- Cannot authorize publication
- Is stored with the Agent Run for traceability

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

| Prompt field | Source |
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

Return one JSON object:

```json
{
  "gaps": [
    {
      "question_id": "Q001",
      "severity": "HIGH",
      "priority": 95,
      "title": "Short gap title",
      "description": "Why this is a readiness gap.",
      "rationale": "How the supplied context supports the proposal."
    }
  ],
  "risks": [
    {
      "question_id": "Q001",
      "severity": "HIGH",
      "priority": 90,
      "title": "Short risk title",
      "description": "The governance or operational exposure.",
      "rationale": "How the supplied context supports the proposal."
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
- `priority` should be `60`, `70`, `80`, `90`, or `95`
- `recommended_owner` must be one of:
  - `Risk Manager`
  - `Data Governance Lead`
  - `Program Lead`
  - `PMO Lead`
  - `Security Lead`
- `due_in_days` must be `14`, `30`, `60`, or `90`

## Post-Processing and Governance

The stored procedure:

1. Removes optional markdown fences
2. Parses with `TRY_PARSE_JSON`
3. Fails the Agent Run safely if the JSON is invalid
4. Normalizes priority values
5. Stores proposals as `REVIEW_REQUIRED`
6. Creates proposal-source traceability
7. Requires human review
8. Requires explicit publication for governed records
