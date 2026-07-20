-- ============================================================
-- Cleanup: Remove AI-Generated Data Only
-- ============================================================
--
-- !! WARNING !!
-- This script DELETES all AI-generated rows (AR_% prefix).
-- It does NOT affect sample/seed data (GAP_%, ACT_%, AGENT_RUN_%).
--
-- Use this to reset the environment before a fresh agent run,
-- or to clean up after demos and testing.
--
-- Deletion order respects referential dependencies:
--   1. Actions (references gaps)
--   2. Gaps
--   3. Agent history
-- ============================================================

USE SCHEMA READINESSOPS.APP;

-- Step 1: Remove generated actions (depend on gaps)
DELETE FROM RECOMMENDED_ACTIONS WHERE ACTION_ID LIKE 'AR_%';

-- Step 2: Remove generated gaps
DELETE FROM READINESS_GAPS WHERE GAP_ID LIKE 'AR_%';

-- Step 3: Remove agent run history (including any FAILED records)
DELETE FROM AGENT_RUN_HISTORY WHERE AGENT_RUN_ID LIKE 'AR_%';

-- Verify cleanup
SELECT 'Remaining AR_ gaps' AS check_name, COUNT(*) AS remaining FROM READINESS_GAPS WHERE GAP_ID LIKE 'AR_%'
UNION ALL
SELECT 'Remaining AR_ actions', COUNT(*) FROM RECOMMENDED_ACTIONS WHERE ACTION_ID LIKE 'AR_%'
UNION ALL
SELECT 'Remaining AR_ history', COUNT(*) FROM AGENT_RUN_HISTORY WHERE AGENT_RUN_ID LIKE 'AR_%';
