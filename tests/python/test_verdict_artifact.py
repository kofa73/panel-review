"""Black-box coverage for durable verdict writing and validated retrieval."""

import json
from pathlib import Path
import shutil
import subprocess
import unittest
import uuid


ROOT = Path(__file__).resolve().parents[2]
WRITE_ARTIFACT = ROOT / "scripts" / "write_verdict_artifact"
READ_ARTIFACT = ROOT / "scripts" / "read_verdict_artifact"


class VerdictArtifactTest(unittest.TestCase):
    def setUp(self):
        self.run_id = f"py-verdict-{uuid.uuid4().hex}"
        self.run_dir = Path("/tmp") / self.run_id
        self.run_dir.mkdir()
        self.artifact = Path("/tmp") / f"{self.run_id}.md"
        self.scope = "question=check the durable result"
        self.diff_hash = "a" * 64
        manifest = {
            "id": self.run_id,
            "scope": self.scope,
            "instructions": "focus on correctness",
            "limits": {"issue_rounds": 2, "max_rounds": 4},
            "diff_hash": self.diff_hash,
            "created": "2026-07-14 00:00:00",
        }
        (self.run_dir / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
        self.write_index("accepted")
        self.body = (
            "## Panel Review — question\n"
            "**Seats:** Claude + Codex (GPT)\n"
            "**Rounds:** 1 debate round (converged)\n\n"
            "No findings.\n"
        )

    def tearDown(self):
        shutil.rmtree(self.run_dir, ignore_errors=True)
        self.artifact.unlink(missing_ok=True)
        Path(str(self.artifact) + ".bak").unlink(missing_ok=True)

    def write_index(self, state, phase="debate", run_epoch=0, severity="low"):
        (self.run_dir / "index.json").write_text(
            json.dumps(
                {
                    "issues": [{"id": "i1", "state": state, "severity": severity}],
                    "phase": phase,
                    "run_epoch": run_epoch,
                }
            ),
            encoding="utf-8",
        )

    def write_artifact(self, *extra):
        return subprocess.run(
            [str(WRITE_ARTIFACT), "--id", self.run_id, *extra],
            input=self.body,
            text=True,
            capture_output=True,
            check=False,
        )

    def read_artifact(self, *extra):
        return subprocess.run(
            [str(READ_ARTIFACT), "--id", self.run_id, *extra],
            text=True,
            capture_output=True,
            check=False,
        )

    def deliver_artifact(self, *extra):
        return self.read_artifact("--delivery", *extra)

    def test_finished_artifact_is_validated_and_reader_emits_only_body(self):
        written = self.write_artifact()
        self.assertEqual(written.returncode, 0, written.stderr)
        self.assertIn("run_epoch: 0\n", self.artifact.read_text(encoding="utf-8"))
        self.assertIn("status: finished\n", self.artifact.read_text(encoding="utf-8"))

        result = self.read_artifact(
            "--scope", self.scope,
            "--diff-hash", self.diff_hash,
            "--run-epoch", "0",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, self.body)
        by_id = self.read_artifact()
        self.assertEqual(by_id.returncode, 0, by_id.stderr)
        self.assertEqual(by_id.stdout, self.body)

    def test_finished_artifact_delivery_emits_only_the_fixed_file_pointer(self):
        self.assertEqual(self.write_artifact().returncode, 0)

        result = self.deliver_artifact(
            "--scope", self.scope,
            "--diff-hash", self.diff_hash,
            "--run-epoch", "0",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, f"Done. Final report: /tmp/{self.run_id}.md\n")

    def test_continuable_artifact_delivery_adds_only_leftover_status(self):
        self.write_index("contested")
        self.assertEqual(self.write_artifact().returncode, 0)

        result = self.deliver_artifact(
            "--scope", self.scope,
            "--diff-hash", self.diff_hash,
            "--run-epoch", "0",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout,
            f"Done. Final report: /tmp/{self.run_id}.md\n"
            "0 unresolved, 1 contested remain — run panel-review:continue "
            "[unresolved|contested] to debate them further, or panel-review:discard "
            "to remove the saved review.\n",
        )

    def test_incomplete_low_only_gate_delivery_emits_snapshot_pointer(self):
        self.write_index("open", severity="low")
        self.assertEqual(self.write_artifact().returncode, 0)

        result = self.deliver_artifact(
            "--scope", self.scope,
            "--diff-hash", self.diff_hash,
            "--run-epoch", "0",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout,
            f"Review paused because only low-severity findings remain. Report snapshot: "
            f"/tmp/{self.run_id}.md\n",
        )

    def test_low_gate_delivery_rejects_snapshot_from_earlier_same_epoch_state(self):
        self.write_index("open", severity="low")
        self.assertEqual(self.write_artifact().returncode, 0)
        index = json.loads((self.run_dir / "index.json").read_text(encoding="utf-8"))
        index["round"] = 1
        (self.run_dir / "index.json").write_text(json.dumps(index), encoding="utf-8")

        result = self.deliver_artifact(
            "--scope", self.scope,
            "--diff-hash", self.diff_hash,
            "--run-epoch", "0",
        )

        self.assertEqual(result.returncode, 1)
        self.assertIn("retained index does not match the artifact", result.stderr)
        self.assertEqual(result.stdout, "")

    def test_delivery_rejects_missing_or_non_gate_incomplete_artifact(self):
        missing = self.deliver_artifact(
            "--scope", self.scope,
            "--diff-hash", self.diff_hash,
            "--run-epoch", "0",
        )
        self.assertEqual(missing.returncode, 1)
        self.assertEqual(missing.stdout, "")

        self.write_index("open", severity="medium")
        self.assertEqual(self.write_artifact().returncode, 0)
        invalid = self.deliver_artifact(
            "--scope", self.scope,
            "--diff-hash", self.diff_hash,
            "--run-epoch", "0",
        )
        self.assertEqual(invalid.returncode, 1)
        self.assertIn("not a low-severity gate", invalid.stderr)
        self.assertEqual(invalid.stdout, "")

    def test_delivery_rejects_corrupt_retained_state(self):
        self.assertEqual(self.write_artifact().returncode, 0)
        self.write_index("unknown")

        result = self.deliver_artifact(
            "--scope", self.scope,
            "--diff-hash", self.diff_hash,
            "--run-epoch", "0",
        )

        self.assertEqual(result.returncode, 1)
        self.assertIn("retained index is malformed", result.stderr)
        self.assertEqual(result.stdout, "")

    def test_reader_rejects_scope_or_hash_mismatch(self):
        self.assertEqual(self.write_artifact().returncode, 0)
        cases = [
            ("--scope", "question=different", "--diff-hash", self.diff_hash, "--run-epoch", "0"),
            ("--scope", self.scope, "--diff-hash", "b" * 64, "--run-epoch", "0"),
            ("--scope", self.scope, "--diff-hash", self.diff_hash, "--run-epoch", "1"),
        ]
        for args in cases:
            with self.subTest(args=args):
                result = self.read_artifact(*args)
                self.assertEqual(result.returncode, 1)
                self.assertEqual(result.stdout, "")

    def test_reader_rejects_unfinished_artifact(self):
        self.write_index("open")
        self.assertEqual(self.write_artifact().returncode, 0)
        self.assertIn("status: incomplete\n", self.artifact.read_text(encoding="utf-8"))

        result = self.read_artifact()

        self.assertEqual(result.returncode, 1)
        self.assertIn("artifact is not a finished review", result.stderr)
        self.assertEqual(result.stdout, "")

    def test_finalized_gate_artifact_is_retrievable(self):
        self.write_index("open")

        written = self.write_artifact("--final")

        self.assertEqual(written.returncode, 0, written.stderr)
        self.assertIn("status: finished\n", self.artifact.read_text(encoding="utf-8"))
        result = self.read_artifact()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, self.body)
        delivery = self.deliver_artifact()
        self.assertEqual(delivery.returncode, 0, delivery.stderr)
        self.assertEqual(delivery.stdout, f"Done. Final report: /tmp/{self.run_id}.md\n")

    def test_finalization_rejects_non_low_open_issues(self):
        self.write_index("open", severity="medium")

        result = self.write_artifact("--final")

        self.assertEqual(result.returncode, 1)
        self.assertIn("invalid index", result.stderr)
        self.assertFalse(self.artifact.exists())

    def test_finalization_requires_an_open_gate_issue(self):
        self.write_index("accepted")

        result = self.write_artifact("--final")

        self.assertEqual(result.returncode, 1)
        self.assertIn("invalid index", result.stderr)
        self.assertFalse(self.artifact.exists())

    def test_round_zero_artifact_is_not_marked_finished_before_issue_birth(self):
        (self.run_dir / "index.json").write_text(
            json.dumps({"issues": [], "phase": "round0", "run_epoch": 0}),
            encoding="utf-8",
        )

        self.assertEqual(self.write_artifact().returncode, 0)

        self.assertIn("status: incomplete\n", self.artifact.read_text(encoding="utf-8"))
        self.assertEqual(self.read_artifact().returncode, 1)

    def test_recovery_rejects_finished_artifact_from_previous_epoch(self):
        self.assertEqual(self.write_artifact().returncode, 0)
        self.write_index("open", run_epoch=1)

        result = self.read_artifact(
            "--scope", self.scope,
            "--diff-hash", self.diff_hash,
            "--run-epoch", "1",
        )

        self.assertEqual(result.returncode, 1)
        self.assertIn("artifact run_epoch does not match", result.stderr)
        self.assertEqual(result.stdout, "")

    def test_reader_rejects_tampered_artifact_id(self):
        self.assertEqual(self.write_artifact().returncode, 0)
        text = self.artifact.read_text(encoding="utf-8")
        self.artifact.write_text(text.replace(f"id: {self.run_id}", "id: different-id", 1), encoding="utf-8")

        result = self.read_artifact()

        self.assertEqual(result.returncode, 1)
        self.assertIn("artifact id does not match", result.stderr)
        self.assertEqual(result.stdout, "")

    def test_writer_rejects_unknown_index_state(self):
        self.write_index("not-a-state")

        result = self.write_artifact()

        self.assertEqual(result.returncode, 1)
        self.assertIn("invalid index", result.stderr)
        self.assertFalse(self.artifact.exists())

    def test_reader_rejects_malformed_frontmatter_metadata(self):
        self.assertEqual(self.write_artifact().returncode, 0)
        text = self.artifact.read_text(encoding="utf-8")
        self.artifact.write_text(
            text.replace("limits: issue-rounds=2 max-rounds=4", "limits: unknown", 1),
            encoding="utf-8",
        )

        result = self.read_artifact()

        self.assertEqual(result.returncode, 1)
        self.assertIn("artifact limits are invalid", result.stderr)
        self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main()
