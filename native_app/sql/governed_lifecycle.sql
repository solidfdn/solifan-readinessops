-- Governed lifecycle for the existing ReadinessOps Decision Pack.
-- Human editing, review, and explicit publication all use the same normalized
-- content version and hash. AI generation never calls these procedures.

ALTER TABLE APP_DATA.GOVERNANCE_AGENT_PROPOSAL
    ADD COLUMN IF NOT EXISTS CONTENT_VERSION NUMBER DEFAULT 1;
ALTER TABLE APP_DATA.GOVERNANCE_AGENT_PROPOSAL
    ADD COLUMN IF NOT EXISTS CONTENT_HASH VARCHAR;
ALTER TABLE APP_DATA.GOVERNANCE_AGENT_PROPOSAL
    ADD COLUMN IF NOT EXISTS APPROVED_CONTENT_VERSION NUMBER;
ALTER TABLE APP_DATA.GOVERNANCE_AGENT_PROPOSAL
    ADD COLUMN IF NOT EXISTS APPROVED_CONTENT_HASH VARCHAR;

ALTER TABLE APP_DATA.GOVERNED_DECISION_RECORD
    ADD COLUMN IF NOT EXISTS CONTENT_VERSION NUMBER;
ALTER TABLE APP_DATA.GOVERNED_DECISION_RECORD
    ADD COLUMN IF NOT EXISTS CONTENT_HASH VARCHAR;

-- Upgrade-safe normalization for proposals created by the R1 package.
UPDATE APP_DATA.GOVERNANCE_AGENT_PROPOSAL
SET PROPOSAL_PAYLOAD = OBJECT_INSERT(
        OBJECT_INSERT(
            COALESCE(PROPOSAL_PAYLOAD, OBJECT_CONSTRUCT()),
            'title', TITLE, TRUE
        ),
        'description', DESCRIPTION, TRUE
    ),
    CONTENT_VERSION = COALESCE(CONTENT_VERSION, 1)
WHERE CONTENT_HASH IS NULL;

UPDATE APP_DATA.GOVERNANCE_AGENT_PROPOSAL
SET CONTENT_HASH = SHA2(
        COALESCE(TITLE, '') || '\n' ||
        COALESCE(DESCRIPTION, '') || '\n' ||
        COALESCE(TO_JSON(PROPOSAL_PAYLOAD), '{}'),
        256
    )
WHERE CONTENT_HASH IS NULL;

