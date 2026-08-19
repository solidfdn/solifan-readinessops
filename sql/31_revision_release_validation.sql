-- ============================================================
-- Revision Release Validation
-- ============================================================
-- Read-only checks for publication state, comparison coverage, and naming.

USE SCHEMA APP;

SELECT '1_CURRENT_REVISION_RUN_STATUS_MISMATCH' AS TEST_NAME, COUNT(*) AS FAIL_COUNT
FROM ASSESSMENT_CASE case_record
JOIN ASSESSMENT_REVISION revision
  ON revision.REVISION_ID = case_record.CURRENT_REVISION_ID
JOIN ASSESSMENT_RUNS assessment_run
  ON assessment_run.RUN_ID = revision.RUN_ID
WHERE revision.STATUS <> 'PUBLISHED'
   OR assessment_run.STATUS <> 'PUBLISHED'
UNION ALL
SELECT '2_PUBLISHED_REVISION_RUN_STATUS_MISMATCH', COUNT(*)
FROM ASSESSMENT_REVISION revision
JOIN ASSESSMENT_RUNS assessment_run
  ON assessment_run.RUN_ID = revision.RUN_ID
WHERE revision.STATUS = 'PUBLISHED'
  AND assessment_run.STATUS <> 'PUBLISHED'
UNION ALL
SELECT '3_PUBLISHED_REVISION_WITHOUT_COMPARISON', COUNT(*)
FROM ASSESSMENT_REVISION revision
WHERE revision.REVISION_NO > 1
  AND revision.STATUS = 'PUBLISHED'
  AND NOT EXISTS (
      SELECT 1
      FROM ASSESSMENT_REVISION_DELTA delta
      WHERE delta.TO_REVISION_ID = revision.REVISION_ID
  )
UNION ALL
SELECT '4_DUPLICATE_REVISION_SUFFIX', COUNT(*)
FROM ASSESSMENT_RUNS
WHERE REGEXP_COUNT(RUN_NAME, ' - Revision [0-9]+') > 1
UNION ALL
SELECT '5_PUBLISHED_PROPOSAL_WITHOUT_GOVERNED_RECORD', COUNT(*)
FROM GOVERNANCE_AGENT_PROPOSAL proposal
LEFT JOIN GOVERNED_DECISION_RECORD decision_record
  ON decision_record.SOURCE_PROPOSAL_ID = proposal.PROPOSAL_ID
WHERE proposal.PROPOSAL_TYPE LIKE 'DECISION_%'
  AND proposal.STATUS = 'PUBLISHED'
  AND decision_record.DECISION_RECORD_ID IS NULL
ORDER BY TEST_NAME;

SELECT
    current_state.CASE_ID,
    current_state.CASE_NAME,
    current_state.CURRENT_REVISION_NO,
    current_state.CURRENT_RUN_ID,
    current_state.DRAFT_REVISION_NO,
    current_state.DRAFT_STATUS,
    current_state.HAS_PENDING_CHANGES,
    COUNT(DISTINCT comparison.DELTA_ID) AS COMPARISON_ITEM_COUNT
FROM V_ASSESSMENT_CASE_CURRENT current_state
LEFT JOIN V_ASSESSMENT_REVISION_COMPARISON comparison
  ON comparison.CASE_ID = current_state.CASE_ID
 AND comparison.TO_REVISION_NO = current_state.CURRENT_REVISION_NO
GROUP BY
    current_state.CASE_ID,
    current_state.CASE_NAME,
    current_state.CURRENT_REVISION_NO,
    current_state.CURRENT_RUN_ID,
    current_state.DRAFT_REVISION_NO,
    current_state.DRAFT_STATUS,
    current_state.HAS_PENDING_CHANGES
ORDER BY current_state.CASE_ID;
