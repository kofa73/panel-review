"""Black-box coverage for Claude-seat raw output persistence."""

from pathlib import Path
import shutil
import subprocess
import unittest
import uuid


ROOT = Path(__file__).resolve().parents[2]
WRITE_RAW = ROOT / "scripts" / "write_seat_raw"

FINDING = (
    '{"claim":"bug","location":"f.c:1","category":"correctness",'
    '"severity":"high","points":[{"assertion":"broken","location":"f.c:1"}]}'
)
STANCE = '{"id":"i1","stance":"support","rationale":"confirmed"}'


class WriteSeatRawTest(unittest.TestCase):
    def setUp(self):
        self.run_id = f"py-seat-raw-{uuid.uuid4().hex}"
        self.run_dir = Path("/tmp") / self.run_id
        self.run_dir.mkdir()

    def tearDown(self):
        shutil.rmtree(self.run_dir, ignore_errors=True)

    def run_writer(self, *args, raw=""):
        return subprocess.run(
            [str(WRITE_RAW), "--id", self.run_id, *args],
            input=raw,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_round_zero_validates_and_writes_expected_path(self):
        raw = f"```findings\n{FINDING}\n```\nsummary\n"

        result = self.run_writer("--round", "0", raw=raw)

        destination = self.run_dir / "raw" / "round0.claude.txt"
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, f"{destination}\n")
        self.assertEqual(destination.read_text(encoding="utf-8"), raw)

    def test_debate_requires_and_writes_both_blocks(self):
        raw = f"```stances\n{STANCE}\n```\n```new_findings\n[]\n```\n"

        result = self.run_writer("--round", "2", "--batch", "b1", raw=raw)

        destination = self.run_dir / "raw" / "round2.claude.b1.txt"
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(destination.read_text(encoding="utf-8"), raw)

    def test_invalid_input_does_not_replace_existing_raw(self):
        destination = self.run_dir / "raw" / "round0.claude.txt"
        destination.parent.mkdir()
        destination.write_text("previous\n", encoding="utf-8")
        mixed = f"```findings\n{FINDING}\n{{not json}}\n```\n"

        result = self.run_writer("--round", "0", raw=mixed)

        self.assertEqual(result.returncode, 1)
        self.assertIn("invalid findings block", result.stderr)
        self.assertEqual(destination.read_text(encoding="utf-8"), "previous\n")

    def test_debate_rejects_missing_new_findings_block(self):
        result = self.run_writer(
            "--round",
            "1",
            "--batch",
            "1",
            raw=f"```stances\n{STANCE}\n```\n",
        )

        self.assertEqual(result.returncode, 1)
        self.assertIn("invalid new_findings block", result.stderr)
        self.assertFalse((self.run_dir / "raw" / "round1.claude.1.txt").exists())

    def test_round_and_batch_shape_is_strict(self):
        cases = [
            (("--round", "0", "--batch", "1"), "round 0 does not take --batch"),
            (("--round", "1"), "debate rounds require --batch"),
            (("--round", "01", "--batch", "1"), "--round must be 0 or a positive integer"),
            (("--round", "1", "--batch", "../x"), "--batch must be a safe name"),
        ]
        for args, message in cases:
            with self.subTest(args=args):
                result = self.run_writer(*args, raw="")
                self.assertEqual(result.returncode, 2)
                self.assertIn(message, result.stderr)


if __name__ == "__main__":
    unittest.main()