CREATE OR REPLACE PROCEDURE APP_CODE.SP_EDIT_DECISION_PROPOSAL(
    P_PROPOSAL_ID VARCHAR,
    P_EXPECTED_CONTENT_VERSION NUMBER,
    P_EXPECTED_CONTENT_HASH VARCHAR,
    P_NEW_TITLE VARCHAR,
    P_NEW_DESCRIPTION VARCHAR,
    P_EDIT_REASON VARCHAR DEFAULT NULL
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
    v_actor VARCHAR DEFAULT CURRENT_USER();
    v_exists NUMBER DEFAULT 0;
    v_old_title VARCHAR;
    v_old_description VARCHAR;
    v_new_payload VARIANT;
    v_new_version NUMBER;
    v_new_hash VARCHAR;
    v_updated NUMBER DEFAULT 0;
BEGIN
    IF (:v_actor IS NULL) THEN
        RETURN '{"status":"FAILED","error":"READ SESSION is required for operator attribution"}';
    END IF;

    IF (TRIM(COALESCE(:P_NEW_TITLE, '')) = '') THEN
        RETURN '{"status":"FAILED","error":"Proposal title is required"}';
    END IF;

    SELECT COUNT(*) INTO :v_exists
    FROM APP_DATA.GOVERNANCE_AGENT_PROPOSAL
    WHERE PROPOSAL_ID = :P_PROPOSAL_ID;

    IF (:v_exists <> 1) THEN
        RETURN '{"status":"FAILED","error":"Proposal not found or proposal ID is not unique"}';
    END IF;

    SELECT
        TITLE,
        DESCRIPTION,
        CONTENT_VERSION + 1,
        OBJECT_INSERT(
            OBJECT_INSERT(
                COALESCE(PROPOSAL_PAYLOAD, OBJECT_CONSTRUCT()),
                'title', :P_NEW_TITLE, TRUE
            ),
            'description', :P_NEW_DESCRIPTION, TRUE
        )
    INTO
        :v_old_title,
        :v_old_description,
        :v_new_version,
        :v_new_payload
    FROM APP_DATA.GOVERNANCE_AGENT_PROPOSAL
    WHERE PROPOSAL_ID = :P_PROPOSAL_ID;

    v_new_hash := SHA2(
        COALESCE(:P_NEW_TITLE, '') || '\n' ||
        COALESCE(:P_NEW_DESCRIPTION, '') || '\n' ||
        COALESCE(TO_JSON(:v_new_payload), '{}'),
        256
    );

    BEGIN TRANSACTION;

    UPDATE APP_DATA.GOVERNANCE_AGENT_PROPOSAL
    SET TITLE = :P_NEW_TITLE,
        DESCRIPTION = :P_NEW_DESCRIPTION,
        PROPOSAL_PAYLOAD = :v_new_payload,
        CONTENT_VERSION = :v_new_version,
        CONTENT_HASH = :v_new_hash,
        APPROVED_CONTENT_VERSION = NULL,
        APPROVED_CONTENT_HASH = NULL,
        UPDATED_AT = CURRENT_TIMESTAMP()
    WHERE PROPOSAL_ID = :P_PROPOSAL_ID
      AND STATUS = 'REVIEW_REQUIRED'
      AND CONTENT_VERSION = :P_EXPECTED_CONTENT_VERSION
      AND CONTENT_HASH = :P_EXPECTED_CONTENT_HASH;

    v_updated := SQLROWCOUNT;
    IF (:v_updated <> 1) THEN
        ROLLBACK;
        RETURN '{"status":"CONFLICT","error":"Proposal changed after it was displayed; reload before editing"}';
    END IF;

    INSERT INTO APP_DATA.GOVERNANCE_APPROVAL_HISTORY (
        APPROVAL_HISTORY_ID,
        PROPOSAL_ID,
        ACTION_TYPE,
        PREVIOUS_STATUS,
        NEW_STATUS,
        COMMENT,
        ACTED_BY
    ) VALUES (
        'AH_EDIT_' || :P_PROPOSAL_ID || '_' || UUID_STRING(),
        :P_PROPOSAL_ID,
        'EDIT',
        'REVIEW_REQUIRED',
        'REVIEW_REQUIRED',
        TO_JSON(OBJECT_CONSTRUCT_KEEP_NULL(
            'reason', :P_EDIT_REASON,
            'before_title', :v_old_title,
            'after_title', :P_NEW_TITLE,
            'before_description', :v_old_description,
            'after_description', :P_NEW_DESCRIPTION,
            'content_version', :v_new_version,
            'content_hash', :v_new_hash
        )),
        :v_actor
    );

    COMMIT;

    RETURN TO_JSON(OBJECT_CONSTRUCT(
        'status', 'OK',
        'proposal_id', :P_PROPOSAL_ID,
        'content_version', :v_new_version,
        'content_hash', :v_new_hash
    ));
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RETURN TO_JSON(OBJECT_CONSTRUCT(
            'status', 'FAILED',
            'error', LEFT(SQLERRM, 300)
        ));
END;
$$;

CREATE OR REPLACE PROCEDURE APP_CODE.SP_REVIEW_DECISION_PROPOSAL(
    P_PROPOSAL_ID VARCHAR,
    P_DECISION VARCHAR,
    P_EXPECTED_CONTENT_VERSION NUMBER,
    P_EXPECTED_CONTENT_HASH VARCHAR,
    P_REVIEW_COMMENT VARCHAR DEFAULT NULL
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
    v_actor VARCHAR DEFAULT CURRENT_USER();
    v_new_status VARCHAR;
    v_updated NUMBER DEFAULT 0;
BEGIN
    IF (:v_actor IS NULL) THEN
        RETURN '{"status":"FAILED","error":"READ SESSION is required for operator attribution"}';
    END IF;

    IF (UPPER(:P_DECISION) NOT IN ('APPROVE', 'REJECT')) THEN
        RETURN '{"status":"FAILED","error":"Decision must be APPROVE or REJECT"}';
    END IF;

    v_new_status := IFF(UPPER(:P_DECISION) = 'APPROVE', 'APPROVED', 'REJECTED');

    BEGIN TRANSACTION;

    UPDATE APP_DATA.GOVERNANCE_AGENT_PROPOSAL
    SET STATUS = :v_new_status,
        REVIEW_COMMENT = :P_REVIEW_COMMENT,
        REVIEWED_BY = :v_actor,
        REVIEWED_AT = CURRENT_TIMESTAMP(),
        APPROVED_CONTENT_VERSION = IFF(
            :v_new_status = 'APPROVED', CONTENT_VERSION, NULL
        ),
        APPROVED_CONTENT_HASH = IFF(
            :v_new_status = 'APPROVED', CONTENT_HASH, NULL
        ),
        UPDATED_AT = CURRENT_TIMESTAMP()
    WHERE PROPOSAL_ID = :P_PROPOSAL_ID
      AND STATUS = 'REVIEW_REQUIRED'
      AND CONTENT_VERSION = :P_EXPECTED_CONTENT_VERSION
      AND CONTENT_HASH = :P_EXPECTED_CONTENT_HASH;

    v_updated := SQLROWCOUNT;
    IF (:v_updated <> 1) THEN
        ROLLBACK;
        RETURN '{"status":"CONFLICT","error":"Proposal changed or was already reviewed; reload before deciding"}';
    END IF;

    INSERT INTO APP_DATA.GOVERNANCE_APPROVAL_HISTORY (
        APPROVAL_HISTORY_ID,
        PROPOSAL_ID,
        ACTION_TYPE,
        PREVIOUS_STATUS,
        NEW_STATUS,
        COMMENT,
        ACTED_BY
    ) VALUES (
        'AH_REVIEW_' || :P_PROPOSAL_ID || '_' || UUID_STRING(),
        :P_PROPOSAL_ID,
        UPPER(:P_DECISION),
        'REVIEW_REQUIRED',
        :v_new_status,
        :P_REVIEW_COMMENT,
        :v_actor
    );

    COMMIT;

    RETURN TO_JSON(OBJECT_CONSTRUCT(
        'status', 'OK',
        'proposal_id', :P_PROPOSAL_ID,
        'new_status', :v_new_status,
        'content_version', :P_EXPECTED_CONTENT_VERSION,
        'content_hash', :P_EXPECTED_CONTENT_HASH
    ));
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RETURN TO_JSON(OBJECT_CONSTRUCT(
            'status', 'FAILED',
            'error', LEFT(SQLERRM, 300)
        ));
END;
$$;

CREATE OR REPLACE PROCEDURE APP_CODE.SP_PUBLISH_DECISION_PACK(
    P_AGENT_RUN_ID VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
    v_actor VARCHAR DEFAULT CURRENT_USER();
    v_run_count NUMBER DEFAULT 0;
    v_section_count NUMBER DEFAULT 0;
    v_type_count NUMBER DEFAULT 0;
    v_assessment_id_count NUMBER DEFAULT 0;
    v_assessment_row_count NUMBER DEFAULT 0;
    v_approved_count NUMBER DEFAULT 0;
    v_published_count NUMBER DEFAULT 0;
    v_hash_mismatch_count NUMBER DEFAULT 0;
    v_record_count NUMBER DEFAULT 0;
    v_record_type_count NUMBER DEFAULT 0;
    v_record_mismatch_count NUMBER DEFAULT 0;
    v_updated NUMBER DEFAULT 0;
BEGIN
    IF (:v_actor IS NULL) THEN
        RETURN '{"status":"FAILED","error":"READ SESSION is required for operator attribution"}';
    END IF;

    SELECT COUNT(*) INTO :v_run_count
    FROM APP_DATA.GOVERNANCE_AGENT_RUN
    WHERE AGENT_RUN_ID = :P_AGENT_RUN_ID
      AND STATUS = 'COMPLETED';

    IF (:v_run_count <> 1) THEN
        RETURN '{"status":"FAILED","error":"Completed Decision Pack Run not found"}';
    END IF;

    SELECT
        COUNT(*),
        COUNT(DISTINCT PROPOSAL_TYPE),
        COUNT(DISTINCT ASSESSMENT_RUN_ID),
        COUNT_IF(STATUS = 'APPROVED'),
        COUNT_IF(STATUS = 'PUBLISHED'),
        COUNT_IF(
            STATUS = 'APPROVED' AND (
                APPROVED_CONTENT_VERSION IS NULL OR
                APPROVED_CONTENT_HASH IS NULL OR
                APPROVED_CONTENT_VERSION <> CONTENT_VERSION OR
                APPROVED_CONTENT_HASH <> CONTENT_HASH
            )
        )
    INTO
        :v_section_count,
        :v_type_count,
        :v_assessment_id_count,
        :v_approved_count,
        :v_published_count,
        :v_hash_mismatch_count
    FROM APP_DATA.GOVERNANCE_AGENT_PROPOSAL
    WHERE AGENT_RUN_ID = :P_AGENT_RUN_ID
      AND PROPOSAL_TYPE IN (
          'DECISION_GOVERNANCE',
          'DECISION_VALUE',
          'DECISION_MODEL_ROUTING',
          'DECISION_PORTFOLIO'
      );

    IF (
        :v_section_count <> 4 OR
        :v_type_count <> 4 OR
        :v_assessment_id_count <> 1
    ) THEN
        RETURN '{"status":"FAILED","error":"Decision Pack must contain one of each section for one Assessment"}';
    END IF;

    SELECT COUNT(*) INTO :v_assessment_row_count
    FROM APP_DATA.ASSESSMENT_RUNS r
    WHERE r.RUN_ID = (
        SELECT MIN(p.ASSESSMENT_RUN_ID)
        FROM APP_DATA.GOVERNANCE_AGENT_PROPOSAL p
        WHERE p.AGENT_RUN_ID = :P_AGENT_RUN_ID
    );

    IF (:v_assessment_row_count <> 1) THEN
        RETURN '{"status":"FAILED","error":"Decision Pack Assessment is missing or not unique"}';
    END IF;

    SELECT
        COUNT(*),
        COUNT(DISTINCT d.DECISION_TYPE),
        COUNT_IF(
            p.PROPOSAL_ID IS NULL OR
            d.CONTENT_VERSION <> p.CONTENT_VERSION OR
            d.CONTENT_HASH <> p.CONTENT_HASH OR
            d.CONTENT_VERSION <> p.APPROVED_CONTENT_VERSION OR
            d.CONTENT_HASH <> p.APPROVED_CONTENT_HASH
        )
    INTO
        :v_record_count,
        :v_record_type_count,
        :v_record_mismatch_count
    FROM APP_DATA.GOVERNED_DECISION_RECORD d
    LEFT JOIN APP_DATA.GOVERNANCE_AGENT_PROPOSAL p
      ON p.PROPOSAL_ID = d.SOURCE_PROPOSAL_ID
     AND p.AGENT_RUN_ID = d.SOURCE_AGENT_RUN_ID
    WHERE d.SOURCE_AGENT_RUN_ID = :P_AGENT_RUN_ID;

    IF (:v_published_count = 4) THEN
        IF (
            :v_record_count <> 4 OR
            :v_record_type_count <> 4 OR
            :v_record_mismatch_count <> 0
        ) THEN
            RETURN '{"status":"FAILED","error":"Published status does not match four approved governed records"}';
        END IF;
        RETURN TO_JSON(OBJECT_CONSTRUCT(
            'status', 'SKIPPED',
            'reason', 'Decision Pack is already published',
            'agent_run_id', :P_AGENT_RUN_ID
        ));
    END IF;

    IF (:v_approved_count <> 4 OR :v_hash_mismatch_count <> 0) THEN
        RETURN '{"status":"FAILED","error":"All four current content versions must be approved before publication"}';
    END IF;

    IF (:v_record_count NOT IN (0, 4)) THEN
        RETURN '{"status":"FAILED","error":"Partial governed Decision Pack already exists"}';
    END IF;

    IF (
        :v_record_count = 4 AND (
            :v_record_type_count <> 4 OR
            :v_record_mismatch_count <> 0
        )
    ) THEN
        RETURN '{"status":"FAILED","error":"Existing governed records do not match the approved content"}';
    END IF;

    BEGIN TRANSACTION;

    INSERT INTO APP_DATA.GOVERNED_DECISION_RECORD (
        DECISION_RECORD_ID,
        SOURCE_PROPOSAL_ID,
        SOURCE_AGENT_RUN_ID,
        ASSESSMENT_RUN_ID,
        INITIATIVE_ID,
        DECISION_TYPE,
        TITLE,
        DESCRIPTION,
        DECISION_PAYLOAD,
        CONTENT_VERSION,
        CONTENT_HASH,
        PUBLISHED_BY,
        PUBLISHED_AT
    )
    SELECT
        'DR_' || p.PROPOSAL_ID,
        p.PROPOSAL_ID,
        p.AGENT_RUN_ID,
        p.ASSESSMENT_RUN_ID,
        r.INITIATIVE_ID,
        p.PROPOSAL_TYPE,
        p.TITLE,
        p.DESCRIPTION,
        p.PROPOSAL_PAYLOAD,
        p.CONTENT_VERSION,
        p.CONTENT_HASH,
        :v_actor,
        CURRENT_TIMESTAMP()
    FROM APP_DATA.GOVERNANCE_AGENT_PROPOSAL p
    JOIN APP_DATA.ASSESSMENT_RUNS r
      ON r.RUN_ID = p.ASSESSMENT_RUN_ID
    WHERE p.AGENT_RUN_ID = :P_AGENT_RUN_ID
      AND p.STATUS = 'APPROVED'
      AND p.CONTENT_VERSION = p.APPROVED_CONTENT_VERSION
      AND p.CONTENT_HASH = p.APPROVED_CONTENT_HASH
      AND NOT EXISTS (
          SELECT 1
          FROM APP_DATA.GOVERNED_DECISION_RECORD d
          WHERE d.SOURCE_PROPOSAL_ID = p.PROPOSAL_ID
      );

    SELECT
        COUNT(*),
        COUNT(DISTINCT d.DECISION_TYPE),
        COUNT_IF(
            p.PROPOSAL_ID IS NULL OR
            d.ASSESSMENT_RUN_ID <> p.ASSESSMENT_RUN_ID OR
            d.CONTENT_VERSION <> p.CONTENT_VERSION OR
            d.CONTENT_HASH <> p.CONTENT_HASH OR
            d.CONTENT_VERSION <> p.APPROVED_CONTENT_VERSION OR
            d.CONTENT_HASH <> p.APPROVED_CONTENT_HASH
        )
    INTO
        :v_record_count,
        :v_record_type_count,
        :v_record_mismatch_count
    FROM APP_DATA.GOVERNED_DECISION_RECORD d
    LEFT JOIN APP_DATA.GOVERNANCE_AGENT_PROPOSAL p
      ON p.PROPOSAL_ID = d.SOURCE_PROPOSAL_ID
     AND p.AGENT_RUN_ID = d.SOURCE_AGENT_RUN_ID
    WHERE d.SOURCE_AGENT_RUN_ID = :P_AGENT_RUN_ID;

    IF (
        :v_record_count <> 4 OR
        :v_record_type_count <> 4 OR
        :v_record_mismatch_count <> 0
    ) THEN
        ROLLBACK;
        RETURN '{"status":"CONFLICT","error":"Four matching governed records were not saved; no governed state was updated"}';
    END IF;

    UPDATE APP_DATA.GOVERNANCE_AGENT_PROPOSAL
    SET STATUS = 'PUBLISHED',
        PUBLISHED_ENTITY_ID = 'DR_' || PROPOSAL_ID,
        UPDATED_AT = CURRENT_TIMESTAMP()
    WHERE AGENT_RUN_ID = :P_AGENT_RUN_ID
      AND STATUS = 'APPROVED'
      AND CONTENT_VERSION = APPROVED_CONTENT_VERSION
      AND CONTENT_HASH = APPROVED_CONTENT_HASH;

    v_updated := SQLROWCOUNT;
    IF (:v_updated <> 4) THEN
        ROLLBACK;
        RETURN '{"status":"CONFLICT","error":"Decision Pack changed during publication; no governed state was updated"}';
    END IF;

    INSERT INTO APP_DATA.GOVERNANCE_APPROVAL_HISTORY (
        APPROVAL_HISTORY_ID,
        PROPOSAL_ID,
        ACTION_TYPE,
        PREVIOUS_STATUS,
        NEW_STATUS,
        COMMENT,
        ACTED_BY
    )
    SELECT
        'AH_PUBLISH_' || p.PROPOSAL_ID,
        p.PROPOSAL_ID,
        'PUBLISH',
        'APPROVED',
        'PUBLISHED',
        'Explicit publication of approved content version ' ||
            p.CONTENT_VERSION || ' (' || p.CONTENT_HASH || ')',
        :v_actor
    FROM APP_DATA.GOVERNANCE_AGENT_PROPOSAL p
    WHERE p.AGENT_RUN_ID = :P_AGENT_RUN_ID
      AND p.STATUS = 'PUBLISHED'
      AND NOT EXISTS (
          SELECT 1
          FROM APP_DATA.GOVERNANCE_APPROVAL_HISTORY h
          WHERE h.PROPOSAL_ID = p.PROPOSAL_ID
            AND h.ACTION_TYPE = 'PUBLISH'
      );

    COMMIT;

    RETURN TO_JSON(OBJECT_CONSTRUCT(
        'status', 'OK',
        'agent_run_id', :P_AGENT_RUN_ID,
        'published_decisions', 4,
        'published_by', :v_actor
    ));
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RETURN TO_JSON(OBJECT_CONSTRUCT(
            'status', 'FAILED',
            'error', LEFT(SQLERRM, 300)
        ));
END;
$$;

CREATE OR REPLACE VIEW APP_CODE.V_DECISION_PACK_REVIEW AS
SELECT
    p.PROPOSAL_ID,
    p.AGENT_RUN_ID,
    p.ASSESSMENT_RUN_ID,
    p.PROPOSAL_TYPE,
    p.TITLE,
    p.DESCRIPTION,
    p.SEVERITY,
    p.PRIORITY,
    p.RATIONALE,
    p.STATUS,
    p.PROPOSAL_PAYLOAD,
    p.CONTENT_VERSION,
    p.CONTENT_HASH,
    p.APPROVED_CONTENT_VERSION,
    p.APPROVED_CONTENT_HASH,
    p.REVIEW_COMMENT,
    p.REVIEWED_BY,
    p.REVIEWED_AT,
    p.CREATED_AT,
    p.UPDATED_AT
FROM APP_DATA.GOVERNANCE_AGENT_PROPOSAL p
WHERE p.PROPOSAL_TYPE IN (
    'DECISION_GOVERNANCE',
    'DECISION_VALUE',
    'DECISION_MODEL_ROUTING',
    'DECISION_PORTFOLIO'
);

CREATE OR REPLACE VIEW APP_CODE.V_GOVERNED_DECISION_RECORDS AS
SELECT
    DECISION_RECORD_ID,
    SOURCE_PROPOSAL_ID,
    SOURCE_AGENT_RUN_ID,
    ASSESSMENT_RUN_ID,
    INITIATIVE_ID,
    DECISION_TYPE,
    TITLE,
    DESCRIPTION,
    DECISION_PAYLOAD,
    CONTENT_VERSION,
    CONTENT_HASH,
    PUBLISHED_BY,
    PUBLISHED_AT
FROM APP_DATA.GOVERNED_DECISION_RECORD;

CREATE OR REPLACE VIEW APP_CODE.V_AI_PORTFOLIO AS
WITH current_sets AS (
    SELECT
        INITIATIVE_ID,
        SOURCE_AGENT_RUN_ID,
        MAX(PUBLISHED_AT) AS LAST_DECISION_AT
    FROM APP_DATA.GOVERNED_DECISION_RECORD
    GROUP BY INITIATIVE_ID, SOURCE_AGENT_RUN_ID
    HAVING COUNT(DISTINCT DECISION_TYPE) = 4
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY INITIATIVE_ID
        ORDER BY MAX(PUBLISHED_AT) DESC, SOURCE_AGENT_RUN_ID DESC
    ) = 1
),
decision_sets AS (
    SELECT d.*
    FROM APP_DATA.GOVERNED_DECISION_RECORD d
    JOIN current_sets c
      ON c.INITIATIVE_ID = d.INITIATIVE_ID
     AND c.SOURCE_AGENT_RUN_ID = d.SOURCE_AGENT_RUN_ID
)
SELECT
    i.INITIATIVE_ID,
    i.INITIATIVE_NAME,
    i.DESCRIPTION AS INITIATIVE_DESCRIPTION,
    i.OWNER_NAME,
    i.LIFECYCLE_STAGE,
    i.BUSINESS_OUTCOME,
    i.STATUS AS INITIATIVE_STATUS,
    MAX(IFF(d.DECISION_TYPE = 'DECISION_GOVERNANCE', d.TITLE, NULL))
        AS GOVERNANCE_TITLE,
    MAX(IFF(d.DECISION_TYPE = 'DECISION_GOVERNANCE',
        d.DECISION_PAYLOAD:readiness_level::VARCHAR, NULL))
        AS GOVERNANCE_READINESS,
    MAX(IFF(d.DECISION_TYPE = 'DECISION_VALUE', d.TITLE, NULL))
        AS VALUE_TITLE,
    MAX(IFF(d.DECISION_TYPE = 'DECISION_VALUE',
        d.DECISION_PAYLOAD:realization_confidence::VARCHAR, NULL))
        AS VALUE_CONFIDENCE,
    MAX(IFF(d.DECISION_TYPE = 'DECISION_MODEL_ROUTING', d.TITLE, NULL))
        AS ROUTING_TITLE,
    MAX(IFF(d.DECISION_TYPE = 'DECISION_MODEL_ROUTING',
        d.DECISION_PAYLOAD:recommended_approach::VARCHAR, NULL))
        AS ROUTING_APPROACH,
    MAX(IFF(d.DECISION_TYPE = 'DECISION_PORTFOLIO', d.TITLE, NULL))
        AS PORTFOLIO_TITLE,
    MAX(IFF(d.DECISION_TYPE = 'DECISION_PORTFOLIO',
        d.DECISION_PAYLOAD:recommendation::VARCHAR, NULL))
        AS PORTFOLIO_RECOMMENDATION,
    MAX(IFF(d.DECISION_TYPE = 'DECISION_PORTFOLIO',
        d.DECISION_PAYLOAD:priority_score::NUMBER, NULL))
        AS PORTFOLIO_PRIORITY,
    MAX(d.PUBLISHED_AT) AS LAST_DECISION_AT,
    MAX(d.SOURCE_AGENT_RUN_ID) AS SOURCE_AGENT_RUN_ID
FROM APP_DATA.AI_INITIATIVE i
LEFT JOIN decision_sets d
  ON d.INITIATIVE_ID = i.INITIATIVE_ID
WHERE i.STATUS = 'ACTIVE'
GROUP BY
    i.INITIATIVE_ID,
    i.INITIATIVE_NAME,
    i.DESCRIPTION,
    i.OWNER_NAME,
    i.LIFECYCLE_STAGE,
    i.BUSINESS_OUTCOME,
    i.STATUS;

GRANT SELECT ON VIEW APP_CODE.V_DECISION_PACK_REVIEW
    TO APPLICATION ROLE READINESSOPS_USER;
GRANT SELECT ON VIEW APP_CODE.V_GOVERNED_DECISION_RECORDS
    TO APPLICATION ROLE READINESSOPS_USER;
GRANT SELECT ON VIEW APP_CODE.V_AI_PORTFOLIO
    TO APPLICATION ROLE READINESSOPS_USER;

GRANT USAGE ON PROCEDURE APP_CODE.SP_EDIT_DECISION_PROPOSAL(
    VARCHAR, NUMBER, VARCHAR, VARCHAR, VARCHAR, VARCHAR
) TO APPLICATION ROLE READINESSOPS_REVIEWER;
GRANT USAGE ON PROCEDURE APP_CODE.SP_REVIEW_DECISION_PROPOSAL(
    VARCHAR, VARCHAR, NUMBER, VARCHAR, VARCHAR
) TO APPLICATION ROLE READINESSOPS_REVIEWER;
GRANT USAGE ON PROCEDURE APP_CODE.SP_PUBLISH_DECISION_PACK(VARCHAR)
    TO APPLICATION ROLE READINESSOPS_PUBLISHER;
