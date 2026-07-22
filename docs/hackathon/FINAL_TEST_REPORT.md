# Final test report

Date: 2026-07-22

## Static validation

- Python syntax: PASS
- Direct `st.dataframe` usage: common compatibility helper only
- Unsupported `hide_index` argument: not used
- Visible table numbering: one-based (`No.`)
- Existing production Streamlit replacement command: not included

## Observed end-to-end test

### Approve

- Needs human decision: `8 → 7`
- Approved, not published: `0 → 1`
- Published governance records: unchanged at `5`
- Approval history written

### Publish

- Approved, not published: `1 → 0`
- Published governance records: `5 → 6`
- Published actions: `1 → 2`
- Canonical Action created

### Audit

Latest events confirmed:

1. `PUBLISH / ACTION / Develop High-Risk AI Review Process`
2. `APPROVE / ACTION / Develop High-Risk AI Review Process`

### UI

- Summary: PASS
- Review by issue: PASS
- Approved & publish: PASS
- Published record list + detail: PASS
- Audit list + detail: PASS
- One-based row numbering: PASS

## Remaining operational note

For a clean live demo, create a new AI Review at the beginning.
This makes the latest Run the active review without deleting historical evidence,
published records, or audit history.
