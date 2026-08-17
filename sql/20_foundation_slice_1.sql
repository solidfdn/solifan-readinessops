-- ============================================================
-- Foundation Slice 1: AI Initiative, Dynamic Evidence, Decision Pack
-- ============================================================
-- Idempotent: uses IF NOT EXISTS / ADD COLUMN IF NOT EXISTS.
-- Safe to re-run against an already-migrated schema.
--
-- ROLLBACK GUIDANCE (do NOT run unless reverting this slice):
--   DROP TABLE IF EXISTS GOVERNED_DECISION_RECORD;
--   DROP TABLE IF EXISTS AI_INITIATIVE;
--   DROP VIEW IF EXISTS V_AI_PORTFOLIO;
--   DROP PROCEDURE IF EXISTS SP_GENERATE_DECISION_PACK(VARCHAR, VARCHAR);
--   DROP PROCEDURE IF EXISTS SP_EDIT_AGENT_PROPOSAL(VARCHAR, VARCHAR, VARCHAR, VARCHAR);
--   -- Column drops require ALTER TABLE ... DROP COLUMN (irreversible data loss):
--   --   ALTER TABLE ASSESSMENT_RUNS DROP COLUMN INITIATIVE_ID;
--   --   ALTER TABLE EVIDENCE_ITEMS DROP COLUMN SOURCE_FILENAME, SOURCE_TYPE, ...;
--   --   ALTER TABLE GOVERNANCE_AGENT_PROPOSAL DROP COLUMN PROPOSAL_PAYLOAD;
--   -- Restore SP_PUBLISH_AGENT_RUN from the pre-migration GET_DDL or baseline commit.
-- ============================================================

USE SCHEMA READINESSOPS_VALIDATION.APP;

-- ============================================================
-- A. AI_INITIATIVE: stable portfolio entity
-- ============================================================
CREATE TABLE IF NOT EXISTS AI_INITIATIVE (
    INITIATIVE_ID       VARCHAR(16777216) NOT NULL,
    INITIATIVE_NAME     VARCHAR(16777216) NOT NULL,
    DESCRIPTION         VARCHAR(16777216),
    OWNER_NAME          VARCHAR(200),
    LIFECYCLE_STAGE     VARCHAR(50) DEFAULT 'IDEATION',
    BUSINESS_OUTCOME    VARCHAR(16777216),
    STATUS              VARCHAR(50) DEFAULT 'ACTIVE',
    CREATED_AT          TIMESTAMP_NTZ(9) DEFAULT CURRENT_TIMESTAMP(),
    CREATED_BY          VARCHAR(200) DEFAULT CURRENT_USER(),
    UPDATED_AT          TIMESTAMP_NTZ(9) DEFAULT CURRENT_TIMESTAMP(),
    UPDATED_BY          VARCHAR(200) DEFAULT CURRENT_USER()
);

-- Link assessment runs to an initiative
ALTER TABLE ASSESSMENT_RUNS ADD COLUMN IF NOT EXISTS INITIATIVE_ID VARCHAR(16777216);

-- ============================================================
-- B. EVIDENCE_ITEMS: dynamic evidence metadata
-- ============================================================
ALTER TABLE EVIDENCE_ITEMS ADD COLUMN IF NOT EXISTS SOURCE_FILENAME VARCHAR(16777216);
ALTER TABLE EVIDENCE_ITEMS ADD COLUMN IF NOT EXISTS SOURCE_TYPE VARCHAR(50);
ALTER TABLE EVIDENCE_ITEMS ADD COLUMN IF NOT EXISTS MEDIA_TYPE VARCHAR(100);
ALTER TABLE EVIDENCE_ITEMS ADD COLUMN IF NOT EXISTS CONTENT_SHA256 VARCHAR(64);
ALTER TABLE EVIDENCE_ITEMS ADD COLUMN IF NOT EXISTS BYTE_COUNT NUMBER(38,0);
ALTER TABLE EVIDENCE_ITEMS ADD COLUMN IF NOT EXISTS CHAR_COUNT NUMBER(38,0);
ALTER TABLE EVIDENCE_ITEMS ADD COLUMN IF NOT EXISTS UPLOADED_AT TIMESTAMP_NTZ(9);
ALTER TABLE EVIDENCE_ITEMS ADD COLUMN IF NOT EXISTS UPLOADED_BY VARCHAR(200);
ALTER TABLE EVIDENCE_ITEMS ADD COLUMN IF NOT EXISTS STAGE_PATH VARCHAR(16777216);
ALTER TABLE EVIDENCE_ITEMS ADD COLUMN IF NOT EXISTS PARSER_NAME VARCHAR(100);
ALTER TABLE EVIDENCE_ITEMS ADD COLUMN IF NOT EXISTS PAGE_COUNT NUMBER(38,0);

CREATE STAGE IF NOT EXISTS READINESSOPS_EVIDENCE_STAGE
    COMMENT = 'Original evidence files uploaded through ReadinessOps';

-- ============================================================
-- C. GOVERNANCE_AGENT_PROPOSAL: structured payload
-- ============================================================
ALTER TABLE GOVERNANCE_AGENT_PROPOSAL ADD COLUMN IF NOT EXISTS PROPOSAL_PAYLOAD VARIANT;

-- ============================================================
-- D. GOVERNED_DECISION_RECORD: immutable published snapshot
-- ============================================================
CREATE TABLE IF NOT EXISTS GOVERNED_DECISION_RECORD (
    DECISION_RECORD_ID      VARCHAR(16777216) NOT NULL,
    SOURCE_PROPOSAL_ID      VARCHAR(16777216) NOT NULL,
    SOURCE_AGENT_RUN_ID     VARCHAR(16777216) NOT NULL,
    ASSESSMENT_RUN_ID       VARCHAR(16777216) NOT NULL,
    INITIATIVE_ID           VARCHAR(16777216),
    DECISION_TYPE           VARCHAR(50) NOT NULL,
    TITLE                   VARCHAR(16777216),
    DESCRIPTION             VARCHAR(16777216),
    DECISION_PAYLOAD        VARIANT NOT NULL,
    PUBLISHED_BY            VARCHAR(200) DEFAULT CURRENT_USER(),
    PUBLISHED_AT            TIMESTAMP_NTZ(9) DEFAULT CURRENT_TIMESTAMP()
);

