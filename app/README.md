# Streamlit App — ReadinessOps Governance Review

## Purpose

`streamlit_app.py` is the human-governed review workspace for the current ReadinessOps implementation.

The application separates:

```text
Evidence context
→ AI proposal
→ Human decision
→ Controlled publication
→ Governed record and audit trail
```

## Files

| File | Purpose |
|---|---|
| `streamlit_app.py` | Main Streamlit in Snowflake application |
| `environment.yml` | Optional dependency declaration for packaging approaches that use it; the verified production deployment uploads the Python app directly |

## Workspaces

### Review queue

- Summary of proposals awaiting a human decision
- Issue-based review so Question, Answer, Evidence, and Rule Context appear once
- Gap, Risk, and Action proposal tabs shown only when that proposal type exists
- Decision status, domain, and severity filters
- Approve and Reject actions with an optional comment
- Approved-proposal publication queue
- Explicit **Back to review queue** action when no proposals await publication

### Published records

- Governed Gap, normalized Risk, and Action records
- Compact list plus one selected record detail
- Source Proposal and Agent Run traceability

### Audit trail

- Latest decision and publication events
- Compact list plus selected event detail
- Actor, timestamp, state transition, proposal, and comment

### Review setup

- Assessment context preview
- Standard evidence-grounding instruction
- Optional natural-language business instruction
- Cortex proposal generation
- Latest completed run and generated counts

## Runtime Compatibility

The application includes compatibility handling for the deployed Snowflake Streamlit runtime:

- `st.rerun` with fallback to `st.experimental_rerun`
- Dataframe rendering without unsupported `hide_index`
- One-based visible row numbering
- Native Python `bool` values for Streamlit boolean parameters

## Deployment

Use the parameterized production script from the repository root:

```powershell
.\scripts\deploy_production_dashboard.ps1 `
  -ConnectionName "<SNOWFLAKE_CLI_CONNECTION>" `
  -Database "READINESSOPS_VALIDATION" `
  -Schema "APP" `
  -Warehouse "READINESSOPS_WH" `
  -Role "ACCOUNTADMIN"
```

The script:

1. Resolves `app/streamlit_app.py` from the repository
2. Uploads it to a dedicated production stage
3. Recreates the configured Streamlit app
4. Leaves the legacy rollback stage unchanged
5. Prints the object description for verification

## Governance Boundary

The app never treats model output as a governed record.

```text
Cortex AI output
→ REVIEW_REQUIRED
→ APPROVED or REJECTED by a person
→ explicit publication
→ governed record
```

Rejected, unresolved, and merely approved proposals remain outside the published-record workspace until the publication procedure completes.
