# Revision Evidence Impact Test Report

Date: 2026-08-19

## Scope

The Revision extension was validated against an active Draft Revision whose
published base decisions remained immutable. The test confirmed that only
changed Evidence is analyzed, the output remains advisory, and no impact result
can approve, publish, regenerate, or advance Current State.

## Environment

| Item | Value |
|---|---|
| Database | `READINESSOPS_REVISION_DEV` |
| Schema | `APP` |
| Streamlit app | `READINESSOPS_REVISION_DASHBOARD` |
| Warehouse | `READINESSOPS_WH` |
| Model | `mistral-large2` |
| Prompt version | `EVIDENCE_IMPACT_V1` |

## Validated Result

| Check | Result |
|---|---:|
| Changed Evidence | 1 |
| Published base decision sections evaluated | 4 |
| Impact items persisted | 4 |
| `HIGH` impact | 4 |
| `REASSESS` recommended | 4 |
| Human confirmation label | Present |
| Changed-Evidence citations | Validated |
| Duplicate execution | `SKIPPED` |
| Database integrity checks | 7 checks, 0 failures |
| Streamlit deployment | Completed |

## Safety Assertions

- Published Revisions and Governed Decision Records remained unchanged.
- Analysis used only `ADDED` or `REPLACED` Evidence from the active Draft.
- The procedure produced exactly one result for each required Decision Pack
  section.
- Model, prompt, actor, timestamp, input fingerprint, and failure state were
  retained.
- A person remains responsible for deciding whether to regenerate the Decision
  Pack.

## Acceptance Result

**PASS.** AI can detect what changed. People decide what changes. Snowflake
keeps Evidence lineage, frozen decisions, impact analysis, and publication
history in one governed system.
