import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / "app" / "streamlit_app.py").read_text(encoding="utf-8")


class GovernedAssessmentSelectionContractTests(unittest.TestCase):
    def test_manual_run_selector_is_removed(self):
        self.assertNotIn('st.selectbox(\n    "Assessment Run"', APP)
        self.assertNotIn('"Show historical and standalone runs"', APP)

    def test_selection_is_resolved_from_the_assessment_case(self):
        self.assertIn("FROM ASSESSMENT_CASE case_record", APP)
        self.assertIn("case_record.CURRENT_REVISION_ID", APP)
        self.assertIn("case_record.ACTIVE_DRAFT_REVISION_ID", APP)

    def test_active_draft_is_preferred_over_current_state(self):
        self.assertIn("COALESCE(DRAFT_RUN_ID, CURRENT_RUN_ID)", APP)
        self.assertIn("IFF(DRAFT_RUN_ID IS NOT NULL, 1, 2)", APP)

    def test_only_one_governed_assessment_is_opened(self):
        context_query = APP[
            APP.index("WITH case_catalog AS ("):
            APP.index("except Exception as exc:", APP.index("WITH case_catalog AS ("))
        ]
        self.assertIn("LIMIT 1", context_query)


if __name__ == "__main__":
    unittest.main()
