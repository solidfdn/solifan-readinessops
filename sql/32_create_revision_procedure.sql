-- ============================================================
-- Safe Recreation: SP_CREATE_ASSESSMENT_REVISION only
-- ============================================================
-- Do not replace SP_REGISTER_REVISION_EVIDENCE from this file.
-- That procedure is independently maintained by sql/29.

USE SCHEMA APP;

CREATE OR REPLACE PROCEDURE SP_CREATE_ASSESSMENT_REVISION(
    P_CASE_ID VARCHAR,
    P_REASON VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_case_exists INTEGER;
    v_current_revision_id VARCHAR;
    v_active_draft_revision_id VARCHAR;
    v_base_run_id VARCHAR;
    v_revision_no NUMBER;
    v_revision_id VARCHAR;
    v_run_id VARCHAR;
    v_change_set_id VARCHAR;
    v_answer_count INTEGER;
    v_evidence_count INTEGER;
BEGIN
    IF (P_REASON IS NULL OR LENGTH(TRIM(P_REASON)) = 0) THEN
        RETURN '{"status":"FAILED","error":"Change reason is required"}';
    END IF;

    v_case_exists := (
        SELECT COUNT(*)
        FROM ASSESSMENT_CASE
        WHERE CASE_ID = :P_CASE_ID
          AND STATUS = 'ACTIVE'
    );

    IF (:v_case_exists <> 1) THEN
        RETURN '{"status":"FAILED","error":"Active assessment Case not found"}';
    END IF;

    SELECT CURRENT_REVISION_ID, ACTIVE_DRAFT_REVISION_ID
      INTO :v_current_revision_id, :v_active_draft_revision_id
    FROM ASSESSMENT_CASE
    WHERE CASE_ID = :P_CASE_ID;

    IF (:v_current_revision_id IS NULL) THEN
        RETURN '{"status":"FAILED","error":"Published base Revision not found"}';
    END IF;

    IF (:v_active_draft_revision_id IS NOT NULL) THEN
        RETURN '{"status":"FAILED","error":"An active draft Revision already exists","revision_id":"' ||
            :v_active_draft_revision_id || '"}';
    END IF;

    v_base_run_id := (
        SELECT RUN_ID
        FROM ASSESSMENT_REVISION
        WHERE REVISION_ID = :v_current_revision_id
          AND CASE_ID = :P_CASE_ID
          AND STATUS = 'PUBLISHED'
    );

    IF (:v_base_run_id IS NULL) THEN
        RETURN '{"status":"FAILED","error":"Current pointer does not reference a published Revision"}';
    END IF;

    v_revision_no := (
        SELECT COALESCE(MAX(REVISION_NO), 0) + 1
        FROM ASSESSMENT_REVISION
        WHERE CASE_ID = :P_CASE_ID
    );
    v_revision_id := 'REV_' || REPLACE(UUID_STRING(), '-', '');
    v_run_id := 'RUN_REV_' || REPLACE(UUID_STRING(), '-', '');
    v_change_set_id := 'CS_' || REPLACE(UUID_STRING(), '-', '');

    CREATE OR REPLACE TEMPORARY TABLE TMP_REVISION_INHERITED_EVIDENCE AS
    SELECT
        'RE_' || SHA2(:v_revision_id || '|' || evidence.EVIDENCE_ID, 256) AS REVISION_EVIDENCE_ID,
        :v_revision_id AS REVISION_ID,
        'EV_' || SHA2(:v_revision_id || '|' || evidence.EVIDENCE_ID, 256) AS TARGET_EVIDENCE_ID,
        COALESCE(base_lineage.ORIGIN_EVIDENCE_ID, evidence.EVIDENCE_ID) AS ORIGIN_EVIDENCE_ID,
        evidence.EVIDENCE_ID AS INHERITED_FROM_EVIDENCE_ID,
        evidence.QUESTION_ID,
        evidence.EVIDENCE_TITLE,
        evidence.EVIDENCE_TEXT,
        evidence.EVIDENCE_STATUS,
        evidence.CREATED_AT,
        evidence.SOURCE_FILENAME,
        evidence.SOURCE_TYPE,
        evidence.MEDIA_TYPE,
        evidence.CONTENT_SHA256,
        evidence.BYTE_COUNT,
        evidence.CHAR_COUNT,
        evidence.UPLOADED_AT,
        evidence.UPLOADED_BY,
        evidence.STAGE_PATH,
        evidence.PARSER_NAME,
        evidence.PAGE_COUNT
    FROM EVIDENCE_ITEMS evidence
    LEFT JOIN ASSESSMENT_REVISION_EVIDENCE base_lineage
      ON base_lineage.REVISION_ID = :v_current_revision_id
     AND base_lineage.EVIDENCE_ID = evidence.EVIDENCE_ID
    WHERE evidence.RUN_ID = :v_base_run_id;

    BEGIN TRANSACTION;

    INSERT INTO ASSESSMENT_RUNS (
        RUN_ID,
        RUN_NAME,
        ORGANIZATION_NAME,
        ASSESSMENT_SCOPE,
        STATUS,
        CREATED_AT,
        INITIATIVE_ID
    )
    SELECT
        :v_run_id,
        REGEXP_REPLACE(RUN_NAME, ' - Revision [0-9]+$', '') ||
            ' - Revision ' || :v_revision_no,
        ORGANIZATION_NAME,
        ASSESSMENT_SCOPE,
        'IN_REVIEW',
        CURRENT_TIMESTAMP(),
        INITIATIVE_ID
    FROM ASSESSMENT_RUNS
    WHERE RUN_ID = :v_base_run_id;

    INSERT INTO ASSESSMENT_REVISION (
        REVISION_ID,
        CASE_ID,
        RUN_ID,
        REVISION_NO,
        BASE_REVISION_ID,
        STATUS,
        CHANGE_REASON
    ) VALUES (
        :v_revision_id,
        :P_CASE_ID,
        :v_run_id,
        :v_revision_no,
        :v_current_revision_id,
        'DRAFT',
        TRIM(:P_REASON)
    );

    INSERT INTO ASSESSMENT_CHANGE_SET (
        CHANGE_SET_ID,
        CASE_ID,
        BASE_REVISION_ID,
        TARGET_REVISION_ID,
        STATUS,
        REASON
    ) VALUES (
        :v_change_set_id,
        :P_CASE_ID,
        :v_current_revision_id,
        :v_revision_id,
        'PENDING',
        TRIM(:P_REASON)
    );

    INSERT INTO ASSESSMENT_ANSWERS (
        RUN_ID,
        QUESTION_ID,
        ANSWER_STATUS,
        ANSWER_TEXT,
        OWNER_NAME,
        UPDATED_AT
    )
    SELECT
        :v_run_id,
        QUESTION_ID,
        ANSWER_STATUS,
        ANSWER_TEXT,
        OWNER_NAME,
        UPDATED_AT
    FROM ASSESSMENT_ANSWERS
    WHERE RUN_ID = :v_base_run_id;

    INSERT INTO EVIDENCE_ITEMS (
        EVIDENCE_ID,
        RUN_ID,
        QUESTION_ID,
        EVIDENCE_TITLE,
        EVIDENCE_TEXT,
        EVIDENCE_STATUS,
        CREATED_AT,
        SOURCE_FILENAME,
        SOURCE_TYPE,
        MEDIA_TYPE,
        CONTENT_SHA256,
        BYTE_COUNT,
        CHAR_COUNT,
        UPLOADED_AT,
        UPLOADED_BY,
        STAGE_PATH,
        PARSER_NAME,
        PAGE_COUNT
    )
    SELECT
        TARGET_EVIDENCE_ID,
        :v_run_id,
        QUESTION_ID,
        EVIDENCE_TITLE,
        EVIDENCE_TEXT,
        EVIDENCE_STATUS,
        CREATED_AT,
        SOURCE_FILENAME,
        SOURCE_TYPE,
        MEDIA_TYPE,
        CONTENT_SHA256,
        BYTE_COUNT,
        CHAR_COUNT,
        UPLOADED_AT,
        UPLOADED_BY,
        STAGE_PATH,
        PARSER_NAME,
        PAGE_COUNT
    FROM TMP_REVISION_INHERITED_EVIDENCE;

    INSERT INTO ASSESSMENT_REVISION_EVIDENCE (
        REVISION_EVIDENCE_ID,
        REVISION_ID,
        EVIDENCE_ID,
        ORIGIN_EVIDENCE_ID,
        INHERITED_FROM_EVIDENCE_ID,
        SNAPSHOT_ROLE,
        CHANGE_SET_ID
    )
    SELECT
        REVISION_EVIDENCE_ID,
        REVISION_ID,
        TARGET_EVIDENCE_ID,
        ORIGIN_EVIDENCE_ID,
        INHERITED_FROM_EVIDENCE_ID,
        'INHERITED',
        :v_change_set_id
    FROM TMP_REVISION_INHERITED_EVIDENCE;

    UPDATE ASSESSMENT_CASE
    SET
        ACTIVE_DRAFT_REVISION_ID = :v_revision_id,
        UPDATED_BY = CURRENT_USER(),
        UPDATED_AT = CURRENT_TIMESTAMP()
    WHERE CASE_ID = :P_CASE_ID
      AND CURRENT_REVISION_ID = :v_current_revision_id
      AND ACTIVE_DRAFT_REVISION_ID IS NULL;

    IF (SQLROWCOUNT <> 1) THEN
        ROLLBACK;
        RETURN '{"status":"FAILED","error":"Draft pointer update conflict"}';
    END IF;

    COMMIT;

    v_answer_count := (
        SELECT COUNT(*) FROM ASSESSMENT_ANSWERS WHERE RUN_ID = :v_run_id
    );
    v_evidence_count := (
        SELECT COUNT(*) FROM EVIDENCE_ITEMS WHERE RUN_ID = :v_run_id
    );

    RETURN '{"status":"OK","case_id":"' || :P_CASE_ID ||
        '","revision_id":"' || :v_revision_id ||
        '","revision_no":' || :v_revision_no ||
        ',"run_id":"' || :v_run_id ||
        '","change_set_id":"' || :v_change_set_id ||
        '","inherited_answers":' || :v_answer_count ||
        ',"inherited_evidence":' || :v_evidence_count || '}';

EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RETURN '{"status":"FAILED","error":"' || LEFT(SQLERRM, 500) || '"}';
END;
$$;
