import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / "app" / "streamlit_app.py").read_text(encoding="utf-8")


class RunSelectorContractTests(unittest.TestCase):
    def test_catalog_assigns_explicit_run_roles(self):
        self.assertIn("THEN 'CURRENT'", APP)
        self.assertIn("THEN 'DRAFT'", APP)
        self.assertIn("THEN 'HISTORY'", APP)
        self.assertIn("ELSE 'STANDALONE'", APP)

    def test_current_run_is_ordered_first(self):
        current = APP.index("WHEN 'CURRENT' THEN 1")
        draft = APP.index("WHEN 'DRAFT' THEN 2")
        standalone = APP.index("WHEN 'STANDALONE' THEN 3")
        history = APP.index("WHEN 'HISTORY' THEN 4")
        self.assertLess(current, draft)
        self.assertLess(draft, standalone)
        self.assertLess(standalone, history)

    def test_label_exposes_role_revision_and_status(self):
        self.assertIn('f"{role} | {assessment_name}{revision_label}"', APP)
        self.assertIn('f" | Revision {integer(revision_no)}"', APP)
        self.assertIn("run_row['ORGANIZATION_NAME']", APP)
        self.assertIn('f" | {text(run_row[\'STATUS\'])}"', APP)

    def test_history_and_standalone_are_hidden_by_default(self):
        self.assertIn('"Show historical and standalone runs"', APP)
        self.assertIn(
            'runs_df["RUN_ROLE"].isin(["CURRENT", "DRAFT"])',
            APP,
        )
        self.assertIn("if show_other_runs or visible_runs_df.empty:", APP)


if __name__ == "__main__":
    unittest.main()
