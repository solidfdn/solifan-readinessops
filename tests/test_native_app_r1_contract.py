import unittest
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]
NATIVE = ROOT / "native_app"
MANIFEST_TEXT = (NATIVE / "manifest.yml").read_text(encoding="utf-8")
MANIFEST = yaml.safe_load(MANIFEST_TEXT)
SETUP = (NATIVE / "setup.sql").read_text(encoding="utf-8")
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
        self.assertEqual(
            app["from"]["target"], "readinessops_marketplace_package"
        )

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

    def test_setup_is_native_app_safe(self):
        upper = SETUP.upper()
        self.assertNotIn("USE DATABASE", upper)
        self.assertNotIn("USE SCHEMA", upper)
        self.assertNotIn("EXECUTE AS CALLER", upper)
        self.assertNotIn("ACCOUNTADMIN", upper)
        self.assertIn("CREATE APPLICATION ROLE", upper)
        self.assertIn("CREATE OR ALTER VERSIONED SCHEMA APP_CODE", upper)

    def test_human_gate_is_structural(self):
        upper = SETUP.upper()
        self.assertIn("'REVIEW_REQUIRED'", upper)
        self.assertNotIn("STATUS = 'APPROVED'", upper)
        self.assertNotIn("STATUS = 'PUBLISHED'", upper)
        self.assertNotIn("SP_PUBLISH", upper)
        self.assertNotIn("CURRENT_REVISION_ID", upper)

    def test_consumer_data_is_read_through_declared_references(self):
        self.assertIn("REFERENCE('EVIDENCE_SOURCE_TABLE')", SETUP)
        self.assertIn("REFERENCE('EVIDENCE_SOURCE_VIEW')", SETUP)
        self.assertIn("SYSTEM$SET_REFERENCE", SETUP)
        self.assertIn("REFERENCE_BINDING_STATE", SETUP)
        self.assertIn("V_MATCH_COUNT > 1", SETUP)
        self.assertIn("CONTENT_SHA256", SETUP)
        self.assertIn("CAPTURED_AT", SETUP)

    def test_cortex_is_fixed_and_output_is_not_self_approved(self):
        self.assertEqual(SETUP.count("SNOWFLAKE.CORTEX.AI_COMPLETE("), 1)
        self.assertIn("mistral-large2", SETUP)
        self.assertIn("R1_EVIDENCE_REVIEW_V1", SETUP)
        self.assertIn("Do not claim approval", SETUP)

    def test_identity_changes_when_source_or_mapping_changes(self):
        identity = SETUP[
            SETUP.index("V_EVIDENCE_ID :=") : SETUP.index("V_PROPOSAL_ID :=")
        ]
        for value in (
            "V_BINDING_TOKEN",
            "SOURCE_KEY_COLUMN",
            "SOURCE_KEY_VALUE",
            "TITLE_COLUMN",
            "TEXT_COLUMN",
            "V_TITLE",
            "V_CONTENT_SHA256",
        ):
            self.assertIn(value, identity)

    def test_native_streamlit_avoids_unsupported_upload(self):
        self.assertNotIn("st.file_uploader", UI)
        self.assertIn("permissions.request_reference", UI)
        self.assertIn("permissions.request_account_privileges", UI)
        self.assertIn("SP_IMPORT_AND_PROPOSE_ONE", UI)
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
