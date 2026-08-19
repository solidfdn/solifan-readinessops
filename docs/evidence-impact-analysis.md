# Evidence Change Impact Analysis

## Decision

Implement a Snowflake-native, advisory analysis between Evidence registration
and Decision Pack regeneration. The feature determines which of the four
published decision sections can be affected by a Draft Revision's changed
Evidence.

## User flow

```text
Published Revision
→ Create Draft Revision
→ Add or replace Evidence
→ Analyze Evidence impact
→ Human inspects four impact results
→ Optionally regenerate Decision Pack
→ Existing review and publication workflow
```

## Scope

### Included

- Active Draft Revision precondition
- `ADDED` and `REPLACED` Evidence isolation
- Published base Decision Pack snapshot
- One Cortex inference call
- Exactly four section-level results
- Evidence-citation validation
- Input fingerprint and duplicate-run prevention
- Model, prompt, actor, timestamps, and failure trace
- Revision UI with summary metrics and detail
- Read-only validation queries

### Excluded from this release

- Automatic Decision Pack regeneration
- Automatic approval or publication
- Blocking publication based on an AI result
- Cross-company or cross-department authorization
- Notifications or periodic review scheduling
- Model or prompt A/B evaluation

## Decision contract

| Field | Contract |
|---|---|
| Section | Governance, Value, Model Routing, Portfolio; one each |
| Impact | `HIGH`, `MEDIUM`, `LOW`, `NONE` |
| Treatment | `REASSESS`, `HUMAN_REVIEW`, `NO_CHANGE` |
| Confidence | `HIGH`, `MEDIUM`, `LOW` |
| Rationale | Required |
| Citations | Changed Evidence IDs only; required for non-`NONE` |

## Safety invariants

1. Published Revisions and Governed Decision Records remain immutable.
2. The impact procedure writes only to impact-analysis tables.
3. Current State moves only through the existing publication procedure.
4. A completed analysis contains exactly four distinct sections.
5. Identical governed inputs do not create a second completed analysis.
6. Every non-`NONE` result is traceable to changed Evidence.
7. The UI labels all results as requiring human confirmation.

## Acceptance checks

| Scenario | Expected result |
|---|---|
| Published Revision selected | Read-only historical analysis; no Run button |
| Active Draft without changed Evidence | Analysis disabled with guidance |
| Active Draft with changed Evidence | Analysis available |
| Base has fewer than four governed decisions | Procedure fails without partial writes |
| Cortex returns incomplete or invalid output | Failed Run recorded; no items persisted |
| Cortex cites inherited or unknown Evidence | Output rejected |
| Same inputs rerun | `SKIPPED` with prior analysis ID |
| Valid output | One completed Run and exactly four items |
| Impact output exists | No proposal, approval, publication, or Current State mutation |

Run `sql/35_evidence_impact_validation.sql`; every `FAIL_COUNT` must be zero.

## Validation result

The 2026-08-19 isolated validation completed with one changed Evidence item,
four persisted impact items, four `HIGH` impacts, four `REASSESS`
recommendations, duplicate execution returning `SKIPPED`, and zero failures
across all seven database integrity checks. See
[hackathon/REVISION_EVIDENCE_IMPACT_TEST_REPORT.md](hackathon/REVISION_EVIDENCE_IMPACT_TEST_REPORT.md).
