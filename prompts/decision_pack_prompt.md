# Decision Pack — LLM Prompt Template

## Purpose

`SP_GENERATE_DECISION_PACK` constructs this prompt and sends it to:

```sql
SNOWFLAKE.CORTEX.COMPLETE('mistral-large2', <prompt>)
```

The model generates a four-section Decision Pack. Output is stored as four
`REVIEW_REQUIRED` proposals in `GOVERNANCE_AGENT_PROPOSAL`. No section can
become a governed record without human review, optional inline editing,
explicit approval, and separate publication.

## Workflow Compatibility

This procedure is designed to be decomposable into a multi-step CoCo
orchestration in the next slice:

1. **Evidence scan** — gather and validate all evidence for the run
2. **Governance evaluation** — produce `governance_summary`
3. **Value/routing analysis** — produce `value_realization` and `model_routing`
4. **Portfolio synthesis** — produce `portfolio_recommendation`

The current implementation executes all steps in a single LLM call. The schema
and proposal structure are forward-compatible with per-step agent runs.

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

### Evidence (from EVIDENCE_ITEMS, including uploaded TXT files)

```text
---
Evidence ID: EV_TXT_20260801_001
Title: data_governance_policy.txt
Source Type: UPLOADED_TXT
Status: VALIDATED
Content: [first 4000 chars of evidence text]
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
    "value_hypothesis": "...",
    "kpis": [
      {"name": "...", "baseline": "...", "target": "...", "measurement_window": "..."}
    ],
    "estimated_cost": "...",
    "expected_benefit": "...",
    "realization_confidence": "HIGH|MEDIUM|LOW",
    "blockers": ["..."],
    "enablers": ["..."],
    "source_evidence_ids": ["EV_001"]
  },
  "model_routing": {
    "title": "...",
    "description": "Model selection and routing recommendation",
    "recommended_model_class": "...",
    "recommended_approach": "...",
    "complexity_level": "HIGH|MEDIUM|LOW",
    "data_readiness": "HIGH|MEDIUM|LOW",
    "quality_cost_latency_constraints": ["..."],
    "fallback_approach": "...",
    "human_gate": "...",
    "considerations": ["..."],
    "source_evidence_ids": ["EV_001"]
  },
  "portfolio_recommendation": {
    "title": "...",
    "description": "Portfolio-level recommendation",
    "recommendation": "PROCEED|HOLD|REDESIGN|RETIRE",
    "priority_score": 85,
    "funding_posture": "INCREASE|MAINTAIN|REDUCE|STOP",
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
- Prompt/schema version `DECISION_PACK_V1`

If an identical fingerprint already has a COMPLETED run, generation is skipped.

## Post-Processing

1. Strip optional markdown fences
2. Parse with `TRY_PARSE_JSON`
3. Validate the exact four top-level keys and each section's evidence citations
4. Insert four `GOVERNANCE_AGENT_PROPOSAL` rows atomically
5. Create source traceability records
6. Mark agent run COMPLETED

On any failure: mark run FAILED, roll back proposals, return error JSON.
