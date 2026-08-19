-- ============================================================
-- Evidence Change Impact Analysis Foundation
-- ============================================================
-- Additive-only foundation for AI-assisted impact analysis.
-- Existing Decision Pack generation, review, and publication objects are
-- intentionally not changed by this file.
-- ============================================================

USE SCHEMA APP;

CREATE TABLE IF NOT EXISTS REVISION_IMPACT_ANALYSIS_RUN (
    ANALYSIS_RUN_ID             VARCHAR(16777216) NOT NULL,
    REVISION_ID                 VARCHAR(16777216) NOT NULL,
    BASE_REVISION_ID            VARCHAR(16777216) NOT NULL,
    BASE_ASSESSMENT_RUN_ID      VARCHAR(16777216) NOT NULL,
    TARGET_ASSESSMENT_RUN_ID    VARCHAR(16777216) NOT NULL,
    STATUS                      VARCHAR(50) NOT NULL,
    MODEL_NAME                  VARCHAR(200) NOT NULL,
    PROMPT_VERSION              VARCHAR(100) NOT NULL,
    INPUT_FINGERPRINT           VARCHAR(64) NOT NULL,
    CHANGED_EVIDENCE_COUNT      NUMBER(38,0) NOT NULL,
    STARTED_AT                  TIMESTAMP_NTZ(9) NOT NULL,
    COMPLETED_AT                TIMESTAMP_NTZ(9),
    ERROR_MESSAGE               VARCHAR(16777216),
    CREATED_BY                  VARCHAR(200) NOT NULL DEFAULT CURRENT_USER(),
    CREATED_AT                  TIMESTAMP_NTZ(9) NOT NULL DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'One governed Cortex execution that evaluates changed Evidence against the published base Decision Pack.';

CREATE TABLE IF NOT EXISTS REVISION_IMPACT_ANALYSIS_ITEM (
    IMPACT_ITEM_ID              VARCHAR(16777216) NOT NULL,
    ANALYSIS_RUN_ID             VARCHAR(16777216) NOT NULL,
    REVISION_ID                 VARCHAR(16777216) NOT NULL,
    SECTION_TYPE                VARCHAR(50) NOT NULL,
    IMPACT_LEVEL                VARCHAR(20) NOT NULL,
    RECOMMENDED_TREATMENT       VARCHAR(50) NOT NULL,
    CONFIDENCE                  VARCHAR(20) NOT NULL,
    RATIONALE                   VARCHAR(16777216) NOT NULL,
    SOURCE_EVIDENCE_IDS         ARRAY NOT NULL,
    CREATED_AT                  TIMESTAMP_NTZ(9) NOT NULL DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Exactly four advisory impact items per completed analysis Run; these rows never approve or publish a decision.';

CREATE OR REPLACE VIEW V_REVISION_EVIDENCE_CHANGE AS
SELECT
    target_revision.CASE_ID,
    case_record.CASE_NAME,
    target_revision.REVISION_ID,
    target_revision.REVISION_NO,
    target_revision.RUN_ID AS TARGET_ASSESSMENT_RUN_ID,
    target_revision.BASE_REVISION_ID,
    base_revision.REVISION_NO AS BASE_REVISION_NO,
    base_revision.RUN_ID AS BASE_ASSESSMENT_RUN_ID,
    lineage.CHANGE_SET_ID,
    lineage.SNAPSHOT_ROLE AS EVIDENCE_CHANGE_TYPE,
    lineage.EVIDENCE_ID,
    lineage.ORIGIN_EVIDENCE_ID,
    lineage.INHERITED_FROM_EVIDENCE_ID AS REPLACED_EVIDENCE_ID,
    evidence.EVIDENCE_TITLE,
    evidence.SOURCE_FILENAME,
    evidence.SOURCE_TYPE,
    evidence.MEDIA_TYPE,
    evidence.CONTENT_SHA256,
    evidence.EVIDENCE_STATUS,
    evidence.EVIDENCE_TEXT,
    evidence.UPLOADED_BY,
    evidence.UPLOADED_AT,
    lineage.CREATED_AT AS CHANGE_RECORDED_AT
FROM ASSESSMENT_REVISION target_revision
JOIN ASSESSMENT_CASE case_record
  ON case_record.CASE_ID = target_revision.CASE_ID
JOIN ASSESSMENT_REVISION base_revision
  ON base_revision.REVISION_ID = target_revision.BASE_REVISION_ID
 AND base_revision.CASE_ID = target_revision.CASE_ID
JOIN ASSESSMENT_REVISION_EVIDENCE lineage
  ON lineage.REVISION_ID = target_revision.REVISION_ID
JOIN EVIDENCE_ITEMS evidence
  ON evidence.EVIDENCE_ID = lineage.EVIDENCE_ID
 AND evidence.RUN_ID = target_revision.RUN_ID
WHERE lineage.SNAPSHOT_ROLE IN ('ADDED', 'REPLACED');

CREATE OR REPLACE VIEW V_REVISION_IMPACT_ANALYSIS AS
SELECT
    analysis.ANALYSIS_RUN_ID,
    analysis.REVISION_ID,
    revision.CASE_ID,
    case_record.CASE_NAME,
    revision.REVISION_NO,
    revision.STATUS AS REVISION_STATUS,
    IFF(case_record.ACTIVE_DRAFT_REVISION_ID = revision.REVISION_ID, TRUE, FALSE) AS IS_ACTIVE_DRAFT,
    analysis.BASE_REVISION_ID,
    base_revision.REVISION_NO AS BASE_REVISION_NO,
    analysis.BASE_ASSESSMENT_RUN_ID,
    analysis.TARGET_ASSESSMENT_RUN_ID,
    analysis.STATUS AS ANALYSIS_STATUS,
    analysis.MODEL_NAME,
    analysis.PROMPT_VERSION,
    analysis.INPUT_FINGERPRINT,
    analysis.CHANGED_EVIDENCE_COUNT,
    analysis.STARTED_AT,
    analysis.COMPLETED_AT,
    analysis.ERROR_MESSAGE,
    analysis.CREATED_BY,
    item.IMPACT_ITEM_ID,
    item.SECTION_TYPE,
    item.IMPACT_LEVEL,
    item.RECOMMENDED_TREATMENT,
    item.CONFIDENCE,
    item.RATIONALE,
    item.SOURCE_EVIDENCE_IDS,
    IFF(
        ROW_NUMBER() OVER (
            PARTITION BY analysis.REVISION_ID, item.SECTION_TYPE
            ORDER BY analysis.COMPLETED_AT DESC NULLS LAST, analysis.CREATED_AT DESC
        ) = 1,
        TRUE,
        FALSE
    ) AS IS_LATEST
FROM REVISION_IMPACT_ANALYSIS_RUN analysis
JOIN ASSESSMENT_REVISION revision
  ON revision.REVISION_ID = analysis.REVISION_ID
JOIN ASSESSMENT_CASE case_record
  ON case_record.CASE_ID = revision.CASE_ID
JOIN ASSESSMENT_REVISION base_revision
  ON base_revision.REVISION_ID = analysis.BASE_REVISION_ID
LEFT JOIN REVISION_IMPACT_ANALYSIS_ITEM item
  ON item.ANALYSIS_RUN_ID = analysis.ANALYSIS_RUN_ID
 AND item.REVISION_ID = analysis.REVISION_ID;

-- Rollback guidance (only if the feature has not been adopted):
--   DROP VIEW IF EXISTS V_REVISION_IMPACT_ANALYSIS;
--   DROP VIEW IF EXISTS V_REVISION_EVIDENCE_CHANGE;
--   DROP TABLE IF EXISTS REVISION_IMPACT_ANALYSIS_ITEM;
--   DROP TABLE IF EXISTS REVISION_IMPACT_ANALYSIS_RUN;
