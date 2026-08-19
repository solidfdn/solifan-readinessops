-- ============================================================
-- Revision Draft Validation
-- ============================================================
-- Read-only checks. Expected FAIL_COUNT is zero for every row.
-- ============================================================

USE SCHEMA APP;

SELECT '1_ACTIVE_DRAFT_COUNT_PER_CASE' AS TEST_NAME, COUNT(*) AS FAIL_COUNT
FROM (
    SELECT CASE_ID
    FROM ASSESSMENT_REVISION
    WHERE STATUS IN ('DRAFT', 'GENERATING', 'FAILED', 'REVIEW_REQUIRED')
    GROUP BY CASE_ID
    HAVING COUNT(*) > 1
)
UNION ALL
SELECT '2_DRAFT_WITHOUT_CHANGE_SET', COUNT(*)
FROM ASSESSMENT_REVISION revision
LEFT JOIN ASSESSMENT_CHANGE_SET change_set
  ON change_set.TARGET_REVISION_ID = revision.REVISION_ID
 AND change_set.STATUS = 'PENDING'
WHERE revision.STATUS IN ('DRAFT', 'FAILED')
  AND change_set.CHANGE_SET_ID IS NULL
UNION ALL
SELECT '3_DRAFT_RUN_ANSWER_COUNT_MISMATCH', COUNT(*)
FROM ASSESSMENT_REVISION revision
JOIN ASSESSMENT_REVISION base_revision
  ON base_revision.REVISION_ID = revision.BASE_REVISION_ID
WHERE revision.STATUS IN ('DRAFT', 'FAILED')
  AND (SELECT COUNT(*) FROM ASSESSMENT_ANSWERS WHERE RUN_ID = revision.RUN_ID)
      <> (SELECT COUNT(*) FROM ASSESSMENT_ANSWERS WHERE RUN_ID = base_revision.RUN_ID)
UNION ALL
SELECT '4_DRAFT_INHERITED_EVIDENCE_COUNT_MISMATCH', COUNT(*)
FROM ASSESSMENT_REVISION revision
JOIN ASSESSMENT_REVISION base_revision
  ON base_revision.REVISION_ID = revision.BASE_REVISION_ID
WHERE revision.STATUS IN ('DRAFT', 'FAILED')
  AND (SELECT COUNT(*)
       FROM ASSESSMENT_REVISION_EVIDENCE
       WHERE REVISION_ID = revision.REVISION_ID
         AND SNAPSHOT_ROLE = 'INHERITED')
      <> (SELECT COUNT(*)
          FROM ASSESSMENT_REVISION_EVIDENCE
          WHERE REVISION_ID = base_revision.REVISION_ID)
UNION ALL
SELECT '5_BASE_EVIDENCE_CHANGED_BY_DRAFT', COUNT(*)
FROM ASSESSMENT_REVISION_EVIDENCE draft_lineage
JOIN ASSESSMENT_REVISION draft_revision
  ON draft_revision.REVISION_ID = draft_lineage.REVISION_ID
JOIN EVIDENCE_ITEMS draft_evidence
  ON draft_evidence.EVIDENCE_ID = draft_lineage.EVIDENCE_ID
JOIN EVIDENCE_ITEMS base_evidence
  ON base_evidence.EVIDENCE_ID = draft_lineage.INHERITED_FROM_EVIDENCE_ID
WHERE draft_lineage.SNAPSHOT_ROLE = 'INHERITED'
  AND (
      draft_evidence.CONTENT_SHA256 IS DISTINCT FROM base_evidence.CONTENT_SHA256
      OR draft_evidence.STAGE_PATH IS DISTINCT FROM base_evidence.STAGE_PATH
      OR draft_evidence.EVIDENCE_TEXT IS DISTINCT FROM base_evidence.EVIDENCE_TEXT
  )
ORDER BY TEST_NAME;

SELECT
    current_state.CASE_ID,
    current_state.CASE_NAME,
    current_state.CURRENT_REVISION_NO,
    current_state.CURRENT_RUN_ID,
    current_state.DRAFT_REVISION_NO,
    current_state.DRAFT_STATUS,
    current_state.HAS_PENDING_CHANGES,
    current_state.PENDING_CHANGE_SET_ID
FROM V_ASSESSMENT_CASE_CURRENT current_state
ORDER BY current_state.CASE_ID;
