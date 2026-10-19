"""Report regression tests use synthetic fixtures, never experimental results."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

from pptx import Presentation

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("build_report", ROOT / "build_report.py")
report = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(report)


class ReportTests(unittest.TestCase):
    def test_draft_is_explicit_and_packages_no_virtualenv(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            results = root / "results"
            output = root / "submission"
            deck = report.build_deck(ROOT, results)
            self.assertTrue(deck.draft)
            self.assertEqual(len(deck.pages), 13)
            report.write_outputs(deck, output)
            presentation = Presentation(output / "project3_draft.pptx")
            self.assertEqual(len(presentation.slides), 13)
            self.assertTrue((output / "project3_draft.pdf").read_bytes().startswith(b"%PDF"))
            self.assertTrue((output / "approach_walkthrough.gif").is_file())
            archive = report.package(ROOT, results, output, True, False)
            with zipfile.ZipFile(archive) as stream:
                names = stream.namelist()
                self.assertIn("runProject.m", names)
                self.assertIn("presentation/project3_draft.pptx", names)
                self.assertFalse(any(".venv" in name or ".git/" in name for name in names))

    def test_measured_summary_and_infinite_threshold(self):
        metric = {
            "Precision": 0.8, "Recall": 0.6, "TP": 4, "FP": 1, "FN": 3,
            "CorrectLocalization": 4, "AcceptedDetections": 5,
            "LocalizationSuccess": 0.8, "LocalizationSuccessDefined": True,
            "PrecisionDefined": True, "RecallDefined": True,
            "Threshold": None, "MeanSecondsPerFrame": 0.25,
            "EvaluationTargetsMet": True, "AnchorWins": [2, 1, 2],
        }
        fixture = {
            "Status": "Measured on reviewed held-out frames",
            "ValidationFrames": 10, "EvaluationFrames": 12,
            "ValidationTargetPresent": 5, "ValidationTargetAbsent": 5,
            "TargetPresent": 7, "TargetAbsent": 5,
            "Baseline": metric, "Final": metric, "CandidateCenterRecall": 0.8,
        }
        with tempfile.TemporaryDirectory() as temporary:
            results = Path(temporary)
            (results / "summary.json").write_text(json.dumps(fixture), encoding="utf-8")
            deck = report.build_deck(ROOT, results)
            self.assertFalse(deck.draft)
            self.assertEqual(len(deck.pages), 13)
            self.assertIn("80.0%", report.metric_text(metric))
            self.assertIn("reject-all", report.metric_text(metric))

    def test_flags_and_unknown_summary(self):
        self.assertTrue(report.flag("true"))
        self.assertTrue(report.flag("1"))
        self.assertFalse(report.flag("0"))
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary)
            (path / "summary.json").write_text('{"Status": "pending"}', encoding="utf-8")
            with self.assertRaises(ValueError):
                report.build_deck(ROOT, path)


if __name__ == "__main__":
    unittest.main()
