# Hackathon Submission

## Project: SOLIFAN ReadinessOps — AI-Powered Readiness Gap Agent

### What It Does

An AI agent that evaluates organizational AI readiness by analyzing assessment
answers and evidence, then automatically generates prioritized gaps and remediation
actions using Snowflake Cortex AI.

### Application Screenshots

| Dashboard | After Agent Run |
|:---------:|:---------------:|
| ![Dashboard](../assets/screenshots/app_ss_01.png) | ![Agent Run](../assets/screenshots/app_ss_02.png) |

---

## Evaluation Criteria Mapping

### Technical Execution

| Aspect | Implementation |
|--------|---------------|
| Snowflake-native | Entire agent runs as a SQL stored procedure |
| Cortex AI integration | `SNOWFLAKE.CORTEX.COMPLETE('mistral-large2', ...)` |
| Structured output parsing | FLATTEN + TRY_PARSE_JSON on LLM response |
| Error handling | Transaction rollback + FAILED audit logging |
| Type safety | TRY_CAST with fallback defaults |
| Idempotency | AR_ prefix cleanup before each run |
| Audit trail | 4-step AGENT_RUN_HISTORY logging |

### Solution Completeness

| Component | Status |
|-----------|--------|
| Data model (8 tables) | Deployed and verified |
| AI agent procedure | Deployed and verified |
| Denormalized view | Deployed and verified |
| Seed data for demo | Complete |
| Verification suite | Complete |
| Cleanup scripts | Complete |
| Prompt engineering | Documented |
| Architecture documentation | Complete |
| Streamlit dashboard | Deployed and verified |

### Real-World Relevance

- **Problem**: Organizations struggle to systematically identify and track AI readiness gaps
- **Solution**: Automated gap detection with evidence-based severity scoring
- **Users**: CCoE teams, governance leads, risk managers
- **Scale**: Works with any number of assessment questions per run
- **Governance**: Full audit trail of AI-generated recommendations

---

## Built With CoCo CLI

The entire implementation was developed using Snowflake's Cortex Code CLI:

1. **Schema exploration** — Inspected live Snowflake objects via `sql_execute`
2. **Procedure authoring** — Iterative development with syntax validation
3. **Debugging** — Identified TRY_CAST VARIANT limitation through isolated testing
4. **Code review** — Systematic audit for security, correctness, and transaction safety
5. **Repository assembly** — Generated all documentation and SQL from verified state

---

## Verified Results

From the actual production run on 2026-07-18:

| Metric | Value |
|--------|-------|
| Gaps generated | 5 |
| Actions generated | 5 |
| History rows logged | 4 |
| FAILED audit rows | 0 |
| Sample data preserved | Yes (5 gaps, 5 actions, 4 history) |
| Transaction rollback tested | Yes |
| Markdown fence stripping | Confirmed needed and working |

---

## Relationship to SOLIFAN CCoE Readiness Studio

ReadinessOps is the backend agent layer for the SOLIFAN Cloud Center of Excellence
(CCoE) Readiness Studio. It provides:

- Automated assessment gap analysis
- Evidence-based severity scoring
- Prioritized action generation with ownership assignment
- Audit-ready execution history

The Readiness Studio will consume the `V_READINESSOPS_ACTION_BOARD` view
to present results through an interactive Streamlit dashboard.
