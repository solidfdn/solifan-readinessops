import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / "app" / "streamlit_app.py").read_text(encoding="utf-8")
VALUE_CONTROL_PLANE = (
    ROOT / "app" / "value_control_plane.py"
).read_text(encoding="utf-8")


class AssessmentContextHeaderContractTests(unittest.TestCase):
    def test_run_selector_and_history_checkbox_are_removed(self):
        self.assertNotIn('st.selectbox(\n    "Assessment Run"', APP)
        self.assertNotIn('"Show historical and standalone runs"', APP)

    def test_context_is_resolved_at_assessment_case_level(self):
        self.assertIn("FROM ASSESSMENT_CASE case_record", APP)
        self.assertIn("case_record.CURRENT_REVISION_ID", APP)
        self.assertIn("case_record.ACTIVE_DRAFT_REVISION_ID", APP)
        self.assertIn("COALESCE(DRAFT_RUN_ID, CURRENT_RUN_ID)", APP)

    def test_active_draft_is_preferred_and_selected_automatically(self):
        self.assertIn("IFF(DRAFT_RUN_ID IS NOT NULL, 1, 2)", APP)
        self.assertIn(
            'selected_run_id = text(assessment_context["SELECTED_RUN_ID"])',
            APP,
        )

    def test_header_explains_draft_and_published_state(self):
        self.assertIn('st.caption("Assessment")', APP)
        self.assertIn('st.caption(f"Organization: {organization_name}")', APP)
        self.assertIn("Reviewing Revision", APP)
        self.assertIn("remains the published", APP)
        self.assertIn("No Draft Revision is active", APP)

    def test_revision_history_remains_in_the_revision_workspace(self):
        self.assertIn("Revision history and comparison", VALUE_CONTROL_PLANE)
        self.assertIn("Frozen decision comparison", VALUE_CONTROL_PLANE)


if __name__ == "__main__":
    unittest.main()
