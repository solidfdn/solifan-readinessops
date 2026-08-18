-- ============================================================
-- Existing Runs to Revision 1 Migration
-- ============================================================
-- Defines an idempotent migration procedure. The procedure does not alter
-- existing ASSESSMENT_RUNS, Evidence, proposal, decision, or audit rows.
-- Execute the CALL separately after the migration preview passes.
-- ============================================================

USE SCHEMA APP;

CREATE OR REPLACE PROCEDURE SP_MIGRATE_EXISTING_RUNS_TO_REVISION_V1()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_blocker_count INTEGER;
    v_case_count INTEGER;
    v_revision_count INTEGER;
    v_evidence_lineage_count INTEGER;
    v_proposal_lineage_count INTEGER;
BEGIN
    v_blocker_count := (
        SELECT COUNT(*)
        FROM (
            SELECT RUN_ID
            FROM ASSESSMENT_RUNS
            WHERE RUN_ID IS NULL

            UNION ALL

            SELECT RUN_ID
            FROM ASSESSMENT_RUNS
            GROUP BY RUN_ID
            HAVING COUNT(*) > 1

            UNION ALL

            SELECT evidence.RUN_ID
            FROM EVIDENCE_ITEMS evidence
            LEFT JOIN ASSESSMENT_RUNS run
              ON run.RUN_ID = evidence.RUN_ID
            WHERE run.RUN_ID IS NULL

            UNION ALL

            SELECT proposal.ASSESSMENT_RUN_ID
            FROM GOVERNANCE_AGENT_PROPOSAL proposal
            LEFT JOIN ASSESSMENT_RUNS run
              ON run.RUN_ID = proposal.ASSESSMENT_RUN_ID
            WHERE run.RUN_ID IS NULL

            UNION ALL

            SELECT decision_record.ASSESSMENT_RUN_ID
            FROM GOVERNED_DECISION_RECORD decision_record
            LEFT JOIN ASSESSMENT_RUNS run
              ON run.RUN_ID = decision_record.ASSESSMENT_RUN_ID
            WHERE run.RUN_ID IS NULL
        ) blockers
    );

    IF (:v_blocker_count > 0) THEN
        RETURN '{"status":"FAILED","error":"Migration blockers detected","blocker_count":' ||
            :v_blocker_count || '}';
    END IF;

    CREATE OR REPLACE TEMPORARY TABLE TMP_REVISION_V1_MIGRATION AS
    SELECT
        'CASE_' || run.RUN_ID AS CASE_ID,
        'REV_' || run.RUN_ID AS REVISION_ID,
        run.RUN_ID,
        run.RUN_NAME AS CASE_NAME,
        run.INITIATIVE_ID,
        run.CREATED_AT,
        COALESCE(
            (SELECT MAX(agent_run.COMPLETED_AT)
             FROM GOVERNANCE_AGENT_RUN agent_run
             WHERE agent_run.ASSESSMENT_RUN_ID = run.RUN_ID),
            run.CREATED_AT
        ) AS GENERATED_AT,
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM GOVERNED_DECISION_RECORD decision_record
                WHERE decision_record.ASSESSMENT_RUN_ID = run.RUN_ID
            ) OR EXISTS (
                SELECT 1
                FROM GOVERNANCE_AGENT_PROPOSAL proposal
                WHERE proposal.ASSESSMENT_RUN_ID = run.RUN_ID
                  AND proposal.STATUS = 'PUBLISHED'
            ) THEN 'PUBLISHED'
            WHEN EXISTS (
                SELECT 1
                FROM GOVERNANCE_AGENT_PROPOSAL proposal
                WHERE proposal.ASSESSMENT_RUN_ID = run.RUN_ID
                  AND proposal.STATUS IN ('REVIEW_REQUIRED', 'APPROVED', 'REJECTED')
            ) THEN 'REVIEW_REQUIRED'
            ELSE 'DRAFT'
        END AS REVISION_STATUS,
        COALESCE(
            (SELECT MAX_BY(history.ACTED_BY, history.ACTED_AT)
             FROM GOVERNANCE_APPROVAL_HISTORY history
             JOIN GOVERNANCE_AGENT_PROPOSAL proposal
               ON proposal.PROPOSAL_ID = history.PROPOSAL_ID
             WHERE proposal.ASSESSMENT_RUN_ID = run.RUN_ID
               AND history.ACTION_TYPE = 'APPROVE'),
            (SELECT MAX_BY(decision_record.PUBLISHED_BY, decision_record.PUBLISHED_AT)
             FROM GOVERNED_DECISION_RECORD decision_record
             WHERE decision_record.ASSESSMENT_RUN_ID = run.RUN_ID)
        ) AS APPROVED_BY,
        COALESCE(
            (SELECT MAX(history.ACTED_AT)
             FROM GOVERNANCE_APPROVAL_HISTORY history
             JOIN GOVERNANCE_AGENT_PROPOSAL proposal
               ON proposal.PROPOSAL_ID = history.PROPOSAL_ID
             WHERE proposal.ASSESSMENT_RUN_ID = run.RUN_ID
               AND history.ACTION_TYPE = 'APPROVE'),
            (SELECT MAX(decision_record.PUBLISHED_AT)
             FROM GOVERNED_DECISION_RECORD decision_record
             WHERE decision_record.ASSESSMENT_RUN_ID = run.RUN_ID)
        ) AS APPROVED_AT,
        COALESCE(
            (SELECT MAX_BY(decision_record.PUBLISHED_BY, decision_record.PUBLISHED_AT)
             FROM GOVERNED_DECISION_RECORD decision_record
             WHERE decision_record.ASSESSMENT_RUN_ID = run.RUN_ID),
            (SELECT MAX_BY(history.ACTED_BY, history.ACTED_AT)
             FROM GOVERNANCE_APPROVAL_HISTORY history
             JOIN GOVERNANCE_AGENT_PROPOSAL proposal
               ON proposal.PROPOSAL_ID = history.PROPOSAL_ID
             WHERE proposal.ASSESSMENT_RUN_ID = run.RUN_ID
               AND history.ACTION_TYPE = 'PUBLISH'),
            CURRENT_USER()
        ) AS PUBLISHED_BY,
        COALESCE(
            (SELECT MAX(decision_record.PUBLISHED_AT)
             FROM GOVERNED_DECISION_RECORD decision_record
             WHERE decision_record.ASSESSMENT_RUN_ID = run.RUN_ID),
            (SELECT MAX(history.ACTED_AT)
             FROM GOVERNANCE_APPROVAL_HISTORY history
             JOIN GOVERNANCE_AGENT_PROPOSAL proposal
               ON proposal.PROPOSAL_ID = history.PROPOSAL_ID
             WHERE proposal.ASSESSMENT_RUN_ID = run.RUN_ID
               AND history.ACTION_TYPE = 'PUBLISH'),
            run.CREATED_AT
        ) AS PUBLISHED_AT
    FROM ASSESSMENT_RUNS run;

    BEGIN TRANSACTION;

    MERGE INTO ASSESSMENT_CASE target
    USING TMP_REVISION_V1_MIGRATION source
      ON target.CASE_ID = source.CASE_ID
    WHEN NOT MATCHED THEN INSERT (
        CASE_ID,
        INITIATIVE_ID,
        CASE_NAME,
        STATUS,
        DATA_ORIGIN,
        CREATED_BY,
        CREATED_AT,
        UPDATED_BY,
        UPDATED_AT
    ) VALUES (
        source.CASE_ID,
        source.INITIATIVE_ID,
        source.CASE_NAME,
        'ACTIVE',
        'MIGRATED',
        CURRENT_USER(),
        source.CREATED_AT,
        CURRENT_USER(),
        CURRENT_TIMESTAMP()
    );

    MERGE INTO ASSESSMENT_REVISION target
    USING TMP_REVISION_V1_MIGRATION source
      ON target.REVISION_ID = source.REVISION_ID
    WHEN NOT MATCHED THEN INSERT (
        REVISION_ID,
        CASE_ID,
        RUN_ID,
        REVISION_NO,
        BASE_REVISION_ID,
        STATUS,
        CHANGE_REASON,
        CREATED_BY,
        CREATED_AT,
        GENERATED_AT,
        APPROVED_BY,
        APPROVED_AT,
        PUBLISHED_BY,
        PUBLISHED_AT
    ) VALUES (
        source.REVISION_ID,
        source.CASE_ID,
        source.RUN_ID,
        1,
        NULL,
        source.REVISION_STATUS,
        'Migrated from existing assessment Run without modifying source records',
        CURRENT_USER(),
        source.CREATED_AT,
        source.GENERATED_AT,
        IFF(source.REVISION_STATUS = 'PUBLISHED', source.APPROVED_BY, NULL),
        IFF(source.REVISION_STATUS = 'PUBLISHED', source.APPROVED_AT, NULL),
        IFF(source.REVISION_STATUS = 'PUBLISHED', source.PUBLISHED_BY, NULL),
        IFF(source.REVISION_STATUS = 'PUBLISHED', source.PUBLISHED_AT, NULL)
    );

    MERGE INTO ASSESSMENT_REVISION_EVIDENCE target
    USING (
        SELECT
            'RE_' || SHA2(migration.REVISION_ID || '|' || evidence.EVIDENCE_ID, 256) AS REVISION_EVIDENCE_ID,
            migration.REVISION_ID,
            evidence.EVIDENCE_ID
        FROM TMP_REVISION_V1_MIGRATION migration
        JOIN EVIDENCE_ITEMS evidence
          ON evidence.RUN_ID = migration.RUN_ID
    ) source
      ON target.REVISION_ID = source.REVISION_ID
     AND target.EVIDENCE_ID = source.EVIDENCE_ID
    WHEN NOT MATCHED THEN INSERT (
        REVISION_EVIDENCE_ID,
        REVISION_ID,
        EVIDENCE_ID,
        ORIGIN_EVIDENCE_ID,
        INHERITED_FROM_EVIDENCE_ID,
        SNAPSHOT_ROLE,
        CHANGE_SET_ID
    ) VALUES (
        source.REVISION_EVIDENCE_ID,
        source.REVISION_ID,
        source.EVIDENCE_ID,
        source.EVIDENCE_ID,
        NULL,
        'BASE',
        NULL
    );

    MERGE INTO GOVERNANCE_PROPOSAL_LINEAGE target
    USING (
        SELECT
            proposal.PROPOSAL_ID,
            migration.REVISION_ID,
            'LI_' || SHA2(proposal.PROPOSAL_ID, 256) AS LOGICAL_ITEM_ID,
            IFF(proposal.STATUS = 'REJECTED', 'SUPERSEDED', 'OPEN') AS ITEM_STATE,
            ARRAY_AGG(DISTINCT source_link.EVIDENCE_ITEM_ID)
                WITHIN GROUP (ORDER BY source_link.EVIDENCE_ITEM_ID) AS SOURCE_EVIDENCE_IDS
        FROM TMP_REVISION_V1_MIGRATION migration
        JOIN GOVERNANCE_AGENT_PROPOSAL proposal
          ON proposal.ASSESSMENT_RUN_ID = migration.RUN_ID
        LEFT JOIN GOVERNANCE_AGENT_PROPOSAL_SOURCE source_link
          ON source_link.PROPOSAL_ID = proposal.PROPOSAL_ID
         AND source_link.EVIDENCE_ITEM_ID IS NOT NULL
        GROUP BY
            proposal.PROPOSAL_ID,
            migration.REVISION_ID,
            proposal.STATUS
    ) source
      ON target.PROPOSAL_ID = source.PROPOSAL_ID
     AND target.REVISION_ID = source.REVISION_ID
    WHEN NOT MATCHED THEN INSERT (
        PROPOSAL_ID,
        REVISION_ID,
        LOGICAL_ITEM_ID,
        PREVIOUS_PROPOSAL_ID,
        CHANGE_TYPE,
        ITEM_STATE,
        CHANGE_REASON,
        SOURCE_EVIDENCE_IDS
    ) VALUES (
        source.PROPOSAL_ID,
        source.REVISION_ID,
        source.LOGICAL_ITEM_ID,
        NULL,
        'NEW',
        source.ITEM_STATE,
        'Baseline item migrated into Revision 1',
        source.SOURCE_EVIDENCE_IDS
    );

    UPDATE ASSESSMENT_CASE target
    SET
        CURRENT_REVISION_ID = source.REVISION_ID,
        UPDATED_BY = CURRENT_USER(),
        UPDATED_AT = CURRENT_TIMESTAMP()
    FROM TMP_REVISION_V1_MIGRATION source
    WHERE target.CASE_ID = source.CASE_ID
      AND target.CURRENT_REVISION_ID IS NULL
      AND target.ACTIVE_DRAFT_REVISION_ID IS NULL
      AND source.REVISION_STATUS = 'PUBLISHED';

    UPDATE ASSESSMENT_CASE target
    SET
        ACTIVE_DRAFT_REVISION_ID = source.REVISION_ID,
        UPDATED_BY = CURRENT_USER(),
        UPDATED_AT = CURRENT_TIMESTAMP()
    FROM TMP_REVISION_V1_MIGRATION source
    WHERE target.CASE_ID = source.CASE_ID
      AND target.CURRENT_REVISION_ID IS NULL
      AND target.ACTIVE_DRAFT_REVISION_ID IS NULL
      AND source.REVISION_STATUS <> 'PUBLISHED';

    COMMIT;

    v_case_count := (SELECT COUNT(*) FROM ASSESSMENT_CASE WHERE DATA_ORIGIN = 'MIGRATED');
    v_revision_count := (SELECT COUNT(*) FROM ASSESSMENT_REVISION WHERE REVISION_NO = 1);
    v_evidence_lineage_count := (SELECT COUNT(*) FROM ASSESSMENT_REVISION_EVIDENCE);
    v_proposal_lineage_count := (SELECT COUNT(*) FROM GOVERNANCE_PROPOSAL_LINEAGE);

    RETURN '{"status":"OK","migrated_cases":' || :v_case_count ||
        ',"revision_1_rows":' || :v_revision_count ||
        ',"evidence_lineage_rows":' || :v_evidence_lineage_count ||
        ',"proposal_lineage_rows":' || :v_proposal_lineage_count || '}';

EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RETURN '{"status":"FAILED","error":"' || LEFT(SQLERRM, 500) || '"}';
END;
$$;
