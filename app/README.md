# Streamlit App — ReadinessOps Governance Workspace

## Files

| File | Purpose |
|---|---|
| `streamlit_app.py` | Main Streamlit in Snowflake application |
| `environment.yml` | Conda environment |

## Deployment

```sql
CREATE STAGE IF NOT EXISTS READINESSOPS.APP.STREAMLIT_STAGE
  DIRECTORY = (ENABLE = TRUE);

PUT file://app/streamlit_app.py
  @READINESSOPS.APP.STREAMLIT_STAGE
  OVERWRITE = TRUE
  AUTO_COMPRESS = FALSE;

PUT file://app/environment.yml
  @READINESSOPS.APP.STREAMLIT_STAGE
  OVERWRITE = TRUE
  AUTO_COMPRESS = FALSE;

CREATE OR REPLACE STREAMLIT READINESSOPS.APP.READINESSOPS_DASHBOARD
  ROOT_LOCATION = '@READINESSOPS.APP.STREAMLIT_STAGE'
  MAIN_FILE = 'streamlit_app.py'
  QUERY_WAREHOUSE = '<YOUR_WAREHOUSE>';
```

## Features

- Assessment Run selector
- Questions, Published Gaps, Latest Draft Proposals, and Agent Status metrics
- Latest Governance Review status, model, completion time, instruction, and generated counts
- Standard governance instruction display
- Optional business-priority instruction
- Assessment-context preview
- Full governance review execution
- Explicit Gap, Risk, and Action proposal selector
- Source traceability expansion
- Review comments
- Approve and Reject actions
- Persistent proposal-type selection after reruns
- Approved-proposal counters
- Controlled publication confirmation
- Publication result message
- Agent Run History
- Canonical Gap Board and Recommended Actions
- Public-safe disclaimer

## Governance Boundary

The app does not write model output directly to canonical dashboard tables.

```text
Cortex AI result
→ REVIEW_REQUIRED proposal
→ Human APPROVED or REJECTED
→ Controlled publish
→ Canonical record
```

Rejected and unreviewed proposals remain outside canonical dashboard results.

## Design

- White background with navy and blue emphasis
- Minimal decorative treatment
- Clear state labels
- Explicit review controls
- Readable without prior explanation