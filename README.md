# SOLIFAN ReadinessOps

**AI-Powered Readiness Gap Agent for Snowflake Cortex**

An autonomous AI agent that evaluates organizational AI readiness by analyzing
assessment answers and evidence, then generates prioritized gaps and remediation
actions — entirely within Snowflake using Cortex AI.

---

## The Problem

Organizations adopting AI need structured readiness assessments to identify
governance gaps, missing evidence, and unowned risks. Manual gap analysis is
slow, inconsistent, and doesn't scale across multiple domains.

## The Outcome

A single `CALL SP_RUN_READINESS_AGENT('RUN_001')` triggers:

1. Reads all assessment answers and evidence
2. Constructs a structured prompt for Cortex AI
3. Receives and validates a JSON response
4. Writes prioritized gaps and actions to the database
5. Logs every step for audit compliance

**Verified result**: 5 gaps detected, 5 actions generated, 4 audit rows logged,
0 failures — with full transaction safety and idempotent reruns.

### Screenshots

#### Dashboard and Gap Board

![Dashboard and Gap Board](assets/screenshots/app_ss_01.png)

#### Recommended Actions and Agent Run History

![Recommended Actions and Agent Run History](assets/screenshots/app_ss_02.png)

---

## Architecture

```
Assessment Tables → Prompt Construction → Snowflake Cortex AI (mistral-large2)
    → JSON Validation → Gaps + Actions → Audit History → Action Board View
```

See [docs/architecture.md](docs/architecture.md) for full diagrams.

---

## Snowflake Features Used

| Feature | Usage |
|---------|-------|
| **Cortex AI** | `SNOWFLAKE.CORTEX.COMPLETE()` for LLM gap analysis |
| **SQL Scripting** | Stored procedure with LET, transactions, exceptions |
| **Semi-structured** | VARIANT, FLATTEN, TRY_PARSE_JSON for JSON |
| **Views** | Denormalized action board for dashboarding |
| **TRY_CAST** | Safe type conversion with fallback defaults |

---

## CoCo CLI Development Workflow

This project was built entirely using Snowflake's Cortex Code CLI:

- Live schema inspection via `sql_execute`
- Iterative procedure development with real-time error diagnosis
- Isolated unit testing of each SQL component
- Systematic code review for security and correctness
- Repository assembly from verified deployed state

---

## Quickstart

### Prerequisites

- Snowflake account with Cortex AI enabled (mistral-large2 model access)
- ACCOUNTADMIN or equivalent privileges

### Setup

```sql
-- 1. Create database, schema, and tables
-- Run: sql/01_setup.sql

-- 2. Load sample data
-- Run: sql/02_seed_data.sql

-- 3. Create the action board view
-- Run: sql/03_views.sql

-- 4. Deploy the agent procedure
-- Run: sql/04_stored_procedure.sql

-- 5. Run the agent
CALL READINESSOPS.APP.SP_RUN_READINESS_AGENT('RUN_001');

-- 6. Verify results
-- Run: sql/06_verify_agent_run.sql

-- 7. Deploy Streamlit dashboard (optional)
CREATE STAGE IF NOT EXISTS READINESSOPS.APP.STREAMLIT_STAGE DIRECTORY = (ENABLE = TRUE);
-- Upload app/streamlit_app.py and app/environment.yml to the stage
CREATE OR REPLACE STREAMLIT READINESSOPS.APP.READINESSOPS_DASHBOARD
  ROOT_LOCATION = '@READINESSOPS.APP.STREAMLIT_STAGE'
  MAIN_FILE = 'streamlit_app.py'
  QUERY_WAREHOUSE = <YOUR_WAREHOUSE>;
```

---

## Repository Structure

```
solifan-readinessops/
├── README.md                  ← You are here
├── COPYRIGHT.md               ← Copyright and use terms
├── .gitignore
├── SECURITY.md
├── app/
│   ├── streamlit_app.py       ← Streamlit dashboard
│   ├── environment.yml        ← Conda environment
│   └── README.md              ← Deployment instructions
├── sql/
│   ├── 01_setup.sql           ← Database + table DDL
│   ├── 02_seed_data.sql       ← Synthetic sample data
│   ├── 03_views.sql           ← Action board view
│   ├── 04_stored_procedure.sql ← AI agent procedure
│   ├── 05_run_agent.sql       ← Execute agent
│   ├── 06_verify_agent_run.sql ← Verification queries
│   └── 07_cleanup_generated_data.sql ← Remove AI output
├── prompts/
│   └── readiness_agent_prompt.md ← LLM prompt documentation
├── docs/
│   ├── architecture.md        ← System design + Mermaid diagrams
│   ├── demo-guide.md          ← 3-5 minute demo script
│   ├── hackathon-submission.md ← Evaluation criteria mapping
│   └── implementation-notes.md ← Debugging history
└── assets/
    └── screenshots/
        ├── app_ss_01.png          ← Dashboard and Gap Board
        └── app_ss_02.png          ← Recommended Actions and Agent Run History
```

---

## Demo Flow

1. Show assessment data with mixed answer/evidence statuses
2. Call `SP_RUN_READINESS_AGENT('RUN_001')`
3. Query generated gaps (sorted by priority)
4. Query generated actions (with owners and deadlines)
5. Show audit trail (4 timestamped steps)
6. Show action board view (denormalized output)

See [docs/demo-guide.md](docs/demo-guide.md) for the full script.

---

## Verified Results

| Metric | Value |
|--------|-------|
| Gaps generated | 5 |
| Actions generated | 5 |
| Audit history rows | 4 |
| FAILED rows | 0 |
| Sample data preserved | Yes |
| Transaction safety | Verified (rollback tested) |
| Idempotent rerun | Verified |

---

## Relationship to SOLIFAN CCoE Readiness Studio

ReadinessOps is a standalone AI agent prototype designed to demonstrate how
automated gap analysis and action generation could complement the SOLIFAN
CCoE Readiness Studio.

---

## Current Limitations

- Single LLM call per run (no batching for large question sets)
- Fixed set of allowed owner roles in the prompt
- No scheduling or automatic re-evaluation triggers
- Model selection is hardcoded (`mistral-large2`)

---

## Public-Safe Disclaimer

This repository contains only synthetic sample data created for demonstration
purposes. No real organizational assessments, credentials, account identifiers,
or proprietary information is included. All Snowflake connection details must be
configured locally and are excluded via `.gitignore`.

---

## Copyright and Use

Copyright © 2026 SOLIFAN LLC. All rights reserved.

This repository is published solely for hackathon evaluation and technical demonstration.

No license is granted to use, copy, modify, distribute, sublicense, commercialize, or create derivative works from the source code, prompts, schemas, documentation, screenshots, or other materials in this repository without prior written permission from SOLIFAN LLC.
