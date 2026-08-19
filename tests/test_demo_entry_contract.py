import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / "app" / "streamlit_app.py").read_text(encoding="utf-8")
VALUE_CONTROL_PLANE = (
    ROOT / "app" / "value_control_plane.py"
).read_text(encoding="utf-8")


class DemoEntryContractTests(unittest.TestCase):
    def test_active_draft_opens_value_control_plane(self):
        self.assertIn("index=1 if has_active_draft else 0", APP)

    def test_active_draft_opens_revision_workspace(self):
        self.assertIn(
            'initial_section="Revisions" if has_active_draft else "Initiative"',
            APP,
        )
        self.assertIn("index=section_options.index(initial_section)", VALUE_CONTROL_PLANE)

    def test_navigation_uses_revision_specific_widget_keys(self):
        self.assertIn(
            'key=f"workspace_navigation_{assessment_navigation_context}"',
            APP,
        )
        self.assertNotIn('st.session_state["workspace_navigation"]', APP)
        self.assertIn(
            'key=f"vcp_section_nav_{navigation_key or assessment_run_id}"',
            VALUE_CONTROL_PLANE,
        )

    def test_user_facing_copy_uses_revision_not_run(self):
        self.assertNotIn(
            "No completed AI governance review exists for this Assessment Run.",
            APP,
        )
        self.assertIn(
            "This Draft Revision does not yet have a completed governance",
            APP,
        )


if __name__ == "__main__":
    unittest.main()
