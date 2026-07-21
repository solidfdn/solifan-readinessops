CREATE OR REPLACE PROCEDURE READINESSOPS_VALIDATION.APP.SP_REVIEW_AGENT_PROPOSAL(P_PROPOSAL_ID VARCHAR, P_DECISION VARCHAR, P_REVIEW_COMMENT VARCHAR DEFAULT NULL)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
BEGIN
    USE SCHEMA READINESSOPS_VALIDATION.APP;

    LET v_current_status VARCHAR;
    LET v_new_status VARCHAR;

    -- Validate decision
    IF (:P_DECISION NOT IN ('APPROVE', 'REJECT')) THEN
        RETURN '{"status":"FAILED","error":"Decision must be APPROVE or REJECT"}';
    END IF;

    -- Get current proposal status
    v_current_status := (SELECT STATUS FROM GOVERNANCE_AGENT_PROPOSAL WHERE PROPOSAL_ID = :P_PROPOSAL_ID);

    IF (:v_current_status IS NULL) THEN
        RETURN '{"status":"FAILED","error":"Proposal not found"}';
    END IF;

    IF (:v_current_status != 'REVIEW_REQUIRED') THEN
        RETURN '{"status":"FAILED","error":"Only REVIEW_REQUIRED proposals can be reviewed. Current status: ' || :v_current_status || '"}';
    END IF;

    -- Determine new status
    IF (:P_DECISION = 'APPROVE') THEN
        v_new_status := 'APPROVED';
    ELSE
        v_new_status := 'REJECTED';
    END IF;

    -- Update proposal
    UPDATE GOVERNANCE_AGENT_PROPOSAL
    SET STATUS = :v_new_status,
        REVIEW_COMMENT = :P_REVIEW_COMMENT,
        REVIEWED_BY = CURRENT_USER(),
        REVIEWED_AT = CURRENT_TIMESTAMP(),
        UPDATED_AT = CURRENT_TIMESTAMP()
    WHERE PROPOSAL_ID = :P_PROPOSAL_ID;

    -- Write approval history
    INSERT INTO GOVERNANCE_APPROVAL_HISTORY (APPROVAL_HISTORY_ID, PROPOSAL_ID, ACTION_TYPE, PREVIOUS_STATUS, NEW_STATUS, COMMENT, ACTED_BY)
    VALUES (
        'AH_' || TO_VARCHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD_HH24MISS_FF3'),
        :P_PROPOSAL_ID,
        :P_DECISION,
        :v_current_status,
        :v_new_status,
        :P_REVIEW_COMMENT,
        CURRENT_USER()
    );

    RETURN '{"status":"OK","proposal_id":"' || :P_PROPOSAL_ID || '","decision":"' || :P_DECISION || '","new_status":"' || :v_new_status || '"}';

EXCEPTION
    WHEN OTHER THEN
        RETURN '{"status":"FAILED","error":"' || LEFT(SQLERRM, 200) || '"}';
END;
$$;
