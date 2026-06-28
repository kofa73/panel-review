"""Black-box coverage for the Python index migration."""

import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import uuid


ROOT = Path(__file__).resolve().parents[2]
INDEX = ROOT / "scripts" / "index"
sys.path.insert(0, str(ROOT / "scripts"))
import panel_common  # noqa: E402


def issue(issue_id="i1", state="open", severity="medium", peer=False, vetted=False, contested=False):
    return {
        "id": issue_id,
        "claim": "A concrete claim.",
        "location": "src/file.py:1",
        "category": "correctness",
        "severity": severity,
        "evidence_pro": [{"assertion": "Observed behavior.", "location": "src/file.py:1"}],
        "evidence_contra": [],
        "peer_reviewed": peer,
        "fully_vetted": vetted,
        "detail_contested": contested,
        "state": state,
        "rounds_debated": 0,
        "card_rev": 0,
    }


class IndexTest(unittest.TestCase):
    def setUp(self):
        self.run_id = f"py-index-{uuid.uuid4().hex}"
        self.run_dir = Path("/tmp") / self.run_id
        self.run_dir.mkdir()
        self.index_path = self.run_dir / "index.json"
        self.write_index({"issues": [issue("i1"), issue("i2", severity="low")], "round": 0, "run_epoch": 0, "committed_rounds": [], "evaluated_by": {}})

    def tearDown(self):
        shutil.rmtree(self.run_dir, ignore_errors=True)

    def write_index(self, value):
        self.index_path.write_text(json.dumps(value), encoding="utf-8")

    def read_index(self):
        return json.loads(self.index_path.read_text(encoding="utf-8"))

    def run_index(self, *args, input_data=None):
        return subprocess.run([str(INDEX), *args], input=input_data, text=True, capture_output=True, check=False)

    def commit(self, payload, round_number=1, epoch=0):
        return self.run_index("commit-sweep", self.run_id, str(round_number), str(epoch), input_data=json.dumps(payload))

    def test_panel_common_helpers(self):
        self.assertTrue(panel_common.panel_valid_id("valid.1-_"))
        self.assertFalse(panel_common.panel_valid_id("../escape"))
        self.assertFalse(panel_common.panel_valid_id(".."))
        self.assertTrue(panel_common.valid_location(["a:1", "b:2"]))
        self.assertFalse(panel_common.valid_point({"assertion": "x", "location": []}))
        target_dir = Path(tempfile.mkdtemp(prefix="panel-common-"))
        self.addCleanup(shutil.rmtree, target_dir, True)
        target = target_dir / "state.json"
        panel_common.panel_atomic_write(str(target), b"one")
        panel_common.panel_atomic_write(str(target), "two")
        self.assertEqual(target.read_bytes(), b"two")
        self.assertEqual((target_dir / "state.json.bak").read_bytes(), b"one")

    def test_gate_status_variants(self):
        result = self.run_index("gate-status", self.run_id)
        self.assertEqual(result.stdout, '{"open":2,"low_only":false}\n')
        data = self.read_index()
        for item in data["issues"]:
            item["severity"] = "low"
        self.write_index(data)
        self.assertEqual(self.run_index("gate-status", self.run_id).stdout, '{"open":2,"low_only":true}\n')
        for item in data["issues"]:
            item.update({"state": "accepted", "peer_reviewed": True})
        self.write_index(data)
        self.assertEqual(self.run_index("gate-status", self.run_id).stdout, '{"open":0,"low_only":false}\n')

    def test_state_validates_and_bumps_card_revision(self):
        result = self.run_index("state", self.run_id, "i1", "contested")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(self.read_index()["issues"][0]["state"], "contested")
        self.assertEqual(self.read_index()["issues"][0]["card_rev"], 1)
        result = self.run_index("state", self.run_id, "i1", "bad")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stderr, "index state: bad state bad (allowed: open|accepted|rejected|contested|unresolved|merged)\n")

    def test_commit_happy_path_idempotency_and_evaluated_by(self):
        payload = {"bump": ["i1"], "set_flag": [{"id": "i1", "flag": "peer_reviewed", "value": True}], "evaluated_by": {"i1": ["codex", "claude"]}}
        self.assertEqual(self.commit(payload).returncode, 0)
        data = self.read_index()
        self.assertEqual(data["round"], 1)
        self.assertEqual(data["issues"][0]["rounds_debated"], 1)
        self.assertEqual(data["evaluated_by"]["i1"], ["codex", "claude"])
        self.assertEqual(self.commit(payload).returncode, 0)
        self.assertEqual(self.read_index()["issues"][0]["rounds_debated"], 1)

    def test_commit_writes_audit_trail(self):
        audit_file = self.run_dir / "audit" / "round-1.md"
        payload = {
            "add_issues": [issue("i3", state="open")],
            "bump": ["i1"],
            "set_state": [{"id": "i1", "state": "accepted"}],
            "set_flag": [{"id": "i1", "flag": "peer_reviewed", "value": True}],
            "add_evidence": [{"id": "i2", "side": "contra", "point": {"assertion": "A counterpoint.", "location": "src/file.py:2"}}],
            "revise": [{"id": "i2", "fields": {"severity": "high"}}],
            "evaluated_by": {"i1": ["codex", "claude"]},
        }
        self.assertEqual(self.commit(payload).returncode, 0)
        self.assertTrue(audit_file.exists())
        text = audit_file.read_text(encoding="utf-8")
        for marker in (
            "# Round 1 audit",
            "## New issues", "`i3`",
            "## State changes", "`i1`: open → accepted",
            "## Flag changes", "peer_reviewed",
            "## Revisions", "`i2` severity",
            "## Evidence added", "`i2` contra",
            "## Coverage (evaluated_by)", "`i1`: codex, claude",
            "## Rounds debated bumped",
        ):
            self.assertIn(marker, text)
        # The trail is inspection-only: an idempotent re-commit of an already-committed
        # round must not regenerate it (nothing is re-applied, so nothing is re-audited).
        audit_file.unlink()
        self.assertEqual(self.commit(payload).returncode, 0)
        self.assertFalse(audit_file.exists())

    def test_commit_empty_round_writes_no_audit(self):
        # A round that applies no field mutations leaves no audit file (only non-empty
        # trails are persisted), yet still commits and advances the round counter.
        self.assertEqual(self.commit({}).returncode, 0)
        self.assertEqual(self.read_index()["round"], 1)
        self.assertFalse((self.run_dir / "audit" / "round-1.md").exists())

    def test_commit_rejections_keep_index_intact(self):
        original = self.index_path.read_bytes()
        cases = [
            ({"set_state": [{"id": "i1", "state": "open"}, {"id": "i1", "state": "contested"}]}, 1, 0, 1),
            ({}, 2, 0, 1),
            ({}, 1, 1, 1),
            ({"bump": ["missing"]}, 1, 0, 1),
            ({"set_state": [{"id": "i1", "state": "accepted"}]}, 1, 0, 1),
        ]
        for payload, round_number, epoch, expected in cases:
            result = self.commit(payload, round_number, epoch)
            self.assertEqual(result.returncode, expected)
            self.assertEqual(self.index_path.read_bytes(), original)
        result = self.run_index("commit-sweep", self.run_id, "1", "0", input_data='[]')
        self.assertEqual(result.returncode, 2)
        self.assertEqual(self.index_path.read_bytes(), original)
        result = self.commit({"add_evidence": [{"id": "i1", "side": [], "point": {}}]})
        self.assertEqual(result.returncode, 2)
        self.assertEqual(self.index_path.read_bytes(), original)

    def test_put_invariant_and_valid_data(self):
        invalid = {"issues": [issue(state="accepted", peer=False)]}
        result = self.run_index("put", self.run_id, input_data=json.dumps(invalid))
        self.assertEqual(result.returncode, 1)
        valid = {"issues": [issue(state="accepted", peer=True)]}
        result = self.run_index("put", self.run_id, input_data=json.dumps(valid))
        self.assertEqual(result.returncode, 0)
        self.assertEqual(self.read_index()["issues"][0]["state"], "accepted")

    def test_reopen_no_match_and_reset(self):
        result = self.run_index("reopen", self.run_id, "both")
        self.assertEqual(result.returncode, 3)
        data = self.read_index()
        data.update({"round": 4, "run_epoch": 2, "committed_rounds": [1, 2, 3, 4]})
        data["issues"][0].update({"state": "unresolved", "rounds_debated": 4, "peer_reviewed": True, "fully_vetted": True, "detail_contested": True, "card_rev": 7})
        self.write_index(data)
        result = self.run_index("reopen", self.run_id, "both")
        self.assertEqual(result.returncode, 0)
        updated = self.read_index()
        item = updated["issues"][0]
        self.assertEqual((updated["round"], updated["run_epoch"], updated["committed_rounds"]), (0, 3, []))
        self.assertEqual((item["state"], item["rounds_debated"], item["peer_reviewed"], item["fully_vetted"], item["detail_contested"], item["card_rev"]), ("open", 0, False, False, False, 8))


if __name__ == "__main__":
    unittest.main()
