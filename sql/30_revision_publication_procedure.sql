-- ============================================================
-- Revision Publication Procedure
-- ============================================================
-- Publishes an approved Revision, advances Current State atomically,
-- and keeps ASSESSMENT_RUNS.STATUS aligned with Revision status.
-- ============================================================

USE SCHEMA APP;

CREATE OR REPLACE PROCEDURE SP_PUBLISH_ASSESSMENT_REVISION(
    P_REVISION_ID VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_case_id VARCHAR;
    v_run_id VARCHAR;
    v_base_revision_id VARCHAR;
    v_revision_no NUMBER;
    v_revision_status VARCHAR;
    v_current_revision_id VARCHAR;
    v_is_active_draft BOOLEAN;
    v_agent_run_id VARCHAR;
    v_section_count NUMBER DEFAULT 0;
    v_approved_count NUMBER DEFAULT 0;
    v_published_count NUMBER DEFAULT 0;
    v_lineage_count NUMBER DEFAULT 0;
    v_delta_count NUMBER DEFAULT 0;
    v_publish_result VARCHAR;
    v_publish_json VARIANT;
    v_publish_status VARCHAR;
BEGIN
    SELECT
        revision.CASE_ID,
        revision.RUN_ID,
        revision.BASE_REVISION_ID,
        revision.REVISION_NO,
        revision.STATUS,
        case_record.CURRENT_REVISION_ID,
        IFF(case_record.ACTIVE_DRAFT_REVISION_ID = revision.REVISION_ID, TRUE, FALSE)
    INTO
        :v_case_id,
        :v_run_id,
        :v_base_revision_id,
        :v_revision_no,
        :v_revision_status,
        :v_current_revision_id,
        :v_is_active_draft
    FROM ASSESSMENT_REVISION revision
    JOIN ASSESSMENT_CASE case_record
      ON case_record.CASE_ID = revision.CASE_ID
    WHERE revision.REVISION_ID = :P_REVISION_ID;

    IF (:v_is_active_draft = FALSE) THEN
        RETURN '{"status":"FAILED","error":"Revision is not the active Draft"}';
    END IF;

    IF (:v_revision_status <> 'REVIEW_REQUIRED') THEN
        RETURN '{"status":"FAILED","error":"Revision must be REVIEW_REQUIRED before publication"}';
    END IF;

    IF (:v_current_revision_id <> :v_base_revision_id) THEN
        RETURN '{"status":"FAILED","error":"Published Current State no longer matches the Revision base"}';
    END IF;

    v_agent_run_id := (
        SELECT AGENT_RUN_ID
        FROM GOVERNANCE_AGENT_RUN
        WHERE ASSESSMENT_RUN_ID = :v_run_id
          AND WORKFLOW_TYPE = 'DECISION_PACK'
          AND STATUS = 'COMPLETED'
        ORDER BY COMPLETED_AT DESC, CREATED_AT DESC
        LIMIT 1
    );

    IF (:v_agent_run_id IS NULL) THEN
        RETURN '{"status":"FAILED","error":"Completed Decision Pack Run not found"}';
    END IF;

    SELECT
        COUNT(*),
        COUNT_IF(STATUS = 'APPROVED'),
        COUNT_IF(STATUS = 'PUBLISHED')
    INTO
        :v_section_count,
        :v_approved_count,
        :v_published_count
    FROM GOVERNANCE_AGENT_PROPOSAL
    WHERE AGENT_RUN_ID = :v_agent_run_id
      AND PROPOSAL_TYPE IN (
          'DECISION_GOVERNANCE',
          'DECISION_VALUE',
          'DECISION_MODEL_ROUTING',
          'DECISION_PORTFOLIO'
      );

    IF (:v_section_count <> 4 OR :v_approved_count + :v_published_count <> 4) THEN
        RETURN '{"status":"FAILED","error":"All four Decision Pack sections must be approved","section_count":' ||
            :v_section_count || ',"approved_count":' || :v_approved_count ||
            ',"published_count":' || :v_published_count || '}';
    END IF;

    v_lineage_count := (
        SELECT COUNT(*)
        FROM GOVERNANCE_PROPOSAL_LINEAGE lineage
        JOIN GOVERNANCE_AGENT_PROPOSAL proposal
          ON proposal.PROPOSAL_ID = lineage.PROPOSAL_ID
        WHERE lineage.REVISION_ID = :P_REVISION_ID
          AND proposal.AGENT_RUN_ID = :v_agent_run_id
    );

    v_delta_count := (
        SELECT COUNT(*)
        FROM ASSESSMENT_REVISION_DELTA
        WHERE TO_REVISION_ID = :P_REVISION_ID
          AND ENTITY_TYPE = 'DECISION_PACK_SECTION'
    );

    IF (:v_lineage_count <> 4 OR :v_delta_count <> 4) THEN
        RETURN '{"status":"FAILED","error":"Revision lineage or comparison is incomplete","lineage_count":' ||
            :v_lineage_count || ',"delta_count":' || :v_delta_count || '}';
    END IF;

    -- SP_PUBLISH_AGENT_RUN is idempotent by proposal ID.
    IF (:v_published_count = 0) THEN
        CALL SP_PUBLISH_AGENT_RUN(:v_agent_run_id)
          INTO :v_publish_result;

        v_publish_json := (SELECT TRY_PARSE_JSON(:v_publish_result));
        v_publish_status := (SELECT :v_publish_json:status::VARCHAR);

        IF (:v_publish_json IS NULL OR :v_publish_status <> 'OK') THEN
            RETURN COALESCE(
                :v_publish_result,
                '{"status":"FAILED","error":"Decision publication returned invalid output"}'
            );
        END IF;
    END IF;

    v_published_count := (
        SELECT COUNT(*)
        FROM GOVERNANCE_AGENT_PROPOSAL
        WHERE AGENT_RUN_ID = :v_agent_run_id
          AND PROPOSAL_TYPE IN (
              'DECISION_GOVERNANCE',
              'DECISION_VALUE',
              'DECISION_MODEL_ROUTING',
              'DECISION_PORTFOLIO'
          )
          AND STATUS = 'PUBLISHED'
    );

    IF (:v_published_count <> 4 OR (
        SELECT COUNT(*)
        FROM GOVERNED_DECISION_RECORD
        WHERE SOURCE_AGENT_RUN_ID = :v_agent_run_id
    ) <> 4) THEN
        RETURN '{"status":"FAILED","error":"Four governed Decision records were not confirmed after publication"}';
    END IF;

    BEGIN TRANSACTION;

    UPDATE ASSESSMENT_REVISION
    SET
        STATUS = 'PUBLISHED',
        APPROVED_BY = COALESCE(APPROVED_BY, CURRENT_USER()),
        APPROVED_AT = COALESCE(APPROVED_AT, CURRENT_TIMESTAMP()),
        PUBLISHED_BY = CURRENT_USER(),
        PUBLISHED_AT = CURRENT_TIMESTAMP()
    WHERE REVISION_ID = :P_REVISION_ID
      AND STATUS = 'REVIEW_REQUIRED';

    -- Keep the selector/status label aligned with the published Revision.
    UPDATE ASSESSMENT_RUNS
    SET STATUS = 'PUBLISHED'
    WHERE RUN_ID = :v_run_id;

    UPDATE ASSESSMENT_CASE
    SET
        CURRENT_REVISION_ID = :P_REVISION_ID,
        ACTIVE_DRAFT_REVISION_ID = NULL,
        UPDATED_BY = CURRENT_USER(),
        UPDATED_AT = CURRENT_TIMESTAMP()
    WHERE CASE_ID = :v_case_id
      AND CURRENT_REVISION_ID = :v_base_revision_id
      AND ACTIVE_DRAFT_REVISION_ID = :P_REVISION_ID;

    UPDATE ASSESSMENT_CHANGE_SET
    SET
        STATUS = 'APPLIED',
        CLOSED_BY = CURRENT_USER(),
        CLOSED_AT = CURRENT_TIMESTAMP()
    WHERE TARGET_REVISION_ID = :P_REVISION_ID
      AND STATUS = 'PENDING';

    COMMIT;

    IF ((
        SELECT COUNT(*)
        FROM ASSESSMENT_CASE case_record
        JOIN ASSESSMENT_REVISION revision
          ON revision.REVISION_ID = case_record.CURRENT_REVISION_ID
        JOIN ASSESSMENT_RUNS assessment_run
          ON assessment_run.RUN_ID = revision.RUN_ID
        WHERE case_record.CASE_ID = :v_case_id
          AND case_record.CURRENT_REVISION_ID = :P_REVISION_ID
          AND case_record.ACTIVE_DRAFT_REVISION_ID IS NULL
          AND revision.STATUS = 'PUBLISHED'
          AND assessment_run.STATUS = 'PUBLISHED'
    ) <> 1) THEN
        RETURN '{"status":"FAILED","error":"Publication completed but Current State or Run status validation failed"}';
    END IF;

    RETURN '{"status":"OK","revision_id":"' || :P_REVISION_ID ||
        '","revision_no":' || :v_revision_no ||
        ',"agent_run_id":"' || :v_agent_run_id ||
        '","published_decisions":4,"current_state_updated":true,"run_status":"PUBLISHED"}';

EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RETURN '{"status":"FAILED","error":"' ||
            REPLACE(LEFT(SQLERRM, 300), '"', '\\"') || '"}';
END;
$$;
