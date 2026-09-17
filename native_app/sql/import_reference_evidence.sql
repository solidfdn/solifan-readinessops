-- Native App reference adapter for the existing ReadinessOps model.
-- It maps one consumer-owned row into AI_INITIATIVE, ASSESSMENT_RUNS, and
-- EVIDENCE_ITEMS; it does not introduce a parallel proposal model.

CREATE OR REPLACE PROCEDURE APP_CODE.SP_IMPORT_REFERENCE_EVIDENCE(
    P_SOURCE_KIND STRING,
    P_SOURCE_KEY_COLUMN STRING,
    P_SOURCE_KEY_VALUE STRING,
    P_TITLE_COLUMN STRING,
    P_TEXT_COLUMN STRING,
    P_ASSESSMENT_RUN_ID STRING,
    P_INITIATIVE_ID STRING,
    P_RUN_NAME STRING,
    P_ORGANIZATION_NAME STRING,
    P_ASSESSMENT_SCOPE STRING,
    P_INITIATIVE_NAME STRING,
    P_INITIATIVE_DESCRIPTION STRING,
    P_BUSINESS_OUTCOME STRING
)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
    v_source_kind STRING;
    v_source_reference STRING;
    v_binding_token STRING;
    v_binding_count NUMBER DEFAULT 0;
    v_match_count NUMBER DEFAULT 0;
    v_row OBJECT;
    v_title STRING;
    v_text STRING;
    v_content_sha256 STRING;
    v_run_id STRING;
    v_initiative_id STRING;
    v_evidence_id STRING;
    v_existing NUMBER DEFAULT 0;
    v_run_conflict NUMBER DEFAULT 0;
    v_actor STRING DEFAULT CURRENT_USER();
