-- Run after `snow app run` with a role that owns the development application.
-- Replace the application name only if snowflake.yml was intentionally changed.

SHOW REFERENCES IN APPLICATION READINESSOPS_MARKETPLACE_DEV;
SHOW PRIVILEGES IN APPLICATION READINESSOPS_MARKETPLACE_DEV;
SHOW APPLICATION ROLES IN APPLICATION READINESSOPS_MARKETPLACE_DEV;

SELECT *
FROM READINESSOPS_MARKETPLACE_DEV.APP_CODE.V_ASSESSMENT_CONTEXT
ORDER BY CREATED_AT DESC;

SELECT *
FROM READINESSOPS_MARKETPLACE_DEV.APP_CODE.V_EVIDENCE_ITEMS
ORDER BY CREATED_AT DESC;

SELECT *
FROM READINESSOPS_MARKETPLACE_DEV.APP_CODE.V_DECISION_PACK_REVIEW
ORDER BY CREATED_AT DESC, PROPOSAL_TYPE;

SELECT *
FROM READINESSOPS_MARKETPLACE_DEV.APP_CODE.V_AGENT_RUN_STEP
ORDER BY STARTED_AT DESC, STEP_SEQUENCE;

-- Required manual/runtime evidence:
-- 1. Install under a second application name and confirm there is no fixed DB dependency.
-- 2. Bind one existing ReadinessOps Evidence TABLE, then register one row.
-- 3. Clear the table reference, bind one existing VIEW, and repeat.
-- 4. Revoke SELECT/reference access and confirm processing is denied.
-- 5. Revoke SNOWFLAKE.CORTEX_USER and confirm Cortex processing is denied.
-- 6. Revoke READ SESSION and confirm processing is blocked before attribution.
-- 7. Confirm READINESSOPS_USER cannot open the Streamlit or call mutation procedures.
-- 8. Confirm CREATED_BY/UPLOADED_BY for two different consumer users.
-- 9. Re-submit the unchanged source row and confirm Evidence import is SKIPPED.
-- 10. Generate the Decision Pack and confirm exactly four REVIEW_REQUIRED types:
--     DECISION_GOVERNANCE, DECISION_VALUE, DECISION_MODEL_ROUTING, DECISION_PORTFOLIO.
-- 11. Confirm no APPROVED/PUBLISHED record or Current-state update is created.
-- 12. Change only the source title and confirm a new Evidence ID is created.
-- 13. Rebind to a different object with the same key/text and confirm a new ID.
-- 14. Create a duplicate row key and confirm import fails before Cortex.
-- 15. Force Cortex failure and confirm no proposal/source partial write remains.
-- 16. Upgrade the app and confirm Evidence, runs, proposals, references, and role grants remain.
