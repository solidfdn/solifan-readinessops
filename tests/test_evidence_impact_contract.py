import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROCEDURE = (ROOT / "sql/34_evidence_impact_procedure.sql").read_text(encoding="utf-8")
FOUNDATION = (ROOT / "sql/33_evidence_impact_foundation.sql").read_text(encoding="utf-8")
UI = (ROOT / "app/value_control_plane.py").read_text(encoding="utf-8")
DEPLOY = (ROOT / "scripts/deploy_evidence_impact_analysis.ps1").read_text(encoding="utf-8")


class EvidenceImpactContractTest(unittest.TestCase):
    def test_single_cortex_call_and_versioned_inputs(self):
        self.assertEqual(PROCEDURE.count("AI_COMPLETE("), 1)
        self.assertIn("mistral-large2", PROCEDURE)
        self.assertIn("EVIDENCE_IMPACT_V1", PROCEDURE)
        self.assertIn("INPUT_FINGERPRINT", FOUNDATION)

    def test_exact_four_decision_sections_are_contractual(self):
        required = (
            "DECISION_GOVERNANCE",
            "DECISION_VALUE",
            "DECISION_MODEL_ROUTING",
            "DECISION_PORTFOLIO",
        )
        for section in required:
            self.assertIn(section, PROCEDURE)
        self.assertIn("v_output_count <> 4", PROCEDURE)
        self.assertIn("v_distinct_section_count <> 4", PROCEDURE)
        self.assertNotIn("minItems", PROCEDURE)
        self.assertNotIn("maxItems", PROCEDURE)

    def test_procedure_cannot_write_governed_state(self):
        forbidden_tables = (
            "ASSESSMENT_CASE",
            "ASSESSMENT_REVISION",
            "GOVERNANCE_AGENT_PROPOSAL",
            "GOVERNED_DECISION_RECORD",
            "ASSESSMENT_REVISION_DELTA",
            "GOVERNANCE_PROPOSAL_LINEAGE",
        )
        for table in forbidden_tables:
            pattern = rf"(?is)\b(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+{table}\b"
            self.assertIsNone(re.search(pattern, PROCEDURE), table)

    def test_changed_evidence_citations_are_validated(self):
        self.assertIn("V_REVISION_EVIDENCE_CHANGE", PROCEDURE)
        self.assertIn("v_invalid_source_count", PROCEDURE)
        self.assertIn("SNAPSHOT_ROLE IN ('ADDED', 'REPLACED')", FOUNDATION)

    def test_ui_preserves_human_authority(self):
        self.assertIn("CALL SP_ANALYZE_REVISION_EVIDENCE_IMPACT(?)", UI)
        self.assertIn("AI analysis — human confirmation required", UI)
        self.assertNotIn("CALL SP_PUBLISH_ASSESSMENT_REVISION", UI[UI.index("def _render_evidence_impact_analysis"):UI.index("def _render_revision_history")])

    def test_deployment_order(self):
        positions = [
            DEPLOY.index("33_evidence_impact_foundation.sql"),
            DEPLOY.index("34_evidence_impact_procedure.sql"),
            DEPLOY.index("35_evidence_impact_validation.sql"),
        ]
        self.assertEqual(positions, sorted(positions))


if __name__ == "__main__":
    unittest.main()
