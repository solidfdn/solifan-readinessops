-- Run after `snow app run` with a role that owns the development application.
-- Replace the application name only if snowflake.yml was intentionally changed.

SHOW REFERENCES IN APPLICATION READINESSOPS_MARKETPLACE_DEV;
SHOW PRIVILEGES IN APPLICATION READINESSOPS_MARKETPLACE_DEV;
SHOW APPLICATION ROLES IN APPLICATION READINESSOPS_MARKETPLACE_DEV;

SELECT *
FROM READINESSOPS_MARKETPLACE_DEV.APP_CODE.V_EVIDENCE_SNAPSHOT
ORDER BY CAPTURED_AT DESC;

SELECT *
FROM READINESSOPS_MARKETPLACE_DEV.APP_CODE.V_REVIEW_REQUIRED_PROPOSAL
ORDER BY CREATED_AT DESC;

-- Required manual/runtime evidence:
-- 1. Install under a second application name and confirm there is no fixed DB dependency.
-- 2. Bind one existing TABLE, then run one row through the Streamlit UI.
-- 3. Clear the table reference, bind one existing VIEW, and repeat.
-- 4. Revoke SELECT/reference access and confirm processing is denied.
-- 5. Revoke SNOWFLAKE.CORTEX_USER and confirm Cortex processing is denied.
-- 6. Revoke READ SESSION and confirm processing is blocked before attribution.
-- 7. Confirm READINESSOPS_USER cannot open the Streamlit or call the mutation SP.
-- 8. Confirm CREATED_BY/CAPTURED_BY for two different consumer users.
-- 9. Re-submit the unchanged source row and confirm SKIPPED.
-- 10. Confirm no APPROVED/PUBLISHED record or Current-state update is created.
-- 11. Change only the source title and confirm a new evidence/proposal ID is created.
-- 12. Rebind to a different object with the same key/text and confirm a new ID.
-- 13. Create a duplicate row key and confirm processing fails before Cortex.
-- 14. Force Cortex failure and confirm no snapshot-only partial write remains.
-- 15. Upgrade the app and confirm snapshots, proposals, references, and role grants remain.
