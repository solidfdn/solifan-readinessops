# Decision Pack — LLM Prompt Template

## Purpose

`SP_GENERATE_DECISION_PACK` constructs this prompt and sends it to:

```sql
AI_COMPLETE(
  model => 'mistral-large2',
  prompt => <prompt>,
  response_format => <strict JSON schema>
)
```

The model generates a four-section Decision Pack. Output is stored as four
`REVIEW_REQUIRED` proposals in `GOVERNANCE_AGENT_PROPOSAL`. No section can
become a governed record without human review, optional inline editing,
explicit approval, and separate publication.

## Governed Execution Trace

The procedure executes one schema-constrained Cortex inference call and records
five governed Run Steps around it:

1. **Input validation** — validate the Run, Initiative, evidence, and fingerprint
2. **Context assembly** — assemble assessment, evidence, and prompt context
3. **Cortex generation** — generate the strict four-section object
4. **Output validation** — validate schema, enums, priority, and evidence IDs
5. **Draft persistence** — atomically save proposals, source links, and run status

This trace makes the AI workflow inspectable without multiplying model calls or
inference cost. The generated sections remain proposals until human review and
explicit publication.

## Input Context

### Initiative Context (from AI_INITIATIVE)

```text
AI INITIATIVE CONTEXT:
Name: Customer Churn Predictor
Description: ML model predicting customer churn for proactive retention
Owner: Data Science Lead
Lifecycle Stage: PILOT
Business Outcome: Reduce churn by 15% within 6 months
Status: ACTIVE
```

### Assessment Data (from ASSESSMENT_ANSWERS + READINESS_QUESTIONS)

Same format as the existing governance review prompt.

### Evidence (from EVIDENCE_ITEMS, including uploaded TXT and parsed PDF files)

```text
---
Evidence ID: EV_TXT_20260801_001
Title: data_governance_policy.txt
Source Type: UPLOADED_TXT
Status: VALIDATED
Content: [first 4000 chars of evidence text]
---
Evidence ID: EV_PDF_20260801_002
Title: ai_risk_review.pdf
Source Type: UPLOADED_PDF
Status: VALIDATED
Content: [first 4000 chars extracted with AI_PARSE_DOCUMENT]
```

## Required Output

```json
{
  "governance_summary": {
    "title": "...",
    "description": "Overall governance readiness assessment",
    "readiness_level": "RED|AMBER|GREEN",
    "key_findings": ["..."],
    "recommendations": ["..."],
    "source_evidence_ids": ["EV_001", "EV_TXT_..."]
  },
  "value_realization": {
    "title": "...",
    "description": "Value and business outcome assessment",
    "expected_value": "...",
    "realization_confidence": "HIGH|MEDIUM|LOW",
    "blockers": ["..."],
    "enablers": ["..."],
    "source_evidence_ids": ["EV_001"]
  },
  "model_routing": {
    "title": "...",
    "description": "Model selection and routing recommendation",
    "recommended_approach": "...",
    "complexity_level": "HIGH|MEDIUM|LOW",
    "data_readiness": "HIGH|MEDIUM|LOW",
    "considerations": ["..."],
    "source_evidence_ids": ["EV_001"]
  },
  "portfolio_recommendation": {
    "title": "...",
    "description": "Portfolio-level recommendation",
    "recommendation": "PROCEED|HOLD|REDESIGN|RETIRE",
    "priority_score": 85,
    "rationale": "...",
    "next_review": "YYYY-MM-DD",
    "next_steps": ["..."],
    "source_evidence_ids": ["EV_001"]
  }
}
```

## Output Rules

- Return JSON only — no markdown fences
- All four sections are required; partial output is rejected
- Every `source_evidence_ids` must be non-empty and contain only valid IDs from the selected run
- Do not invent evidence IDs
- `readiness_level`: RED, AMBER, or GREEN
- `realization_confidence`: HIGH, MEDIUM, or LOW
- `recommendation`: PROCEED, HOLD, REDESIGN, or RETIRE
- `priority_score`: integer 1–100
- Ground every statement in supplied evidence

## Idempotency

`INPUT_FINGERPRINT` = SHA-256 of every generation input:
- Initiative context
- Ordered assessment answers
- Ordered evidence IDs, statuses, and content hashes
- Additional instruction
- Prompt/schema version `DECISION_PACK_V2`

If an identical fingerprint already has a COMPLETED run, generation is skipped.

## Post-Processing

1. Strip optional markdown fences
2. Parse with `TRY_PARSE_JSON`
3. Validate the exact four top-level keys and each section's evidence citations
4. Insert four `GOVERNANCE_AGENT_PROPOSAL` rows atomically
5. Create source traceability records
6. Mark agent run COMPLETED

On any failure: mark run FAILED, roll back proposals, return error JSON.
