# Hackathon Submission

## Project

**SOLIFAN ReadinessOps — Human-Governed AI Readiness Management on Snowflake**

## One-Sentence Description

A Snowflake-native governance workspace that uses Cortex AI to generate evidence-grounded Gap, Risk, and Action drafts, requires human approval or rejection, and publishes only approved items to canonical governance records.

## Problem

Organizations need more than a one-time AI readiness score. They need a repeatable operating process that connects:

```text
Question → Evidence → Gap → Risk → Action
```

A direct-write AI agent is unsafe because a generated recommendation can become the system of record without human accountability.

## Solution

ReadinessOps separates AI analysis from governance authority:

1. Read Assessment Run answers and evidence
2. Generate Gap, Risk, and Action proposals with Snowflake Cortex AI
3. Store every proposal as `REVIEW_REQUIRED`
4. Show source evidence to the reviewer
5. Approve or reject individual proposals with comments
6. Publish only approved proposals
7. Store decision and publication history
8. Present only canonical records in the dashboard

## Application Screenshots

### Governance Review Summary

![Governance review summary](../assets/screenshots/app_ss_01.png)

### Natural-Language AI Review Setup

![Natural-language AI review setup](../assets/screenshots/app_ss_02.png)

### Human Decision and Publication Audit

![Human decision and publication audit](../assets/screenshots/app_ss_03.png)
## Evaluation Criteria Mapping

### Technical Execution

| Aspect | Implementation |
|---|---|
| Snowflake-native | Data, AI inference, procedures, Streamlit, and history remain in Snowflake |
| Cortex AI integration | `SNOWFLAKE.CORTEX.COMPLETE('mistral-large2', ...)` |
| Structured output | JSON containing `gaps`, `risks`, and `actions` |
| Safe parsing | Fence stripping and `TRY_PARSE_JSON` |
| Type normalization | Priority normalization and safe numeric casts |
| Governance state | `REVIEW_REQUIRED`, `APPROVED`, `REJECTED`, `PUBLISHED` |
| Human review | `SP_REVIEW_AGENT_PROPOSAL` with reviewer comment |
| Controlled publication | `SP_PUBLISH_AGENT_RUN` publishes approved proposals only |
| Traceability | Proposal source rows link back to Question, Answer, Evidence, and Rule |
| Auditability | Review and publication events in `GOVERNANCE_APPROVAL_HISTORY` |
| Idempotency | Duplicate canonical publication is prevented |
| Presentation safety | Dashboard excludes legacy `AR_%` direct-write output |

### Solution Completeness

| Component | Status |
|---|---|
| Assessment data model | Complete |
| Governance agent run model | Complete |
| Gap/Risk/Action proposal model | Complete |
| Proposal-source traceability | Complete |
| Human approval and rejection | Complete |
| Controlled publication | Complete |
| Approval and publication history | Complete |
| Canonical dashboard view | Complete |
| Streamlit governance workspace | Complete |
| Validation SQL | Complete |
| Documentation and demo guide | Complete |

### Real-World Relevance

- **Users:** CCoE teams, AI governance leads, risk managers, program owners, and executive sponsors
- **Decision boundary:** AI proposes; accountable people decide
- **Operational model:** Assessment history supports repeated maturity reviews
- **Evidence model:** Every proposal is inspectable before approval
- **Integration value:** Published Snowflake records can feed BI, Cortex, and AI-agent workflows
- **Scalability:** The same governance lifecycle can be applied across domains and repeated Assessment Runs

## Built With CoCo CLI

The implementation was developed and validated through Snowflake Cortex Code CLI workflows:

1. Live schema inspection
2. SQL procedure development
3. Cortex output testing
4. Failure diagnosis
5. Read-only validation
6. Streamlit deployment
7. Governance lifecycle verification
8. Repository and documentation updates

## Verified Results

The demonstrated full review generated:

| Metric | Value |
|---|---:|
| Gaps generated | 5 |
| Risks generated | 2 |
| Actions generated | 5 |
| Total draft proposals | 12 |

The human-governance test verified:

| Decision | Result |
|---|---|
| Gap | Approved and published |
| Risk | Rejected and not published |
| Action | Approved and published |
| Published Gap records | 1 |
| Published Action records | 1 |
| Gap history records | 2 |
| Action history records | 2 |
| Risk history records | 1 |

## Why It Matters

ReadinessOps demonstrates that an AI governance product should not stop at diagnosis and should not allow AI output to silently become truth. It operationalizes the accountable path from evidence to action while keeping the system of record under human control.

## Relationship to SOLIFAN CCoE Readiness Studio

ReadinessOps is the governed agent workflow for the broader SOLIFAN CCoE Readiness Studio concept: an Enterprise AI Governance operating platform that tracks readiness over time and connects assessment evidence to gaps, risks, decisions, and actions.