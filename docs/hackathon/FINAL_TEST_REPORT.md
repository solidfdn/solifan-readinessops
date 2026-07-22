# Final Test Report

Date: 2026-07-22

## Static Validation

- Python syntax: PASS
- Unsupported `hide_index`: not used
- Streamlit boolean arguments: native Python `bool`
- Rerun compatibility helper: present
- Visible table numbering: one-based (`No.`)
- Back-to-review navigation: present
- Production source: Git-tracked `app/streamlit_app.py`

## End-to-End Governance Tests

### Generation

A completed review produced:

| Type | Count |
|---|---:|
| Gap | 5 |
| Risk | 2 |
| Action | 5 |
| Total | 12 |

### Approval

Observed:

- Needs human decision decreased
- Approved, not published increased
- Published governance records did not change
- Approval history was written

### Publication

Observed:

- Approved, not published returned to zero for the selected proposal
- Published governance records increased
- Governed Action record was created
- Publication history was written

### Audit

Confirmed separate events:

1. `PUBLISH / ACTION`
2. `APPROVE / ACTION`

### Additional Lifecycle Checks

- Gap approval and publication: PASS
- Risk rejection without publication: PASS
- Action approval and publication: PASS
- Duplicate publication prevention: PASS
- Source Proposal and Agent Run traceability: PASS
- Published record list and detail: PASS
- Audit list and detail: PASS
- One-based numbering: PASS
- Empty publication-state Back button: PASS
- Production dashboard display: PASS
- Git `main` synchronization: PASS

## Production Object

```text
READINESSOPS_VALIDATION.APP.READINESSOPS_DASHBOARD
```

## Operational Note

Live counts change after each review, decision, and publication. The stable acceptance criteria are the state transitions, traceability, duplicate prevention, and separation between AI proposal and human publication authority.
