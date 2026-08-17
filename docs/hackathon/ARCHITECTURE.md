# Architecture and Control Boundary

```text
AI Initiative
  └─ Assessment Run
      └─ Evidence Items
          ├─ Extracted TXT / PDF text
          └─ Original file in Snowflake Stage
                    │
                    ▼
          Cortex Decision Pack Generation
                    │
                    ▼
       Four REVIEW_REQUIRED Proposals
       GOVERNANCE / VALUE / ROUTING / PORTFOLIO
                    │
                    ▼
             Human Decision
             APPROVE / REJECT
                    │
                    ▼
           Explicit Publication
                    │
                    ▼
       GOVERNED_DECISION_RECORD
                    │
                    ▼
              V_AI_PORTFOLIO

Every approval and publication:
GOVERNANCE_APPROVAL_HISTORY
```

## Control Boundary

```text
Evidence Supplied
→ AI Drafted
→ Human Reviewed
→ Explicitly Published
→ Governed Record
```

AI can parse and propose. It cannot approve or publish.

## Evidence Provenance

TXT and PDF originals are retained in `READINESSOPS_EVIDENCE_STAGE`. `EVIDENCE_ITEMS` stores extracted text, hash, stage path, parser metadata, uploader, and timestamp. PDF extraction uses Cortex `AI_PARSE_DOCUMENT`.

## Decision Pack Contract

`SP_GENERATE_DECISION_PACK` accepts only a complete four-section object:

- Governance
- Value
- Model Routing
- Portfolio

Each section requires a valid priority and non-empty evidence IDs belonging to the selected Assessment Run.

## Compatibility

The existing Gap, Risk, and Action workflow is preserved. Decision Pack proposals use `DECISION_*` types and publish to `GOVERNED_DECISION_RECORD`; legacy proposals keep their established canonical mappings.

## Traceability

```text
Initiative
→ Assessment Run
→ Evidence + Original File
→ Agent Run
→ Proposal
→ Human Decision
→ Published Record
→ Portfolio
```
