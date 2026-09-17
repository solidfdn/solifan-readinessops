import unittest
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]
NATIVE = ROOT / "native_app"
MANIFEST_TEXT = (NATIVE / "manifest.yml").read_text(encoding="utf-8")
MANIFEST = yaml.safe_load(MANIFEST_TEXT)
SETUP = (NATIVE / "setup.sql").read_text(encoding="utf-8")
IMPORT = (NATIVE / "sql" / "import_reference_evidence.sql").read_text(
    encoding="utf-8"
)
DECISION_PACK = (NATIVE / "sql" / "decision_pack.sql").read_text(
    encoding="utf-8"
)
UI = (NATIVE / "streamlit" / "readinessops_native.py").read_text(
    encoding="utf-8"
)
PROJECT = yaml.safe_load((ROOT / "snowflake.yml").read_text(encoding="utf-8"))


class NativeAppR1ContractTests(unittest.TestCase):
    def test_project_has_package_and_installable_application(self):
        entities = PROJECT["entities"]
        package = entities["readinessops_marketplace_package"]
        app = entities["readinessops_marketplace_dev"]
        self.assertEqual(package["type"], "application package")
        self.assertEqual(package["manifest"], "native_app/manifest.yml")
        self.assertEqual(app["type"], "application")
        self.assertEqual(app["from"]["target"], "readinessops_marketplace_package")

    def test_manifest_declares_minimum_cortex_role_and_read_only_references(self):
        privileges = MANIFEST["privileges"]
        self.assertTrue(any("READ SESSION" in privilege for privilege in privileges))
        roles = MANIFEST["snowflake_database"]["roles"]
        self.assertTrue(any("CORTEX_USER" in role for role in roles))
        self.assertNotIn("IMPORTED PRIVILEGES", MANIFEST_TEXT.upper())

        references = {
            next(iter(item)): next(iter(item.values()))
            for item in MANIFEST["references"]
        }
        self.assertEqual(references["EVIDENCE_SOURCE_TABLE"]["object_type"], "TABLE")
        self.assertEqual(references["EVIDENCE_SOURCE_VIEW"]["object_type"], "VIEW")
        for reference in references.values():
            self.assertEqual(reference["privileges"], ["SELECT"])
            self.assertFalse(reference["multi_valued"])

    def test_setup_is_native_app_safe_and_modular(self):
        combined = "\n".join((SETUP, IMPORT, DECISION_PACK)).upper()
        self.assertNotIn("USE DATABASE", combined)
        self.assertNotIn("USE SCHEMA", combined)
        self.assertNotIn("EXECUTE AS CALLER", combined)
        self.assertNotIn("ACCOUNTADMIN", combined)
        self.assertIn("CREATE APPLICATION ROLE", combined)
        self.assertIn("CREATE OR ALTER VERSIONED SCHEMA APP_CODE", combined)
        self.assertIn("EXECUTE IMMEDIATE FROM '/SQL/IMPORT_REFERENCE_EVIDENCE.SQL'", combined)
        self.assertIn("EXECUTE IMMEDIATE FROM '/SQL/DECISION_PACK.SQL'", combined)

    def test_existing_readinessops_model_is_used_without_parallel_proposal_model(self):
        combined = "\n".join((SETUP, IMPORT, DECISION_PACK)).upper()
        for table in (
            "AI_INITIATIVE",
            "ASSESSMENT_RUNS",
            "EVIDENCE_ITEMS",
            "GOVERNANCE_AGENT_RUN",
            "GOVERNANCE_AGENT_PROPOSAL",
            "GOVERNANCE_AGENT_PROPOSAL_SOURCE",
            "GOVERNANCE_AGENT_RUN_STEP",
        ):
            self.assertIn(f"APP_DATA.{table}", combined)
        self.assertNotIn("APP_DATA.AI_PROPOSAL", combined)
        self.assertNotIn("APP_DATA.EVIDENCE_SNAPSHOT", combined)
        self.assertNotIn("SP_IMPORT_AND_PROPOSE_ONE", combined)

    def test_decision_pack_contract_is_the_existing_four_sections(self):
        upper = DECISION_PACK.upper()
        self.assertEqual(upper.count("SNOWFLAKE.CORTEX.AI_COMPLETE("), 1)
        self.assertEqual(upper.count("'LLAMA3.1-8B'"), 1)
        self.assertNotIn("MISTRAL-LARGE2", upper)
        self.assertIn("MODEL => :V_MODEL_NAME", upper)
        self.assertIn("DECISION_PACK_V2", upper)
        for proposal_type in (
            "DECISION_GOVERNANCE",
            "DECISION_VALUE",
            "DECISION_MODEL_ROUTING",
            "DECISION_PORTFOLIO",
        ):
            self.assertIn(f"'{proposal_type}'", upper)
        self.assertIn("'PROPOSAL_COUNT', 4", upper)
        self.assertIn("'REVIEW_REQUIRED'", upper)

    def test_human_gate_is_structural(self):
        combined = "\n".join((SETUP, IMPORT, DECISION_PACK, UI)).upper()
        self.assertIn("'REVIEW_REQUIRED'", combined)
        self.assertNotIn("STATUS = 'APPROVED'", combined)
        self.assertNotIn("STATUS = 'PUBLISHED'", combined)
        self.assertNotIn("SP_PUBLISH", combined)
        self.assertNotIn("SP_APPROVE", combined)

    def test_operator_attribution_fails_closed_in_both_mutation_procedures(self):
        for procedure in (IMPORT, DECISION_PACK):
            self.assertIn("CURRENT_USER()", procedure)
            self.assertIn("IS NULL) THEN", procedure)
            self.assertIn("READ SESSION is required", procedure)
        self.assertIn("disabled=not read_session_granted", UI)

    def test_failed_decision_pack_run_steps_do_not_depend_on_proposals(self):
        self.assertIn("r.ASSESSMENT_RUN_ID", SETUP)
        self.assertIn("JOIN APP_DATA.GOVERNANCE_AGENT_RUN r", SETUP)
        self.assertIn("WHERE s.ASSESSMENT_RUN_ID = ?", UI)
        self.assertNotIn("JOIN APP_CODE.V_DECISION_PACK_REVIEW p", UI)

    def test_native_streamlit_uses_supported_page_config(self):
        self.assertIn('st.set_page_config(layout="wide")', UI)
        self.assertNotIn("page_title=", UI)

    def test_consumer_data_is_mapped_into_existing_evidence(self):
        upper = IMPORT.upper()
        self.assertIn("REFERENCE('EVIDENCE_SOURCE_TABLE')", upper)
        self.assertIn("REFERENCE('EVIDENCE_SOURCE_VIEW')", upper)
        self.assertIn("INSERT INTO APP_DATA.EVIDENCE_ITEMS", upper)
        self.assertIn("MERGE INTO APP_DATA.AI_INITIATIVE", upper)
        self.assertIn("MERGE INTO APP_DATA.ASSESSMENT_RUNS", upper)
        self.assertIn("V_MATCH_COUNT > 1", upper)
        self.assertIn("CONTENT_SHA256", upper)

    def test_reference_row_object_is_built_only_in_select_clause(self):
        upper = IMPORT.upper()
        self.assertEqual(
            upper.count("SELECT OBJECT_CONSTRUCT_KEEP_NULL(*) AS ROW_OBJECT"),
            4,
        )
        self.assertNotIn(
            "GET_IGNORE_CASE(\n                   OBJECT_CONSTRUCT_KEEP_NULL(*)",
            upper,
        )

    def test_evidence_values_use_materialized_procedure_variables(self):
        upper = IMPORT.upper()
        evidence_values = upper[
            upper.index("INSERT INTO APP_DATA.EVIDENCE_ITEMS") :
            upper.index("COMMIT;", upper.index("INSERT INTO APP_DATA.EVIDENCE_ITEMS"))
        ]
        self.assertIn(":V_SOURCE_TYPE", evidence_values)
        self.assertIn(":V_CHAR_COUNT", evidence_values)
        self.assertNotIn("'REFERENCE_' || :V_SOURCE_KIND", evidence_values)
        self.assertNotIn("LENGTH(:V_TEXT)", evidence_values)

    def test_identity_changes_when_source_mapping_or_content_changes(self):
        identity = IMPORT[
            IMPORT.index("v_evidence_id :=") : IMPORT.index("BEGIN TRANSACTION")
        ].upper()
        for value in (
            "V_BINDING_TOKEN",
            "P_SOURCE_KEY_COLUMN",
            "P_SOURCE_KEY_VALUE",
            "P_TITLE_COLUMN",
            "P_TEXT_COLUMN",
            "V_TITLE",
            "V_CONTENT_SHA256",
        ):
            self.assertIn(value, identity)

    def test_assessment_identity_is_explicit_and_independent_of_evidence(self):
        upper = IMPORT.upper()
        self.assertIn("P_ASSESSMENT_RUN_ID STRING", upper)
        self.assertIn("P_INITIATIVE_ID STRING", upper)
        self.assertIn("V_RUN_ID := TRIM(P_ASSESSMENT_RUN_ID)", upper)
        self.assertIn("V_INITIATIVE_ID := TRIM(P_INITIATIVE_ID)", upper)
        self.assertNotIn("V_INITIATIVE_ID := 'INIT_'", upper)
        self.assertIn("ASSESSMENT ID IS ALREADY LINKED", upper)
        merge_end = upper.index("SELECT COUNT(*)", upper.index("MERGE INTO APP_DATA.ASSESSMENT_RUNS"))
        self.assertGreater(merge_end, upper.index("MERGE INTO APP_DATA.AI_INITIATIVE"))

    def test_native_streamlit_uses_ported_workflow(self):
        self.assertNotIn("st.file_uploader", UI)
        self.assertIn("permissions.request_reference", UI)
        self.assertIn("permissions.request_account_privileges", UI)
        self.assertIn("SP_IMPORT_REFERENCE_EVIDENCE", UI)
        self.assertIn("SP_GENERATE_DECISION_PACK", UI)
        self.assertIn("V_DECISION_PACK_REVIEW", UI)
        self.assertNotIn("SP_PUBLISH", UI)

    def test_mutating_streamlit_is_admin_only(self):
        grant = (
            "GRANT USAGE ON STREAMLIT APP_CODE.READINESSOPS\n"
            "    TO APPLICATION ROLE READINESSOPS_ADMIN;"
        )
        self.assertIn(grant, SETUP)
        self.assertNotIn(
            "GRANT USAGE ON STREAMLIT APP_CODE.READINESSOPS\n"
            "    TO APPLICATION ROLE READINESSOPS_USER;",
            SETUP,
        )


if __name__ == "__main__":
    unittest.main()
