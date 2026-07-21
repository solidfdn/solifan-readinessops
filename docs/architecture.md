# Architecture

## Purpose

ReadinessOps is a Snowflake-native governance workspace. It analyzes an Assessment Run, generates evidence-grounded Gap, Risk, and Action drafts, requires human review, and publishes only approved proposals to canonical governance tables.

The central control is separation between **AI-generated proposals** and **published records**.

## End-to-End Flow

```mermaid
flowchart TD
    subgraph Assessment Context
        AR[ASSESSMENT_RUNS]
        RQ[READINESS_QUESTIONS]
        AA[ASSESSMENT_ANSWERS]
        EI[EVIDENCE_ITEMS]
    end

    subgraph Governed Generation
        SP1[SP_RUN_FULL_GOVERNANCE_REVIEW]
        CX[SNOWFLAKE.CORTEX.COMPLETE]
        GR[GOVERNANCE_AGENT_RUN]
        GP[GOVERNANCE_AGENT_PROPOSAL]
        GS[GOVERNANCE_AGENT_PROPOSAL_SOURCE]
    end

    subgraph Human Decision
        ST[Streamlit Governance Agent Workspace]
        SP2[SP_REVIEW_AGENT_PROPOSAL]
        AH[GOVERNANCE_APPROVAL_HISTORY]
    end

    subgraph Controlled Publication
        SP3[SP_PUBLISH_AGENT_RUN]
        RG[READINESS_GAPS]
        RA[RECOMMENDED_ACTIONS]
        VW[V_READINESSOPS_ACTION_BOARD]
    end

    AR --> SP1
    RQ --> SP1
    AA --> SP1
    EI --> SP1
    SP1 --> CX
    CX --> SP1
    SP1 --> GR
    SP1 --> GP
    SP1 --> GS

    GP --> ST
    GS --> ST
    ST --> SP2
    SP2 --> GP
    SP2 --> AH

    GP --> SP3
    SP3 --> RG
    SP3 --> RA
    SP3 --> AH
    RG --> VW
    RA --> VW
    VW --> ST
```

## Governance State Model

```mermaid
stateDiagram-v2
    [*] --> REVIEW_REQUIRED
    REVIEW_REQUIRED --> APPROVED: Human approves
    REVIEW_REQUIRED --> REJECTED: Human rejects
    APPROVED --> PUBLISHED: Controlled publish
    REJECTED --> [*]
    PUBLISHED --> [*]
```

AI output is initially stored as `REVIEW_REQUIRED`. It cannot appear as a new canonical governance record until it is `APPROVED` and processed by `SP_PUBLISH_AGENT_RUN`.

## Data Responsibilities

| Object | Responsibility |
|---|---|
| `ASSESSMENT_RUNS` | Assessment execution container |
| `READINESS_QUESTIONS` | Question and expected-evidence rule |
| `ASSESSMENT_ANSWERS` | Current answer for a run and question |
| `EVIDENCE_ITEMS` | Supplied supporting evidence |
| `GOVERNANCE_AGENT_RUN` | Review execution, model, instruction, status, timestamps, fingerprint, and summary |
| `GOVERNANCE_AGENT_PROPOSAL` | Gap, Risk, or Action proposal and review state |
| `GOVERNANCE_AGENT_PROPOSAL_SOURCE` | Proposal-to-source traceability |
| `GOVERNANCE_APPROVAL_HISTORY` | Approval, rejection, and publication events |
| `READINESS_GAPS` | Canonical published Gap records |
| `RECOMMENDED_ACTIONS` | Canonical published Action records |
| `V_READINESSOPS_ACTION_BOARD` | Dashboard presentation of canonical records |

## Procedures

### `SP_RUN_FULL_GOVERNANCE_REVIEW`

Inputs:

- Assessment Run ID
- Optional additional instruction

Behavior:

1. Validates the Assessment Run
2. Creates a governance agent run
3. Builds a prompt from Question, Answer, Evidence, and Rule context
4. Calls Snowflake Cortex AI
5. Strips optional markdown fences and parses JSON safely
6. Creates Gap, Risk, and Action proposals
7. Normalizes priority values
8. Creates source-traceability rows
9. Marks the run `COMPLETED` or `FAILED`

The optional instruction can set a business priority or time horizon, but it does not replace the standard evidence-grounding rule.

### `SP_REVIEW_AGENT_PROPOSAL`

Inputs:

- Proposal ID
- `APPROVE` or `REJECT`
- Review comment

Behavior:

- Updates one proposal only
- Records reviewer identity and timestamp
- Writes a decision event to `GOVERNANCE_APPROVAL_HISTORY`
- Does not publish canonical records

### `SP_PUBLISH_AGENT_RUN`

Input:

- Agent Run ID

Behavior:

- Reads only `APPROVED` proposals
- Writes approved Gaps and Actions to canonical tables
- Leaves rejected and unreviewed proposals unpublished
- Stores source proposal and agent-run identifiers
- Updates proposal state to `PUBLISHED`
- Writes publication history
- Prevents duplicate canonical records on repeat execution

## Traceability

Each proposal can be traced to:

```text
Assessment Run
  → Question
  → Answer
  → Evidence Item
  → Expected Evidence / Rule
  → Agent Run
  → Proposal
  → Human Decision
  → Published Record
```

This allows a reviewer to inspect why a proposal exists before approving it.

## Presentation Layer

`V_READINESSOPS_ACTION_BOARD` is the canonical dashboard source. The governed update excludes legacy `AR_%` records created by the earlier direct-write prototype. Draft, rejected, and merely approved proposals stay outside dashboard results until publication.

## Key Design Decisions

| Decision | Rationale |
|---|---|
| Separate proposals from canonical tables | Prevents AI output from silently becoming the system of record |
| Human decision per proposal | Enables selective approval and rejection |
| Controlled publication step | Separates review from write authority |
| Immutable history | Supports audit and operational accountability |
| Source table per proposal | Makes evidence grounding inspectable |
| Input fingerprint | Supports repeatability and run comparison |
| Priority normalization | Handles model output that uses either 1–5 or 1–100 scales |
| Stable proposal-type selector | Prevents review actions from being applied under a different UI category after reruns |
| Canonical dashboard filter | Keeps legacy direct-write output out of governed results |

## Snowflake Features

- `SNOWFLAKE.CORTEX.COMPLETE()` for inference
- SQL stored procedures for governed workflows
- `VARIANT`, `FLATTEN`, and `TRY_PARSE_JSON` for structured model output
- Streamlit in Snowflake for human review
- Views for presentation
- Snowflake identity and timestamps for decision history