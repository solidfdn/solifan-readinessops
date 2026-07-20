# Architecture

## System Overview

ReadinessOps is an AI-powered assessment agent that evaluates organizational readiness
for AI adoption. It reads structured assessment data, calls Snowflake Cortex AI to
identify gaps, and writes prioritized remediation actions back to the database.

## Data Flow

```mermaid
graph LR
    subgraph Input Tables
        AR[ASSESSMENT_RUNS]
        AA[ASSESSMENT_ANSWERS]
        EI[EVIDENCE_ITEMS]
        RQ[READINESS_QUESTIONS]
        RD[READINESS_DOMAINS]
    end

    subgraph Agent Procedure
        SP[SP_RUN_READINESS_AGENT]
    end

    subgraph Cortex AI
        LLM[mistral-large2]
    end

    subgraph Output Tables
        RG[READINESS_GAPS]
        RA[RECOMMENDED_ACTIONS]
        AH[AGENT_RUN_HISTORY]
    end

    subgraph Presentation
        VW[V_READINESSOPS_ACTION_BOARD]
        ST[Streamlit Dashboard]
    end

    AR --> SP
    AA --> SP
    EI --> SP
    RQ --> SP
    RD --> SP
    SP -->|prompt| LLM
    LLM -->|JSON| SP
    SP --> RG
    SP --> RA
    SP --> AH
    RG --> VW
    RA --> VW
    VW --> ST
```

## Agent Pipeline Steps

| Step | Name | What Happens |
|:---:|------|--------------|
| 1 | LOAD_ASSESSMENT | Read answers + evidence for the target run |
| 2 | VALIDATE_EVIDENCE | Construct prompt with all assessment context |
| 3 | DETECT_GAPS | Call Cortex AI, strip fences, validate JSON |
| 4 | GENERATE_ACTIONS | Parse gaps + actions, write to tables |

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Single stored procedure | Smallest deployable unit; no external dependencies |
| Transaction wrapping | Atomic success/failure; DELETEs roll back with INSERTs |
| AR_ prefix on IDs | Cleanly separates AI output from seed data |
| TRY_PARSE_JSON | Graceful failure instead of unhandled exception |
| REGEXP_REPLACE for fences | LLMs frequently ignore "no markdown" instructions |
| TRY_CAST via VARCHAR | Snowflake's TRY_CAST rejects VARIANT directly |
| INNER JOIN for actions | Prevents orphan rows with NULL GAP_ID |
| Millisecond timestamp IDs | Avoids collisions without UUID overhead |

## Table Relationships

```mermaid
erDiagram
    ASSESSMENT_RUNS ||--o{ ASSESSMENT_ANSWERS : "RUN_ID"
    READINESS_QUESTIONS ||--o{ ASSESSMENT_ANSWERS : "QUESTION_ID"
    READINESS_DOMAINS ||--o{ READINESS_QUESTIONS : "DOMAIN_ID"
    ASSESSMENT_RUNS ||--o{ EVIDENCE_ITEMS : "RUN_ID"
    READINESS_QUESTIONS ||--o{ EVIDENCE_ITEMS : "QUESTION_ID"
    ASSESSMENT_RUNS ||--o{ READINESS_GAPS : "RUN_ID"
    READINESS_QUESTIONS ||--o{ READINESS_GAPS : "QUESTION_ID"
    READINESS_GAPS ||--o{ RECOMMENDED_ACTIONS : "GAP_ID"
    ASSESSMENT_RUNS ||--o{ AGENT_RUN_HISTORY : "RUN_ID"
```

## Snowflake Features Used

- **Cortex AI** — `SNOWFLAKE.CORTEX.COMPLETE()` for LLM inference
- **SQL Scripting** — Stored procedure with variables, transactions, exception handling
- **Semi-structured data** — VARIANT, FLATTEN, TRY_PARSE_JSON for JSON processing
- **Views** — Denormalized action board for presentation layer
- **Streamlit in Snowflake** — Interactive dashboard with agent trigger button
