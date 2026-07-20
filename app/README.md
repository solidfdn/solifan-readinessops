# Streamlit App — ReadinessOps Dashboard

## Files

| File | Purpose |
|------|---------|
| `streamlit_app.py` | Main Streamlit application |
| `environment.yml` | Conda environment for Streamlit in Snowflake |

## Deployment

```sql
-- Create a stage for the app files
CREATE STAGE IF NOT EXISTS READINESSOPS.APP.STREAMLIT_STAGE
  DIRECTORY = (ENABLE = TRUE);

-- Upload files (from SnowSQL or Snowsight)
PUT file://app/streamlit_app.py @READINESSOPS.APP.STREAMLIT_STAGE OVERWRITE=TRUE AUTO_COMPRESS=FALSE;
PUT file://app/environment.yml @READINESSOPS.APP.STREAMLIT_STAGE OVERWRITE=TRUE AUTO_COMPRESS=FALSE;

-- Create the Streamlit app
CREATE OR REPLACE STREAMLIT READINESSOPS.APP.READINESSOPS_DASHBOARD
  ROOT_LOCATION = '@READINESSOPS.APP.STREAMLIT_STAGE'
  MAIN_FILE = 'streamlit_app.py'
  QUERY_WAREHOUSE = '<YOUR_WAREHOUSE>';
```

## Features

- Assessment run selector
- Summary metrics (questions, gaps, actions, agent status)
- Run Agent button with confirmation and error handling
- Gap Board with domain, severity, priority, and source distinction
- Recommended Actions with owner, deadline, and linked gap
- Agent Run History with step status and failure messages
- Public-safe disclaimer footer

## Design

- Professional, restrained styling
- White background with navy/blue emphasis
- No decorative gradients
- Clear visual hierarchy
- Readable without prior explanation
