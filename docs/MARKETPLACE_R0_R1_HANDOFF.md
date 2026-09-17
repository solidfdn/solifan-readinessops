# Marketplace release handoff — R0 / R1

Updated: 2026-09-17
Baseline: `a818f954b2f54cb4b86fc6c3fd8d5a6e01d7e51b`

## Complete

- Confirmed local `main` and `origin/main` both equal the agreed baseline; there
  was no newer repository diff at implementation start.
- Added the first Snowflake Native App package structure: project definition,
  manifest, setup script, application roles, references, Streamlit UI, and R1
  validation SQL.
- Declared `SNOWFLAKE.CORTEX_USER` and `READ SESSION`; did not request broad
  imported privileges on the SNOWFLAKE database. Both grants remain explicit
  consumer actions.
- Added separate read-only references for an existing consumer Table and View.
- Added a one-row snapshot and Cortex proposal path. Output is always
  `REVIEW_REQUIRED`; approval, publication, and Current updates are absent.
- Included the bound-reference token, key mapping, title mapping, title, and
  text hash in source identity; duplicate row keys are rejected before Cortex.
- Limited the mutation-capable R1 Streamlit to `READINESSOPS_ADMIN` because
  Native App Streamlit uses owner's rights. `READINESSOPS_USER` receives only
  read-only views.
- Removed file upload from the Native App surface because `st.file_uploader` is
  unsupported there. The existing evaluator app is unchanged.

## Verification result

- Repository contract tests: **28/28 passed** with
  `python -m unittest discover -s tests -v` after the Astra review fixes.
- Python source compilation: passed with
  `python -m compileall -q app native_app/streamlit`.
- Snowflake CLI 3.27.0 local bundle generation: passed with
  `snow app bundle --package-entity-id readinessops_marketplace_package`.
- Git whitespace/error check: passed with `git diff --check`.
- `snowflake.yml` is tracked by the project and no longer excluded by the
  repository `.gitignore`.
- Snowflake Native App installation/runtime: **not verified**.
- Current deployed evaluator objects and privileges vs baseline: **not
  verified**.

The current execution environment did not contain Snowflake CLI, a Snowflake
connector, or a configured Snowflake connection. No Snowflake object, grant,
application package, application, listing, contract, billing setting, or public
state was changed.

## Remaining issues

- Run `snow app run` against an isolated development package and resolve any
  platform syntax/runtime differences.
- Bind real existing Table and View references; validate Cortex and operator
  attribution with two users and negative privilege tests.
- Confirm `mistral-large2` availability in the initial target region.
- R2 still must connect the full governed lifecycle and fix proposal payload,
  Revision publication, Current/Portfolio atomicity, authorization, stale
  decisions, concurrency, retry, and failure injection.

## Next work

1. Execute `snow app run -c <development-connection>` from this repository.
2. Run `scripts/native_app_r1_validation.sql` and retain the output as runtime
   evidence.
3. After R1 runtime acceptance, port the existing governed workflow onto this
   package and start the R2 consistency fixes.
