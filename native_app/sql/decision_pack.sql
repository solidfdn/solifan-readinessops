-- Native App adaptation of sql/20_foundation_slice_1.sql::SP_GENERATE_DECISION_PACK.
-- The four-section contract, validation, source traceability, idempotency, and
-- Human Gate are preserved. Only schema qualification and owner-rights
-- execution are changed for the Native App runtime.

CREATE OR REPLACE PROCEDURE APP_CODE.SP_GENERATE_DECISION_PACK(
    P_ASSESSMENT_RUN_ID VARCHAR,
    P_ADDITIONAL_INSTRUCTION VARCHAR DEFAULT NULL
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
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
    LET v_prompt_version VARCHAR := 'DECISION_PACK_V2';
    LET v_model_name VARCHAR := 'llama3.1-8b';
    LET v_assessment_block VARCHAR;
    LET v_assessment_fingerprint VARCHAR;
    LET v_evidence_fingerprint VARCHAR;
    LET v_gov_ids ARRAY;
    LET v_val_ids ARRAY;
    LET v_route_ids ARRAY;
    LET v_port_ids ARRAY;
    LET v_invalid_source_count INTEGER := 0;
    LET v_port_priority NUMBER;
    LET v_source_link_count INTEGER := 0;
    LET v_actor VARCHAR := CURRENT_USER();

    -- Fail closed when the consumer has not granted operator attribution.
    IF (:v_actor IS NULL) THEN
        RETURN '{"status":"FAILED","error":"READ SESSION is required for operator attribution"}';
    END IF;

    -- Validate assessment run
    v_run_exists := (SELECT COUNT(*) FROM APP_DATA.ASSESSMENT_RUNS WHERE RUN_ID = :P_ASSESSMENT_RUN_ID);
    IF (:v_run_exists = 0) THEN
        RETURN '{"status":"FAILED","error":"Assessment Run not found"}';
    END IF;

    -- Get initiative context
    v_initiative_id := (
        SELECT INITIATIVE_ID FROM APP_DATA.ASSESSMENT_RUNS WHERE RUN_ID = :P_ASSESSMENT_RUN_ID
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
            FROM APP_DATA.AI_INITIATIVE
            WHERE INITIATIVE_ID = :v_initiative_id
        );
        IF (:v_initiative_context IS NULL) THEN
            RETURN '{"status":"FAILED","error":"Linked AI Initiative not found"}';
        END IF;
    END IF;

    v_evidence_count := (
        SELECT COUNT(*) FROM APP_DATA.EVIDENCE_ITEMS WHERE RUN_ID = :P_ASSESSMENT_RUN_ID
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
        FROM APP_DATA.ASSESSMENT_ANSWERS a
        JOIN APP_DATA.READINESS_QUESTIONS q ON a.QUESTION_ID = q.QUESTION_ID
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
        FROM APP_DATA.EVIDENCE_ITEMS
        WHERE RUN_ID = :P_ASSESSMENT_RUN_ID
    );

    v_input_fingerprint := SHA2(
        COALESCE(:v_initiative_context, 'NO_INITIATIVE') || '||' ||
        COALESCE(:v_assessment_fingerprint, 'NO_ASSESSMENT_ANSWERS') || '||' ||
        COALESCE(:v_evidence_fingerprint, 'NO_EVIDENCE') || '||' ||
        COALESCE(:P_ADDITIONAL_INSTRUCTION, '') || '||' ||
        :v_prompt_version || '||' ||
        :v_model_name,
        256
    );

    -- Idempotency: check for existing successful run with same fingerprint
    v_existing_run := (
        SELECT COUNT(*)
        FROM APP_DATA.GOVERNANCE_AGENT_RUN
        WHERE ASSESSMENT_RUN_ID = :P_ASSESSMENT_RUN_ID
          AND WORKFLOW_TYPE = 'DECISION_PACK'
          AND INPUT_FINGERPRINT = :v_input_fingerprint
          AND STATUS = 'COMPLETED'
    );
    IF (:v_existing_run > 0) THEN
        RETURN '{"status":"SKIPPED","reason":"Identical input fingerprint already has a completed Decision Pack run","fingerprint":"' || :v_input_fingerprint || '"}';
    END IF;

    -- Register agent run
    INSERT INTO APP_DATA.GOVERNANCE_AGENT_RUN (
        AGENT_RUN_ID, ASSESSMENT_RUN_ID, WORKFLOW_TYPE,
        STANDARD_INSTRUCTION, ADDITIONAL_INSTRUCTION,
        STATUS, MODEL_NAME, PROMPT_VERSION, INPUT_FINGERPRINT, CREATED_BY
    ) VALUES (
        :v_agent_run_id, :P_ASSESSMENT_RUN_ID, 'DECISION_PACK',
        'Generate a structured Decision Pack covering Governance, Value Realization, Model Routing, and Portfolio recommendations.',
        :P_ADDITIONAL_INSTRUCTION,
        'RUNNING', :v_model_name, :v_prompt_version, :v_input_fingerprint,
        :v_actor
    );

    -- Step 1 records the validated, fingerprinted input boundary.
    INSERT INTO APP_DATA.GOVERNANCE_AGENT_RUN_STEP (
        AGENT_RUN_STEP_ID, AGENT_RUN_ID, STEP_SEQUENCE, STEP_CODE,
        STEP_NAME, STATUS, STARTED_AT, COMPLETED_AT, DURATION_MS, STEP_DETAIL
    )
    SELECT
        :v_agent_run_id || '_STEP_01', :v_agent_run_id, 1,
        'INPUT_VALIDATION', 'Validate governed inputs', 'COMPLETED',
        CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP(), 0,
        OBJECT_CONSTRUCT(
            'assessment_run_id', :P_ASSESSMENT_RUN_ID,
            'initiative_id', :v_initiative_id,
            'evidence_count', :v_evidence_count,
            'input_fingerprint', :v_input_fingerprint
        );

    -- Step 2 covers deterministic context and prompt assembly.
    INSERT INTO APP_DATA.GOVERNANCE_AGENT_RUN_STEP (
        AGENT_RUN_STEP_ID, AGENT_RUN_ID, STEP_SEQUENCE, STEP_CODE,
        STEP_NAME, STATUS, STARTED_AT
    )
    SELECT
        :v_agent_run_id || '_STEP_02', :v_agent_run_id, 2,
        'CONTEXT_ASSEMBLY', 'Assemble assessment and evidence context',
        'RUNNING', CURRENT_TIMESTAMP();

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
        FROM APP_DATA.EVIDENCE_ITEMS
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
        FROM APP_DATA.ASSESSMENT_ANSWERS a
        JOIN APP_DATA.READINESS_QUESTIONS q ON a.QUESTION_ID = q.QUESTION_ID
        JOIN APP_DATA.READINESS_DOMAINS d ON q.DOMAIN_ID = d.DOMAIN_ID
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
        '    "expected_value": "...",\n' ||
        '    "realization_confidence": "HIGH|MEDIUM|LOW",\n' ||
        '    "blockers": ["..."],\n' ||
        '    "enablers": ["..."],\n' ||
        '    "source_evidence_ids": ["EV_001"]\n' ||
        '  },\n' ||
        '  "model_routing": {\n' ||
        '    "title": "...",\n' ||
        '    "description": "Model selection and routing recommendation",\n' ||
        '    "recommended_approach": "...",\n' ||
        '    "complexity_level": "HIGH|MEDIUM|LOW",\n' ||
        '    "data_readiness": "HIGH|MEDIUM|LOW",\n' ||
        '    "considerations": ["..."],\n' ||
        '    "source_evidence_ids": ["EV_001"]\n' ||
        '  },\n' ||
        '  "portfolio_recommendation": {\n' ||
        '    "title": "...",\n' ||
        '    "description": "Portfolio-level recommendation",\n' ||
        '    "recommendation": "PROCEED|HOLD|REDESIGN|RETIRE",\n' ||
        '    "priority_score": 85,\n' ||
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

    UPDATE APP_DATA.GOVERNANCE_AGENT_RUN_STEP
    SET STATUS = 'COMPLETED', COMPLETED_AT = CURRENT_TIMESTAMP(),
        DURATION_MS = DATEDIFF('millisecond', STARTED_AT, CURRENT_TIMESTAMP()),
        STEP_DETAIL = OBJECT_CONSTRUCT(
            'assessment_context_chars', LENGTH(COALESCE(:v_assessment_block, '')),
            'evidence_context_chars', LENGTH(COALESCE(:v_evidence_block, '')),
            'prompt_chars', LENGTH(COALESCE(:v_prompt, ''))
        )
    WHERE AGENT_RUN_STEP_ID = :v_agent_run_id || '_STEP_02';

    -- Step 3 is the only model inference call. Run-step observability does not
    -- increase the number of Cortex calls or inference cost.
    INSERT INTO APP_DATA.GOVERNANCE_AGENT_RUN_STEP (
        AGENT_RUN_STEP_ID, AGENT_RUN_ID, STEP_SEQUENCE, STEP_CODE,
        STEP_NAME, STATUS, STARTED_AT, STEP_DETAIL
    )
    SELECT
        :v_agent_run_id || '_STEP_03', :v_agent_run_id, 3,
        'CORTEX_GENERATION', 'Generate four-section Decision Pack',
        'RUNNING', CURRENT_TIMESTAMP(),
        OBJECT_CONSTRUCT('model', :v_model_name, 'prompt_version', :v_prompt_version);

    -- Call LLM
    -- Strict JSON v2: schema-constrained Decision Pack output
    v_llm_response := (
        SELECT TO_JSON(
            SNOWFLAKE.CORTEX.AI_COMPLETE(
                model => :v_model_name,
                prompt => :v_prompt,
                model_parameters => {
                    'temperature': 0,
                    'max_tokens': 4096
                },
                response_format => {
                    'type': 'json',
                    'schema': {
                        'type': 'object',
                        'properties': {
                            'governance_summary': {
                                'type': 'object',
                                'properties': {
                                    'title': {'type': 'string'},
                                    'description': {'type': 'string'},
                                    'readiness_level': {
                                        'type': 'string',
                                        'enum': ['RED', 'AMBER', 'GREEN']
                                    },
                                    'key_findings': {
                                        'type': 'array',
                                        'items': {'type': 'string'}
                                    },
                                    'recommendations': {
                                        'type': 'array',
                                        'items': {'type': 'string'}
                                    },
                                    'source_evidence_ids': {
                                        'type': 'array',
                                        'items': {'type': 'string'}
                                    }
                                },
                                'required': [
                                    'title',
                                    'description',
                                    'readiness_level',
                                    'key_findings',
                                    'recommendations',
                                    'source_evidence_ids'
                                ],
                                'additionalProperties': false
                            },
                            'value_realization': {
                                'type': 'object',
                                'properties': {
                                    'title': {'type': 'string'},
                                    'description': {'type': 'string'},
                                    'expected_value': {'type': 'string'},
                                    'realization_confidence': {
                                        'type': 'string',
                                        'enum': ['HIGH', 'MEDIUM', 'LOW']
                                    },
                                    'blockers': {
                                        'type': 'array',
                                        'items': {'type': 'string'}
                                    },
                                    'enablers': {
                                        'type': 'array',
                                        'items': {'type': 'string'}
                                    },
                                    'source_evidence_ids': {
                                        'type': 'array',
                                        'items': {'type': 'string'}
                                    }
                                },
                                'required': [
                                    'title',
                                    'description',
                                    'expected_value',
                                    'realization_confidence',
                                    'blockers',
                                    'enablers',
                                    'source_evidence_ids'
                                ],
                                'additionalProperties': false
                            },
                            'model_routing': {
                                'type': 'object',
                                'properties': {
                                    'title': {'type': 'string'},
                                    'description': {'type': 'string'},
                                    'recommended_approach': {'type': 'string'},
                                    'complexity_level': {
                                        'type': 'string',
                                        'enum': ['HIGH', 'MEDIUM', 'LOW']
                                    },
                                    'data_readiness': {
                                        'type': 'string',
                                        'enum': ['HIGH', 'MEDIUM', 'LOW']
                                    },
                                    'considerations': {
                                        'type': 'array',
                                        'items': {'type': 'string'}
                                    },
                                    'source_evidence_ids': {
                                        'type': 'array',
                                        'items': {'type': 'string'}
                                    }
                                },
                                'required': [
                                    'title',
                                    'description',
                                    'recommended_approach',
                                    'complexity_level',
                                    'data_readiness',
                                    'considerations',
                                    'source_evidence_ids'
                                ],
                                'additionalProperties': false
                            },
                            'portfolio_recommendation': {
                                'type': 'object',
                                'properties': {
                                    'title': {'type': 'string'},
                                    'description': {'type': 'string'},
                                    'recommendation': {
                                        'type': 'string',
                                        'enum': ['PROCEED', 'HOLD', 'REDESIGN', 'RETIRE']
                                    },
                                    'priority_score': {'type': 'integer'},
                                    'rationale': {'type': 'string'},
                                    'next_review': {'type': 'string'},
                                    'next_steps': {
                                        'type': 'array',
                                        'items': {'type': 'string'}
                                    },
                                    'source_evidence_ids': {
                                        'type': 'array',
                                        'items': {'type': 'string'}
                                    }
                                },
                                'required': [
                                    'title',
                                    'description',
                                    'recommendation',
                                    'priority_score',
                                    'rationale',
                                    'next_review',
                                    'next_steps',
                                    'source_evidence_ids'
                                ],
                                'additionalProperties': false
                            }
                        },
                        'required': [
                            'governance_summary',
                            'value_realization',
                            'model_routing',
                            'portfolio_recommendation'
                        ],
                        'additionalProperties': false
                    }
                }
            )
        )
    );

    UPDATE APP_DATA.GOVERNANCE_AGENT_RUN_STEP
    SET STATUS = 'COMPLETED', COMPLETED_AT = CURRENT_TIMESTAMP(),
        DURATION_MS = DATEDIFF('millisecond', STARTED_AT, CURRENT_TIMESTAMP()),
        STEP_DETAIL = OBJECT_CONSTRUCT(
            'model', :v_model_name,
            'prompt_version', :v_prompt_version,
            'response_chars', LENGTH(COALESCE(:v_llm_response, ''))
        )
    WHERE AGENT_RUN_STEP_ID = :v_agent_run_id || '_STEP_03';

    -- Step 4 validates schema, enums, priority, and evidence citations.
    INSERT INTO APP_DATA.GOVERNANCE_AGENT_RUN_STEP (
        AGENT_RUN_STEP_ID, AGENT_RUN_ID, STEP_SEQUENCE, STEP_CODE,
        STEP_NAME, STATUS, STARTED_AT
    )
    SELECT
        :v_agent_run_id || '_STEP_04', :v_agent_run_id, 4,
        'OUTPUT_VALIDATION', 'Validate schema and evidence grounding',
        'RUNNING', CURRENT_TIMESTAMP();

    -- Clean markdown fences
    v_llm_response := REGEXP_REPLACE(:v_llm_response, '^\\s*```(json|JSON)?\\s*', '');
    v_llm_response := REGEXP_REPLACE(:v_llm_response, '\\s*```\\s*$', '');
    v_llm_response := TRIM(:v_llm_response);

    -- Parse JSON
    v_parsed := (SELECT TRY_PARSE_JSON(:v_llm_response));
    IF (:v_parsed IS NULL) THEN
        UPDATE APP_DATA.GOVERNANCE_AGENT_RUN_STEP
        SET STATUS = 'FAILED', COMPLETED_AT = CURRENT_TIMESTAMP(),
            DURATION_MS = DATEDIFF('millisecond', STARTED_AT, CURRENT_TIMESTAMP()),
            ERROR_MESSAGE = 'Invalid JSON from Cortex'
        WHERE AGENT_RUN_STEP_ID = :v_agent_run_id || '_STEP_04';
        UPDATE APP_DATA.GOVERNANCE_AGENT_RUN
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
        UPDATE APP_DATA.GOVERNANCE_AGENT_RUN_STEP
        SET STATUS = 'FAILED', COMPLETED_AT = CURRENT_TIMESTAMP(),
            DURATION_MS = DATEDIFF('millisecond', STARTED_AT, CURRENT_TIMESTAMP()),
            ERROR_MESSAGE = 'Incomplete four-section Decision Pack'
        WHERE AGENT_RUN_STEP_ID = :v_agent_run_id || '_STEP_04';
        UPDATE APP_DATA.GOVERNANCE_AGENT_RUN
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
        UPDATE APP_DATA.GOVERNANCE_AGENT_RUN_STEP
        SET STATUS = 'FAILED', COMPLETED_AT = CURRENT_TIMESTAMP(),
            DURATION_MS = DATEDIFF('millisecond', STARTED_AT, CURRENT_TIMESTAMP()),
            ERROR_MESSAGE = 'Required field or enum validation failed'
        WHERE AGENT_RUN_STEP_ID = :v_agent_run_id || '_STEP_04';
        UPDATE APP_DATA.GOVERNANCE_AGENT_RUN
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
        UPDATE APP_DATA.GOVERNANCE_AGENT_RUN_STEP
        SET STATUS = 'FAILED', COMPLETED_AT = CURRENT_TIMESTAMP(),
            DURATION_MS = DATEDIFF('millisecond', STARTED_AT, CURRENT_TIMESTAMP()),
            ERROR_MESSAGE = 'source_evidence_ids must be arrays'
        WHERE AGENT_RUN_STEP_ID = :v_agent_run_id || '_STEP_04';
        UPDATE APP_DATA.GOVERNANCE_AGENT_RUN
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
        UPDATE APP_DATA.GOVERNANCE_AGENT_RUN_STEP
        SET STATUS = 'FAILED', COMPLETED_AT = CURRENT_TIMESTAMP(),
            DURATION_MS = DATEDIFF('millisecond', STARTED_AT, CURRENT_TIMESTAMP()),
            ERROR_MESSAGE = 'Every section must cite evidence'
        WHERE AGENT_RUN_STEP_ID = :v_agent_run_id || '_STEP_04';
        UPDATE APP_DATA.GOVERNANCE_AGENT_RUN
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
        LEFT JOIN APP_DATA.EVIDENCE_ITEMS e
          ON e.RUN_ID = :P_ASSESSMENT_RUN_ID
         AND e.EVIDENCE_ID = cited.EVIDENCE_ID
        WHERE e.EVIDENCE_ID IS NULL
    );

    IF (:v_invalid_source_count > 0) THEN
        UPDATE APP_DATA.GOVERNANCE_AGENT_RUN_STEP
        SET STATUS = 'FAILED', COMPLETED_AT = CURRENT_TIMESTAMP(),
            DURATION_MS = DATEDIFF('millisecond', STARTED_AT, CURRENT_TIMESTAMP()),
            ERROR_MESSAGE = 'Evidence citation is outside the selected Assessment Run'
        WHERE AGENT_RUN_STEP_ID = :v_agent_run_id || '_STEP_04';
        UPDATE APP_DATA.GOVERNANCE_AGENT_RUN
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
        UPDATE APP_DATA.GOVERNANCE_AGENT_RUN_STEP
        SET STATUS = 'FAILED', COMPLETED_AT = CURRENT_TIMESTAMP(),
            DURATION_MS = DATEDIFF('millisecond', STARTED_AT, CURRENT_TIMESTAMP()),
            ERROR_MESSAGE = 'Portfolio priority must be an integer from 1 through 100'
        WHERE AGENT_RUN_STEP_ID = :v_agent_run_id || '_STEP_04';
        UPDATE APP_DATA.GOVERNANCE_AGENT_RUN
        SET STATUS = 'FAILED', COMPLETED_AT = CURRENT_TIMESTAMP(),
            ERROR_MESSAGE = 'portfolio_recommendation.priority_score must be an integer from 1 through 100'
        WHERE AGENT_RUN_ID = :v_agent_run_id;
        RETURN '{"status":"FAILED","agent_run_id":"' || :v_agent_run_id || '","error":"Invalid priority_score"}';
    END IF;

    UPDATE APP_DATA.GOVERNANCE_AGENT_RUN_STEP
    SET STATUS = 'COMPLETED', COMPLETED_AT = CURRENT_TIMESTAMP(),
        DURATION_MS = DATEDIFF('millisecond', STARTED_AT, CURRENT_TIMESTAMP()),
        STEP_DETAIL = OBJECT_CONSTRUCT(
            'section_count', 4,
            'evidence_citation_count',
                ARRAY_SIZE(:v_gov_ids) + ARRAY_SIZE(:v_val_ids) +
                ARRAY_SIZE(:v_route_ids) + ARRAY_SIZE(:v_port_ids),
            'invalid_evidence_citations', :v_invalid_source_count,
            'portfolio_priority', :v_port_priority
        )
    WHERE AGENT_RUN_STEP_ID = :v_agent_run_id || '_STEP_04';

    -- Step 5 atomically persists proposals, evidence links, and run status.
    INSERT INTO APP_DATA.GOVERNANCE_AGENT_RUN_STEP (
        AGENT_RUN_STEP_ID, AGENT_RUN_ID, STEP_SEQUENCE, STEP_CODE,
        STEP_NAME, STATUS, STARTED_AT
    )
    SELECT
        :v_agent_run_id || '_STEP_05', :v_agent_run_id, 5,
        'DRAFT_PERSISTENCE', 'Persist governed AI drafts and source links',
        'RUNNING', CURRENT_TIMESTAMP();

    -- Insert four proposals atomically
    BEGIN TRANSACTION;

    -- DECISION_GOVERNANCE
    INSERT INTO APP_DATA.GOVERNANCE_AGENT_PROPOSAL (
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
    INSERT INTO APP_DATA.GOVERNANCE_AGENT_PROPOSAL (
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
    INSERT INTO APP_DATA.GOVERNANCE_AGENT_PROPOSAL (
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
    INSERT INTO APP_DATA.GOVERNANCE_AGENT_PROPOSAL (
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

    -- Freeze the exact content that the human review and publication path sees.
    -- The payload is normalized with the editable fields so the table columns,
    -- review surface, approval snapshot, and governed record cannot diverge.
    UPDATE APP_DATA.GOVERNANCE_AGENT_PROPOSAL
    SET PROPOSAL_PAYLOAD = OBJECT_INSERT(
            OBJECT_INSERT(
                COALESCE(PROPOSAL_PAYLOAD, OBJECT_CONSTRUCT()),
                'title', TITLE, TRUE
            ),
            'description', DESCRIPTION, TRUE
        ),
        CONTENT_VERSION = 1,
        CONTENT_HASH = SHA2(
            COALESCE(TITLE, '') || '\n' ||
            COALESCE(DESCRIPTION, '') || '\n' ||
            COALESCE(TO_JSON(OBJECT_INSERT(
                OBJECT_INSERT(
                    COALESCE(PROPOSAL_PAYLOAD, OBJECT_CONSTRUCT()),
                    'title', TITLE, TRUE
                ),
                'description', DESCRIPTION, TRUE
            )), '{}'),
            256
        )
    WHERE AGENT_RUN_ID = :v_agent_run_id
      AND STATUS = 'REVIEW_REQUIRED';

    -- Source traceability: one immutable row per cited evidence item and section.
    INSERT INTO APP_DATA.GOVERNANCE_AGENT_PROPOSAL_SOURCE (
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
    JOIN APP_DATA.EVIDENCE_ITEMS e
      ON e.RUN_ID = :P_ASSESSMENT_RUN_ID
     AND e.EVIDENCE_ID = cited.EVIDENCE_ID;

    v_source_link_count := (
        SELECT COUNT(*)
        FROM APP_DATA.GOVERNANCE_AGENT_PROPOSAL_SOURCE s
        JOIN APP_DATA.GOVERNANCE_AGENT_PROPOSAL p
          ON p.PROPOSAL_ID = s.PROPOSAL_ID
        WHERE p.AGENT_RUN_ID = :v_agent_run_id
    );

    UPDATE APP_DATA.GOVERNANCE_AGENT_RUN_STEP
    SET STATUS = 'COMPLETED', COMPLETED_AT = CURRENT_TIMESTAMP(),
        DURATION_MS = DATEDIFF('millisecond', STARTED_AT, CURRENT_TIMESTAMP()),
        STEP_DETAIL = OBJECT_CONSTRUCT(
            'proposal_count', 4,
            'source_link_count', :v_source_link_count
        )
    WHERE AGENT_RUN_STEP_ID = :v_agent_run_id || '_STEP_05';

    -- Mark completed inside the same transaction as proposals and citations.
    UPDATE APP_DATA.GOVERNANCE_AGENT_RUN
    SET STATUS = 'COMPLETED', COMPLETED_AT = CURRENT_TIMESTAMP(),
        SUMMARY = 'Decision Pack: 4 sections generated'
    WHERE AGENT_RUN_ID = :v_agent_run_id;

    COMMIT;

    RETURN '{"status":"COMPLETED","agent_run_id":"' || :v_agent_run_id || '","sections":4,"run_steps":5}';

EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        UPDATE APP_DATA.GOVERNANCE_AGENT_RUN_STEP
        SET STATUS = 'FAILED', COMPLETED_AT = CURRENT_TIMESTAMP(),
            DURATION_MS = DATEDIFF('millisecond', STARTED_AT, CURRENT_TIMESTAMP()),
            ERROR_MESSAGE = LEFT(:SQLERRM, 500)
        WHERE AGENT_RUN_ID = :v_agent_run_id
          AND STATUS = 'RUNNING';
        UPDATE APP_DATA.GOVERNANCE_AGENT_RUN
        SET STATUS = 'FAILED', COMPLETED_AT = CURRENT_TIMESTAMP(),
            ERROR_MESSAGE = LEFT(:SQLERRM, 500)
        WHERE AGENT_RUN_ID = :v_agent_run_id;
        RETURN '{"status":"FAILED","agent_run_id":"' || :v_agent_run_id || '","error":"' || LEFT(SQLERRM, 200) || '"}';
END;
$$;


GRANT USAGE ON PROCEDURE APP_CODE.SP_GENERATE_DECISION_PACK(VARCHAR, VARCHAR)
    TO APPLICATION ROLE READINESSOPS_ADMIN;
