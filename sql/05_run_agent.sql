-- ============================================================
-- Run the Readiness Agent
-- ============================================================
-- Calls the stored procedure for a given assessment run.
-- Inspect the return value to confirm success or failure.
-- ============================================================

USE SCHEMA READINESSOPS.APP;

-- Execute the agent
CALL SP_RUN_READINESS_AGENT('RUN_001');

-- Quick result check
SELECT * FROM V_READINESSOPS_ACTION_BOARD
WHERE GAP_ID LIKE 'AR_%'
ORDER BY PRIORITY_SCORE DESC;