BEGIN
    IF (v_actor IS NULL) THEN
        RETURN OBJECT_CONSTRUCT(
            'status', 'FAILED',
            'error', 'READ SESSION is required for operator attribution.'
        );
    END IF;

    v_source_kind := UPPER(TRIM(P_SOURCE_KIND));

    IF (v_source_kind NOT IN ('TABLE', 'VIEW')) THEN
        RETURN OBJECT_CONSTRUCT(
            'status', 'FAILED',
            'error', 'SOURCE_KIND must be TABLE or VIEW.'
        );
    END IF;

    IF (
        NULLIF(TRIM(P_SOURCE_KEY_COLUMN), '') IS NULL OR
        NULLIF(TRIM(P_SOURCE_KEY_VALUE), '') IS NULL OR
        NULLIF(TRIM(P_TITLE_COLUMN), '') IS NULL OR
        NULLIF(TRIM(P_TEXT_COLUMN), '') IS NULL OR
        NULLIF(TRIM(P_ASSESSMENT_RUN_ID), '') IS NULL OR
        NULLIF(TRIM(P_INITIATIVE_ID), '') IS NULL OR
        NULLIF(TRIM(P_RUN_NAME), '') IS NULL OR
        NULLIF(TRIM(P_ORGANIZATION_NAME), '') IS NULL OR
        NULLIF(TRIM(P_ASSESSMENT_SCOPE), '') IS NULL OR
        NULLIF(TRIM(P_INITIATIVE_NAME), '') IS NULL
    ) THEN
        RETURN OBJECT_CONSTRUCT(
            'status', 'FAILED',
            'error', 'Source mapping, assessment context, and initiative name are required.'
        );
    END IF;

    IF (v_source_kind = 'TABLE') THEN
        v_source_reference := 'EVIDENCE_SOURCE_TABLE';
    ELSE
        v_source_reference := 'EVIDENCE_SOURCE_VIEW';
    END IF;

    SELECT COUNT(*)
      INTO :v_binding_count
      FROM APP_DATA.REFERENCE_BINDING_STATE
     WHERE REFERENCE_NAME = :v_source_reference;

    IF (v_binding_count != 1) THEN
        RETURN OBJECT_CONSTRUCT(
            'status', 'FAILED',
            'error', 'Bind exactly one source reference before importing evidence.'
        );
    END IF;

    SELECT BINDING_TOKEN
      INTO :v_binding_token
      FROM APP_DATA.REFERENCE_BINDING_STATE
     WHERE REFERENCE_NAME = :v_source_reference
     LIMIT 1;

    IF (v_source_kind = 'TABLE') THEN
        SELECT COUNT(*)
          INTO :v_match_count
          FROM REFERENCE('EVIDENCE_SOURCE_TABLE')
         WHERE TO_VARCHAR(GET_IGNORE_CASE(
                   OBJECT_CONSTRUCT_KEEP_NULL(*), :P_SOURCE_KEY_COLUMN
               )) = :P_SOURCE_KEY_VALUE;
    ELSE
        SELECT COUNT(*)
          INTO :v_match_count
          FROM REFERENCE('EVIDENCE_SOURCE_VIEW')
         WHERE TO_VARCHAR(GET_IGNORE_CASE(
                   OBJECT_CONSTRUCT_KEEP_NULL(*), :P_SOURCE_KEY_COLUMN
               )) = :P_SOURCE_KEY_VALUE;
    END IF;

    IF (v_match_count = 0) THEN
        RETURN OBJECT_CONSTRUCT(
            'status', 'FAILED',
            'error', 'No source row matched the supplied key.'
        );
    ELSEIF (v_match_count > 1) THEN
        RETURN OBJECT_CONSTRUCT(
            'status', 'FAILED',
            'error', 'The supplied source key is not unique.'
        );
    END IF;

    IF (v_source_kind = 'TABLE') THEN
        SELECT OBJECT_CONSTRUCT_KEEP_NULL(*)
          INTO :v_row
          FROM REFERENCE('EVIDENCE_SOURCE_TABLE')
         WHERE TO_VARCHAR(GET_IGNORE_CASE(
                   OBJECT_CONSTRUCT_KEEP_NULL(*), :P_SOURCE_KEY_COLUMN
               )) = :P_SOURCE_KEY_VALUE
         LIMIT 1;
    ELSE
        SELECT OBJECT_CONSTRUCT_KEEP_NULL(*)
          INTO :v_row
          FROM REFERENCE('EVIDENCE_SOURCE_VIEW')
         WHERE TO_VARCHAR(GET_IGNORE_CASE(
                   OBJECT_CONSTRUCT_KEEP_NULL(*), :P_SOURCE_KEY_COLUMN
               )) = :P_SOURCE_KEY_VALUE
         LIMIT 1;
    END IF;

    SELECT
        TO_VARCHAR(GET_IGNORE_CASE(:v_row, :P_TITLE_COLUMN)),
        TO_VARCHAR(GET_IGNORE_CASE(:v_row, :P_TEXT_COLUMN))
      INTO :v_title, :v_text;

    IF (NULLIF(TRIM(v_title), '') IS NULL OR NULLIF(TRIM(v_text), '') IS NULL) THEN
        RETURN OBJECT_CONSTRUCT(
            'status', 'FAILED',
            'error', 'The mapped title or evidence text is null or empty.'
        );
    END IF;

    IF (LENGTH(v_text) > 50000) THEN
        RETURN OBJECT_CONSTRUCT(
            'status', 'FAILED',
            'error', 'Evidence text exceeds the R1 limit of 50,000 characters.'
        );
    END IF;

    SELECT SHA2(:v_text, 256) INTO :v_content_sha256;

    -- Assessment and Initiative identities are explicit existing-model keys.
    -- They do not change when Evidence rows or reference bindings change.
    v_run_id := TRIM(P_ASSESSMENT_RUN_ID);
    v_initiative_id := TRIM(P_INITIATIVE_ID);

    SELECT COUNT(*)
      INTO :v_run_conflict
      FROM APP_DATA.ASSESSMENT_RUNS
     WHERE RUN_ID = :v_run_id
       AND INITIATIVE_ID IS NOT NULL
       AND INITIATIVE_ID != :v_initiative_id;

    IF (v_run_conflict > 0) THEN
        RETURN OBJECT_CONSTRUCT(
            'status', 'FAILED',
            'error', 'Assessment ID is already linked to a different Initiative ID.'
        );
    END IF;

    v_evidence_id := 'EV_' || SUBSTR(
        SHA2(
            v_binding_token || '|' || P_SOURCE_KEY_COLUMN || '|' ||
            P_SOURCE_KEY_VALUE || '|' || P_TITLE_COLUMN || '|' ||
            P_TEXT_COLUMN || '|' || v_title || '|' || v_content_sha256,
            256
        ),
        1,
        32
    );

    BEGIN TRANSACTION;

    MERGE INTO APP_DATA.AI_INITIATIVE target
    USING (
        SELECT
            :v_initiative_id AS INITIATIVE_ID,
            :P_INITIATIVE_NAME AS INITIATIVE_NAME,
            :P_INITIATIVE_DESCRIPTION AS DESCRIPTION,
            :P_BUSINESS_OUTCOME AS BUSINESS_OUTCOME
    ) source
    ON target.INITIATIVE_ID = source.INITIATIVE_ID
    WHEN MATCHED THEN UPDATE SET
        INITIATIVE_NAME = source.INITIATIVE_NAME,
        DESCRIPTION = source.DESCRIPTION,
        BUSINESS_OUTCOME = source.BUSINESS_OUTCOME,
        UPDATED_AT = CURRENT_TIMESTAMP(),
        UPDATED_BY = :v_actor
    WHEN NOT MATCHED THEN INSERT (
        INITIATIVE_ID,
        INITIATIVE_NAME,
        DESCRIPTION,
        LIFECYCLE_STAGE,
        BUSINESS_OUTCOME,
        STATUS,
        CREATED_AT,
        CREATED_BY,
        UPDATED_AT,
        UPDATED_BY
    ) VALUES (
        source.INITIATIVE_ID,
        source.INITIATIVE_NAME,
        source.DESCRIPTION,
        'IDEATION',
        source.BUSINESS_OUTCOME,
        'ACTIVE',
        CURRENT_TIMESTAMP(),
        :v_actor,
        CURRENT_TIMESTAMP(),
        :v_actor
    );

    MERGE INTO APP_DATA.ASSESSMENT_RUNS target
    USING (
        SELECT
            :v_run_id AS RUN_ID,
            :P_RUN_NAME AS RUN_NAME,
            :P_ORGANIZATION_NAME AS ORGANIZATION_NAME,
            :P_ASSESSMENT_SCOPE AS ASSESSMENT_SCOPE,
            :v_initiative_id AS INITIATIVE_ID
    ) source
    ON target.RUN_ID = source.RUN_ID
    WHEN MATCHED THEN UPDATE SET
        RUN_NAME = source.RUN_NAME,
        ORGANIZATION_NAME = source.ORGANIZATION_NAME,
        ASSESSMENT_SCOPE = source.ASSESSMENT_SCOPE,
        INITIATIVE_ID = source.INITIATIVE_ID
    WHEN NOT MATCHED THEN INSERT (
        RUN_ID,
        RUN_NAME,
        ORGANIZATION_NAME,
        ASSESSMENT_SCOPE,
        STATUS,
        CREATED_AT,
        INITIATIVE_ID
    ) VALUES (
        source.RUN_ID,
        source.RUN_NAME,
        source.ORGANIZATION_NAME,
        source.ASSESSMENT_SCOPE,
        'DRAFT',
        CURRENT_TIMESTAMP(),
        source.INITIATIVE_ID
    );

    SELECT COUNT(*)
      INTO :v_existing
      FROM APP_DATA.EVIDENCE_ITEMS
     WHERE EVIDENCE_ID = :v_evidence_id
       AND RUN_ID = :v_run_id;

    IF (v_existing > 0) THEN
        COMMIT;
        RETURN OBJECT_CONSTRUCT(
            'status', 'SKIPPED',
            'reason', 'Assessment context was updated; unchanged Evidence already exists.',
            'assessment_run_id', v_run_id,
            'initiative_id', v_initiative_id,
            'evidence_id', v_evidence_id
        );
    END IF;

    INSERT INTO APP_DATA.EVIDENCE_ITEMS (
        EVIDENCE_ID,
        RUN_ID,
        QUESTION_ID,
        EVIDENCE_TITLE,
        EVIDENCE_TEXT,
        EVIDENCE_STATUS,
        CREATED_AT,
        SOURCE_TYPE,
        MEDIA_TYPE,
        CONTENT_SHA256,
        CHAR_COUNT,
        UPLOADED_AT,
        UPLOADED_BY,
        PARSER_NAME,
        SOURCE_REFERENCE,
        SOURCE_BINDING_TOKEN,
        SOURCE_KEY_COLUMN,
        SOURCE_ROW_KEY,
        TITLE_COLUMN,
        TEXT_COLUMN
    ) VALUES (
        :v_evidence_id,
        :v_run_id,
        NULL,
        :v_title,
        :v_text,
        'VALIDATED',
        CURRENT_TIMESTAMP(),
        'REFERENCE_' || :v_source_kind,
        'text/plain',
        :v_content_sha256,
        LENGTH(:v_text),
        CURRENT_TIMESTAMP(),
        :v_actor,
        'SNOWFLAKE_REFERENCE',
        :v_source_reference,
        :v_binding_token,
        :P_SOURCE_KEY_COLUMN,
        :P_SOURCE_KEY_VALUE,
        :P_TITLE_COLUMN,
        :P_TEXT_COLUMN
    );

    COMMIT;

    RETURN OBJECT_CONSTRUCT(
        'status', 'IMPORTED',
        'assessment_run_id', v_run_id,
        'initiative_id', v_initiative_id,
        'evidence_id', v_evidence_id,
        'content_sha256', v_content_sha256,
        'next_action', 'Generate the existing four-section Decision Pack.'
    );
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RETURN OBJECT_CONSTRUCT(
            'status', 'FAILED',
            'error', LEFT(SQLERRM, 500)
        );
END;
$$;

GRANT USAGE ON PROCEDURE APP_CODE.SP_IMPORT_REFERENCE_EVIDENCE(
    STRING, STRING, STRING, STRING, STRING,
    STRING, STRING, STRING, STRING, STRING,
    STRING, STRING, STRING
) TO APPLICATION ROLE READINESSOPS_ADMIN;
