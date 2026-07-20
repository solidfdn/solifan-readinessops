-- ============================================================
-- READINESSOPS Stored Procedure: AI Readiness Gap Agent
-- ============================================================
-- Reads assessment answers and evidence, calls Snowflake Cortex AI
-- to detect gaps and recommend actions, then writes results back
-- to existing tables with full audit logging.
--
-- Verified fix: TRY_CAST requires VARIANT -> VARCHAR -> INTEGER
-- (direct VARIANT -> INTEGER fails with compilation error).
-- ============================================================

USE SCHEMA READINESSOPS.APP;

CREATE OR REPLACE PROCEDURE SP_RUN_READINESS_AGENT(P_RUN_ID VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
BEGIN
    -- Unique prefix: timestamp with milliseconds prevents sub-second ID collisions
    LET v_agent_run_prefix VARCHAR := 'AR_' || TO_VARCHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD_HH24MISS_FF3');
    LET v_prompt VARCHAR;
    LET v_llm_response VARCHAR;
    LET v_parsed VARIANT;
    LET v_num_gaps INTEGER := 0;
    LET v_num_actions INTEGER := 0;

    -- ================================================================
    -- Single transaction wraps DELETEs + INSERTs together.
    -- On failure, ROLLBACK restores prior agent data AND removes
    -- any partial new inserts — the database is unchanged.
    -- ================================================================
    BEGIN TRANSACTION;

    -- Idempotent cleanup: remove only prior agent-generated records (AR_ prefix).
    -- Sample/seed data (GAP_001, ACT_001, AGENT_RUN_001) is never touched.
    -- These DELETEs are inside the transaction so ROLLBACK restores them on failure.
    DELETE FROM RECOMMENDED_ACTIONS WHERE RUN_ID = :P_RUN_ID AND ACTION_ID LIKE 'AR_%';
    DELETE FROM READINESS_GAPS WHERE RUN_ID = :P_RUN_ID AND GAP_ID LIKE 'AR_%';
    DELETE FROM AGENT_RUN_HISTORY WHERE RUN_ID = :P_RUN_ID AND AGENT_RUN_ID LIKE 'AR_%';

    -- Log: LOAD step
    INSERT INTO AGENT_RUN_HISTORY (AGENT_RUN_ID, RUN_ID, AGENT_STEP, INPUT_SUMMARY, OUTPUT_SUMMARY)
    VALUES (:v_agent_run_prefix || '_01', :P_RUN_ID, 'LOAD_ASSESSMENT',
            'Reading assessment answers and evidence for run ' || :P_RUN_ID,
            'Data loaded successfully.');

    -- Build the LLM prompt from actual assessment data
    v_prompt := (
        SELECT
            'You are an AI readiness gap analyst. Analyze the following assessment data and produce a JSON response.\n\n' ||
            'INPUT DATA:\n' ||
            LISTAGG(
                '---\nQuestion ID: ' || q.QUESTION_ID ||
                '\nDomain: ' || d.DOMAIN_NAME ||
                '\nQuestion: ' || q.QUESTION_TEXT ||
                '\nExpected Evidence: ' || q.EXPECTED_EVIDENCE ||
                '\nAnswer Status: ' || a.ANSWER_STATUS ||
                '\nAnswer Text: ' || COALESCE(a.ANSWER_TEXT, 'N/A') ||
                '\nEvidence Title: ' || COALESCE(e.EVIDENCE_TITLE, 'None') ||
                '\nEvidence Text: ' || COALESCE(e.EVIDENCE_TEXT, 'None') ||
                '\nEvidence Status: ' || COALESCE(e.EVIDENCE_STATUS, 'MISSING'),
                '\n'
            ) WITHIN GROUP (ORDER BY q.SORT_ORDER) ||
            '\n\n---\nINSTRUCTIONS:\n' ||
            'For each question where the answer is not fully confirmed with sufficient evidence, identify a gap.\n' ||
            'Then for each gap, recommend one concrete action.\n\n' ||
            'RULES:\n' ||
            '- severity must be HIGH, MEDIUM, or LOW\n' ||
            '- priority_score must be an integer 1-100 (higher = more urgent)\n' ||
            '- suggested_owner must be one of: Risk Manager, Data Governance Lead, Program Lead, PMO Lead, Security Lead\n' ||
            '- due_in_days must be 14, 30, 60, or 90\n\n' ||
            'Respond ONLY with valid JSON in this exact structure. Do NOT wrap in markdown code fences.\n' ||
            '{"gaps": [{"question_id": "...", "severity": "...", "priority_score": N, "gap_title": "...", "gap_description": "..."}], ' ||
            '"actions": [{"question_id": "...", "action_title": "...", "action_description": "...", "suggested_owner": "...", "due_in_days": N}]}'
        FROM ASSESSMENT_ANSWERS a
        JOIN READINESS_QUESTIONS q ON a.QUESTION_ID = q.QUESTION_ID
        JOIN READINESS_DOMAINS d ON q.DOMAIN_ID = d.DOMAIN_ID
        LEFT JOIN EVIDENCE_ITEMS e ON a.RUN_ID = e.RUN_ID AND a.QUESTION_ID = e.QUESTION_ID
        WHERE a.RUN_ID = :P_RUN_ID
    );

    -- Log: VALIDATE step
    INSERT INTO AGENT_RUN_HISTORY (AGENT_RUN_ID, RUN_ID, AGENT_STEP, INPUT_SUMMARY, OUTPUT_SUMMARY)
    VALUES (:v_agent_run_prefix || '_02', :P_RUN_ID, 'VALIDATE_EVIDENCE',
            'Built prompt with answer and evidence data for LLM analysis.',
            'Prompt constructed. Calling Cortex AI.');

    -- Call Cortex LLM
    v_llm_response := (
        SELECT SNOWFLAKE.CORTEX.COMPLETE('mistral-large2', :v_prompt)
    );

    -- Safeguard: Strip markdown code fences that LLMs frequently add despite instructions.
    -- Handles ```json ... ``` and ``` ... ``` wrapping patterns.
    v_llm_response := REGEXP_REPLACE(:v_llm_response, '^\\s*```(json|JSON)?\\s*', '');
    v_llm_response := REGEXP_REPLACE(:v_llm_response, '\\s*```\\s*$', '');
    v_llm_response := TRIM(:v_llm_response);

    -- Safeguard: Validate JSON with TRY_PARSE_JSON (returns NULL instead of throwing).
    v_parsed := (SELECT TRY_PARSE_JSON(:v_llm_response));

    IF (:v_parsed IS NULL) THEN
        -- Invalid JSON: roll back everything (DELETEs + partial INSERTs are undone).
        ROLLBACK;
        -- Write FAILED audit record in a separate auto-committed statement.
        -- This persists regardless of the rollback above so operators can diagnose.
        INSERT INTO AGENT_RUN_HISTORY (AGENT_RUN_ID, RUN_ID, AGENT_STEP, INPUT_SUMMARY, OUTPUT_SUMMARY)
        VALUES (:v_agent_run_prefix || '_ERR', :P_RUN_ID, 'FAILED',
                'Cortex returned invalid or unparseable JSON after fence stripping.',
                LEFT(COALESCE(:v_llm_response, '<NULL RESPONSE>'), 500));
        RETURN 'FAILED: Cortex returned invalid JSON for run ' || :P_RUN_ID || '. See AGENT_RUN_HISTORY for details.';
    END IF;

    -- Log: DETECT_GAPS step
    INSERT INTO AGENT_RUN_HISTORY (AGENT_RUN_ID, RUN_ID, AGENT_STEP, INPUT_SUMMARY, OUTPUT_SUMMARY)
    VALUES (:v_agent_run_prefix || '_03', :P_RUN_ID, 'DETECT_GAPS',
            'Received valid LLM response. Parsing gaps.',
            LEFT(:v_llm_response, 200));

    -- Insert gaps from validated JSON.
    -- TRY_CAST on priority_score: cast VARIANT->VARCHAR first (TRY_CAST rejects VARIANT directly).
    -- Defaults to 50 if LLM returns non-numeric value.
    INSERT INTO READINESS_GAPS (GAP_ID, RUN_ID, DOMAIN_ID, QUESTION_ID, GAP_TITLE, GAP_DESCRIPTION, SEVERITY, PRIORITY_SCORE)
    SELECT
        :v_agent_run_prefix || '_G' || ROW_NUMBER() OVER (ORDER BY f.INDEX),
        :P_RUN_ID,
        q.DOMAIN_ID,
        f.VALUE:question_id::VARCHAR,
        f.VALUE:gap_title::VARCHAR,
        f.VALUE:gap_description::VARCHAR,
        f.VALUE:severity::VARCHAR,
        COALESCE(TRY_CAST(f.VALUE:priority_score::VARCHAR AS INTEGER), 50)
    FROM TABLE(FLATTEN(:v_parsed:gaps)) f
    LEFT JOIN READINESS_QUESTIONS q ON f.VALUE:question_id::VARCHAR = q.QUESTION_ID;

    v_num_gaps := (SELECT COUNT(*) FROM READINESS_GAPS WHERE GAP_ID LIKE :v_agent_run_prefix || '%');

    -- Insert actions linked to their corresponding gaps.
    -- INNER JOIN: only inserts actions whose question_id matches a gap we just created.
    -- Prevents orphan actions with NULL GAP_ID.
    -- TRY_CAST on due_in_days: cast VARIANT->VARCHAR first. Defaults to 30.
    INSERT INTO RECOMMENDED_ACTIONS (ACTION_ID, RUN_ID, GAP_ID, ACTION_TITLE, ACTION_DESCRIPTION, OWNER_NAME, DUE_IN_DAYS, ACTION_STATUS)
    SELECT
        :v_agent_run_prefix || '_A' || ROW_NUMBER() OVER (ORDER BY f.INDEX),
        :P_RUN_ID,
        g.GAP_ID,
        f.VALUE:action_title::VARCHAR,
        f.VALUE:action_description::VARCHAR,
        f.VALUE:suggested_owner::VARCHAR,
        COALESCE(TRY_CAST(f.VALUE:due_in_days::VARCHAR AS INTEGER), 30),
        'PROPOSED'
    FROM TABLE(FLATTEN(:v_parsed:actions)) f
    INNER JOIN READINESS_GAPS g
        ON g.RUN_ID = :P_RUN_ID
       AND g.QUESTION_ID = f.VALUE:question_id::VARCHAR
       AND g.GAP_ID LIKE :v_agent_run_prefix || '%';

    v_num_actions := (SELECT COUNT(*) FROM RECOMMENDED_ACTIONS WHERE ACTION_ID LIKE :v_agent_run_prefix || '%');

    -- Log: GENERATE_ACTIONS step
    INSERT INTO AGENT_RUN_HISTORY (AGENT_RUN_ID, RUN_ID, AGENT_STEP, INPUT_SUMMARY, OUTPUT_SUMMARY)
    VALUES (:v_agent_run_prefix || '_04', :P_RUN_ID, 'GENERATE_ACTIONS',
            'Parsed ' || :v_num_gaps || ' gaps from LLM output.',
            'Inserted ' || :v_num_gaps || ' gaps and ' || :v_num_actions || ' actions into tables.');

    -- Success: commit DELETEs + all INSERTs atomically.
    COMMIT;

    RETURN 'Agent complete. Generated ' || :v_num_gaps || ' gaps and ' || :v_num_actions || ' actions for run ' || :P_RUN_ID;

EXCEPTION
    WHEN OTHER THEN
        -- Roll back the entire transaction: DELETEs and INSERTs are all undone.
        -- The database returns to its pre-call state.
        ROLLBACK;
        -- Write a FAILED audit record in a separate auto-committed statement.
        -- v_agent_run_prefix and P_RUN_ID are declared in the enclosing BEGIN scope
        -- and remain accessible in the EXCEPTION handler per Snowflake Scripting rules.
        INSERT INTO AGENT_RUN_HISTORY (AGENT_RUN_ID, RUN_ID, AGENT_STEP, INPUT_SUMMARY, OUTPUT_SUMMARY)
        VALUES (:v_agent_run_prefix || '_ERR', :P_RUN_ID, 'FAILED',
                'Unhandled exception in agent procedure.',
                LEFT(SQLERRM, 500));
        RETURN 'FAILED: ' || SQLERRM;
END;
