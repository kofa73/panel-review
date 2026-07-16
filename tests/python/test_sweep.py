import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import uuid


ROOT = Path(__file__).resolve().parents[2]
SWEEP = ROOT / "scripts" / "sweep"


def issue(issue_id):
    return {
        "id": issue_id,
        "claim": "claim",
        "location": "file.c:1",
        "category": "correctness",
        "severity": "high",
        "evidence_pro": [{"location": "file.c:1", "assertion": "evidence"}],
        "evidence_contra": [],
        "peer_reviewed": False,
        "fully_vetted": False,
        "detail_contested": False,
        "state": "open",
        "rounds_debated": 0,
        "card_rev": 0,
    }


class TestSweep(unittest.TestCase):
    def setUp(self):
        self.run_id = f"py-sweep-{uuid.uuid4().hex}"
        self.run_dir = Path("/tmp") / self.run_id
        self.run_dir.mkdir()
        self.tmp = Path(tempfile.mkdtemp(prefix="panel-sweep-"))
        self.write_json(self.run_dir / "index.json", {"run_epoch": 0, "round": 0, "committed_rounds": [], "issues": [issue("i1"), issue("i2"), issue("i3")]})
        self.plan = self.tmp / "plan.json"
        self.write_json(self.plan, {"batches": [{"seat": "codex", "batch": "b1", "expected_ids": ["i1", "i2"]}, {"seat": "claude", "batch": "b1", "expected_ids": ["i1", "i2"]}]})
        self.expected = self.tmp / "expected.ids"
        self.expected.write_text("i1\ni2\n", encoding="utf-8")

    def tearDown(self):
        shutil.rmtree(self.run_dir, ignore_errors=True)
        shutil.rmtree(self.tmp, ignore_errors=True)

    def write_json(self, path, value):
        path.write_text(json.dumps(value), encoding="utf-8")

    def run_sweep(self, *args, input_data=None):
        return subprocess.run([str(SWEEP), *map(str, args)], input=input_data, capture_output=True, text=True)

    def raw(self, name, content):
        path = self.tmp / name
        path.write_text(content, encoding="utf-8")
        return path

    def ingest(self, raw):
        return self.run_sweep("ingest-batch", self.run_id, "1", "0", "codex", "b1", self.expected, raw)

    def begin_and_plan(self):
        self.assertEqual(self.run_sweep("begin", self.run_id, "1", "0").returncode, 0)
        self.assertEqual(self.run_sweep("plan", self.run_id, "1", "0", self.plan).returncode, 0)

    def test_ingest_classification_and_complete_checkpoint(self):
        self.begin_and_plan()
        self.assertEqual(self.ingest(self.tmp / "missing.txt").stdout, '{"status":"missing"}\n')
        self.assertEqual(self.ingest(self.raw("empty.txt", "```stances\n```\n")).stdout, '{"status":"empty"}\n')
        self.assertEqual(self.ingest(self.raw("malformed.txt", "```stances\nnope\n```\n")).stdout, '{"status":"malformed"}\n')
        partial = self.ingest(self.raw("partial.txt", "```stances\n{\"id\":\"i1\",\"stance\":\"support\"}\n```\n"))
        self.assertEqual(partial.stdout, '{"status":"partial"}\n')
        self.assertEqual(self.run_sweep("has", self.run_id, "1", "codex", "b1").returncode, 1)
        duplicate = self.ingest(self.raw("duplicate.txt", "```stances\n{\"id\":\"i1\",\"stance\":\"support\"}\n{\"id\":\"i1\",\"stance\":\"reject\",\"rationale\":\"The issue is not established.\"}\n```\n"))
        self.assertEqual(duplicate.stdout, '{"status":"wrong_ids"}\n')
        wrong = self.ingest(self.raw("wrong.txt", "```stances\n{\"id\":\"i1\",\"stance\":\"support\"}\n{\"id\":\"i3\",\"stance\":\"reject\",\"rationale\":\"The issue is not established.\"}\n```\n"))
        self.assertEqual(wrong.stdout, '{"status":"wrong_ids"}\n')
        missing_new_findings = self.ingest(self.raw("missing-nf.txt", "```stances\n{\"id\":\"i1\",\"stance\":\"support\"}\n{\"id\":\"i2\",\"stance\":\"reject\",\"rationale\":\"The issue is not established.\"}\n```\n"))
        self.assertEqual(missing_new_findings.stdout, '{"status":"missing_new_findings"}\n')
        self.assertEqual(self.run_sweep("has", self.run_id, "1", "codex", "b1").returncode, 1)
        self.assertFalse((self.run_dir / "sweeps" / "round-1" / "codex.b1.stances.json").exists())
        self.assertFalse((self.run_dir / "nf.1.codex.b1.json").exists())
        complete = self.ingest(self.raw("complete.txt", "```stances\n{\"id\":\"i1\",\"stance\":\"support\"}\n{\"id\":\"i2\",\"stance\":\"reject\",\"rationale\":\"The issue is not established.\"}\n```\n```new_findings\n[]\n```\n"))
        self.assertEqual(complete.stdout, '{"status":"complete"}\n')
        self.assertEqual(self.run_sweep("has", self.run_id, "1", "codex", "b1").returncode, 0)
        source = json.loads(
            (self.run_dir / "sweeps" / "round-1" / "codex.b1.source.json").read_text(encoding="utf-8")
        )
        self.assertEqual(source["salvaged"], False)
        self.assertEqual((self.run_dir / "status.nf.1.codex.b1").read_text(encoding="utf-8"), "0\n")

    def test_resume_drop_and_commit(self):
        self.begin_and_plan()
        complete = self.raw("complete.txt", "```stances\n{\"id\":\"i1\",\"stance\":\"support\"}\n{\"id\":\"i2\",\"stance\":\"reject\",\"rationale\":\"The issue is not established.\"}\n```\n```new_findings\n[]\n```\n")
        self.assertEqual(self.ingest(complete).returncode, 0)
        resume = json.loads(self.run_sweep("resume-plan", self.run_id).stdout)
        self.assertEqual([batch["status"] for batch in resume["batches"]], ["complete", "missing"])
        self.assertEqual(self.run_sweep("drop-seat", self.run_id, "1", "codex").returncode, 0)
        resume = json.loads(self.run_sweep("resume-plan", self.run_id).stdout)
        self.assertEqual(resume["batches"][0]["status"], "dropped")
        self.assertEqual(self.ingest(complete).returncode, 1)
        self.assertEqual(self.run_sweep("done", self.run_id, "1").returncode, 1)
        self.assertEqual(self.run_sweep("commit", self.run_id, "1", "0", input_data="{}").returncode, 0)
        self.assertEqual(self.run_sweep("done", self.run_id, "1").returncode, 0)
        self.assertEqual(self.run_sweep("commit", self.run_id, "1", "1", input_data="{}").returncode, 1)

    def test_published_checkpoint_with_missing_companion_is_corrupt(self):
        self.begin_and_plan()
        complete = self.raw("complete.txt", "```stances\n{\"id\":\"i1\",\"stance\":\"support\"}\n{\"id\":\"i2\",\"stance\":\"reject\",\"rationale\":\"The issue is not established.\"}\n```\n```new_findings\n[]\n```\n")
        self.assertEqual(self.ingest(complete).returncode, 0)
        (self.run_dir / "sweeps" / "round-1" / "codex.b1.stances.json").unlink()

        has = self.run_sweep("has", self.run_id, "1", "codex", "b1")
        resume = self.run_sweep("resume-plan", self.run_id)

        self.assertEqual(has.returncode, 2)
        self.assertIn("corrupt complete checkpoint", has.stderr)
        self.assertEqual(resume.returncode, 1)
        self.assertIn("corrupt complete checkpoint", resume.stderr)

    def test_plan_rejects_invalid_and_existing_difference(self):
        self.assertEqual(self.run_sweep("begin", self.run_id, "1", "0").returncode, 0)
        invalid_plans = [
            ([], "plan must be an object"),
            ({}, "plan: top-level 'batches' must be a non-empty list"),
            ({"batches": []}, "plan: top-level 'batches' must be a non-empty list"),
            ({"batches": ["bad"]}, "batch[0] must be an object"),
            ({"batches": [{"seat": "codex", "batch": "1", "ids": ["i1"]}]},
             "batch[0]: unknown key 'ids' (did you mean 'expected_ids'?)"),
            ({"batches": [{"seat": "codex", "batch": "1", "expected_ids": ["i1"]}], "seats": ["codex"]},
             "plan: unknown key 'seats'"),
            ({"batches": [{"seat": "codex", "batch": 1, "expected_ids": ["i1"]}]},
             "batch[0].batch must be a string, got int"),
            ({"batches": [{"seat": 1, "batch": "1", "expected_ids": ["i1"]}]},
             "batch[0].seat must be a string"),
            ({"batches": [{"seat": "codex", "batch": "1", "expected_ids": "i1"}]},
             "batch[0].expected_ids must be a non-empty list"),
            ({"batches": [{"seat": "codex", "batch": "1", "expected_ids": []}]},
             "batch[0].expected_ids must be a non-empty list"),
            ({"batches": [{"seat": "codex", "batch": "1", "expected_ids": ["i1", 2]}]},
             "batch[0].expected_ids[1] must be a non-empty string"),
            ({"batches": [{"seat": "codex", "batch": "1", "expected_ids": ["i1", ""]}]},
             "batch[0].expected_ids[1] must be a non-empty string"),
            ({"batches": [{"seat": "codex", "batch": "1", "expected_ids": ["i1", "i1"]}]},
             "batch[0].expected_ids contains duplicates"),
            ({"batches": [
                {"seat": "codex", "batch": "1", "expected_ids": ["i1"]},
                {"seat": "codex", "batch": "1", "expected_ids": ["i2"]},
            ]}, "duplicate (seat,batch) pair: (codex,1)"),
        ]
        for number, (plan, reason) in enumerate(invalid_plans):
            with self.subTest(reason=reason):
                invalid = self.tmp / f"invalid-{number}.json"
                self.write_json(invalid, plan)
                result = self.run_sweep("plan", self.run_id, "1", "0", invalid)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(result.stderr, f"sweep plan: {reason}\n")

        malformed = self.tmp / "malformed.json"
        malformed.write_text("{", encoding="utf-8")
        result = self.run_sweep("plan", self.run_id, "1", "0", malformed)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stderr, "sweep plan: plan file is unreadable or not valid JSON\n")

        self.assertEqual(self.run_sweep("plan", self.run_id, "1", "0", self.plan).returncode, 0)
        different = self.tmp / "different.json"
        self.write_json(different, {"batches": [{"seat": "codex", "batch": "b1", "expected_ids": ["i1"]}]})
        self.assertEqual(self.run_sweep("plan", self.run_id, "1", "0", different).returncode, 1)

    def test_plan_scaffold_round_trip(self):
        index = json.loads((self.run_dir / "index.json").read_text(encoding="utf-8"))
        index["issues"][2]["state"] = "accepted"
        index["issues"].reverse()
        self.write_json(self.run_dir / "index.json", index)

        scaffold = self.run_sweep("plan-scaffold", self.run_id, "1", "codex", "gemini", "claude")
        self.assertEqual(scaffold.returncode, 0, msg=scaffold.stderr)
        self.assertEqual(json.loads(scaffold.stdout), {"batches": [
            {"seat": "codex", "batch": "1", "expected_ids": ["i1", "i2"]},
            {"seat": "gemini", "batch": "1", "expected_ids": ["i1", "i2"]},
            {"seat": "claude", "batch": "1", "expected_ids": ["i1", "i2"]},
        ]})

        scaffold_path = self.tmp / "scaffold.json"
        scaffold_path.write_text(scaffold.stdout, encoding="utf-8")
        self.assertEqual(self.run_sweep("begin", self.run_id, "1", "0").returncode, 0)
        accepted = self.run_sweep("plan", self.run_id, "1", "0", scaffold_path)
        self.assertEqual(accepted.returncode, 0, msg=accepted.stderr)

    def test_plan_scaffold_rejects_bad_inputs(self):
        no_seats = self.run_sweep("plan-scaffold", self.run_id, "1")
        self.assertEqual(no_seats.returncode, 2)
        self.assertEqual(no_seats.stderr, "sweep plan-scaffold: requires at least one seat\n")

        duplicate = self.run_sweep("plan-scaffold", self.run_id, "1", "codex", "codex")
        self.assertEqual(duplicate.returncode, 2)
        self.assertEqual(duplicate.stderr, "sweep plan-scaffold: duplicate seat: codex\n")

    def test_extend_plan_adds_new_seat_without_replacing_checkpoints(self):
        scaffold = self.run_sweep("plan-scaffold", self.run_id, "1", "claude", "codex")
        scaffold_path = self.tmp / "common.json"
        scaffold_path.write_text(scaffold.stdout, encoding="utf-8")
        self.assertEqual(self.run_sweep("begin", self.run_id, "1", "0").returncode, 0)
        self.assertEqual(self.run_sweep("plan", self.run_id, "1", "0", scaffold_path).returncode, 0)
        self.assertEqual(self.run_sweep("drop-seat", self.run_id, "1", "codex").returncode, 0)

        extended = self.run_sweep("extend-plan", self.run_id, "1", "0", "claude", "gemini")

        self.assertEqual(extended.returncode, 0, extended.stderr)
        plan = json.loads((self.run_dir / "sweeps" / "round-1" / "plan.json").read_text(encoding="utf-8"))
        self.assertEqual([entry["seat"] for entry in plan["batches"]], ["claude", "codex", "gemini"])
        self.assertEqual(plan["dropped_seats"], ["codex"])
        self.assertTrue(all(entry["expected_ids"] == ["i1", "i2", "i3"] for entry in plan["batches"]))

    def test_usage_reachable_without_valid_id(self):
        # Regression for issues-2026-07-04 #1: USAGE must be reachable WITHOUT a run
        # id. If panel_require_id ran before dispatch, `sweep`/`sweep -h`/unknown verb
        # died on "invalid run id: ''" and the interface was undiscoverable.
        for args, code in [((), 2), (("-h",), 0), (("--help",), 0), (("bogus",), 2)]:
            result = self.run_sweep(*args)
            self.assertEqual(result.returncode, code, msg=f"sweep {args}")
            self.assertIn("usage: sweep", result.stdout + result.stderr, msg=f"sweep {args}")
            self.assertNotIn("invalid run id", result.stderr, msg=f"sweep {args}")


if __name__ == "__main__":
    unittest.main()
