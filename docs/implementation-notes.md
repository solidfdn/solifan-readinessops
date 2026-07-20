# Implementation Notes

## Debugging History

This document records the verified debugging steps taken during development
of `SP_RUN_READINESS_AGENT`. All issues were identified and resolved using
Snowflake's Cortex Code CLI through iterative testing.

---

### Issue 1: Cortex COMPLETE Returns Markdown Fences

**Discovery**: Called `SNOWFLAKE.CORTEX.COMPLETE('mistral-large2', ...)` directly
and observed the response wrapped in ` ```json ... ``` ` despite explicit prompt
instructions not to.

**Fix**: Added `REGEXP_REPLACE` to strip fences before JSON parsing:
```sql
v_llm_response := REGEXP_REPLACE(:v_llm_response, '^\\s*```(json|JSON)?\\s*', '');
v_llm_response := REGEXP_REPLACE(:v_llm_response, '\\s*```\\s*$', '');
v_llm_response := TRIM(:v_llm_response);
```

**Verification**: Tested with synthetic fenced JSON — `TRY_PARSE_JSON` returned
valid VARIANT after stripping.

---

### Issue 2: TRY_PARSE_JSON vs PARSE_JSON

**Discovery**: If the LLM returns malformed JSON, `PARSE_JSON` throws an unhandled
exception that could leave the database in an inconsistent state.

**Fix**: Used `TRY_PARSE_JSON` which returns NULL on invalid input, allowing
graceful handling:
```sql
v_parsed := (SELECT TRY_PARSE_JSON(:v_llm_response));
IF (:v_parsed IS NULL) THEN
    ROLLBACK;
    -- log FAILED record
    RETURN 'FAILED: ...';
END IF;
```

---

### Issue 3: Transaction and Rollback Placement

**Discovery (code review)**: Initial version placed `DELETE` statements before
`BEGIN TRANSACTION`. This meant rollback would not restore deleted data.

**Fix**: Moved `BEGIN TRANSACTION` before all `DELETE` statements so that
both cleanup and insertion are atomic.

**Verification**: Tested exception path — confirmed database returns to
pre-call state on failure.

---

### Issue 4: TRY_CAST Rejects VARIANT Directly

**Discovery**: First procedure execution hit internal error `300010`. Isolated
testing revealed:

```sql
-- FAILS: "Function TRY_CAST cannot be used with arguments of types VARIANT and NUMBER(38,0)"
TRY_CAST(f.VALUE:priority_score AS INTEGER)

-- WORKS: Cast to VARCHAR first, then to INTEGER
TRY_CAST(f.VALUE:priority_score::VARCHAR AS INTEGER)
```

**Root cause**: Snowflake's `TRY_CAST` function does not accept VARIANT as input.
The `::VARCHAR` accessor extracts the value as a string, which `TRY_CAST` can
then safely convert.

**Fix**: Applied `::VARCHAR` before `TRY_CAST` for both `priority_score` and
`due_in_days`, with `COALESCE` defaults (50 and 30 respectively).

**Verification**: Anonymous block test confirmed INSERT succeeded. Full procedure
call then completed successfully.

---

### Issue 5: INNER JOIN for Action-Gap Linking

**Discovery (code review)**: Using `LEFT JOIN` when inserting actions could produce
rows with NULL `GAP_ID` if the LLM returned a `question_id` not matching any gap.

**Fix**: Changed to `INNER JOIN` with additional filter `g.GAP_ID LIKE :v_agent_run_prefix || '%'`
to ensure actions only link to gaps created in the same run.

---

## End-to-End Verification

After all fixes, the procedure was called successfully:

```
CALL SP_RUN_READINESS_AGENT('RUN_001');
→ 'Agent complete. Generated 5 gaps and 5 actions for run RUN_001'
```

Post-run validation confirmed:
- 5 new gaps with AR_ prefix (priorities 70-95)
- 5 new actions linked to correct gaps
- 4 agent history rows with distinct timestamps
- 0 FAILED audit rows
- All sample data (GAP_%, ACT_%, AGENT_RUN_%) preserved intact

---

### Issue 6: Streamlit Agent Status Metric — Alphabetical MAX

**Discovery (validation)**: The metric `MAX(AGENT_STEP)` returned `VALIDATE_EVIDENCE`
instead of `GENERATE_ACTIONS` because SQL `MAX` on VARCHAR is alphabetical, not temporal.

**Fix**: Changed to subquery with `ORDER BY CREATED_AT DESC LIMIT 1`:
```sql
SELECT COALESCE(
    (SELECT AGENT_STEP FROM AGENT_RUN_HISTORY
     WHERE RUN_ID = :run_id AND AGENT_RUN_ID LIKE 'AR_%'
     ORDER BY CREATED_AT DESC LIMIT 1),
    'NO RUNS'
) AS S
```

**Verification**: Returns `GENERATE_ACTIONS` after a successful run (the chronologically
last step), and `FAILED` if the most recent step was a failure.

---

## Clean-Room Validation

The repository SQL scripts were validated end-to-end in a separate
`READINESSOPS_VALIDATION` database with no prior state:

1. All 8 tables created successfully
2. View created successfully
3. Procedure created successfully
4. Seed data loaded (deterministic reruns confirmed)
5. Agent run: 5 gaps, 5 actions, 4 history steps, 0 failures
6. Cleanup removed only AR_% rows, preserved sample data
7. Second agent run after cleanup succeeded identically
8. Streamlit app deployed and queries validated

### Required Privileges

- `CREATE DATABASE` (or existing database with CREATE SCHEMA)
- `CREATE TABLE`, `CREATE VIEW`, `CREATE PROCEDURE` in target schema
- `USAGE` on `SNOWFLAKE.CORTEX` (for COMPLETE function)
- `USAGE` on a warehouse (for query execution and Streamlit)
- `CREATE STREAMLIT` (for dashboard deployment)
- `CREATE STAGE` (for Streamlit file hosting)

### Cortex Dependencies

- Model: `mistral-large2` must be available in the account's region
- Function: `SNOWFLAKE.CORTEX.COMPLETE()` must be enabled
- No external network access required
