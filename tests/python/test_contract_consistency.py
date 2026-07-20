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

    def copy_contract_tree(self, root):
        for name in ("agents", "skills", "prompts", "hooks"):
            shutil.copytree(ROOT / name, root / name)
        (root / "scripts").mkdir()
        shutil.copy2(ROOT / "scripts/read_protocol_phase", root / "scripts/read_protocol_phase")
        shutil.copy2(ROOT / "CONTRACTS.md", root / "CONTRACTS.md")
        shutil.copy2(ROOT / "README.md", root / "README.md")

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
                "review-profile-owner",
                "prompts/debate.tmpl",
                "\n{{PROFILEINFO}}\n",
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
                self.copy_contract_tree(root)
                target = root / relative_path
                target.write_text(target.read_text(encoding="utf-8") + bad_text, encoding="utf-8")

                result = self.run_check(root)

                self.assertNotEqual(result.returncode, 0)
                self.assertIn(invariant, result.stderr)

    def test_direct_normal_debate_transaction_helpers_are_rejected(self):
        commands = (
            '"$SC/merge_payload" /tmp/base.json < /tmp/addendum.json',
            '"$SC/sweep" commit "$id" "$round" "$epoch" < /tmp/payload.json',
            '"$SC/regen_cards" --id "$id" --workdir "$workdir"',
        )

        for command in commands:
            with self.subTest(command=command), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                self.copy_contract_tree(root)
                protocol = root / "skills/panel-review-for-agent/references/protocol.md"
                text = protocol.read_text(encoding="utf-8")
                injected = f"\n```bash\n{command}\n```\n\n<!-- /phase:debate -->"
                prefix, marker, suffix = text.rpartition("<!-- /phase:debate -->")
                self.assertTrue(marker)
                text = prefix + injected + suffix
                protocol.write_text(text, encoding="utf-8")

                result = self.run_check(root)

                self.assertNotEqual(result.returncode, 0)
                self.assertIn("normal-debate-transaction-owner", result.stderr)

    def test_claude_runtime_contract_drift_is_reported(self):
        cases = (
            (
                "outer-referee-agent-contract",
                "skills/start/SKILL.md",
                "run_in_background: false",
                "run_in_background: true",
            ),
            (
                "agent-spawn-budget",
                "skills/panel-review-for-agent/SKILL.md",
                "Subagent spawn limit reached",
                "Subagent capacity unavailable",
            ),
            (
                "agent-spawn-budget",
                "skills/start/SKILL.md",
                "fixed status does not disclose",
                "fixed status discloses",
            ),
            (
                "bash-timeout-contract",
                "agents/panel-review-cli-barrier.md",
                "moves the call to the background",
                "stops the call",
            ),
            (
                "agent-spawn-budget",
                "README.md",
                "down-seat pass",
                "ordinary seat pass",
            ),
        )

        for invariant, relative_path, old, new in cases:
            with self.subTest(invariant=invariant), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                self.copy_contract_tree(root)
                target = root / relative_path
                text = target.read_text(encoding="utf-8")
                self.assertIn(old, text)
                target.write_text(text.replace(old, new, 1), encoding="utf-8")

                result = self.run_check(root)

                self.assertNotEqual(result.returncode, 0)
                self.assertIn(invariant, result.stderr)


if __name__ == "__main__":
    unittest.main()
