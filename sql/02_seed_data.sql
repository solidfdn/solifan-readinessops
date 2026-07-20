-- ============================================================
-- READINESSOPS Seed Data: Synthetic sample data for RUN_001
-- ============================================================
-- All data below is synthetic and public-safe.
-- Does NOT include AI-generated output (AR_% rows).
--
-- RERUN BEHAVIOR:
-- This script uses DELETE + INSERT for deterministic reruns.
-- Running it multiple times produces the same state every time.
-- Only sample rows (GAP_%, ACT_%, AGENT_RUN_%) are affected.
-- AI-generated rows (AR_%) are never touched by this script.
-- ============================================================

USE SCHEMA READINESSOPS.APP;

-- ============================================================
-- 1. Assessment Run
-- ============================================================
DELETE FROM ASSESSMENT_RUNS WHERE RUN_ID = 'RUN_001';

INSERT INTO ASSESSMENT_RUNS (RUN_ID, RUN_NAME, ORGANIZATION_NAME, ASSESSMENT_SCOPE, STATUS)
VALUES ('RUN_001', 'AI Readiness Baseline Assessment', 'Sample Enterprise', 'Enterprise AI and Data Governance', 'IN_REVIEW');

-- ============================================================
-- 2. Readiness Domains
-- ============================================================
DELETE FROM READINESS_DOMAINS WHERE DOMAIN_ID IN ('D01', 'D02', 'D03', 'D04');

INSERT INTO READINESS_DOMAINS (DOMAIN_ID, DOMAIN_NAME, DOMAIN_DESCRIPTION, SORT_ORDER) VALUES
('D01', 'Strategy and Ownership', 'Clarifies executive ownership, decision rights, and AI adoption priorities.', 1),
('D02', 'Data and Evidence', 'Checks whether policies, documents, and operational evidence support the assessment.', 2),
('D03', 'Risk and Governance', 'Reviews risks, controls, approval processes, and accountability.', 3),
('D04', 'Execution and Improvement', 'Confirms whether gaps are converted into accountable actions.', 4);

-- ============================================================
-- 3. Readiness Questions
-- ============================================================
DELETE FROM READINESS_QUESTIONS WHERE QUESTION_ID IN ('Q001', 'Q002', 'Q003', 'Q004', 'Q005');

INSERT INTO READINESS_QUESTIONS (QUESTION_ID, DOMAIN_ID, QUESTION_TEXT, EXPECTED_EVIDENCE, WEIGHT, SORT_ORDER) VALUES
('Q001', 'D01', 'Is there a named executive owner for the AI and data program?', 'Executive sponsor memo or governance charter', 25, 1),
('Q002', 'D01', 'Are decision rights for AI use cases clearly documented?', 'Decision matrix or operating model document', 25, 2),
('Q003', 'D02', 'Are key policies and evidence documents linked to readiness answers?', 'Policy documents, meeting notes, or evidence register', 25, 3),
('Q004', 'D03', 'Is there a documented review process for high-risk AI use cases?', 'Risk review workflow or approval checklist', 25, 4),
('Q005', 'D04', 'Are readiness gaps converted into prioritized actions with owners and due dates?', 'Action tracker or improvement plan', 25, 5);

-- ============================================================
-- 4. Assessment Answers
-- ============================================================
DELETE FROM ASSESSMENT_ANSWERS WHERE RUN_ID = 'RUN_001';

INSERT INTO ASSESSMENT_ANSWERS (RUN_ID, QUESTION_ID, ANSWER_STATUS, ANSWER_TEXT, OWNER_NAME) VALUES
('RUN_001', 'Q001', 'ANSWERED', 'The CIO is the executive sponsor, but the role is not yet reflected in the formal governance charter.', NULL),
('RUN_001', 'Q002', 'UNCONFIRMED', 'Decision rights are discussed in meetings but not consistently documented.', NULL),
('RUN_001', 'Q003', 'UNKNOWN', 'Some policies exist, but they are not linked to individual assessment answers.', NULL),
('RUN_001', 'Q004', 'NOT_PREPARED', 'No formal high-risk AI review workflow has been prepared.', NULL),
('RUN_001', 'Q005', 'UNCONFIRMED', 'Actions are discussed manually, but ownership and due dates are not always tracked.', NULL);

-- ============================================================
-- 5. Evidence Items
-- ============================================================
DELETE FROM EVIDENCE_ITEMS WHERE RUN_ID = 'RUN_001';

INSERT INTO EVIDENCE_ITEMS (EVIDENCE_ID, RUN_ID, QUESTION_ID, EVIDENCE_TITLE, EVIDENCE_TEXT, EVIDENCE_STATUS) VALUES
('EV_001', 'RUN_001', 'Q001', 'Draft AI Governance Charter', 'The CIO is mentioned as sponsor. However, operating responsibilities and escalation rules are still marked as draft.', 'PARTIAL'),
('EV_002', 'RUN_001', 'Q002', 'AI Steering Committee Notes', 'The committee discussed decision rights, but no approved decision matrix was attached.', 'PARTIAL'),
('EV_003', 'RUN_001', 'Q003', 'Evidence Register', 'Evidence is stored across folders. Several readiness answers do not have linked supporting documents.', 'INSUFFICIENT'),
('EV_004', 'RUN_001', 'Q004', 'Risk Review Notes', 'High-risk use cases are reviewed case by case. There is no standard approval checklist.', 'INSUFFICIENT'),
('EV_005', 'RUN_001', 'Q005', 'Manual Action List', 'Improvement items are listed, but owners and due dates are missing for several items.', 'PARTIAL');

