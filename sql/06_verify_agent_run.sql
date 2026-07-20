-- ============================================================
-- Verify Agent Run Results
-- ============================================================
-- Run after SP_RUN_READINESS_AGENT to validate correctness.
-- Does not assume a specific AR_ timestamp prefix.
-- ============================================================

USE SCHEMA READINESSOPS.APP;

-- 1. Agent-generated gaps (expect 5 rows)
SELECT 'GENERATED GAPS' AS check_name, COUNT(*) AS row_count
FROM READINESS_GAPS WHERE GAP_ID LIKE 'AR_%';

-- 2. Agent-generated actions (expect 5 rows)
SELECT 'GENERATED ACTIONS' AS check_name, COUNT(*) AS row_count
FROM RECOMMENDED_ACTIONS WHERE ACTION_ID LIKE 'AR_%';

-- 3. Agent run history steps (expect 4 rows: LOAD, VALIDATE, DETECT, GENERATE)
SELECT 'AGENT HISTORY STEPS' AS check_name, COUNT(*) AS row_count
FROM AGENT_RUN_HISTORY WHERE AGENT_RUN_ID LIKE 'AR_%' AND AGENT_STEP != 'FAILED';

-- 4. FAILED audit rows (expect 0)
SELECT 'FAILED ROWS' AS check_name, COUNT(*) AS row_count
FROM AGENT_RUN_HISTORY WHERE AGENT_STEP = 'FAILED';

-- 5. Sample data preservation check
SELECT 'SAMPLE GAPS' AS check_name, COUNT(*) AS row_count
FROM READINESS_GAPS WHERE GAP_ID LIKE 'GAP_%';

SELECT 'SAMPLE ACTIONS' AS check_name, COUNT(*) AS row_count
FROM RECOMMENDED_ACTIONS WHERE ACTION_ID LIKE 'ACT_%';

SELECT 'SAMPLE HISTORY' AS check_name, COUNT(*) AS row_count
FROM AGENT_RUN_HISTORY WHERE AGENT_RUN_ID LIKE 'AGENT_RUN_%';

-- 6. Check no AR_TEST_% leftover rows exist
SELECT 'TEST LEFTOVER GAPS' AS check_name, COUNT(*) AS row_count
FROM READINESS_GAPS WHERE GAP_ID LIKE 'AR_TEST_%';

SELECT 'TEST LEFTOVER ACTIONS' AS check_name, COUNT(*) AS row_count
FROM RECOMMENDED_ACTIONS WHERE ACTION_ID LIKE 'AR_TEST_%';

-- 7. Detail: generated gaps
SELECT GAP_ID, QUESTION_ID, GAP_TITLE, SEVERITY, PRIORITY_SCORE
FROM READINESS_GAPS WHERE GAP_ID LIKE 'AR_%'
ORDER BY PRIORITY_SCORE DESC;

-- 8. Detail: generated actions
SELECT ACTION_ID, GAP_ID, ACTION_TITLE, OWNER_NAME, DUE_IN_DAYS, ACTION_STATUS
FROM RECOMMENDED_ACTIONS WHERE ACTION_ID LIKE 'AR_%'
ORDER BY DUE_IN_DAYS ASC;

-- 9. Detail: agent history timeline
SELECT AGENT_RUN_ID, AGENT_STEP, INPUT_SUMMARY, OUTPUT_SUMMARY, CREATED_AT
FROM AGENT_RUN_HISTORY WHERE AGENT_RUN_ID LIKE 'AR_%'
ORDER BY CREATED_AT ASC;