-- ============================================================
-- E. SP_GENERATE_DECISION_PACK
-- ============================================================
CREATE OR REPLACE PROCEDURE SP_GENERATE_DECISION_PACK(
    P_ASSESSMENT_RUN_ID VARCHAR,
    P_ADDITIONAL_INSTRUCTION VARCHAR DEFAULT NULL
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_agent_run_id VARCHAR DEFAULT 'DP_' || TO_VARCHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD_HH24MISS_FF3');
BEGIN
    LET v_initiative_id VARCHAR;
    LET v_initiative_context VARCHAR := '';
    LET v_evidence_block VARCHAR;
    LET v_input_fingerprint VARCHAR;
    LET v_existing_run INTEGER;
    LET v_run_exists INTEGER;
    LET v_evidence_count INTEGER;
    LET v_prompt VARCHAR;
    LET v_llm_response VARCHAR;
    LET v_parsed VARIANT;
    LET v_gov_valid BOOLEAN := FALSE;
    LET v_val_valid BOOLEAN := FALSE;
    LET v_route_valid BOOLEAN := FALSE;
    LET v_port_valid BOOLEAN := FALSE;
    LET v_prompt_version VARCHAR := 'DECISION_PACK_V1';
    LET v_assessment_block VARCHAR;
    LET v_assessment_fingerprint VARCHAR;
    LET v_evidence_fingerprint VARCHAR;
    LET v_gov_ids ARRAY;
    LET v_val_ids ARRAY;
    LET v_route_ids ARRAY;
    LET v_port_ids ARRAY;
    LET v_invalid_source_count INTEGER := 0;
    LET v_port_priority NUMBER;

    -- Validate assessment run
    v_run_exists := (SELECT COUNT(*) FROM ASSESSMENT_RUNS WHERE RUN_ID = :P_ASSESSMENT_RUN_ID);
    IF (:v_run_exists = 0) THEN
        RETURN '{"status":"FAILED","error":"Assessment Run not found"}';
    END IF;

    -- Get initiative context
    v_initiative_id := (
        SELECT INITIATIVE_ID FROM ASSESSMENT_RUNS WHERE RUN_ID = :P_ASSESSMENT_RUN_ID
    );
    IF (:v_initiative_id IS NULL) THEN
        RETURN '{"status":"FAILED","error":"Link an AI Initiative before generating a Decision Pack"}';
    ELSE
        v_initiative_context := (
            SELECT
                'AI INITIATIVE CONTEXT:\nName: ' || COALESCE(INITIATIVE_NAME, 'Not set') ||
                '\nDescription: ' || COALESCE(DESCRIPTION, 'Not set') ||
                '\nOwner: ' || COALESCE(OWNER_NAME, 'Not set') ||
                '\nLifecycle Stage: ' || COALESCE(LIFECYCLE_STAGE, 'Not set') ||
                '\nBusiness Outcome: ' || COALESCE(BUSINESS_OUTCOME, 'Not set') ||
                '\nStatus: ' || COALESCE(STATUS, 'Not set') || '\n\n'
            FROM AI_INITIATIVE
            WHERE INITIATIVE_ID = :v_initiative_id
        );
        IF (:v_initiative_context IS NULL) THEN
            RETURN '{"status":"FAILED","error":"Linked AI Initiative not found"}';
        END IF;
    END IF;

    v_evidence_count := (
        SELECT COUNT(*) FROM EVIDENCE_ITEMS WHERE RUN_ID = :P_ASSESSMENT_RUN_ID
    );
    IF (:v_evidence_count = 0) THEN
        RETURN '{"status":"FAILED","error":"At least one evidence item is required"}';
    END IF;

    -- Fingerprint every input that can change the generated Decision Pack.
    v_assessment_fingerprint := (
        SELECT COALESCE(
            LISTAGG(
                q.QUESTION_ID || ':' || COALESCE(a.ANSWER_STATUS, '') || ':' ||
                COALESCE(a.ANSWER_TEXT, ''),
                '||'
            ) WITHIN GROUP (ORDER BY q.SORT_ORDER),
            'NO_ASSESSMENT_ANSWERS'
        )
        FROM ASSESSMENT_ANSWERS a
        JOIN READINESS_QUESTIONS q ON a.QUESTION_ID = q.QUESTION_ID
        WHERE a.RUN_ID = :P_ASSESSMENT_RUN_ID
    );

    v_evidence_fingerprint := (
        SELECT COALESCE(
            LISTAGG(
                EVIDENCE_ID || ':' || COALESCE(EVIDENCE_STATUS, '') || ':' ||
                COALESCE(CONTENT_SHA256, SHA2(COALESCE(EVIDENCE_TEXT, ''), 256)),
                '||'
            ) WITHIN GROUP (ORDER BY EVIDENCE_ID),
            'NO_EVIDENCE'
        )
        FROM EVIDENCE_ITEMS
        WHERE RUN_ID = :P_ASSESSMENT_RUN_ID
    );

    v_input_fingerprint := SHA2(
        COALESCE(:v_initiative_context, 'NO_INITIATIVE') || '||' ||
        COALESCE(:v_assessment_fingerprint, 'NO_ASSESSMENT_ANSWERS') || '||' ||
        COALESCE(:v_evidence_fingerprint, 'NO_EVIDENCE') || '||' ||
        COALESCE(:P_ADDITIONAL_INSTRUCTION, '') || '||' ||
        :v_prompt_version,
        256
    );

    -- Idempotency: check for existing successful run with same fingerprint
    v_existing_run := (
        SELECT COUNT(*)
        FROM GOVERNANCE_AGENT_RUN
        WHERE ASSESSMENT_RUN_ID = :P_ASSESSMENT_RUN_ID
          AND WORKFLOW_TYPE = 'DECISION_PACK'
          AND INPUT_FINGERPRINT = :v_input_fingerprint
          AND STATUS = 'COMPLETED'
    );
    IF (:v_existing_run > 0) THEN
        RETURN '{"status":"SKIPPED","reason":"Identical input fingerprint already has a completed Decision Pack run","fingerprint":"' || :v_input_fingerprint || '"}';
    END IF;

    -- Register agent run
    INSERT INTO GOVERNANCE_AGENT_RUN (
        AGENT_RUN_ID, ASSESSMENT_RUN_ID, WORKFLOW_TYPE,
        STANDARD_INSTRUCTION, ADDITIONAL_INSTRUCTION,
        STATUS, MODEL_NAME, PROMPT_VERSION, INPUT_FINGERPRINT
    ) VALUES (
        :v_agent_run_id, :P_ASSESSMENT_RUN_ID, 'DECISION_PACK',
        'Generate a structured Decision Pack covering Governance, Value Realization, Model Routing, and Portfolio recommendations.',
        :P_ADDITIONAL_INSTRUCTION,
        'RUNNING', 'mistral-large2', :v_prompt_version, :v_input_fingerprint
    );

    -- Build evidence block
    v_evidence_block := (
        SELECT LISTAGG(
            '---\nEvidence ID: ' || EVIDENCE_ID ||
            '\nTitle: ' || COALESCE(EVIDENCE_TITLE, 'Untitled') ||
            '\nSource Type: ' || COALESCE(SOURCE_TYPE, 'SEED') ||
            '\nStatus: ' || COALESCE(EVIDENCE_STATUS, 'UNKNOWN') ||
            '\nContent: ' || LEFT(COALESCE(EVIDENCE_TEXT, ''), 4000),
            '\n'
        ) WITHIN GROUP (ORDER BY EVIDENCE_ID)
        FROM EVIDENCE_ITEMS
        WHERE RUN_ID = :P_ASSESSMENT_RUN_ID
    );

    -- Build assessment context
    v_assessment_block := (
        SELECT LISTAGG(
            '---\nQuestion ID: ' || q.QUESTION_ID ||
            '\nDomain: ' || d.DOMAIN_NAME ||
            '\nQuestion: ' || q.QUESTION_TEXT ||
            '\nRule: ' || q.EXPECTED_EVIDENCE ||
            '\nAnswer Status: ' || a.ANSWER_STATUS ||
            '\nAnswer: ' || COALESCE(a.ANSWER_TEXT, 'N/A'),
            '\n'
        ) WITHIN GROUP (ORDER BY q.SORT_ORDER)
        FROM ASSESSMENT_ANSWERS a
        JOIN READINESS_QUESTIONS q ON a.QUESTION_ID = q.QUESTION_ID
        JOIN READINESS_DOMAINS d ON q.DOMAIN_ID = d.DOMAIN_ID
        WHERE a.RUN_ID = :P_ASSESSMENT_RUN_ID
    );

    -- Build prompt
    v_prompt :=
        'You are a governance and AI strategy advisor. Generate a Decision Pack for the following AI initiative assessment.\n\n' ||
        :v_initiative_context ||
        'ASSESSMENT DATA:\n' || COALESCE(:v_assessment_block, 'No assessment answers available.') || '\n\n' ||
        'EVIDENCE:\n' || COALESCE(:v_evidence_block, 'No evidence items available.') || '\n\n' ||
        CASE WHEN :P_ADDITIONAL_INSTRUCTION IS NOT NULL
            THEN 'ADDITIONAL INSTRUCTION: ' || :P_ADDITIONAL_INSTRUCTION || '\n\n'
            ELSE ''
        END ||
        'OUTPUT: Return a single JSON object with exactly four keys. Each section must cite source_evidence_ids (array of evidence IDs used).\n\n' ||
        '{\n' ||
        '  "governance_summary": {\n' ||
        '    "title": "...",\n' ||
        '    "description": "Overall governance readiness assessment",\n' ||
        '    "readiness_level": "RED|AMBER|GREEN",\n' ||
        '    "key_findings": ["..."],\n' ||
        '    "recommendations": ["..."],\n' ||
        '    "source_evidence_ids": ["EV_001"]\n' ||
        '  },\n' ||
        '  "value_realization": {\n' ||
        '    "title": "...",\n' ||
        '    "description": "Value and business outcome assessment",\n' ||
        '    "value_hypothesis": "...",\n' ||
        '    "kpis": [{"name":"...","baseline":"...","target":"...","measurement_window":"..."}],\n' ||
        '    "estimated_cost": "...",\n' ||
        '    "expected_benefit": "...",\n' ||
        '    "realization_confidence": "HIGH|MEDIUM|LOW",\n' ||
        '    "blockers": ["..."],\n' ||
        '    "enablers": ["..."],\n' ||
        '    "source_evidence_ids": ["EV_001"]\n' ||
        '  },\n' ||
        '  "model_routing": {\n' ||
        '    "title": "...",\n' ||
        '    "description": "Model selection and routing recommendation",\n' ||
        '    "recommended_model_class": "...",\n' ||
        '    "recommended_approach": "...",\n' ||
        '    "complexity_level": "HIGH|MEDIUM|LOW",\n' ||
        '    "data_readiness": "HIGH|MEDIUM|LOW",\n' ||
        '    "quality_cost_latency_constraints": ["..."],\n' ||
        '    "fallback_approach": "...",\n' ||
        '    "human_gate": "...",\n' ||
        '    "considerations": ["..."],\n' ||
        '    "source_evidence_ids": ["EV_001"]\n' ||
        '  },\n' ||
        '  "portfolio_recommendation": {\n' ||
        '    "title": "...",\n' ||
        '    "description": "Portfolio-level recommendation",\n' ||
        '    "recommendation": "PROCEED|HOLD|REDESIGN|RETIRE",\n' ||
        '    "priority_score": 85,\n' ||
        '    "funding_posture": "INCREASE|MAINTAIN|REDUCE|STOP",\n' ||
        '    "rationale": "...",\n' ||
        '    "next_review": "YYYY-MM-DD",\n' ||
        '    "next_steps": ["..."],\n' ||
        '    "source_evidence_ids": ["EV_001"]\n' ||
        '  }\n' ||
        '}\n\n' ||
        'RULES:\n' ||
        '- Return ONLY valid JSON. No markdown fences.\n' ||
        '- Every source_evidence_ids array must be non-empty and contain only IDs from the supplied evidence.\n' ||
        '- priority_score must be one integer from 1 through 100.\n' ||
        '- Do not invent evidence IDs.\n' ||
        '- Ground every recommendation in supplied evidence and assessment answers.';

    -- Call LLM
    v_llm_response := (SELECT SNOWFLAKE.CORTEX.COMPLETE('mistral-large2', :v_prompt));

    -- Clean markdown fences
    v_llm_response := REGEXP_REPLACE(:v_llm_response, '^\\s*```(json|JSON)?\\s*', '');
    v_llm_response := REGEXP_REPLACE(:v_llm_response, '\\s*```\\s*$', '');
    v_llm_response := TRIM(:v_llm_response);

    -- Parse JSON
    v_parsed := (SELECT TRY_PARSE_JSON(:v_llm_response));
    IF (:v_parsed IS NULL) THEN
        UPDATE GOVERNANCE_AGENT_RUN
        SET STATUS = 'FAILED', COMPLETED_AT = CURRENT_TIMESTAMP(),
            ERROR_MESSAGE = 'Invalid JSON response: ' || LEFT(COALESCE(:v_llm_response, 'NULL'), 500)
        WHERE AGENT_RUN_ID = :v_agent_run_id;
        RETURN '{"status":"FAILED","agent_run_id":"' || :v_agent_run_id || '","error":"Invalid JSON from LLM"}';
    END IF;

    -- Validate the exact four-section object contract.
    v_gov_valid := (TYPEOF(:v_parsed:governance_summary) = 'OBJECT');
    v_val_valid := (TYPEOF(:v_parsed:value_realization) = 'OBJECT');
    v_route_valid := (TYPEOF(:v_parsed:model_routing) = 'OBJECT');
    v_port_valid := (TYPEOF(:v_parsed:portfolio_recommendation) = 'OBJECT');

    IF (
        TYPEOF(:v_parsed) != 'OBJECT' OR
        ARRAY_SIZE(OBJECT_KEYS(:v_parsed)) != 4 OR
        NOT :v_gov_valid OR NOT :v_val_valid OR
        NOT :v_route_valid OR NOT :v_port_valid
    ) THEN
        UPDATE GOVERNANCE_AGENT_RUN
        SET STATUS = 'FAILED', COMPLETED_AT = CURRENT_TIMESTAMP(),
            ERROR_MESSAGE = 'Incomplete Decision Pack: governance=' || :v_gov_valid || ' value=' || :v_val_valid || ' routing=' || :v_route_valid || ' portfolio=' || :v_port_valid
        WHERE AGENT_RUN_ID = :v_agent_run_id;
        RETURN '{"status":"FAILED","agent_run_id":"' || :v_agent_run_id || '","error":"LLM returned incomplete Decision Pack"}';
    END IF;

    IF (
        NULLIF(TRIM(:v_parsed:governance_summary:title::VARCHAR), '') IS NULL OR
        NULLIF(TRIM(:v_parsed:governance_summary:description::VARCHAR), '') IS NULL OR
        COALESCE(UPPER(:v_parsed:governance_summary:readiness_level::VARCHAR), '') NOT IN ('RED', 'AMBER', 'GREEN') OR
        NULLIF(TRIM(:v_parsed:value_realization:title::VARCHAR), '') IS NULL OR
        NULLIF(TRIM(:v_parsed:value_realization:description::VARCHAR), '') IS NULL OR
        COALESCE(UPPER(:v_parsed:value_realization:realization_confidence::VARCHAR), '') NOT IN ('HIGH', 'MEDIUM', 'LOW') OR
        NULLIF(TRIM(:v_parsed:model_routing:title::VARCHAR), '') IS NULL OR
        NULLIF(TRIM(:v_parsed:model_routing:description::VARCHAR), '') IS NULL OR
        COALESCE(UPPER(:v_parsed:model_routing:complexity_level::VARCHAR), '') NOT IN ('HIGH', 'MEDIUM', 'LOW') OR
        COALESCE(UPPER(:v_parsed:model_routing:data_readiness::VARCHAR), '') NOT IN ('HIGH', 'MEDIUM', 'LOW') OR
        NULLIF(TRIM(:v_parsed:portfolio_recommendation:title::VARCHAR), '') IS NULL OR
        NULLIF(TRIM(:v_parsed:portfolio_recommendation:description::VARCHAR), '') IS NULL OR
        COALESCE(UPPER(:v_parsed:portfolio_recommendation:recommendation::VARCHAR), '') NOT IN ('PROCEED', 'HOLD', 'REDESIGN', 'RETIRE')
    ) THEN
        UPDATE GOVERNANCE_AGENT_RUN
        SET STATUS = 'FAILED', COMPLETED_AT = CURRENT_TIMESTAMP(),
            ERROR_MESSAGE = 'Decision Pack failed required field or enum validation'
        WHERE AGENT_RUN_ID = :v_agent_run_id;
        RETURN '{"status":"FAILED","agent_run_id":"' || :v_agent_run_id || '","error":"Invalid Decision Pack field values"}';
    END IF;

    -- Validate source arrays before casting or flattening them.
    IF (
        TYPEOF(:v_parsed:governance_summary:source_evidence_ids) != 'ARRAY' OR
        TYPEOF(:v_parsed:value_realization:source_evidence_ids) != 'ARRAY' OR
        TYPEOF(:v_parsed:model_routing:source_evidence_ids) != 'ARRAY' OR
        TYPEOF(:v_parsed:portfolio_recommendation:source_evidence_ids) != 'ARRAY'
    ) THEN
        UPDATE GOVERNANCE_AGENT_RUN
        SET STATUS = 'FAILED', COMPLETED_AT = CURRENT_TIMESTAMP(),
            ERROR_MESSAGE = 'Each Decision Pack section requires a source_evidence_ids array'
        WHERE AGENT_RUN_ID = :v_agent_run_id;
        RETURN '{"status":"FAILED","agent_run_id":"' || :v_agent_run_id || '","error":"Invalid source_evidence_ids type"}';
    END IF;

    v_gov_ids := (SELECT :v_parsed:governance_summary:source_evidence_ids::ARRAY);
    v_val_ids := (SELECT :v_parsed:value_realization:source_evidence_ids::ARRAY);
    v_route_ids := (SELECT :v_parsed:model_routing:source_evidence_ids::ARRAY);
    v_port_ids := (SELECT :v_parsed:portfolio_recommendation:source_evidence_ids::ARRAY);

    IF (
        ARRAY_SIZE(:v_gov_ids) = 0 OR ARRAY_SIZE(:v_val_ids) = 0 OR
        ARRAY_SIZE(:v_route_ids) = 0 OR ARRAY_SIZE(:v_port_ids) = 0
    ) THEN
        UPDATE GOVERNANCE_AGENT_RUN
        SET STATUS = 'FAILED', COMPLETED_AT = CURRENT_TIMESTAMP(),
            ERROR_MESSAGE = 'Every Decision Pack section must cite at least one evidence item'
        WHERE AGENT_RUN_ID = :v_agent_run_id;
        RETURN '{"status":"FAILED","agent_run_id":"' || :v_agent_run_id || '","error":"Empty source_evidence_ids"}';
    END IF;

    v_invalid_source_count := (
        SELECT COUNT(*)
        FROM (
            SELECT f.VALUE::VARCHAR AS EVIDENCE_ID FROM TABLE(FLATTEN(INPUT => :v_gov_ids)) f
            UNION ALL
            SELECT f.VALUE::VARCHAR AS EVIDENCE_ID FROM TABLE(FLATTEN(INPUT => :v_val_ids)) f
            UNION ALL
            SELECT f.VALUE::VARCHAR AS EVIDENCE_ID FROM TABLE(FLATTEN(INPUT => :v_route_ids)) f
            UNION ALL
            SELECT f.VALUE::VARCHAR AS EVIDENCE_ID FROM TABLE(FLATTEN(INPUT => :v_port_ids)) f
        ) cited
        LEFT JOIN EVIDENCE_ITEMS e
          ON e.RUN_ID = :P_ASSESSMENT_RUN_ID
         AND e.EVIDENCE_ID = cited.EVIDENCE_ID
        WHERE e.EVIDENCE_ID IS NULL
    );

    IF (:v_invalid_source_count > 0) THEN
        UPDATE GOVERNANCE_AGENT_RUN
        SET STATUS = 'FAILED', COMPLETED_AT = CURRENT_TIMESTAMP(),
            ERROR_MESSAGE = 'Decision Pack cited evidence outside the selected Assessment Run'
        WHERE AGENT_RUN_ID = :v_agent_run_id;
        RETURN '{"status":"FAILED","agent_run_id":"' || :v_agent_run_id || '","error":"Invalid evidence citation"}';
    END IF;

    v_port_priority := TRY_TO_NUMBER(:v_parsed:portfolio_recommendation:priority_score::VARCHAR);
    IF (
        :v_port_priority IS NULL OR :v_port_priority < 1 OR :v_port_priority > 100 OR
        MOD(:v_port_priority, 1) != 0
    ) THEN
        UPDATE GOVERNANCE_AGENT_RUN
        SET STATUS = 'FAILED', COMPLETED_AT = CURRENT_TIMESTAMP(),
            ERROR_MESSAGE = 'portfolio_recommendation.priority_score must be an integer from 1 through 100'
        WHERE AGENT_RUN_ID = :v_agent_run_id;
        RETURN '{"status":"FAILED","agent_run_id":"' || :v_agent_run_id || '","error":"Invalid priority_score"}';
    END IF;

    -- Insert four proposals atomically
    BEGIN TRANSACTION;

    -- DECISION_GOVERNANCE
    INSERT INTO GOVERNANCE_AGENT_PROPOSAL (
        PROPOSAL_ID, AGENT_RUN_ID, ASSESSMENT_RUN_ID, PROPOSAL_TYPE,
        TITLE, DESCRIPTION, SEVERITY, PRIORITY, RATIONALE, STATUS, PROPOSAL_PAYLOAD
    )
    SELECT
        :v_agent_run_id || '_GOV',
        :v_agent_run_id,
        :P_ASSESSMENT_RUN_ID,
        'DECISION_GOVERNANCE',
        :v_parsed:governance_summary:title::VARCHAR,
        :v_parsed:governance_summary:description::VARCHAR,
        :v_parsed:governance_summary:readiness_level::VARCHAR,
        80,
        'Generated from assessment evidence and governance evaluation.',
        'REVIEW_REQUIRED',
        :v_parsed:governance_summary;

    -- DECISION_VALUE
    INSERT INTO GOVERNANCE_AGENT_PROPOSAL (
        PROPOSAL_ID, AGENT_RUN_ID, ASSESSMENT_RUN_ID, PROPOSAL_TYPE,
        TITLE, DESCRIPTION, SEVERITY, PRIORITY, RATIONALE, STATUS, PROPOSAL_PAYLOAD
    )
    SELECT
        :v_agent_run_id || '_VAL',
        :v_agent_run_id,
        :P_ASSESSMENT_RUN_ID,
        'DECISION_VALUE',
        :v_parsed:value_realization:title::VARCHAR,
        :v_parsed:value_realization:description::VARCHAR,
        :v_parsed:value_realization:realization_confidence::VARCHAR,
        75,
        'Generated from business outcome and evidence analysis.',
        'REVIEW_REQUIRED',
        :v_parsed:value_realization;

    -- DECISION_MODEL_ROUTING
    INSERT INTO GOVERNANCE_AGENT_PROPOSAL (
        PROPOSAL_ID, AGENT_RUN_ID, ASSESSMENT_RUN_ID, PROPOSAL_TYPE,
        TITLE, DESCRIPTION, SEVERITY, PRIORITY, RATIONALE, STATUS, PROPOSAL_PAYLOAD
    )
    SELECT
        :v_agent_run_id || '_ROUTE',
        :v_agent_run_id,
        :P_ASSESSMENT_RUN_ID,
        'DECISION_MODEL_ROUTING',
        :v_parsed:model_routing:title::VARCHAR,
        :v_parsed:model_routing:description::VARCHAR,
        :v_parsed:model_routing:complexity_level::VARCHAR,
        70,
        'Generated from data readiness and complexity assessment.',
        'REVIEW_REQUIRED',
        :v_parsed:model_routing;

    -- DECISION_PORTFOLIO
    INSERT INTO GOVERNANCE_AGENT_PROPOSAL (
        PROPOSAL_ID, AGENT_RUN_ID, ASSESSMENT_RUN_ID, PROPOSAL_TYPE,
        TITLE, DESCRIPTION, SEVERITY, PRIORITY, RATIONALE, STATUS, PROPOSAL_PAYLOAD
    )
    SELECT
        :v_agent_run_id || '_PORT',
        :v_agent_run_id,
        :P_ASSESSMENT_RUN_ID,
        'DECISION_PORTFOLIO',
        :v_parsed:portfolio_recommendation:title::VARCHAR,
        :v_parsed:portfolio_recommendation:description::VARCHAR,
        NULL,
        :v_port_priority,
        :v_parsed:portfolio_recommendation:rationale::VARCHAR,
        'REVIEW_REQUIRED',
        :v_parsed:portfolio_recommendation;

    -- Source traceability: one immutable row per cited evidence item and section.
    INSERT INTO GOVERNANCE_AGENT_PROPOSAL_SOURCE (
        PROPOSAL_SOURCE_ID, PROPOSAL_ID, SOURCE_TYPE, SOURCE_ID,
        EVIDENCE_ITEM_ID, SOURCE_SUMMARY
    )
    SELECT
        cited.PROPOSAL_ID || '_SRC_' || LPAD(TO_VARCHAR(cited.SOURCE_INDEX + 1), 3, '0'),
        cited.PROPOSAL_ID,
        'DECISION_PACK_EVIDENCE',
        cited.EVIDENCE_ID,
        cited.EVIDENCE_ID,
        LEFT(COALESCE(e.EVIDENCE_TITLE, e.SOURCE_FILENAME, e.EVIDENCE_ID), 500)
    FROM (
        SELECT :v_agent_run_id || '_GOV' AS PROPOSAL_ID, f.INDEX AS SOURCE_INDEX,
               f.VALUE::VARCHAR AS EVIDENCE_ID
        FROM TABLE(FLATTEN(INPUT => :v_gov_ids)) f
        UNION ALL
        SELECT :v_agent_run_id || '_VAL', f.INDEX, f.VALUE::VARCHAR
        FROM TABLE(FLATTEN(INPUT => :v_val_ids)) f
        UNION ALL
        SELECT :v_agent_run_id || '_ROUTE', f.INDEX, f.VALUE::VARCHAR
        FROM TABLE(FLATTEN(INPUT => :v_route_ids)) f
        UNION ALL
        SELECT :v_agent_run_id || '_PORT', f.INDEX, f.VALUE::VARCHAR
        FROM TABLE(FLATTEN(INPUT => :v_port_ids)) f
    ) cited
    JOIN EVIDENCE_ITEMS e
      ON e.RUN_ID = :P_ASSESSMENT_RUN_ID
     AND e.EVIDENCE_ID = cited.EVIDENCE_ID;

    -- Mark completed inside the same transaction as proposals and citations.
    UPDATE GOVERNANCE_AGENT_RUN
    SET STATUS = 'COMPLETED', COMPLETED_AT = CURRENT_TIMESTAMP(),
        SUMMARY = 'Decision Pack: 4 sections generated'
    WHERE AGENT_RUN_ID = :v_agent_run_id;

    COMMIT;

    RETURN '{"status":"COMPLETED","agent_run_id":"' || :v_agent_run_id || '","sections":4}';

EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        UPDATE GOVERNANCE_AGENT_RUN
        SET STATUS = 'FAILED', COMPLETED_AT = CURRENT_TIMESTAMP(),
            ERROR_MESSAGE = LEFT(:SQLERRM, 500)
        WHERE AGENT_RUN_ID = :v_agent_run_id;
        RETURN '{"status":"FAILED","agent_run_id":"' || :v_agent_run_id || '","error":"' || LEFT(SQLERRM, 200) || '"}';
END;
$$;

-- ============================================================
-- F. SP_EDIT_AGENT_PROPOSAL: audited inline editing
-- ============================================================
CREATE OR REPLACE PROCEDURE SP_EDIT_AGENT_PROPOSAL(
    P_PROPOSAL_ID VARCHAR,
    P_NEW_TITLE VARCHAR,
    P_NEW_DESCRIPTION VARCHAR,
    P_EDIT_REASON VARCHAR DEFAULT NULL
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
BEGIN
    LET v_current_status VARCHAR;
    LET v_old_title VARCHAR;
    LET v_old_description VARCHAR;
    LET v_edit_detail VARIANT;

    -- Get current state
    v_current_status := (SELECT STATUS FROM GOVERNANCE_AGENT_PROPOSAL WHERE PROPOSAL_ID = :P_PROPOSAL_ID);

    IF (:v_current_status IS NULL) THEN
        RETURN '{"status":"FAILED","error":"Proposal not found"}';
    END IF;

    IF (:v_current_status != 'REVIEW_REQUIRED') THEN
        RETURN '{"status":"FAILED","error":"Only REVIEW_REQUIRED proposals can be edited. Current status: ' || :v_current_status || '"}';
    END IF;

    IF (TRIM(COALESCE(:P_NEW_TITLE, '')) = '') THEN
        RETURN '{"status":"FAILED","error":"Proposal title is required"}';
    END IF;

    -- Capture before values
    v_old_title := (SELECT TITLE FROM GOVERNANCE_AGENT_PROPOSAL WHERE PROPOSAL_ID = :P_PROPOSAL_ID);
    v_old_description := (SELECT DESCRIPTION FROM GOVERNANCE_AGENT_PROPOSAL WHERE PROPOSAL_ID = :P_PROPOSAL_ID);

    -- Build structured edit detail
    v_edit_detail := (SELECT OBJECT_CONSTRUCT(
        'before_title', :v_old_title,
        'after_title', :P_NEW_TITLE,
        'before_description', :v_old_description,
        'after_description', :P_NEW_DESCRIPTION,
        'edit_reason', :P_EDIT_REASON
    ));

    -- Apply the edit and its audit record atomically.
    BEGIN TRANSACTION;

    UPDATE GOVERNANCE_AGENT_PROPOSAL
    SET TITLE = :P_NEW_TITLE,
        DESCRIPTION = :P_NEW_DESCRIPTION,
        UPDATED_AT = CURRENT_TIMESTAMP()
    WHERE PROPOSAL_ID = :P_PROPOSAL_ID
      AND STATUS = 'REVIEW_REQUIRED';

    -- Write audit history
    INSERT INTO GOVERNANCE_APPROVAL_HISTORY (
        APPROVAL_HISTORY_ID, PROPOSAL_ID, ACTION_TYPE,
        PREVIOUS_STATUS, NEW_STATUS, COMMENT, ACTED_BY
    ) VALUES (
        'AH_EDIT_' || :P_PROPOSAL_ID || '_' || TO_VARCHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD_HH24MISS_FF3'),
        :P_PROPOSAL_ID,
        'EDIT',
        'REVIEW_REQUIRED',
        'REVIEW_REQUIRED',
        COALESCE(:P_EDIT_REASON, 'Inline edit') || ' | Detail: ' || :v_edit_detail::VARCHAR,
        CURRENT_USER()
    );

    COMMIT;

    RETURN '{"status":"OK","proposal_id":"' || :P_PROPOSAL_ID || '","edited_fields":["title","description"]}';

EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RETURN '{"status":"FAILED","error":"' || LEFT(SQLERRM, 200) || '"}';
END;
$$;

-- ============================================================
-- G. SP_PUBLISH_AGENT_RUN: extended for DECISION_* types
-- ============================================================
-- This is ADDITIVE. Existing GAP/RISK/ACTION publication logic is preserved.
-- The extension adds DECISION_*  GOVERNED_DECISION_RECORD publication.
CREATE OR REPLACE PROCEDURE SP_PUBLISH_AGENT_RUN(P_AGENT_RUN_ID VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
BEGIN
    LET v_run_exists INTEGER;
    LET v_approved_count INTEGER;
    LET v_pub_gaps INTEGER := 0;
    LET v_pub_risks INTEGER := 0;
    LET v_pub_actions INTEGER := 0;
    LET v_pub_decisions INTEGER := 0;

    -- Validate agent run exists
    v_run_exists := (
        SELECT COUNT(*) FROM GOVERNANCE_AGENT_RUN WHERE AGENT_RUN_ID = :P_AGENT_RUN_ID
    );
    IF (:v_run_exists = 0) THEN
        RETURN '{"status":"FAILED","error":"Agent Run not found"}';
    END IF;

    -- Freeze approved proposals
    CREATE OR REPLACE TEMPORARY TABLE TMP_APPROVED_AGENT_PROPOSALS AS
    SELECT
        p.*,
        CASE
            WHEN p.PROPOSAL_TYPE IN ('GAP', 'RISK') THEN
                EXISTS (SELECT 1 FROM READINESS_GAPS g WHERE g.SOURCE_PROPOSAL_ID = p.PROPOSAL_ID)
            WHEN p.PROPOSAL_TYPE = 'ACTION' THEN
                EXISTS (SELECT 1 FROM RECOMMENDED_ACTIONS a WHERE a.SOURCE_PROPOSAL_ID = p.PROPOSAL_ID)
            WHEN p.PROPOSAL_TYPE LIKE 'DECISION_%' THEN
                EXISTS (SELECT 1 FROM GOVERNED_DECISION_RECORD d WHERE d.SOURCE_PROPOSAL_ID = p.PROPOSAL_ID)
            ELSE FALSE
        END AS CANONICAL_ALREADY_EXISTS
    FROM GOVERNANCE_AGENT_PROPOSAL p
    WHERE p.AGENT_RUN_ID = :P_AGENT_RUN_ID
      AND p.STATUS = 'APPROVED'
      AND (
          p.PROPOSAL_TYPE IN ('GAP', 'RISK', 'ACTION') OR
          p.PROPOSAL_TYPE IN (
              'DECISION_GOVERNANCE', 'DECISION_VALUE',
              'DECISION_MODEL_ROUTING', 'DECISION_PORTFOLIO'
          )
      );

    v_approved_count := (SELECT COUNT(*) FROM TMP_APPROVED_AGENT_PROPOSALS);
    IF (:v_approved_count = 0) THEN
        RETURN '{"status":"FAILED","error":"No approved proposals to publish"}';
    END IF;

    -- Publish canonical records, proposal state, and audit rows atomically.
    BEGIN TRANSACTION;

    -- ============================================================
    -- EXISTING: Publish GAP proposals (unchanged)
    -- ============================================================
    MERGE INTO READINESS_GAPS target
    USING (
        SELECT
            'PUB_' || p.PROPOSAL_ID AS GAP_ID,
            p.ASSESSMENT_RUN_ID AS RUN_ID,
            q.DOMAIN_ID,
            p.QUESTION_ID,
            p.TITLE AS GAP_TITLE,
            p.DESCRIPTION AS GAP_DESCRIPTION,
            p.SEVERITY,
            p.PRIORITY AS PRIORITY_SCORE,
            p.PROPOSAL_ID AS SOURCE_PROPOSAL_ID,
            p.AGENT_RUN_ID AS SOURCE_AGENT_RUN_ID
        FROM TMP_APPROVED_AGENT_PROPOSALS p
        LEFT JOIN READINESS_QUESTIONS q ON p.QUESTION_ID = q.QUESTION_ID
        WHERE p.PROPOSAL_TYPE = 'GAP'
    ) source
    ON target.SOURCE_PROPOSAL_ID = source.SOURCE_PROPOSAL_ID
    WHEN NOT MATCHED THEN INSERT (
        GAP_ID, RUN_ID, DOMAIN_ID, QUESTION_ID,
        GAP_TITLE, GAP_DESCRIPTION, SEVERITY, PRIORITY_SCORE,
        SOURCE_PROPOSAL_ID, SOURCE_AGENT_RUN_ID
    ) VALUES (
        source.GAP_ID, source.RUN_ID, source.DOMAIN_ID, source.QUESTION_ID,
        source.GAP_TITLE, source.GAP_DESCRIPTION, source.SEVERITY, source.PRIORITY_SCORE,
        source.SOURCE_PROPOSAL_ID, source.SOURCE_AGENT_RUN_ID
    );

    v_pub_gaps := (
        SELECT COUNT(*) FROM TMP_APPROVED_AGENT_PROPOSALS
        WHERE PROPOSAL_TYPE = 'GAP' AND CANONICAL_ALREADY_EXISTS = FALSE
    );

    -- ============================================================
    -- EXISTING: Publish RISK proposals as READINESS_GAPS (unchanged)
    -- ============================================================
    MERGE INTO READINESS_GAPS target
    USING (
        SELECT
            'PUB_' || p.PROPOSAL_ID AS GAP_ID,
            p.ASSESSMENT_RUN_ID AS RUN_ID,
            q.DOMAIN_ID,
            p.QUESTION_ID,
            '[RISK] ' || p.TITLE AS GAP_TITLE,
            p.DESCRIPTION AS GAP_DESCRIPTION,
            p.SEVERITY,
            p.PRIORITY AS PRIORITY_SCORE,
            p.PROPOSAL_ID AS SOURCE_PROPOSAL_ID,
            p.AGENT_RUN_ID AS SOURCE_AGENT_RUN_ID
        FROM TMP_APPROVED_AGENT_PROPOSALS p
        LEFT JOIN READINESS_QUESTIONS q ON p.QUESTION_ID = q.QUESTION_ID
        WHERE p.PROPOSAL_TYPE = 'RISK'
    ) source
    ON target.SOURCE_PROPOSAL_ID = source.SOURCE_PROPOSAL_ID
    WHEN NOT MATCHED THEN INSERT (
        GAP_ID, RUN_ID, DOMAIN_ID, QUESTION_ID,
        GAP_TITLE, GAP_DESCRIPTION, SEVERITY, PRIORITY_SCORE,
        SOURCE_PROPOSAL_ID, SOURCE_AGENT_RUN_ID
    ) VALUES (
        source.GAP_ID, source.RUN_ID, source.DOMAIN_ID, source.QUESTION_ID,
        source.GAP_TITLE, source.GAP_DESCRIPTION, source.SEVERITY, source.PRIORITY_SCORE,
        source.SOURCE_PROPOSAL_ID, source.SOURCE_AGENT_RUN_ID
    );

    v_pub_risks := (
        SELECT COUNT(*) FROM TMP_APPROVED_AGENT_PROPOSALS
        WHERE PROPOSAL_TYPE = 'RISK' AND CANONICAL_ALREADY_EXISTS = FALSE
    );

    -- ============================================================
    -- EXISTING: Publish ACTION proposals (unchanged)
    -- ============================================================
    MERGE INTO RECOMMENDED_ACTIONS target
    USING (
        SELECT
            'PUB_' || p.PROPOSAL_ID AS ACTION_ID,
            p.ASSESSMENT_RUN_ID AS RUN_ID,
            NULL AS GAP_ID,
            p.TITLE AS ACTION_TITLE,
            p.DESCRIPTION AS ACTION_DESCRIPTION,
            p.RECOMMENDED_OWNER AS OWNER_NAME,
            p.RECOMMENDED_DUE_DATE AS DUE_IN_DAYS,
            'PUBLISHED' AS ACTION_STATUS,
            p.PROPOSAL_ID AS SOURCE_PROPOSAL_ID,
            p.AGENT_RUN_ID AS SOURCE_AGENT_RUN_ID
        FROM TMP_APPROVED_AGENT_PROPOSALS p
        WHERE p.PROPOSAL_TYPE = 'ACTION'
    ) source
    ON target.SOURCE_PROPOSAL_ID = source.SOURCE_PROPOSAL_ID
    WHEN NOT MATCHED THEN INSERT (
        ACTION_ID, RUN_ID, GAP_ID, ACTION_TITLE, ACTION_DESCRIPTION,
        OWNER_NAME, DUE_IN_DAYS, ACTION_STATUS,
        SOURCE_PROPOSAL_ID, SOURCE_AGENT_RUN_ID
    ) VALUES (
        source.ACTION_ID, source.RUN_ID, source.GAP_ID, source.ACTION_TITLE,
        source.ACTION_DESCRIPTION, source.OWNER_NAME, source.DUE_IN_DAYS,
        source.ACTION_STATUS, source.SOURCE_PROPOSAL_ID, source.SOURCE_AGENT_RUN_ID
    );

    v_pub_actions := (
        SELECT COUNT(*) FROM TMP_APPROVED_AGENT_PROPOSALS
        WHERE PROPOSAL_TYPE = 'ACTION' AND CANONICAL_ALREADY_EXISTS = FALSE
    );

    -- ============================================================
    -- NEW: Publish DECISION_* proposals to GOVERNED_DECISION_RECORD
    -- ============================================================
    MERGE INTO GOVERNED_DECISION_RECORD target
    USING (
        SELECT
            'DR_' || p.PROPOSAL_ID AS DECISION_RECORD_ID,
            p.PROPOSAL_ID AS SOURCE_PROPOSAL_ID,
            p.AGENT_RUN_ID AS SOURCE_AGENT_RUN_ID,
            p.ASSESSMENT_RUN_ID,
            r.INITIATIVE_ID,
            p.PROPOSAL_TYPE AS DECISION_TYPE,
            p.TITLE,
            p.DESCRIPTION,
            COALESCE(p.PROPOSAL_PAYLOAD, OBJECT_CONSTRUCT('title', p.TITLE, 'description', p.DESCRIPTION)) AS DECISION_PAYLOAD
        FROM TMP_APPROVED_AGENT_PROPOSALS p
        LEFT JOIN ASSESSMENT_RUNS r ON p.ASSESSMENT_RUN_ID = r.RUN_ID
        WHERE p.PROPOSAL_TYPE LIKE 'DECISION_%'
    ) source
    ON target.SOURCE_PROPOSAL_ID = source.SOURCE_PROPOSAL_ID
    WHEN NOT MATCHED THEN INSERT (
        DECISION_RECORD_ID, SOURCE_PROPOSAL_ID, SOURCE_AGENT_RUN_ID,
        ASSESSMENT_RUN_ID, INITIATIVE_ID, DECISION_TYPE,
        TITLE, DESCRIPTION, DECISION_PAYLOAD
    ) VALUES (
        source.DECISION_RECORD_ID, source.SOURCE_PROPOSAL_ID, source.SOURCE_AGENT_RUN_ID,
        source.ASSESSMENT_RUN_ID, source.INITIATIVE_ID, source.DECISION_TYPE,
        source.TITLE, source.DESCRIPTION, source.DECISION_PAYLOAD
    );

    v_pub_decisions := (
        SELECT COUNT(*) FROM TMP_APPROVED_AGENT_PROPOSALS
        WHERE PROPOSAL_TYPE LIKE 'DECISION_%' AND CANONICAL_ALREADY_EXISTS = FALSE
    );

    -- Mark proposals as published
    UPDATE GOVERNANCE_AGENT_PROPOSAL p
    SET STATUS = 'PUBLISHED',
        PUBLISHED_ENTITY_ID = CASE
            WHEN p.PROPOSAL_TYPE LIKE 'DECISION_%' THEN 'DR_' || p.PROPOSAL_ID
            ELSE 'PUB_' || p.PROPOSAL_ID
        END,
        UPDATED_AT = CURRENT_TIMESTAMP()
    WHERE p.PROPOSAL_ID IN (SELECT PROPOSAL_ID FROM TMP_APPROVED_AGENT_PROPOSALS)
      AND p.STATUS = 'APPROVED';

    -- Write publish audit history
    INSERT INTO GOVERNANCE_APPROVAL_HISTORY (
        APPROVAL_HISTORY_ID, PROPOSAL_ID, ACTION_TYPE,
        PREVIOUS_STATUS, NEW_STATUS, COMMENT, ACTED_BY
    )
    SELECT
        'AH_PUB_' || t.PROPOSAL_ID,
        t.PROPOSAL_ID,
        'PUBLISH',
        'APPROVED',
        'PUBLISHED',
        'Published as governed record',
        CURRENT_USER()
    FROM TMP_APPROVED_AGENT_PROPOSALS t
    WHERE NOT EXISTS (
        SELECT 1 FROM GOVERNANCE_APPROVAL_HISTORY h
        WHERE h.PROPOSAL_ID = t.PROPOSAL_ID AND h.ACTION_TYPE = 'PUBLISH'
    );

    COMMIT;

    RETURN '{"status":"OK","published_gaps":' || :v_pub_gaps ||
        ',"published_risks":' || :v_pub_risks ||
        ',"published_actions":' || :v_pub_actions ||
        ',"published_decisions":' || :v_pub_decisions || '}';

EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RETURN '{"status":"FAILED","error":"' || LEFT(SQLERRM, 200) || '"}';
END;
$$;

-- ============================================================
-- H. V_AI_PORTFOLIO: portfolio visibility view
-- ============================================================
CREATE OR REPLACE VIEW V_AI_PORTFOLIO AS
SELECT
    i.INITIATIVE_ID,
    i.INITIATIVE_NAME,
    i.DESCRIPTION AS INITIATIVE_DESCRIPTION,
    i.OWNER_NAME,
    i.LIFECYCLE_STAGE,
    i.BUSINESS_OUTCOME,
    i.STATUS AS INITIATIVE_STATUS,
    gov.TITLE AS GOVERNANCE_TITLE,
    gov.DECISION_PAYLOAD:readiness_level::VARCHAR AS GOVERNANCE_READINESS,
    val.TITLE AS VALUE_TITLE,
    val.DECISION_PAYLOAD:realization_confidence::VARCHAR AS VALUE_CONFIDENCE,
    route.TITLE AS ROUTING_TITLE,
    route.DECISION_PAYLOAD:recommended_approach::VARCHAR AS ROUTING_APPROACH,
    port.TITLE AS PORTFOLIO_TITLE,
    port.DECISION_PAYLOAD:recommendation::VARCHAR AS PORTFOLIO_RECOMMENDATION,
    port.DECISION_PAYLOAD:priority_score::NUMBER AS PORTFOLIO_PRIORITY,
    port.PUBLISHED_AT AS LAST_DECISION_AT
FROM AI_INITIATIVE i
LEFT JOIN (
    SELECT * FROM GOVERNED_DECISION_RECORD
    WHERE DECISION_TYPE = 'DECISION_GOVERNANCE'
    QUALIFY ROW_NUMBER() OVER (PARTITION BY INITIATIVE_ID ORDER BY PUBLISHED_AT DESC) = 1
) gov ON i.INITIATIVE_ID = gov.INITIATIVE_ID
LEFT JOIN (
    SELECT * FROM GOVERNED_DECISION_RECORD
    WHERE DECISION_TYPE = 'DECISION_VALUE'
    QUALIFY ROW_NUMBER() OVER (PARTITION BY INITIATIVE_ID ORDER BY PUBLISHED_AT DESC) = 1
) val ON i.INITIATIVE_ID = val.INITIATIVE_ID
LEFT JOIN (
    SELECT * FROM GOVERNED_DECISION_RECORD
    WHERE DECISION_TYPE = 'DECISION_MODEL_ROUTING'
    QUALIFY ROW_NUMBER() OVER (PARTITION BY INITIATIVE_ID ORDER BY PUBLISHED_AT DESC) = 1
) route ON i.INITIATIVE_ID = route.INITIATIVE_ID
LEFT JOIN (
    SELECT * FROM GOVERNED_DECISION_RECORD
    WHERE DECISION_TYPE = 'DECISION_PORTFOLIO'
    QUALIFY ROW_NUMBER() OVER (PARTITION BY INITIATIVE_ID ORDER BY PUBLISHED_AT DESC) = 1
) port ON i.INITIATIVE_ID = port.INITIATIVE_ID
WHERE i.STATUS = 'ACTIVE';
