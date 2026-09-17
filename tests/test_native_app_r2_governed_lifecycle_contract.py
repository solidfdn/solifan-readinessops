import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
NATIVE = ROOT / "native_app"
SETUP = (NATIVE / "setup.sql").read_text(encoding="utf-8")
DECISION_PACK = (NATIVE / "sql" / "decision_pack.sql").read_text(
    encoding="utf-8"
)
LIFECYCLE = (NATIVE / "sql" / "governed_lifecycle.sql").read_text(
    encoding="utf-8"
)
UI = (NATIVE / "streamlit" / "readinessops_native.py").read_text(
    encoding="utf-8"
)


class NativeAppR2GovernedLifecycleContractTests(unittest.TestCase):
    def test_setup_loads_lifecycle_after_generation_contract(self):
        self.assertIn("/sql/decision_pack.sql", SETUP)
        self.assertIn("/sql/governed_lifecycle.sql", SETUP)
        self.assertLess(
            SETUP.index("/sql/governed_lifecycle.sql"),
            SETUP.index("CREATE OR REPLACE VIEW APP_CODE.V_DECISION_PACK_REVIEW"),
        )
        self.assertLess(
            SETUP.index("/sql/governed_lifecycle.sql"),
            SETUP.index("/sql/decision_pack.sql"),
        )

    def test_generated_content_is_normalized_and_hashed(self):
        upper = DECISION_PACK.upper()
        self.assertIn("OBJECT_INSERT", upper)
        self.assertIn("'TITLE', TITLE, TRUE", upper)
        self.assertIn("'DESCRIPTION', DESCRIPTION, TRUE", upper)
        self.assertIn("CONTENT_VERSION = 1", upper)
        self.assertIn("CONTENT_HASH = SHA2", upper)

    def test_edit_updates_payload_version_and_hash_together(self):
        upper = LIFECYCLE.upper()
        edit = upper[
            upper.index("CREATE OR REPLACE PROCEDURE APP_CODE.SP_EDIT_DECISION_PROPOSAL") :
            upper.index("CREATE OR REPLACE PROCEDURE APP_CODE.SP_REVIEW_DECISION_PROPOSAL")
        ]
        for fragment in (
            "PROPOSAL_PAYLOAD = :V_NEW_PAYLOAD",
            "CONTENT_VERSION = :V_NEW_VERSION",
            "CONTENT_HASH = :V_NEW_HASH",
            "STATUS = 'REVIEW_REQUIRED'",
            "CONTENT_VERSION = :P_EXPECTED_CONTENT_VERSION",
            "CONTENT_HASH = :P_EXPECTED_CONTENT_HASH",
            "V_UPDATED := SQLROWCOUNT",
            "ROLLBACK",
        ):
            self.assertIn(fragment, edit)

    def test_review_binds_approval_to_displayed_content(self):
        upper = LIFECYCLE.upper()
        review = upper[
            upper.index("CREATE OR REPLACE PROCEDURE APP_CODE.SP_REVIEW_DECISION_PROPOSAL") :
            upper.index("CREATE OR REPLACE PROCEDURE APP_CODE.SP_PUBLISH_DECISION_PACK")
        ]
        self.assertIn("APPROVED_CONTENT_VERSION", review)
        self.assertIn("APPROVED_CONTENT_HASH", review)
        self.assertIn("CONTENT_VERSION = :P_EXPECTED_CONTENT_VERSION", review)
        self.assertIn("CONTENT_HASH = :P_EXPECTED_CONTENT_HASH", review)
        self.assertIn('"STATUS":"CONFLICT"', review)

    def test_publish_is_atomic_and_uses_approved_normalized_content(self):
        upper = LIFECYCLE.upper()
        publish = upper[
            upper.index("CREATE OR REPLACE PROCEDURE APP_CODE.SP_PUBLISH_DECISION_PACK") :
            upper.index("CREATE OR REPLACE VIEW APP_CODE.V_DECISION_PACK_REVIEW")
        ]
        self.assertIn("BEGIN TRANSACTION", publish)
        self.assertIn("P.PROPOSAL_PAYLOAD", publish)
        self.assertIn("P.CONTENT_VERSION = P.APPROVED_CONTENT_VERSION", publish)
        self.assertIn("P.CONTENT_HASH = P.APPROVED_CONTENT_HASH", publish)
        self.assertIn("V_UPDATED <> 4", publish)
        self.assertIn("COUNT(DISTINCT PROPOSAL_TYPE)", publish)
        self.assertIn("COUNT(DISTINCT ASSESSMENT_RUN_ID)", publish)
        self.assertIn("COUNT(DISTINCT D.DECISION_TYPE)", publish)
        self.assertIn("V_RECORD_COUNT <> 4", publish)
        self.assertIn("V_RECORD_TYPE_COUNT <> 4", publish)
        self.assertIn("V_RECORD_MISMATCH_COUNT <> 0", publish)
        self.assertIn("D.CONTENT_VERSION <> P.APPROVED_CONTENT_VERSION", publish)
        self.assertIn("D.CONTENT_HASH <> P.APPROVED_CONTENT_HASH", publish)
        self.assertIn("ROLLBACK", publish)
        self.assertIn("COMMIT", publish)

    def test_portfolio_never_mixes_decision_pack_runs(self):
        upper = LIFECYCLE.upper()
        portfolio = upper[upper.index("CREATE OR REPLACE VIEW APP_CODE.V_AI_PORTFOLIO") :]
        self.assertIn("GROUP BY INITIATIVE_ID, SOURCE_AGENT_RUN_ID", portfolio)
        self.assertIn("HAVING COUNT(DISTINCT DECISION_TYPE) = 4", portfolio)
        self.assertIn("C.SOURCE_AGENT_RUN_ID = D.SOURCE_AGENT_RUN_ID", portfolio)

    def test_review_and_publish_roles_are_separate(self):
        upper = "\n".join((SETUP, LIFECYCLE)).upper()
        self.assertIn("READINESSOPS_REVIEWER", upper)
        self.assertIn("READINESSOPS_PUBLISHER", upper)
        self.assertIn(
            "SP_REVIEW_DECISION_PROPOSAL(\n    VARCHAR, VARCHAR, NUMBER, VARCHAR, VARCHAR\n) TO APPLICATION ROLE READINESSOPS_REVIEWER",
            upper,
        )
        self.assertIn(
            "SP_PUBLISH_DECISION_PACK(VARCHAR)\n    TO APPLICATION ROLE READINESSOPS_PUBLISHER",
            upper,
        )

    def test_ui_restores_governed_product_surfaces(self):
        for label in (
            "Evidence & Decision Pack",
            "Human review",
            "Published records",
            "AI Portfolio",
            "Save reviewed draft",
            "Approve displayed version",
            "Reject displayed version",
            "Explicitly publish approved Decision Pack",
            "Evidence and execution trace",
        ):
            self.assertIn(label, UI)
        self.assertNotIn("st.file_uploader", UI)

    def test_ui_keeps_the_displayed_review_token_across_reruns(self):
        self.assertIn('snapshot_key = f"review_snapshot_{proposal_id}"', UI)
        self.assertIn('displayed_snapshot = st.session_state[snapshot_key]', UI)
        self.assertIn('expected_version = int(displayed_snapshot["content_version"])', UI)
        self.assertIn('expected_hash = str(displayed_snapshot["content_hash"])', UI)
        self.assertIn("Reload displayed version", UI)
        self.assertIn("disabled=(not read_session_granted or current_changed)", UI)
        self.assertNotIn("st.session_state.pop(snapshot_key", UI)
        self.assertIn('publication_target_key = "publication_target_run"', UI)
        self.assertIn('confirmation_key = f"publish_confirm_{selected_agent_run_id}"', UI)
        self.assertIn("if all_approved:", UI)
        self.assertNotIn("st.session_state[confirmation_key] = False\n        show_result", UI)


if __name__ == "__main__":
    unittest.main()
