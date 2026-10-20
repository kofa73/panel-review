"""Black-box checks for the regenerable issue-card cache."""

import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import uuid


ROOT = Path(__file__).resolve().parents[2]
REGEN_CARDS = ROOT / "scripts" / "regen_cards"


def issue(issue_id="i1"):
    return {
        "id": issue_id,
        "claim": "A concrete claim.",
        "location": "src/file.py:1",
        "severity": "medium",
        "evidence_pro": [{"assertion": "Observed behavior.", "location": "src/file.py:1"}],
        "evidence_contra": [],
        "peer_reviewed": False,
    }


class CardCacheTest(unittest.TestCase):
    def setUp(self):
        self.run_id = f"py-cards-{uuid.uuid4().hex}"
        self.run_dir = Path("/tmp") / self.run_id
        self.run_dir.mkdir()
        self.workdir = Path(tempfile.mkdtemp(prefix="panel-cards-work-"))
        self.cache = self.workdir / ".panel-review" / self.run_id
        self.cache.mkdir(parents=True)
        self.index_path = self.run_dir / "index.json"

    def tearDown(self):
        shutil.rmtree(self.run_dir, ignore_errors=True)
        shutil.rmtree(self.workdir, ignore_errors=True)

    def write_index(self, issues):
        self.index_path.write_text(json.dumps({"issues": issues}), encoding="utf-8")

    def regenerate(self):
        return subprocess.run(
            [str(REGEN_CARDS), "--id", self.run_id, "--workdir", str(self.workdir)],
            capture_output=True,
            text=True,
            check=False,
        )

    def test_stale_card_is_removed_before_rendering(self):
        self.write_index([{"id": "i1", "evidence_pro": "not-an-array"}])
        stale = self.cache / "issue-stale.md"
        stale.write_text("old card\n", encoding="utf-8")

        result = self.regenerate()

        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertFalse(stale.exists())

    def test_invalid_issue_list_does_not_erase_cached_cards(self):
        self.write_index("invalid")
        stale = self.cache / "issue-stale.md"
        stale.write_text("old card\n", encoding="utf-8")

        result = self.regenerate()

        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertTrue(stale.exists())

    def test_current_cards_are_projected_without_header_metadata(self):
        self.write_index([issue()])
        stale = self.cache / "issue-stale.md"
        stale.write_text("old card\n", encoding="utf-8")
        current = self.cache / "issue-i1.md"
        current.write_text("old projection\n", encoding="utf-8")

        result = self.regenerate()

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(stale.exists())
        self.assertTrue(current.read_text(encoding="utf-8").startswith("# i1\n"))
