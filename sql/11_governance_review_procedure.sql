CREATE OR REPLACE PROCEDURE READINESSOPS_VALIDATION.APP.SP_RUN_FULL_GOVERNANCE_REVIEW(P_ASSESSMENT_RUN_ID VARCHAR, P_ADDITIONAL_INSTRUCTION VARCHAR DEFAULT NULL)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
BEGIN
    LET v_agent_run_id VARCHAR := 'GR_' || TO_VARCHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD_HH24MISS_FF3');
    LET v_standard_instruction VARCHAR := 'Review the selected Assessment Run. Evaluate the sufficiency of available evidence, identify readiness gaps, assess the related governance and operational risks, and propose prioritized actions. Every proposal must be supported by the supplied Question, Answer, Evidence, and Rule context. Do not invent evidence.';
    LET v_prompt VARCHAR;
    LET v_llm_response VARCHAR;
    LET v_parsed VARIANT;
    LET v_num_gaps INTEGER := 0;
    LET v_num_risks INTEGER := 0;
    LET v_num_actions INTEGER := 0;
    LET v_input_fingerprint VARCHAR;
    LET v_run_exists INTEGER;

    v_run_exists := (SELECT COUNT(*) FROM ASSESSMENT_RUNS WHERE RUN_ID = :P_ASSESSMENT_RUN_ID);
    IF (:v_run_exists = 0) THEN
        RETURN '{"status":"FAILED","error":"Assessment Run not found"}';
    END IF;

    INSERT INTO GOVERNANCE_AGENT_RUN (AGENT_RUN_ID, ASSESSMENT_RUN_ID, WORKFLOW_TYPE, STANDARD_INSTRUCTION, ADDITIONAL_INSTRUCTION, STATUS, MODEL_NAME)
    VALUES (:v_agent_run_id, :P_ASSESSMENT_RUN_ID, 'FULL_GOVERNANCE_REVIEW', :v_standard_instruction, :P_ADDITIONAL_INSTRUCTION, 'RUNNING', 'mistral-large2');

    v_input_fingerprint := (
        SELECT MD5(LISTAGG(a.ANSWER_STATUS || COALESCE(a.ANSWER_TEXT,'') || COALESCE(e.EVIDENCE_STATUS,''), ';;') WITHIN GROUP (ORDER BY q.SORT_ORDER))
        FROM ASSESSMENT_ANSWERS a
        JOIN READINESS_QUESTIONS q ON a.QUESTION_ID = q.QUESTION_ID
        LEFT JOIN EVIDENCE_ITEMS e ON a.RUN_ID = e.RUN_ID AND a.QUESTION_ID = e.QUESTION_ID
        WHERE a.RUN_ID = :P_ASSESSMENT_RUN_ID
    );

    UPDATE GOVERNANCE_AGENT_RUN SET INPUT_FINGERPRINT = :v_input_fingerprint WHERE AGENT_RUN_ID = :v_agent_run_id;

    v_prompt := (
        SELECT
            :v_standard_instruction || '\n\n' ||
            CASE WHEN :P_ADDITIONAL_INSTRUCTION IS NOT NULL THEN 'ADDITIONAL INSTRUCTION: ' || :P_ADDITIONAL_INSTRUCTION || '\n\n' ELSE '' END ||
            'INPUT DATA:\n' ||
            LISTAGG(
                '---\nQuestion ID: ' || q.QUESTION_ID ||
                '\nDomain: ' || d.DOMAIN_NAME ||
                '\nQuestion: ' || q.QUESTION_TEXT ||
                '\nRule: ' || q.EXPECTED_EVIDENCE ||
                '\nAnswer Status: ' || a.ANSWER_STATUS ||
                '\nAnswer: ' || COALESCE(a.ANSWER_TEXT, 'N/A') ||
                '\nEvidence ID: ' || COALESCE(e.EVIDENCE_ID, 'None') ||
                '\nEvidence: ' || COALESCE(e.EVIDENCE_TEXT, 'None') ||
                '\nEvidence Status: ' || COALESCE(e.EVIDENCE_STATUS, 'MISSING'),
                '\n'
            ) WITHIN GROUP (ORDER BY q.SORT_ORDER) ||
            '\n\nOUTPUT: Return a JSON object with three arrays: gaps, risks, actions.' ||
            '\nEach gap and risk: {"question_id":"...","severity":"HIGH|MEDIUM|LOW","priority":60|70|80|90|95,"title":"...","description":"...","rationale":"..."}' ||
            '\nEach action: {"question_id":"...","severity":"HIGH|MEDIUM|LOW","priority":60|70|80|90|95,"title":"...","description":"...","rationale":"...","recommended_owner":"...","due_in_days":14|30|60|90}' ||
            '\nrecommended_owner: Risk Manager, Data Governance Lead, Program Lead, PMO Lead, or Security Lead' ||
            '\nRespond ONLY with valid JSON. No markdown fences.' ||
            '\n{"gaps":[...],"risks":[...],"actions":[...]}'
        FROM ASSESSMENT_ANSWERS a
        JOIN READINESS_QUESTIONS q ON a.QUESTION_ID = q.QUESTION_ID
        JOIN READINESS_DOMAINS d ON q.DOMAIN_ID = d.DOMAIN_ID
        LEFT JOIN EVIDENCE_ITEMS e ON a.RUN_ID = e.RUN_ID AND a.QUESTION_ID = e.QUESTION_ID
        WHERE a.RUN_ID = :P_ASSESSMENT_RUN_ID
    );

    v_llm_response := (SELECT SNOWFLAKE.CORTEX.COMPLETE('mistral-large2', :v_prompt));

    v_llm_response := REGEXP_REPLACE(:v_llm_response, '^\\s*```(json|JSON)?\\s*', '');
    v_llm_response := REGEXP_REPLACE(:v_llm_response, '\\s*```\\s*$', '');
    v_llm_response := TRIM(:v_llm_response);

    v_parsed := (SELECT TRY_PARSE_JSON(:v_llm_response));

    IF (:v_parsed IS NULL) THEN
        UPDATE GOVERNANCE_AGENT_RUN SET STATUS = 'FAILED', COMPLETED_AT = CURRENT_TIMESTAMP(),
            ERROR_MESSAGE = LEFT(COALESCE(:v_llm_response, 'NULL'), 500)
        WHERE AGENT_RUN_ID = :v_agent_run_id;
        RETURN '{"agent_run_id":"' || :v_agent_run_id || '","status":"FAILED","error":"Invalid JSON"}';
    END IF;

    -- Insert GAP proposals
    INSERT INTO GOVERNANCE_AGENT_PROPOSAL (PROPOSAL_ID, AGENT_RUN_ID, ASSESSMENT_RUN_ID, PROPOSAL_TYPE, QUESTION_ID, TITLE, DESCRIPTION, SEVERITY, PRIORITY, RATIONALE, STATUS)
    SELECT
        :v_agent_run_id || '_GAP_' || ROW_NUMBER() OVER (ORDER BY f.INDEX),
        :v_agent_run_id, :P_ASSESSMENT_RUN_ID, 'GAP',
        f.VALUE:question_id::VARCHAR,
        f.VALUE:title::VARCHAR, f.VALUE:description::VARCHAR, f.VALUE:severity::VARCHAR,
        CASE
            WHEN TRY_CAST(f.VALUE:priority::VARCHAR AS INTEGER) BETWEEN 1 AND 5 THEN
                CASE TRY_CAST(f.VALUE:priority::VARCHAR AS INTEGER)
                    WHEN 5 THEN 95
                    WHEN 4 THEN 90
                    WHEN 3 THEN 80
                    WHEN 2 THEN 70
                    ELSE 60
                END
            ELSE LEAST(
                100,
                GREATEST(
                    1,
                    COALESCE(
                        TRY_CAST(f.VALUE:priority::VARCHAR AS INTEGER),
                        50
                    )
                )
            )
        END,
        f.VALUE:rationale::VARCHAR, 'REVIEW_REQUIRED'
    FROM TABLE(FLATTEN(:v_parsed:gaps)) f;

    v_num_gaps := (SELECT COUNT(*) FROM GOVERNANCE_AGENT_PROPOSAL WHERE AGENT_RUN_ID = :v_agent_run_id AND PROPOSAL_TYPE = 'GAP');

    -- Insert RISK proposals
    INSERT INTO GOVERNANCE_AGENT_PROPOSAL (PROPOSAL_ID, AGENT_RUN_ID, ASSESSMENT_RUN_ID, PROPOSAL_TYPE, QUESTION_ID, TITLE, DESCRIPTION, SEVERITY, PRIORITY, RATIONALE, STATUS)
    SELECT
        :v_agent_run_id || '_RISK_' || ROW_NUMBER() OVER (ORDER BY f.INDEX),
        :v_agent_run_id, :P_ASSESSMENT_RUN_ID, 'RISK',
        f.VALUE:question_id::VARCHAR,
        f.VALUE:title::VARCHAR, f.VALUE:description::VARCHAR, f.VALUE:severity::VARCHAR,
        CASE
            WHEN TRY_CAST(f.VALUE:priority::VARCHAR AS INTEGER) BETWEEN 1 AND 5 THEN
                CASE TRY_CAST(f.VALUE:priority::VARCHAR AS INTEGER)
                    WHEN 5 THEN 95
                    WHEN 4 THEN 90
                    WHEN 3 THEN 80
                    WHEN 2 THEN 70
                    ELSE 60
                END
            ELSE LEAST(
                100,
                GREATEST(
                    1,
                    COALESCE(
                        TRY_CAST(f.VALUE:priority::VARCHAR AS INTEGER),
                        50
                    )
                )
            )
        END,
        f.VALUE:rationale::VARCHAR, 'REVIEW_REQUIRED'
    FROM TABLE(FLATTEN(:v_parsed:risks)) f;

    v_num_risks := (SELECT COUNT(*) FROM GOVERNANCE_AGENT_PROPOSAL WHERE AGENT_RUN_ID = :v_agent_run_id AND PROPOSAL_TYPE = 'RISK');

    -- Insert ACTION proposals
    INSERT INTO GOVERNANCE_AGENT_PROPOSAL (PROPOSAL_ID, AGENT_RUN_ID, ASSESSMENT_RUN_ID, PROPOSAL_TYPE, QUESTION_ID, TITLE, DESCRIPTION, SEVERITY, PRIORITY, RATIONALE, RECOMMENDED_OWNER, RECOMMENDED_DUE_DATE, STATUS)
    SELECT
        :v_agent_run_id || '_ACT_' || ROW_NUMBER() OVER (ORDER BY f.INDEX),
        :v_agent_run_id, :P_ASSESSMENT_RUN_ID, 'ACTION',
        f.VALUE:question_id::VARCHAR,
        f.VALUE:title::VARCHAR, f.VALUE:description::VARCHAR, f.VALUE:severity::VARCHAR,
        CASE
            WHEN TRY_CAST(f.VALUE:priority::VARCHAR AS INTEGER) BETWEEN 1 AND 5 THEN
                CASE TRY_CAST(f.VALUE:priority::VARCHAR AS INTEGER)
                    WHEN 5 THEN 95
                    WHEN 4 THEN 90
                    WHEN 3 THEN 80
                    WHEN 2 THEN 70
                    ELSE 60
                END
            ELSE LEAST(
                100,
                GREATEST(
                    1,
                    COALESCE(
                        TRY_CAST(f.VALUE:priority::VARCHAR AS INTEGER),
                        50
                    )
                )
            )
        END,
        f.VALUE:rationale::VARCHAR, f.VALUE:recommended_owner::VARCHAR,
        COALESCE(TRY_CAST(f.VALUE:due_in_days::VARCHAR AS INTEGER), 30),
        'REVIEW_REQUIRED'
    FROM TABLE(FLATTEN(:v_parsed:actions)) f;

    v_num_actions := (SELECT COUNT(*) FROM GOVERNANCE_AGENT_PROPOSAL WHERE AGENT_RUN_ID = :v_agent_run_id AND PROPOSAL_TYPE = 'ACTION');

    -- Insert source traceability (1 source per proposal, joined on proposal's question_id)
    INSERT INTO GOVERNANCE_AGENT_PROPOSAL_SOURCE (PROPOSAL_SOURCE_ID, PROPOSAL_ID, SOURCE_TYPE, QUESTION_ID, ANSWER_TEXT, EVIDENCE_ITEM_ID, RULE_ID, RULE_VERSION, SOURCE_SUMMARY)
    SELECT
        p.PROPOSAL_ID || '_SRC',
        p.PROPOSAL_ID, 'QUESTION_ANSWER_EVIDENCE', p.QUESTION_ID, a.ANSWER_TEXT, e.EVIDENCE_ID,
        p.QUESTION_ID, '1.0',
        LEFT(q.QUESTION_TEXT, 80) || ' | ' || a.ANSWER_STATUS || ' | ' || COALESCE(e.EVIDENCE_STATUS, 'MISSING')
    FROM GOVERNANCE_AGENT_PROPOSAL p
    JOIN READINESS_QUESTIONS q ON p.QUESTION_ID = q.QUESTION_ID
    JOIN ASSESSMENT_ANSWERS a ON a.RUN_ID = :P_ASSESSMENT_RUN_ID AND a.QUESTION_ID = p.QUESTION_ID
    LEFT JOIN EVIDENCE_ITEMS e ON e.RUN_ID = :P_ASSESSMENT_RUN_ID AND e.QUESTION_ID = p.QUESTION_ID
    WHERE p.AGENT_RUN_ID = :v_agent_run_id AND p.QUESTION_ID IS NOT NULL;

    -- Mark completed
    UPDATE GOVERNANCE_AGENT_RUN
    SET STATUS = 'COMPLETED', COMPLETED_AT = CURRENT_TIMESTAMP(),
        SUMMARY = :v_num_gaps || ' gaps, ' || :v_num_risks || ' risks, ' || :v_num_actions || ' actions'
    WHERE AGENT_RUN_ID = :v_agent_run_id;

    RETURN '{"agent_run_id":"' || :v_agent_run_id || '","status":"COMPLETED","gaps":' || :v_num_gaps || ',"risks":' || :v_num_risks || ',"actions":' || :v_num_actions || '}';

EXCEPTION
    WHEN OTHER THEN
        UPDATE GOVERNANCE_AGENT_RUN SET STATUS = 'FAILED', COMPLETED_AT = CURRENT_TIMESTAMP(), ERROR_MESSAGE = LEFT(SQLERRM, 500) WHERE AGENT_RUN_ID = :v_agent_run_id;
        RETURN '{"agent_run_id":"' || :v_agent_run_id || '","status":"FAILED","error":"' || LEFT(SQLERRM, 200) || '"}';
END;
$$;