-- ============================================================
-- 6. Sample Gaps (pre-populated baseline, NOT AI-generated)
-- ============================================================
DELETE FROM READINESS_GAPS WHERE GAP_ID LIKE 'GAP_%' AND RUN_ID = 'RUN_001';

INSERT INTO READINESS_GAPS (GAP_ID, RUN_ID, DOMAIN_ID, QUESTION_ID, GAP_TITLE, GAP_DESCRIPTION, SEVERITY, PRIORITY_SCORE) VALUES
('GAP_001', 'RUN_001', 'D01', 'Q001', 'Gap in Q001: Is there a named executive owner for the AI and data program?', 'The available evidence only partially supports the readiness answer.', 'MEDIUM', 60),
('GAP_002', 'RUN_001', 'D01', 'Q002', 'Gap in Q002: Are decision rights for AI use cases clearly documented?', 'The answer is not yet confirmed by sufficient evidence or formal approval.', 'MEDIUM', 65),
('GAP_003', 'RUN_001', 'D02', 'Q003', 'Gap in Q003: Are key policies and evidence documents linked to readiness answers?', 'The current state is unknown and supporting evidence is missing or not linked.', 'HIGH', 85),
('GAP_004', 'RUN_001', 'D03', 'Q004', 'Gap in Q004: Is there a documented review process for high-risk AI use cases?', 'The organization has not prepared the required process or evidence for this readiness item.', 'HIGH', 90),
('GAP_005', 'RUN_001', 'D04', 'Q005', 'Gap in Q005: Are readiness gaps converted into prioritized actions with owners and due dates?', 'The answer is not yet confirmed by sufficient evidence or formal approval.', 'MEDIUM', 65);

-- ============================================================
-- 7. Sample Recommended Actions (pre-populated baseline)
-- ============================================================
DELETE FROM RECOMMENDED_ACTIONS WHERE ACTION_ID LIKE 'ACT_%' AND RUN_ID = 'RUN_001';

INSERT INTO RECOMMENDED_ACTIONS (ACTION_ID, RUN_ID, GAP_ID, ACTION_TITLE, ACTION_DESCRIPTION, OWNER_NAME, DUE_IN_DAYS, ACTION_STATUS) VALUES
('ACT_001', 'RUN_001', 'GAP_004', 'Define a high-risk AI review workflow', 'Create a standard review process for high-risk AI use cases, including approval criteria, reviewers, escalation rules, and required evidence.', 'Risk Manager', 30, 'PROPOSED'),
('ACT_002', 'RUN_001', 'GAP_003', 'Link evidence documents to readiness answers', 'Create an evidence register that links each readiness answer to supporting policies, meeting notes, or control documents.', 'Data Governance Lead', 30, 'PROPOSED'),
('ACT_003', 'RUN_001', 'GAP_002', 'Formalize AI decision rights', 'Document who can approve, pause, escalate, or reject AI use cases, and publish the decision matrix for program stakeholders.', 'Program Lead', 60, 'PROPOSED'),
('ACT_004', 'RUN_001', 'GAP_005', 'Create an accountable readiness action tracker', 'Convert open readiness gaps into actions with owners, due dates, status, and review cadence.', 'PMO Lead', 60, 'PROPOSED'),
('ACT_005', 'RUN_001', 'GAP_001', 'Finalize executive ownership in the governance charter', 'Update the governance charter to clearly name the executive sponsor, operating owner, and escalation path.', 'Program Lead', 60, 'PROPOSED');

-- ============================================================
-- 8. Sample Agent Run History (documents intended workflow steps)
-- ============================================================
DELETE FROM AGENT_RUN_HISTORY WHERE AGENT_RUN_ID LIKE 'AGENT_RUN_%' AND RUN_ID = 'RUN_001';

INSERT INTO AGENT_RUN_HISTORY (AGENT_RUN_ID, RUN_ID, AGENT_STEP, INPUT_SUMMARY, OUTPUT_SUMMARY) VALUES
('AGENT_RUN_001', 'RUN_001', 'LOAD_ASSESSMENT', 'Loaded 5 readiness answers and 5 evidence items for RUN_001.', 'Assessment baseline was prepared for evidence validation.'),
('AGENT_RUN_002', 'RUN_001', 'VALIDATE_EVIDENCE', 'Compared answer status with evidence status across all readiness questions.', 'Detected partial or insufficient evidence for 5 readiness items.'),
('AGENT_RUN_003', 'RUN_001', 'DETECT_GAPS', 'Evaluated UNKNOWN, UNCONFIRMED, NOT_PREPARED, PARTIAL, and INSUFFICIENT statuses.', 'Generated 5 readiness gaps with severity and priority scores.'),
('AGENT_RUN_004', 'RUN_001', 'GENERATE_ACTIONS', 'Converted prioritized gaps into recommended actions with owners and due dates.', 'Generated 5 proposed actions for the readiness improvement plan.');
