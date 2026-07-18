"""Black-box coverage for executable-instruction ownership checks."""

from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
CHECK = ROOT / "scripts" / "check_contracts"


class ContractConsistencyTest(unittest.TestCase):
    def run_check(self, root=ROOT):
        return subprocess.run(
            [str(CHECK), "--root", str(root)],
            capture_output=True,
            text=True,
            check=False,
        )

    def test_live_tree_contracts_are_consistent(self):
        result = self.run_check()

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("instruction contracts: OK", result.stdout)

    def test_each_known_drift_is_reported_by_invariant_name(self):
        cases = [
            (
                "barrier-completion-signal",
                "skills/panel-review-for-agent/references/protocol.md",
                "\nThe barrier watches --done until the seats settle.\n",
            ),
            (
                "absolute-seat-paths",
                "skills/panel-review-for-agent/references/protocol.md",
                "\nThe scratch path is relative because every seat starts in the workdir.\n",
            ),
            (
                "referee-return-status",
                "agents/panel-review-referee.md",
                "\nPANEL_VERDICT_WRITE_FAILED reports any review failure.\n",
            ),
            (
                "configured-panel-wording",
                "prompts/debate.tmpl",
                "\nYou and two other AIs reviewed the same work.\n",
            ),
            (
                "all-seat-health-reporting",
                "skills/panel-review-for-agent/references/protocol.md",
                "\nProcess notes name any peer seat (Codex or Gemini) down.\n",
            ),
            (
                "artifact-only-status-wording",
                "skills/status/SKILL.md",
                "\nThe verdict was shown in the transcript.\n",
            ),
            (
                "canonical-stance-values",
                "prompts/debate.tmpl",
                "\nThe stance may be support_with_revision.\n",
            ),
        ]

        for invariant, relative_path, bad_text in cases:
            with self.subTest(invariant=invariant), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                for name in ("agents", "skills", "prompts", "hooks"):
                    shutil.copytree(ROOT / name, root / name)
                shutil.copy2(ROOT / "CONTRACTS.md", root / "CONTRACTS.md")
                target = root / relative_path
                target.write_text(target.read_text(encoding="utf-8") + bad_text, encoding="utf-8")

                result = self.run_check(root)

                self.assertNotEqual(result.returncode, 0)
                self.assertIn(invariant, result.stderr)


if __name__ == "__main__":
    unittest.main()
