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
        duplicate = self.ingest(self.raw("duplicate.txt", "```stances\n{\"id\":\"i1\",\"stance\":\"support\"}\n{\"id\":\"i1\",\"stance\":\"reject\"}\n```\n"))
        self.assertEqual(duplicate.stdout, '{"status":"wrong_ids"}\n')
        wrong = self.ingest(self.raw("wrong.txt", "```stances\n{\"id\":\"i1\",\"stance\":\"support\"}\n{\"id\":\"i3\",\"stance\":\"reject\"}\n```\n"))
        self.assertEqual(wrong.stdout, '{"status":"wrong_ids"}\n')
        complete = self.ingest(self.raw("complete.txt", "```stances\n{\"id\":\"i1\",\"stance\":\"support\"}\n{\"id\":\"i2\",\"stance\":\"reject\"}\n```\n"))
        self.assertEqual(complete.stdout, '{"status":"complete"}\n')
        self.assertEqual(self.run_sweep("has", self.run_id, "1", "codex", "b1").returncode, 0)

    def test_resume_drop_and_commit(self):
        self.begin_and_plan()
        complete = self.raw("complete.txt", "```stances\n{\"id\":\"i1\",\"stance\":\"support\"}\n{\"id\":\"i2\",\"stance\":\"reject\"}\n```\n")
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

    def test_plan_rejects_invalid_and_existing_difference(self):
        self.assertEqual(self.run_sweep("begin", self.run_id, "1", "0").returncode, 0)
        invalid = self.tmp / "invalid.json"
        self.write_json(invalid, {"batches": []})
        self.assertEqual(self.run_sweep("plan", self.run_id, "1", "0", invalid).returncode, 2)
        self.assertEqual(self.run_sweep("plan", self.run_id, "1", "0", self.plan).returncode, 0)
        different = self.tmp / "different.json"
        self.write_json(different, {"batches": [{"seat": "codex", "batch": "b1", "expected_ids": ["i1"]}]})
        self.assertEqual(self.run_sweep("plan", self.run_id, "1", "0", different).returncode, 1)


if __name__ == "__main__":
    unittest.main()
