-- ============================================================
-- Revision Lifecycle Foundation
-- ============================================================
-- Purpose:
--   Add append-only Revision lifecycle structures without changing
--   existing assessment, evidence, proposal, decision, or audit rows.
--
-- Safety properties:
--   * No UPDATE or DELETE is issued against existing application tables.
--   * Existing ASSESSMENT_RUNS.RUN_ID values remain unchanged.
--   * Current State is an explicit pointer, never a latest-timestamp rule.
--   * Approval and publication remain separate boundaries.
--   * Development reset and hard purge are disabled by default.
--
-- This file creates schema only. Existing-run migration is intentionally
-- deferred until the production object inventory and migration preview pass.
-- ============================================================

USE SCHEMA READINESSOPS_VALIDATION.APP;

-- ============================================================
-- A. ASSESSMENT_CASE
-- Stable container for one continuously managed assessment.
-- ============================================================
CREATE TABLE IF NOT EXISTS ASSESSMENT_CASE (
    CASE_ID                    VARCHAR(16777216) NOT NULL,
    INITIATIVE_ID              VARCHAR(16777216),
    CASE_NAME                  VARCHAR(16777216) NOT NULL,
    STATUS                     VARCHAR(50) NOT NULL DEFAULT 'ACTIVE',
    CURRENT_REVISION_ID        VARCHAR(16777216),
    ACTIVE_DRAFT_REVISION_ID   VARCHAR(16777216),
    DATA_ORIGIN                VARCHAR(50) NOT NULL DEFAULT 'USER',
    CREATED_BY                 VARCHAR(200) NOT NULL DEFAULT CURRENT_USER(),
    CREATED_AT                 TIMESTAMP_NTZ(9) NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    UPDATED_BY                 VARCHAR(200) NOT NULL DEFAULT CURRENT_USER(),
    UPDATED_AT                 TIMESTAMP_NTZ(9) NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    ARCHIVED_BY                VARCHAR(200),
    ARCHIVED_AT                TIMESTAMP_NTZ(9),
    ARCHIVE_REASON             VARCHAR(16777216)
)
COMMENT = 'Stable assessment container. Current State changes only through explicit Revision publication.';

-- ============================================================
-- B. ASSESSMENT_REVISION
-- One assessment snapshot mapped to one existing ASSESSMENT_RUNS row.
-- ============================================================
CREATE TABLE IF NOT EXISTS ASSESSMENT_REVISION (
    REVISION_ID                VARCHAR(16777216) NOT NULL,
    CASE_ID                    VARCHAR(16777216) NOT NULL,
    RUN_ID                     VARCHAR(16777216) NOT NULL,
    REVISION_NO                NUMBER(38,0) NOT NULL,
    BASE_REVISION_ID           VARCHAR(16777216),
    STATUS                     VARCHAR(50) NOT NULL DEFAULT 'DRAFT',
    CHANGE_REASON              VARCHAR(16777216),
    CREATED_BY                 VARCHAR(200) NOT NULL DEFAULT CURRENT_USER(),
    CREATED_AT                 TIMESTAMP_NTZ(9) NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    GENERATED_AT               TIMESTAMP_NTZ(9),
    APPROVED_BY                VARCHAR(200),
    APPROVED_AT                TIMESTAMP_NTZ(9),
    PUBLISHED_BY               VARCHAR(200),
    PUBLISHED_AT               TIMESTAMP_NTZ(9),
    DISCARDED_BY               VARCHAR(200),
    DISCARDED_AT               TIMESTAMP_NTZ(9),
    DISCARD_REASON             VARCHAR(16777216)
)
COMMENT = 'Append-only assessment Revision mapped to an existing assessment Run snapshot.';

-- ============================================================
-- C. ASSESSMENT_CHANGE_SET
-- Pending changes never alter the published Current State.
-- ============================================================
CREATE TABLE IF NOT EXISTS ASSESSMENT_CHANGE_SET (
    CHANGE_SET_ID              VARCHAR(16777216) NOT NULL,
    CASE_ID                    VARCHAR(16777216) NOT NULL,
    BASE_REVISION_ID           VARCHAR(16777216),
    TARGET_REVISION_ID         VARCHAR(16777216) NOT NULL,
    STATUS                     VARCHAR(50) NOT NULL DEFAULT 'PENDING',
    REASON                     VARCHAR(16777216) NOT NULL,
    CREATED_BY                 VARCHAR(200) NOT NULL DEFAULT CURRENT_USER(),
    CREATED_AT                 TIMESTAMP_NTZ(9) NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    CLOSED_BY                  VARCHAR(200),
    CLOSED_AT                  TIMESTAMP_NTZ(9)
)
COMMENT = 'Header for Evidence and answer changes awaiting reassessment and explicit publication.';

