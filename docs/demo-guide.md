# Finalist Demo Guide

## Goal

Demonstrate the complete evidence-to-decision lifecycle without allowing AI to approve or publish its own output:

```text
Initiative → TXT/PDF Evidence → 4-section Decision Pack
→ Human Review → Explicit Publication → Portfolio + Audit
```

## Prerequisites

- `READINESSOPS_VALIDATION.APP.READINESSOPS_DASHBOARD` deployed
- isolated Assessment Run `RUN_FINALIST_E2E_001` selected
- an AI Initiative linked to that Run
- one small synthetic TXT file and one small synthetic PDF file
- Cortex model and `AI_PARSE_DOCUMENT` access

Do not use or modify `RUN_001` during the finalist demonstration.

## Four-Minute Demo

### 0:00–0:25 — Establish the control boundary

Show the four steps at the top of the application and select **Value Control Plane**.

Say:

> ReadinessOps keeps AI analysis inside a governed workflow. Evidence enters Snowflake, Cortex proposes four decision sections, a person decides, and only an explicit publication creates the governed record.

### 0:25–0:50 — Show the AI Initiative

Open **Initiative**.

Show:

- selected Assessment: **Finalist E2E Validation**
- linked initiative: **Claims Triage AI — E2E**
- owner and stage

Explain that the initiative is the portfolio unit and the Assessment Run supplies its current evidence context.

### 0:50–1:25 — Upload and retain evidence

Open **Evidence** and upload the synthetic TXT and PDF files.

Show:

- successful validation message
- TXT/PDF source type
- extracted character count
- PDF page count and parser
- SHA-256 and stored stage path

Explain:

> The original file is retained in a Snowflake stage. TXT is decoded directly; PDF is parsed with Cortex document intelligence. The extracted text and provenance metadata become governed evidence inputs.

### 1:25–2:05 — Generate the Decision Pack

Open **Decision Pack** and select **Generate**.

Show the completed Agent Run and its five governed execution steps:

1. Input validation
2. Context assembly
3. Cortex generation
4. Output validation
5. Draft persistence

Confirm `5 recorded`, `5 completed`, `0 running`, and `0 failed`, then show the four tabs:

1. Governance
2. Value
3. Routing
4. Portfolio

Open one section and show:

- AI Draft status
- title and summary
- priority and rationale
- structured detail
- source evidence IDs

Explain:

> The procedure rejects incomplete output, invalid priorities, or evidence IDs that do not belong to this Assessment Run. Generation creates drafts only.

For recording, run Cortex generation once. Retakes should reuse the completed Agent Run screen rather than create additional runs.

### 2:05–2:50 — Make accountable decisions

Approve each of the four sections. Optionally demonstrate **Edit before deciding** on one section.

Show:

- status changes from **AI Draft** to **Human Reviewed**
- decision actor and timestamp
- approved count increasing
- publication button remaining disabled until confirmation is checked

Explain:

> Approval records a human decision but still does not create a governed record.

### 2:50–3:20 — Publish explicitly

Select **Confirm publication of approved sections**, then **Publish**.

Show:

- `Published 4 decision(s)`
- **Published Governed Record** status

Explain:

> Publication is a separate authority boundary. The procedure accepts only approved proposals and prevents duplicate governed writes and duplicate publication history.

### 3:20–3:45 — Show outcomes

Open **Published** and show all four Governed Decision Records. Then open **Portfolio** and show:

- one initiative
- Governance state
- Value assessment
- recommendation
- priority

### 3:45–4:00 — Verify history and safety

Open **Audit trail** and show the separate `APPROVE` and `PUBLISH` events with actor and timestamp.

Close with:

> ReadinessOps turns evidence into an accountable decision system: AI proposes, people decide, and Snowflake preserves the source, state, and history.

## Verified E2E Result

The completed isolated run produced:

| Check | Result |
|---|---:|
| Decision Pack proposals | 4 |
| Governed Decision Records | 4 |
| APPROVE + PUBLISH events | 8 |
| Uploaded evidence items | TXT and PDF verified |
| Proposal leakage into `RUN_001` | 0 |

The demonstration also confirmed original-file retention, PDF parsing, strict output-schema validation, portfolio presentation, and successful production Streamlit deployment.

## Optional Read-Only Verification

Use a query scoped to the demonstrated Agent Run and `RUN_FINALIST_E2E_001` to confirm proposal, audit, evidence, and `RUN_001` isolation counts. Do not create or modify data during final verification.

## Rehearsal Notes

- Use the already validated isolated Run unless a fresh run is necessary.
- Avoid repeatedly generating Decision Packs; each successful generation creates a new Agent Run.
- Keep uploaded files synthetic and small.
- Explain state transitions rather than relying on fixed dashboard totals.
- If live Cortex latency threatens the time limit, show the completed run and its governed records instead of regenerating.
