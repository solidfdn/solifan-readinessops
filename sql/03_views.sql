-- ============================================================
-- READINESSOPS View: Action Board
-- ============================================================
-- Denormalized view joining all assessment data for presentation.
-- Exact replica of the deployed V_READINESSOPS_ACTION_BOARD.
-- ============================================================

USE SCHEMA READINESSOPS.APP;

CREATE OR REPLACE VIEW V_READINESSOPS_ACTION_BOARD AS
SELECT
  r.RUN_ID,
  r.RUN_NAME,
  r.ORGANIZATION_NAME,
  d.DOMAIN_NAME,
  q.QUESTION_ID,
  q.QUESTION_TEXT,
  a.ANSWER_STATUS,
  e.EVIDENCE_TITLE,
  e.EVIDENCE_STATUS,
  g.GAP_ID,
  g.SEVERITY,
  g.PRIORITY_SCORE,
  g.GAP_TITLE,
  g.GAP_DESCRIPTION,
  act.ACTION_ID,
  act.ACTION_TITLE,
  act.ACTION_DESCRIPTION,
  act.OWNER_NAME,
  act.DUE_IN_DAYS,
  act.ACTION_STATUS,
  act.CREATED_AT AS ACTION_CREATED_AT
FROM ASSESSMENT_RUNS r
JOIN ASSESSMENT_ANSWERS a
  ON r.RUN_ID = a.RUN_ID
JOIN READINESS_QUESTIONS q
  ON a.QUESTION_ID = q.QUESTION_ID
JOIN READINESS_DOMAINS d
  ON q.DOMAIN_ID = d.DOMAIN_ID
LEFT JOIN EVIDENCE_ITEMS e
  ON r.RUN_ID = e.RUN_ID
 AND q.QUESTION_ID = e.QUESTION_ID
LEFT JOIN READINESS_GAPS g
  ON r.RUN_ID = g.RUN_ID
 AND q.QUESTION_ID = g.QUESTION_ID
LEFT JOIN RECOMMENDED_ACTIONS act
  ON r.RUN_ID = act.RUN_ID
 AND g.GAP_ID = act.GAP_ID;
