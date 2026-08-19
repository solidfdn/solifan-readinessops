# Streamlit App — ReadinessOps Governance Review

## Purpose

The Streamlit in Snowflake application separates AI analysis from human decision and publication authority.

```text
Assessment + Evidence
→ AI Draft
→ Human Decision
→ Explicit Publication
→ Governed Record + Portfolio + Audit
→ Changed Evidence in Draft Revision
→ Advisory impact analysis
→ Human reassessment decision
```

## Files

| File | Purpose |
|---|---|
| `streamlit_app.py` | Main governance review application and workspace navigation |
| `value_control_plane.py` | Initiative, TXT/PDF Evidence, Revision history and impact analysis, Decision Pack, Published, and Portfolio workspaces |
| `environment.yml` | Snowflake package declaration with Streamlit pinned to `1.35.0` |

## Workspaces

### Review queue

- Legacy Gap, Risk, and Action review by issue
- Question, Answer, Evidence, and Rule Context displayed together
- Approve and Reject actions with an optional comment
- Explicit approved-proposal publication queue

### Value Control Plane

- **Initiative:** create or link an AI Initiative to the selected Assessment Run
- **Evidence:** upload TXT or PDF files, validate content, hash it, retain immutable originals in `EVIDENCE_ORIGINAL_OBJECT`, and parse PDFs inside the app
- **Revisions:** inspect Current, Draft, and historical states; Evidence lineage; frozen decision comparisons; and advisory changed-Evidence impact analysis
- **Decision Pack:** generate exactly four evidence-grounded drafts; inspect the five-step Agent execution trace and structured detail; edit, approve, or reject each section; explicitly publish approved sections
- **Published:** inspect Governed Decision Records for Governance, Value, Model Routing, and Portfolio
- **Portfolio:** compare initiative stage, owner, governance state, value assessment, recommendation, and priority

### Published records

- Governed legacy Gap, normalized Risk, and Action records
- Source Proposal and Agent Run traceability

### Audit trail

- Approval, rejection, and publication events
- Actor, timestamp, state transition, proposal, and comment

### Review setup

- Assessment context preview
- Optional natural-language business instruction
- Legacy Cortex proposal generation and latest-run metadata

## Runtime Compatibility

- Streamlit pinned to `1.35.0`
- `st.rerun` with fallback to `st.experimental_rerun`
- Dataframe rendering without unsupported `hide_index`
- One-based visible row numbering
- Native Python `bool` values for Streamlit boolean parameters

## Deployment

From the repository root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File '.\scripts\deploy_production_dashboard.ps1' `
  -ConnectionName '<SNOWFLAKE_CLI_CONNECTION>' `
  -Database 'READINESSOPS_REVISION_DEV' `
  -Schema 'APP' `
  -Warehouse 'READINESSOPS_WH' `
  -AppName 'READINESSOPS_REVISION_DASHBOARD' `
  -StageName 'READINESSOPS_REVISION_STAGE' `
  -ViewerRole 'READINESSOPS_EVALUATOR'
```

The script validates and uploads `environment.yml`, `value_control_plane.py`, and `streamlit_app.py`, then recreates the configured Streamlit object.

## Governance Boundary

The app never treats model output as a governed record.

```text
Cortex AI output
→ REVIEW_REQUIRED
→ APPROVED or REJECTED by a person
→ explicit publication confirmation
→ governed record
```

Rejected, unresolved, and merely approved proposals remain outside governed records until publication completes.