-- ============================================================
-- D. ASSESSMENT_REVISION_EVIDENCE
-- Copy-on-write Evidence lineage. Existing EVIDENCE_ITEMS remains canonical.
-- ============================================================
CREATE TABLE IF NOT EXISTS ASSESSMENT_REVISION_EVIDENCE (
    REVISION_EVIDENCE_ID       VARCHAR(16777216) NOT NULL,
    REVISION_ID                VARCHAR(16777216) NOT NULL,
    EVIDENCE_ID                VARCHAR(16777216) NOT NULL,
    ORIGIN_EVIDENCE_ID         VARCHAR(16777216) NOT NULL,
    INHERITED_FROM_EVIDENCE_ID VARCHAR(16777216),
    SNAPSHOT_ROLE              VARCHAR(50) NOT NULL,
    CHANGE_SET_ID              VARCHAR(16777216),
    CREATED_AT                 TIMESTAMP_NTZ(9) NOT NULL DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Evidence membership and lineage for immutable Revision snapshots.';

-- ============================================================
-- E. GOVERNANCE_PROPOSAL_LINEAGE
-- Stable finding/decision identity across Revisions.
-- ============================================================
CREATE TABLE IF NOT EXISTS GOVERNANCE_PROPOSAL_LINEAGE (
    PROPOSAL_ID                VARCHAR(16777216) NOT NULL,
    REVISION_ID                VARCHAR(16777216) NOT NULL,
    LOGICAL_ITEM_ID            VARCHAR(16777216) NOT NULL,
    PREVIOUS_PROPOSAL_ID       VARCHAR(16777216),
    CHANGE_TYPE                VARCHAR(50) NOT NULL,
    ITEM_STATE                 VARCHAR(50) NOT NULL,
    CHANGE_REASON              VARCHAR(16777216),
    SOURCE_EVIDENCE_IDS        ARRAY,
    CREATED_AT                 TIMESTAMP_NTZ(9) NOT NULL DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Stable logical identity and Evidence-grounded change reason for proposals across Revisions.';

-- ============================================================
-- F. ASSESSMENT_REVISION_DELTA
-- Frozen before/after comparison generated before human review.
-- ============================================================
CREATE TABLE IF NOT EXISTS ASSESSMENT_REVISION_DELTA (
    DELTA_ID                   VARCHAR(16777216) NOT NULL,
    CASE_ID                    VARCHAR(16777216) NOT NULL,
    FROM_REVISION_ID           VARCHAR(16777216),
    TO_REVISION_ID             VARCHAR(16777216) NOT NULL,
    ENTITY_TYPE                VARCHAR(50) NOT NULL,
    LOGICAL_ITEM_ID            VARCHAR(16777216),
    CHANGE_TYPE                VARCHAR(50) NOT NULL,
    BEFORE_PAYLOAD             VARIANT,
    AFTER_PAYLOAD              VARIANT,
    CHANGE_REASON              VARCHAR(16777216),
    SOURCE_EVIDENCE_IDS        ARRAY,
    CREATED_AT                 TIMESTAMP_NTZ(9) NOT NULL DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Immutable Revision comparison snapshot used for human review and audit traceability.';

-- ============================================================
-- G. DATA_LIFECYCLE_EVENT
-- Content-free tombstone that survives destructive operations.
-- ============================================================
CREATE TABLE IF NOT EXISTS DATA_LIFECYCLE_EVENT (
    EVENT_ID                   VARCHAR(16777216) NOT NULL,
    ENTITY_TYPE                VARCHAR(50) NOT NULL,
    ENTITY_ID                  VARCHAR(16777216) NOT NULL,
    ACTION_TYPE                VARCHAR(50) NOT NULL,
    REASON                     VARCHAR(16777216) NOT NULL,
    IMPACT_COUNTS              VARIANT,
    ACTED_BY                   VARCHAR(200) NOT NULL DEFAULT CURRENT_USER(),
    ACTED_AT                   TIMESTAMP_NTZ(9) NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    REQUEST_ID                 VARCHAR(16777216)
)
COMMENT = 'Content-free audit tombstone for discard, archive, restore, purge, and development reset.';

-- ============================================================
-- H. DATA_PURGE_REQUEST
-- Resumable two-phase hard deletion. No procedure is enabled by this file.
-- ============================================================
CREATE TABLE IF NOT EXISTS DATA_PURGE_REQUEST (
    PURGE_REQUEST_ID           VARCHAR(16777216) NOT NULL,
    TARGET_TYPE                VARCHAR(50) NOT NULL,
    TARGET_ID                  VARCHAR(16777216) NOT NULL,
    STATUS                     VARCHAR(50) NOT NULL DEFAULT 'PREVIEWED',
    IMPACT_COUNTS              VARIANT NOT NULL,
    STAGE_PATHS                ARRAY,
    CONFIRMATION_HASH          VARCHAR(64) NOT NULL,
    REASON                     VARCHAR(16777216) NOT NULL,
    REQUESTED_BY               VARCHAR(200) NOT NULL DEFAULT CURRENT_USER(),
    REQUESTED_AT               TIMESTAMP_NTZ(9) NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    COMPLETED_AT               TIMESTAMP_NTZ(9),
    ERROR_MESSAGE              VARCHAR(16777216)
)
COMMENT = 'Governed, resumable hard-purge request. Business content is removed from completed tombstones.';

-- ============================================================
-- I. READINESSOPS_ENVIRONMENT_CONTROL
-- Reset and purge are disabled until an administrator explicitly enables them.
-- ============================================================
CREATE TABLE IF NOT EXISTS READINESSOPS_ENVIRONMENT_CONTROL (
    ENVIRONMENT_NAME           VARCHAR(100) NOT NULL,
    ENVIRONMENT_TYPE           VARCHAR(50) NOT NULL,
    ALLOW_DEMO_RESET           BOOLEAN NOT NULL DEFAULT FALSE,
    ALLOW_HARD_PURGE           BOOLEAN NOT NULL DEFAULT FALSE,
    UPDATED_BY                 VARCHAR(200) NOT NULL DEFAULT CURRENT_USER(),
    UPDATED_AT                 TIMESTAMP_NTZ(9) NOT NULL DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Environment safety switch. Production must never permit demo reset.';

MERGE INTO READINESSOPS_ENVIRONMENT_CONTROL target
USING (
    SELECT
        'READINESSOPS_VALIDATION' AS ENVIRONMENT_NAME,
        'PRODUCTION' AS ENVIRONMENT_TYPE,
        FALSE AS ALLOW_DEMO_RESET,
        FALSE AS ALLOW_HARD_PURGE
) source
ON target.ENVIRONMENT_NAME = source.ENVIRONMENT_NAME
WHEN NOT MATCHED THEN INSERT (
    ENVIRONMENT_NAME,
    ENVIRONMENT_TYPE,
    ALLOW_DEMO_RESET,
    ALLOW_HARD_PURGE
) VALUES (
    source.ENVIRONMENT_NAME,
    source.ENVIRONMENT_TYPE,
    source.ALLOW_DEMO_RESET,
    source.ALLOW_HARD_PURGE
);

-- ============================================================
-- J. Read-only lifecycle views
-- These views return rows only after migration/creation procedures populate
-- the foundation tables. They do not replace V_AI_PORTFOLIO yet.
-- ============================================================
CREATE OR REPLACE VIEW V_ASSESSMENT_CASE_CURRENT AS
SELECT
    c.CASE_ID,
    c.INITIATIVE_ID,
    c.CASE_NAME,
    c.STATUS AS CASE_STATUS,
    c.CURRENT_REVISION_ID,
    current_revision.REVISION_NO AS CURRENT_REVISION_NO,
    current_revision.RUN_ID AS CURRENT_RUN_ID,
    current_revision.PUBLISHED_BY,
    current_revision.PUBLISHED_AT,
    c.ACTIVE_DRAFT_REVISION_ID,
    draft_revision.REVISION_NO AS DRAFT_REVISION_NO,
    draft_revision.STATUS AS DRAFT_STATUS,
    IFF(
        c.ACTIVE_DRAFT_REVISION_ID IS NOT NULL
        OR pending_change.CHANGE_SET_ID IS NOT NULL,
        TRUE,
        FALSE
    ) AS HAS_PENDING_CHANGES,
    pending_change.CHANGE_SET_ID AS PENDING_CHANGE_SET_ID,
    pending_change.CREATED_AT AS PENDING_CHANGE_CREATED_AT
FROM ASSESSMENT_CASE c
LEFT JOIN ASSESSMENT_REVISION current_revision
    ON current_revision.REVISION_ID = c.CURRENT_REVISION_ID
   AND current_revision.CASE_ID = c.CASE_ID
LEFT JOIN ASSESSMENT_REVISION draft_revision
    ON draft_revision.REVISION_ID = c.ACTIVE_DRAFT_REVISION_ID
   AND draft_revision.CASE_ID = c.CASE_ID
LEFT JOIN ASSESSMENT_CHANGE_SET pending_change
    ON pending_change.CASE_ID = c.CASE_ID
   AND pending_change.TARGET_REVISION_ID = c.ACTIVE_DRAFT_REVISION_ID
   AND pending_change.STATUS = 'PENDING'
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY c.CASE_ID
    ORDER BY pending_change.CREATED_AT DESC NULLS LAST
) = 1;

CREATE OR REPLACE VIEW V_ASSESSMENT_REVISION_HISTORY AS
SELECT
    r.CASE_ID,
    c.CASE_NAME,
    r.REVISION_ID,
    r.REVISION_NO,
    r.RUN_ID,
    r.BASE_REVISION_ID,
    r.STATUS,
    r.CHANGE_REASON,
    IFF(c.CURRENT_REVISION_ID = r.REVISION_ID, TRUE, FALSE) AS IS_CURRENT,
    IFF(c.ACTIVE_DRAFT_REVISION_ID = r.REVISION_ID, TRUE, FALSE) AS IS_ACTIVE_DRAFT,
    r.CREATED_BY,
    r.CREATED_AT,
    r.GENERATED_AT,
    r.APPROVED_BY,
    r.APPROVED_AT,
    r.PUBLISHED_BY,
    r.PUBLISHED_AT,
    r.DISCARDED_BY,
    r.DISCARDED_AT,
    r.DISCARD_REASON
FROM ASSESSMENT_REVISION r
JOIN ASSESSMENT_CASE c
  ON c.CASE_ID = r.CASE_ID;

CREATE OR REPLACE VIEW V_ASSESSMENT_REVISION_COMPARISON AS
SELECT
    d.CASE_ID,
    c.CASE_NAME,
    d.FROM_REVISION_ID,
    from_revision.REVISION_NO AS FROM_REVISION_NO,
    d.TO_REVISION_ID,
    to_revision.REVISION_NO AS TO_REVISION_NO,
    d.DELTA_ID,
    d.ENTITY_TYPE,
    d.LOGICAL_ITEM_ID,
    d.CHANGE_TYPE,
    d.BEFORE_PAYLOAD,
    d.AFTER_PAYLOAD,
    d.CHANGE_REASON,
    d.SOURCE_EVIDENCE_IDS,
    d.CREATED_AT
FROM ASSESSMENT_REVISION_DELTA d
JOIN ASSESSMENT_CASE c
  ON c.CASE_ID = d.CASE_ID
LEFT JOIN ASSESSMENT_REVISION from_revision
  ON from_revision.REVISION_ID = d.FROM_REVISION_ID
LEFT JOIN ASSESSMENT_REVISION to_revision
  ON to_revision.REVISION_ID = d.TO_REVISION_ID;

-- ============================================================
-- Rollback guidance for this schema-only foundation
-- ============================================================
-- Run only before any production migration or Revision data creation:
--   DROP VIEW IF EXISTS V_ASSESSMENT_REVISION_COMPARISON;
--   DROP VIEW IF EXISTS V_ASSESSMENT_REVISION_HISTORY;
--   DROP VIEW IF EXISTS V_ASSESSMENT_CASE_CURRENT;
--   DROP TABLE IF EXISTS READINESSOPS_ENVIRONMENT_CONTROL;
--   DROP TABLE IF EXISTS DATA_PURGE_REQUEST;
--   DROP TABLE IF EXISTS DATA_LIFECYCLE_EVENT;
--   DROP TABLE IF EXISTS ASSESSMENT_REVISION_DELTA;
--   DROP TABLE IF EXISTS GOVERNANCE_PROPOSAL_LINEAGE;
--   DROP TABLE IF EXISTS ASSESSMENT_REVISION_EVIDENCE;
--   DROP TABLE IF EXISTS ASSESSMENT_CHANGE_SET;
--   DROP TABLE IF EXISTS ASSESSMENT_REVISION;
--   DROP TABLE IF EXISTS ASSESSMENT_CASE;
