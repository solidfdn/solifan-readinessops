CREATE OR REPLACE PROCEDURE READINESSOPS_VALIDATION.APP.SP_PUBLISH_AGENT_RUN(P_AGENT_RUN_ID VARCHAR)
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

    -- Validate agent run exists
    v_run_exists := (
        SELECT COUNT(*)
        FROM GOVERNANCE_AGENT_RUN
        WHERE AGENT_RUN_ID = :P_AGENT_RUN_ID
    );

    IF (:v_run_exists = 0) THEN
        RETURN '{"status":"FAILED","error":"Agent Run not found"}';
    END IF;

    -- Freeze only the proposals approved at the start of this publish call.
    CREATE OR REPLACE TEMPORARY TABLE TMP_APPROVED_AGENT_PROPOSALS AS
    SELECT
        p.*,
        CASE
            WHEN p.PROPOSAL_TYPE IN ('GAP', 'RISK') THEN
                EXISTS (
                    SELECT 1
                    FROM READINESS_GAPS g
                    WHERE g.SOURCE_PROPOSAL_ID = p.PROPOSAL_ID
                )
            WHEN p.PROPOSAL_TYPE = 'ACTION' THEN
                EXISTS (
                    SELECT 1
                    FROM RECOMMENDED_ACTIONS a
                    WHERE a.SOURCE_PROPOSAL_ID = p.PROPOSAL_ID
                )
            ELSE FALSE
        END AS CANONICAL_ALREADY_EXISTS
    FROM GOVERNANCE_AGENT_PROPOSAL p
    WHERE p.AGENT_RUN_ID = :P_AGENT_RUN_ID
      AND p.STATUS = 'APPROVED';

    v_approved_count := (
        SELECT COUNT(*)
        FROM TMP_APPROVED_AGENT_PROPOSALS
    );

    IF (:v_approved_count = 0) THEN
        RETURN '{"status":"FAILED","error":"No approved proposals to publish"}';
    END IF;

    -- Publish approved GAP proposals.
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
        LEFT JOIN READINESS_QUESTIONS q
          ON p.QUESTION_ID = q.QUESTION_ID
        WHERE p.PROPOSAL_TYPE = 'GAP'
    ) source
    ON target.SOURCE_PROPOSAL_ID = source.SOURCE_PROPOSAL_ID
    WHEN NOT MATCHED THEN INSERT (
        GAP_ID,
        RUN_ID,
        DOMAIN_ID,
        QUESTION_ID,
        GAP_TITLE,
        GAP_DESCRIPTION,
        SEVERITY,
        PRIORITY_SCORE,
        SOURCE_PROPOSAL_ID,
        SOURCE_AGENT_RUN_ID
    )
    VALUES (
        source.GAP_ID,
        source.RUN_ID,
        source.DOMAIN_ID,
        source.QUESTION_ID,
        source.GAP_TITLE,
        source.GAP_DESCRIPTION,
        source.SEVERITY,
        source.PRIORITY_SCORE,
        source.SOURCE_PROPOSAL_ID,
        source.SOURCE_AGENT_RUN_ID
    );

    v_pub_gaps := (
        SELECT COUNT(*)
        FROM TMP_APPROVED_AGENT_PROPOSALS
        WHERE PROPOSAL_TYPE = 'GAP'
          AND CANONICAL_ALREADY_EXISTS = FALSE
    );

    -- Publish approved RISK proposals as canonical READINESS_GAPS records.
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
        LEFT JOIN READINESS_QUESTIONS q
          ON p.QUESTION_ID = q.QUESTION_ID
        WHERE p.PROPOSAL_TYPE = 'RISK'
    ) source
    ON target.SOURCE_PROPOSAL_ID = source.SOURCE_PROPOSAL_ID
    WHEN NOT MATCHED THEN INSERT (
        GAP_ID,
        RUN_ID,
        DOMAIN_ID,
        QUESTION_ID,
        GAP_TITLE,
        GAP_DESCRIPTION,
        SEVERITY,
        PRIORITY_SCORE,
        SOURCE_PROPOSAL_ID,
        SOURCE_AGENT_RUN_ID
    )
    VALUES (
        source.GAP_ID,
        source.RUN_ID,
        source.DOMAIN_ID,
        source.QUESTION_ID,
        source.GAP_TITLE,
        source.GAP_DESCRIPTION,
        source.SEVERITY,
        source.PRIORITY_SCORE,
        source.SOURCE_PROPOSAL_ID,
        source.SOURCE_AGENT_RUN_ID
    );

    v_pub_risks := (
        SELECT COUNT(*)
        FROM TMP_APPROVED_AGENT_PROPOSALS
        WHERE PROPOSAL_TYPE = 'RISK'
          AND CANONICAL_ALREADY_EXISTS = FALSE
    );

    -- Publish approved ACTION proposals.
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
        ACTION_ID,
        RUN_ID,
        GAP_ID,
        ACTION_TITLE,
        ACTION_DESCRIPTION,
        OWNER_NAME,
        DUE_IN_DAYS,
        ACTION_STATUS,
        SOURCE_PROPOSAL_ID,
        SOURCE_AGENT_RUN_ID
    )
    VALUES (
        source.ACTION_ID,
        source.RUN_ID,
        source.GAP_ID,
        source.ACTION_TITLE,
        source.ACTION_DESCRIPTION,
        source.OWNER_NAME,
        source.DUE_IN_DAYS,
        source.ACTION_STATUS,
        source.SOURCE_PROPOSAL_ID,
        source.SOURCE_AGENT_RUN_ID
    );

    v_pub_actions := (
        SELECT COUNT(*)
        FROM TMP_APPROVED_AGENT_PROPOSALS
        WHERE PROPOSAL_TYPE = 'ACTION'
          AND CANONICAL_ALREADY_EXISTS = FALSE
    );

    -- Mark only this call's approved proposals as published.
    UPDATE GOVERNANCE_AGENT_PROPOSAL p
    SET
        STATUS = 'PUBLISHED',
        PUBLISHED_ENTITY_ID = 'PUB_' || p.PROPOSAL_ID,
        UPDATED_AT = CURRENT_TIMESTAMP()
    WHERE p.PROPOSAL_ID IN (
        SELECT PROPOSAL_ID
        FROM TMP_APPROVED_AGENT_PROPOSALS
    )
      AND p.STATUS = 'APPROVED';

    -- Write one publish history record per proposal.
    INSERT INTO GOVERNANCE_APPROVAL_HISTORY (
        APPROVAL_HISTORY_ID,
        PROPOSAL_ID,
        ACTION_TYPE,
        PREVIOUS_STATUS,
        NEW_STATUS,
        COMMENT,
        ACTED_BY
    )
    SELECT
        'AH_PUB_' || t.PROPOSAL_ID,
        t.PROPOSAL_ID,
        'PUBLISH',
        'APPROVED',
        'PUBLISHED',
        'Published as canonical record',
        CURRENT_USER()
    FROM TMP_APPROVED_AGENT_PROPOSALS t
    WHERE NOT EXISTS (
        SELECT 1
        FROM GOVERNANCE_APPROVAL_HISTORY h
        WHERE h.PROPOSAL_ID = t.PROPOSAL_ID
          AND h.ACTION_TYPE = 'PUBLISH'
    );

    RETURN
        '{"status":"OK","published_gaps":' || :v_pub_gaps ||
        ',"published_risks":' || :v_pub_risks ||
        ',"published_actions":' || :v_pub_actions || '}';

EXCEPTION
    WHEN OTHER THEN
        RETURN '{"status":"FAILED","error":"' || LEFT(SQLERRM, 200) || '"}';
END;
$$;
