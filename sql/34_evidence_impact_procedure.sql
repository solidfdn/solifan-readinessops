-- ============================================================
-- Evidence Change Impact Analysis Procedure
-- ============================================================
-- Advisory-only analysis. This procedure does not update proposals,
-- approvals, publication state, Current State, or Revision status.
-- ============================================================

USE SCHEMA APP;

CREATE OR REPLACE PROCEDURE SP_ANALYZE_REVISION_EVIDENCE_IMPACT(
    P_REVISION_ID VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_analysis_run_id VARCHAR DEFAULT 'IA_' || REPLACE(UUID_STRING(), '-', '');
    v_case_id VARCHAR;
    v_case_name VARCHAR;
    v_revision_no NUMBER;
    v_change_reason VARCHAR;
    v_target_run_id VARCHAR;
    v_base_revision_id VARCHAR;
    v_base_run_id VARCHAR;
    v_initiative_id VARCHAR;
    v_initiative_context VARCHAR;
    v_changed_evidence_count INTEGER;
    v_base_decision_count INTEGER;
    v_changed_evidence_fingerprint VARCHAR;
    v_base_decision_fingerprint VARCHAR;
    v_input_fingerprint VARCHAR;
    v_existing_analysis_run_id VARCHAR;
    v_changed_evidence_block VARCHAR;
    v_base_decision_block VARCHAR;
    v_prompt VARCHAR;
    v_llm_response VARCHAR;
    v_parsed VARIANT;
    v_output_count INTEGER;
    v_distinct_section_count INTEGER;
    v_invalid_item_count INTEGER;
    v_invalid_source_count INTEGER;
    v_model_name VARCHAR DEFAULT 'mistral-large2';
    v_prompt_version VARCHAR DEFAULT 'EVIDENCE_IMPACT_V1';
    v_revision_context_count INTEGER;
BEGIN
    v_revision_context_count := (
        SELECT COUNT(*)
        FROM ASSESSMENT_REVISION revision
        JOIN ASSESSMENT_CASE case_record
          ON case_record.CASE_ID = revision.CASE_ID
         AND case_record.ACTIVE_DRAFT_REVISION_ID = revision.REVISION_ID
         AND case_record.CURRENT_REVISION_ID = revision.BASE_REVISION_ID
        JOIN ASSESSMENT_REVISION base_revision
          ON base_revision.REVISION_ID = revision.BASE_REVISION_ID
         AND base_revision.CASE_ID = revision.CASE_ID
         AND base_revision.STATUS = 'PUBLISHED'
        JOIN ASSESSMENT_RUNS assessment_run
          ON assessment_run.RUN_ID = revision.RUN_ID
        WHERE revision.REVISION_ID = :P_REVISION_ID
          AND revision.STATUS IN ('DRAFT', 'FAILED')
    );

    IF (:v_revision_context_count <> 1) THEN
        RETURN '{"status":"FAILED","error":"Active draft Revision with a published current base was not found"}';
    END IF;

    SELECT
        revision.CASE_ID,
        case_record.CASE_NAME,
        revision.REVISION_NO,
        revision.CHANGE_REASON,
        revision.RUN_ID,
        revision.BASE_REVISION_ID,
        base_revision.RUN_ID,
        assessment_run.INITIATIVE_ID
      INTO
        :v_case_id,
        :v_case_name,
        :v_revision_no,
        :v_change_reason,
        :v_target_run_id,
        :v_base_revision_id,
        :v_base_run_id,
        :v_initiative_id
    FROM ASSESSMENT_REVISION revision
    JOIN ASSESSMENT_CASE case_record
      ON case_record.CASE_ID = revision.CASE_ID
     AND case_record.ACTIVE_DRAFT_REVISION_ID = revision.REVISION_ID
     AND case_record.CURRENT_REVISION_ID = revision.BASE_REVISION_ID
    JOIN ASSESSMENT_REVISION base_revision
      ON base_revision.REVISION_ID = revision.BASE_REVISION_ID
     AND base_revision.CASE_ID = revision.CASE_ID
     AND base_revision.STATUS = 'PUBLISHED'
    JOIN ASSESSMENT_RUNS assessment_run
      ON assessment_run.RUN_ID = revision.RUN_ID
    WHERE revision.REVISION_ID = :P_REVISION_ID
      AND revision.STATUS IN ('DRAFT', 'FAILED');

    v_changed_evidence_count := (
        SELECT COUNT(*)
        FROM V_REVISION_EVIDENCE_CHANGE
        WHERE REVISION_ID = :P_REVISION_ID
    );

    IF (:v_changed_evidence_count = 0) THEN
        RETURN '{"status":"FAILED","error":"At least one ADDED or REPLACED Evidence item is required"}';
    END IF;

    v_base_decision_count := (
        SELECT COUNT(DISTINCT DECISION_TYPE)
        FROM (
            SELECT DECISION_TYPE, DECISION_PAYLOAD
            FROM GOVERNED_DECISION_RECORD
            WHERE ASSESSMENT_RUN_ID = :v_base_run_id
              AND DECISION_TYPE IN (
                  'DECISION_GOVERNANCE',
                  'DECISION_VALUE',
                  'DECISION_MODEL_ROUTING',
                  'DECISION_PORTFOLIO'
              )
            QUALIFY ROW_NUMBER() OVER (
                PARTITION BY DECISION_TYPE ORDER BY PUBLISHED_AT DESC
            ) = 1
        ) latest_decision
    );

    IF (:v_base_decision_count <> 4) THEN
        RETURN '{"status":"FAILED","error":"Published base Revision must contain all four governed Decision Pack records"}';
    END IF;

    v_initiative_context := (
        SELECT
            'Name: ' || COALESCE(INITIATIVE_NAME, 'Not set') ||
            '\nDescription: ' || COALESCE(DESCRIPTION, 'Not set') ||
            '\nOwner: ' || COALESCE(OWNER_NAME, 'Not set') ||
            '\nLifecycle Stage: ' || COALESCE(LIFECYCLE_STAGE, 'Not set') ||
            '\nBusiness Outcome: ' || COALESCE(BUSINESS_OUTCOME, 'Not set') ||
            '\nStatus: ' || COALESCE(STATUS, 'Not set')
        FROM AI_INITIATIVE
        WHERE INITIATIVE_ID = :v_initiative_id
    );

    v_changed_evidence_fingerprint := (
        SELECT LISTAGG(
            EVIDENCE_ID || ':' || EVIDENCE_CHANGE_TYPE || ':' ||
            COALESCE(CONTENT_SHA256, SHA2(COALESCE(EVIDENCE_TEXT, ''), 256)),
            '||'
        ) WITHIN GROUP (ORDER BY EVIDENCE_ID)
        FROM V_REVISION_EVIDENCE_CHANGE
        WHERE REVISION_ID = :P_REVISION_ID
    );

    v_base_decision_fingerprint := (
        SELECT LISTAGG(
            DECISION_TYPE || ':' || SHA2(TO_JSON(DECISION_PAYLOAD), 256),
            '||'
        ) WITHIN GROUP (ORDER BY DECISION_TYPE)
        FROM (
            SELECT DECISION_TYPE, DECISION_PAYLOAD
            FROM GOVERNED_DECISION_RECORD
            WHERE ASSESSMENT_RUN_ID = :v_base_run_id
              AND DECISION_TYPE IN (
                  'DECISION_GOVERNANCE',
                  'DECISION_VALUE',
                  'DECISION_MODEL_ROUTING',
                  'DECISION_PORTFOLIO'
              )
            QUALIFY ROW_NUMBER() OVER (
                PARTITION BY DECISION_TYPE ORDER BY PUBLISHED_AT DESC
            ) = 1
        ) latest_decision
    );

    v_input_fingerprint := SHA2(
        :P_REVISION_ID || '||' ||
        COALESCE(:v_changed_evidence_fingerprint, 'NO_CHANGED_EVIDENCE') || '||' ||
        COALESCE(:v_base_decision_fingerprint, 'NO_BASE_DECISIONS') || '||' ||
        :v_model_name || '||' || :v_prompt_version,
        256
    );

    v_existing_analysis_run_id := (
        SELECT ANALYSIS_RUN_ID
        FROM REVISION_IMPACT_ANALYSIS_RUN
        WHERE REVISION_ID = :P_REVISION_ID
          AND INPUT_FINGERPRINT = :v_input_fingerprint
          AND STATUS = 'COMPLETED'
        QUALIFY ROW_NUMBER() OVER (ORDER BY COMPLETED_AT DESC, CREATED_AT DESC) = 1
    );

    IF (:v_existing_analysis_run_id IS NOT NULL) THEN
        RETURN '{"status":"SKIPPED","reason":"Identical governed inputs already have a completed impact analysis","analysis_run_id":"' ||
            :v_existing_analysis_run_id || '","fingerprint":"' || :v_input_fingerprint || '"}';
    END IF;

    INSERT INTO REVISION_IMPACT_ANALYSIS_RUN (
        ANALYSIS_RUN_ID,
        REVISION_ID,
        BASE_REVISION_ID,
        BASE_ASSESSMENT_RUN_ID,
        TARGET_ASSESSMENT_RUN_ID,
        STATUS,
        MODEL_NAME,
        PROMPT_VERSION,
        INPUT_FINGERPRINT,
        CHANGED_EVIDENCE_COUNT,
        STARTED_AT
    ) VALUES (
        :v_analysis_run_id,
        :P_REVISION_ID,
        :v_base_revision_id,
        :v_base_run_id,
        :v_target_run_id,
        'RUNNING',
        :v_model_name,
        :v_prompt_version,
        :v_input_fingerprint,
        :v_changed_evidence_count,
        CURRENT_TIMESTAMP()
    );

    v_changed_evidence_block := (
        SELECT LISTAGG(
            '---\nEvidence ID: ' || EVIDENCE_ID ||
            '\nChange Type: ' || EVIDENCE_CHANGE_TYPE ||
            '\nReplaced Evidence ID: ' || COALESCE(REPLACED_EVIDENCE_ID, 'None') ||
            '\nTitle: ' || COALESCE(EVIDENCE_TITLE, 'Untitled') ||
            '\nSource File: ' || COALESCE(SOURCE_FILENAME, 'Not set') ||
            '\nContent: ' || LEFT(COALESCE(EVIDENCE_TEXT, ''), 6000),
            '\n'
        ) WITHIN GROUP (ORDER BY EVIDENCE_ID)
        FROM V_REVISION_EVIDENCE_CHANGE
        WHERE REVISION_ID = :P_REVISION_ID
    );

    v_base_decision_block := (
        SELECT LISTAGG(
            '---\nDecision Type: ' || DECISION_TYPE ||
            '\nTitle: ' || COALESCE(TITLE, 'Untitled') ||
            '\nDescription: ' || COALESCE(DESCRIPTION, 'Not set') ||
            '\nPayload: ' || TO_JSON(DECISION_PAYLOAD),
            '\n'
        ) WITHIN GROUP (ORDER BY DECISION_TYPE)
        FROM (
            SELECT DECISION_TYPE, TITLE, DESCRIPTION, DECISION_PAYLOAD
            FROM GOVERNED_DECISION_RECORD
            WHERE ASSESSMENT_RUN_ID = :v_base_run_id
              AND DECISION_TYPE IN (
                  'DECISION_GOVERNANCE',
                  'DECISION_VALUE',
                  'DECISION_MODEL_ROUTING',
                  'DECISION_PORTFOLIO'
              )
            QUALIFY ROW_NUMBER() OVER (
                PARTITION BY DECISION_TYPE ORDER BY PUBLISHED_AT DESC
            ) = 1
        ) latest_decision
    );

    v_prompt :=
        'You are a conservative AI governance change-impact analyst. ' ||
        'Evaluate only whether the changed Evidence can affect each published governed decision.\n\n' ||
        'ASSESSMENT CASE:\n' || COALESCE(:v_case_name, 'Not set') ||
        '\nTARGET REVISION: ' || :v_revision_no ||
        '\nCHANGE REASON: ' || COALESCE(:v_change_reason, 'Not set') || '\n\n' ||
        'AI INITIATIVE:\n' || COALESCE(:v_initiative_context, 'Not set') || '\n\n' ||
        'CHANGED EVIDENCE ONLY:\n' || :v_changed_evidence_block || '\n\n' ||
        'PUBLISHED BASE DECISION PACK:\n' || :v_base_decision_block || '\n\n' ||
        'Return exactly four impact objects: one for each required section_type.\n' ||
        'Allowed section_type values: DECISION_GOVERNANCE, DECISION_VALUE, ' ||
        'DECISION_MODEL_ROUTING, DECISION_PORTFOLIO.\n' ||
        'Allowed impact_level values: HIGH, MEDIUM, LOW, NONE.\n' ||
        'Allowed recommended_treatment values: REASSESS, HUMAN_REVIEW, NO_CHANGE.\n' ||
        'Allowed confidence values: HIGH, MEDIUM, LOW.\n' ||
        'For every non-NONE impact, source_evidence_ids must be non-empty and contain only ' ||
        'Evidence IDs from CHANGED EVIDENCE ONLY. NONE must use NO_CHANGE.\n' ||
        'Do not approve, publish, or rewrite a decision. Do not infer facts not present in the input.';

    v_llm_response := (
        SELECT TO_JSON(
            AI_COMPLETE(
                model => 'mistral-large2',
                prompt => :v_prompt,
                model_parameters => {
                    'temperature': 0,
                    'max_tokens': 2500
                },
                response_format => {
                    'type': 'json',
                    'schema': {
                        'type': 'object',
                        'properties': {
                            'impacts': {
                                'type': 'array',
                                'items': {
                                    'type': 'object',
                                    'properties': {
                                        'section_type': {
                                            'type': 'string',
                                            'enum': [
                                                'DECISION_GOVERNANCE',
                                                'DECISION_VALUE',
                                                'DECISION_MODEL_ROUTING',
                                                'DECISION_PORTFOLIO'
                                            ]
                                        },
                                        'impact_level': {
                                            'type': 'string',
                                            'enum': ['HIGH', 'MEDIUM', 'LOW', 'NONE']
                                        },
                                        'recommended_treatment': {
                                            'type': 'string',
                                            'enum': ['REASSESS', 'HUMAN_REVIEW', 'NO_CHANGE']
                                        },
                                        'confidence': {
                                            'type': 'string',
                                            'enum': ['HIGH', 'MEDIUM', 'LOW']
                                        },
                                        'rationale': {'type': 'string'},
                                        'source_evidence_ids': {
                                            'type': 'array',
                                            'items': {'type': 'string'}
                                        }
                                    },
                                    'required': [
                                        'section_type',
                                        'impact_level',
                                        'recommended_treatment',
                                        'confidence',
                                        'rationale',
                                        'source_evidence_ids'
                                    ],
                                    'additionalProperties': false
                                }
                            }
                        },
                        'required': ['impacts'],
                        'additionalProperties': false
                    }
                }
            )
        )
    );

    v_llm_response := REGEXP_REPLACE(:v_llm_response, '^\\s*```(json|JSON)?\\s*', '');
    v_llm_response := REGEXP_REPLACE(:v_llm_response, '\\s*```\\s*$', '');
    v_llm_response := TRIM(:v_llm_response);
    v_parsed := (SELECT TRY_PARSE_JSON(:v_llm_response));

    IF (:v_parsed IS NULL OR TYPEOF(:v_parsed:impacts) <> 'ARRAY') THEN
        UPDATE REVISION_IMPACT_ANALYSIS_RUN
        SET STATUS = 'FAILED',
            COMPLETED_AT = CURRENT_TIMESTAMP(),
            ERROR_MESSAGE = 'Cortex returned invalid impact JSON'
        WHERE ANALYSIS_RUN_ID = :v_analysis_run_id;
        RETURN '{"status":"FAILED","analysis_run_id":"' || :v_analysis_run_id ||
            '","error":"Cortex returned invalid impact JSON"}';
    END IF;

    CREATE OR REPLACE TEMPORARY TABLE TMP_REVISION_IMPACT_ITEM AS
    SELECT
        UPPER(item.VALUE:section_type::VARCHAR) AS SECTION_TYPE,
        UPPER(item.VALUE:impact_level::VARCHAR) AS IMPACT_LEVEL,
        UPPER(item.VALUE:recommended_treatment::VARCHAR) AS RECOMMENDED_TREATMENT,
        UPPER(item.VALUE:confidence::VARCHAR) AS CONFIDENCE,
        TRIM(item.VALUE:rationale::VARCHAR) AS RATIONALE,
        item.VALUE:source_evidence_ids::ARRAY AS SOURCE_EVIDENCE_IDS
    FROM TABLE(FLATTEN(INPUT => :v_parsed:impacts)) item;

    SELECT COUNT(*), COUNT(DISTINCT SECTION_TYPE)
      INTO :v_output_count, :v_distinct_section_count
    FROM TMP_REVISION_IMPACT_ITEM;

    v_invalid_item_count := (
        SELECT COUNT(*)
        FROM TMP_REVISION_IMPACT_ITEM
        WHERE SECTION_TYPE NOT IN (
                  'DECISION_GOVERNANCE',
                  'DECISION_VALUE',
                  'DECISION_MODEL_ROUTING',
                  'DECISION_PORTFOLIO'
              )
           OR IMPACT_LEVEL NOT IN ('HIGH', 'MEDIUM', 'LOW', 'NONE')
           OR RECOMMENDED_TREATMENT NOT IN ('REASSESS', 'HUMAN_REVIEW', 'NO_CHANGE')
           OR CONFIDENCE NOT IN ('HIGH', 'MEDIUM', 'LOW')
           OR NULLIF(RATIONALE, '') IS NULL
           OR TYPEOF(SOURCE_EVIDENCE_IDS) <> 'ARRAY'
           OR (IMPACT_LEVEL <> 'NONE' AND ARRAY_SIZE(SOURCE_EVIDENCE_IDS) = 0)
           OR (IMPACT_LEVEL = 'NONE' AND RECOMMENDED_TREATMENT <> 'NO_CHANGE')
    );

    v_invalid_source_count := (
        SELECT COUNT(*)
        FROM TMP_REVISION_IMPACT_ITEM impact,
             LATERAL FLATTEN(INPUT => impact.SOURCE_EVIDENCE_IDS) source
        WHERE NOT EXISTS (
            SELECT 1
            FROM V_REVISION_EVIDENCE_CHANGE changed
            WHERE changed.REVISION_ID = :P_REVISION_ID
              AND changed.EVIDENCE_ID = source.VALUE::VARCHAR
        )
    );

    IF (
        :v_output_count <> 4 OR
        :v_distinct_section_count <> 4 OR
        :v_invalid_item_count > 0 OR
        :v_invalid_source_count > 0
    ) THEN
        UPDATE REVISION_IMPACT_ANALYSIS_RUN
        SET STATUS = 'FAILED',
            COMPLETED_AT = CURRENT_TIMESTAMP(),
            ERROR_MESSAGE = 'Impact output failed governed validation'
        WHERE ANALYSIS_RUN_ID = :v_analysis_run_id;
        RETURN '{"status":"FAILED","analysis_run_id":"' || :v_analysis_run_id ||
            '","error":"Impact output failed governed validation"}';
    END IF;

    BEGIN TRANSACTION;

    INSERT INTO REVISION_IMPACT_ANALYSIS_ITEM (
        IMPACT_ITEM_ID,
        ANALYSIS_RUN_ID,
        REVISION_ID,
        SECTION_TYPE,
        IMPACT_LEVEL,
        RECOMMENDED_TREATMENT,
        CONFIDENCE,
        RATIONALE,
        SOURCE_EVIDENCE_IDS
    )
    SELECT
        'II_' || REPLACE(UUID_STRING(), '-', ''),
        :v_analysis_run_id,
        :P_REVISION_ID,
        SECTION_TYPE,
        IMPACT_LEVEL,
        RECOMMENDED_TREATMENT,
        CONFIDENCE,
        RATIONALE,
        SOURCE_EVIDENCE_IDS
    FROM TMP_REVISION_IMPACT_ITEM;

    UPDATE REVISION_IMPACT_ANALYSIS_RUN
    SET STATUS = 'COMPLETED',
        COMPLETED_AT = CURRENT_TIMESTAMP(),
        ERROR_MESSAGE = NULL
    WHERE ANALYSIS_RUN_ID = :v_analysis_run_id;

    COMMIT;

    RETURN '{"status":"COMPLETED","analysis_run_id":"' || :v_analysis_run_id ||
        '","revision_id":"' || :P_REVISION_ID ||
        '","changed_evidence":' || :v_changed_evidence_count ||
        ',"impact_items":' || :v_output_count ||
        ',"fingerprint":"' || :v_input_fingerprint || '"}';

EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        UPDATE REVISION_IMPACT_ANALYSIS_RUN
        SET STATUS = 'FAILED',
            COMPLETED_AT = CURRENT_TIMESTAMP(),
            ERROR_MESSAGE = LEFT(:SQLERRM, 1000)
        WHERE ANALYSIS_RUN_ID = :v_analysis_run_id
          AND STATUS = 'RUNNING';
        RETURN '{"status":"FAILED","analysis_run_id":"' || :v_analysis_run_id ||
            '","error":"' || REPLACE(LEFT(SQLERRM, 500), '"', '\\"') || '"}';
END;
$$;

-- Rollback guidance:
--   DROP PROCEDURE IF EXISTS SP_ANALYZE_REVISION_EVIDENCE_IMPACT(VARCHAR);
