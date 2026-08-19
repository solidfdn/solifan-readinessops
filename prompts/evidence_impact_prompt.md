# Evidence Impact Prompt — `EVIDENCE_IMPACT_V1`

## Purpose

Assess how Evidence added to or replaced in an active Draft Revision can affect
the four governed decisions published by its base Revision.

The output is advisory. It cannot approve a proposal, publish a Revision, alter
Current State, or replace human review.

## Governed inputs

- Assessment Case and target Revision number
- Revision change reason
- Linked AI Initiative context
- Changed Evidence only (`ADDED` or `REPLACED`)
- The four immutable governed decisions from the published base Revision
- Model name and prompt version, included in the input fingerprint

## Output contract

Return one JSON object with an `impacts` array containing exactly four objects,
one for each section:

- `DECISION_GOVERNANCE`
- `DECISION_VALUE`
- `DECISION_MODEL_ROUTING`
- `DECISION_PORTFOLIO`

Each object contains:

| Field | Allowed values |
|---|---|
| `section_type` | One required section listed above |
| `impact_level` | `HIGH`, `MEDIUM`, `LOW`, `NONE` |
| `recommended_treatment` | `REASSESS`, `HUMAN_REVIEW`, `NO_CHANGE` |
| `confidence` | `HIGH`, `MEDIUM`, `LOW` |
| `rationale` | Non-empty evidence-grounded explanation |
| `source_evidence_ids` | IDs from the changed-Evidence input only |

## Safety rules

1. Use only facts present in the supplied input.
2. Every non-`NONE` impact must cite at least one changed Evidence ID.
3. `NONE` must use `NO_CHANGE`.
4. Do not approve, publish, or rewrite any decision.
5. Do not treat an impact recommendation as a human decision.
6. Return only schema-valid JSON.
