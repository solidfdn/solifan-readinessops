import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / "app" / "streamlit_app.py").read_text(encoding="utf-8")


class DemoEntryContractTests(unittest.TestCase):
    def test_active_draft_opens_value_control_plane(self):
        self.assertIn(
            '"Value Control Plane" if has_active_draft else "Review queue"',
            APP,
        )

    def test_active_draft_opens_revision_workspace(self):
        self.assertIn(
            '"Revisions" if has_active_draft else "Initiative"',
            APP,
        )

    def test_navigation_is_only_reset_when_assessment_context_changes(self):
        self.assertIn('st.session_state.get("assessment_navigation_context")', APP)
        self.assertIn(
            'st.session_state["assessment_navigation_context"]',
            APP,
        )
        navigation_block = APP.split(
            'if (\n    st.session_state.get("assessment_navigation_context")',
            1,
        )[1].split("\n\nworkspace = st.radio(", 1)[0]
        self.assertIn("rerun_app()", navigation_block)

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
