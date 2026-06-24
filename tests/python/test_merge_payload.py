"""Black-box coverage for the merge_payload Python port."""

import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import uuid


ROOT = Path(__file__).resolve().parents[2]
MERGE = ROOT / "scripts" / "merge_payload"
INDEX = ROOT / "scripts" / "index"


def issue(issue_id="i4", severity="medium"):
    return {
        "id": issue_id,
        "claim": "Existing claim.",
        "location": "src/file.py:1",
        "category": "correctness",
        "severity": severity,
        "evidence_pro": [{"assertion": "Observed behavior.", "location": "src/file.py:1"}],
        "evidence_contra": [],
        "peer_reviewed": False,
        "fully_vetted": False,
        "detail_contested": False,
        "state": "open",
        "rounds_debated": 0,
        "card_rev": 0,
    }


class MergePayloadTest(unittest.TestCase):
    def setUp(self):
        self.directory = Path(tempfile.mkdtemp(prefix="merge-payload-"))

    def tearDown(self):
        shutil.rmtree(self.directory, ignore_errors=True)

    def write_base(self, value):
        path = self.directory / "base.json"
        path.write_text(json.dumps(value), encoding="utf-8")
        return path

    def run_merge(self, base_path=None, addendum=""):
        args = [str(MERGE)]
        if base_path is not None:
            args.append(str(base_path))
        return subprocess.run(args, input=addendum, text=True, capture_output=True, check=False)

    def test_finding_three_merges_and_commits(self):
        base = {
            "bump": ["i4"],
            "set_state": [{"id": "i4", "state": "accepted"}],
            "set_flag": [
                {"id": "i4", "flag": "peer_reviewed", "value": True},
                {"id": "i4", "flag": "fully_vetted", "value": True},
            ],
            "revise": [{"id": "i4", "fields": {"severity": "low"}}],
            "add_evidence": [{"id": "i4", "side": "contra", "point": {"location": "analysis", "assertion": "base"}}],
        }
        addendum = {
            "set_state": [{"id": "i4", "state": "open"}],
            "revise": [{"id": "i4", "fields": {"claim": "synth claim"}}],
            "add_issues": [issue("i7", "low")],
        }
        result = self.run_merge(self.write_base(base), json.dumps(addendum))
        self.assertEqual(result.returncode, 0, result.stderr)
        merged = json.loads(result.stdout)
        self.assertEqual(merged["set_state"], [{"id": "i4", "state": "open"}])
        self.assertEqual(merged["revise"], [{"id": "i4", "fields": {"severity": "low", "claim": "synth claim"}}])
        self.assertEqual(len({change["id"] for change in merged["set_state"]}), len(merged["set_state"]))
        self.assertEqual(len({change["id"] for change in merged["revise"]}), len(merged["revise"]))
        self.assertEqual(merged["add_evidence"], base["add_evidence"])
        self.assertEqual(merged["add_issues"], addendum["add_issues"])

        run_id = f"py-merge-{uuid.uuid4().hex}"
        run_dir = Path("/tmp") / run_id
        run_dir.mkdir()
        self.addCleanup(shutil.rmtree, run_dir, True)
        (run_dir / "index.json").write_text(
            json.dumps({"issues": [issue()], "round": 0, "phase": "debate", "committed_rounds": [], "run_epoch": 0}),
            encoding="utf-8",
        )
        commit = subprocess.run(
            [str(INDEX), "commit-sweep", run_id, "1", "0"],
            input=json.dumps(merged),
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(commit.returncode, 0, commit.stderr)
        committed = json.loads((run_dir / "index.json").read_text(encoding="utf-8"))
        i4 = next(item for item in committed["issues"] if item["id"] == "i4")
        self.assertEqual((i4["state"], i4["severity"], i4["claim"]), ("open", "low", "synth claim"))
        self.assertEqual(next(item for item in committed["issues"] if item["id"] == "i7")["state"], "open")

        appended = {"set_state": base["set_state"] + addendum["set_state"]}
        appended_run_id = f"{run_id}-append"
        appended_run_dir = Path("/tmp") / appended_run_id
        appended_run_dir.mkdir()
        self.addCleanup(shutil.rmtree, appended_run_dir, True)
        (appended_run_dir / "index.json").write_text(
            json.dumps({"issues": [issue()], "round": 0, "phase": "debate", "committed_rounds": [], "run_epoch": 0}),
            encoding="utf-8",
        )
        rejection = subprocess.run(
            [str(INDEX), "commit-sweep", appended_run_id, "1", "0"],
            input=json.dumps(appended),
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(rejection.returncode, 1)

    def test_empty_addendum_returns_base_without_empty_keys(self):
        base = {"bump": ["i4"], "add_issues": [], "evaluated_by": {}}
        result = self.run_merge(self.write_base(base))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), {"bump": ["i4"]})

    def test_bump_union_is_sorted_unique_and_addendum_overrides_evaluated_by(self):
        base = {"bump": ["i3", "i1", "i3"], "evaluated_by": {"i1": ["codex"], "i2": ["gemini"]}}
        addendum = {"bump": ["i2", "i1"], "evaluated_by": {"i1": ["claude"]}}
        result = self.run_merge(self.write_base(base), json.dumps(addendum))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), {"bump": ["i1", "i2", "i3"], "evaluated_by": {"i1": ["claude"], "i2": ["gemini"]}})

    def test_error_paths(self):
        cases = [
            (self.run_merge(), 2, "usage: merge_payload <base.json>   (addendum on stdin)\n"),
            (self.run_merge(self.directory / "missing.json"), 1, f"merge_payload: no such base file: {self.directory / 'missing.json'}\n"),
            (self.run_merge(self.write_base([])), 2, "merge_payload: base is not a JSON object\n"),
            (self.run_merge(self.write_base({}), "[]"), 2, "merge_payload: addendum is not a JSON object\n"),
        ]
        for result, code, error in cases:
            with self.subTest(error=error):
                self.assertEqual(result.returncode, code)
                self.assertEqual(result.stderr, error)


if __name__ == "__main__":
    unittest.main()
