"""Black-box coverage for executable-instruction ownership checks."""

from pathlib import Path
import re
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

    def test_merge_payload_validation_drift_is_reported(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.copy_contract_tree(root)
            (root / "scripts/merge_payload").write_text(
                'print("{}")\n',
                encoding="utf-8",
            )

            result = self.run_check(root)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("merge-payload-validation", result.stderr)

    def copy_contract_tree(self, root):
        for name in ("agents", "skills", "prompts", "hooks"):
            shutil.copytree(ROOT / name, root / name)
        (root / "scripts").mkdir()
        shutil.copy2(ROOT / "scripts/read_protocol_phase", root / "scripts/read_protocol_phase")
        shutil.copy2(ROOT / "scripts/merge_payload", root / "scripts/merge_payload")
        shutil.copy2(ROOT / "scripts/repo_guard", root / "scripts/repo_guard")
        # run_agy carries the agy model pins the checker shape-validates.
        shutil.copy2(ROOT / "scripts/run_agy", root / "scripts/run_agy")
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

    def test_round0_duplicate_consequence_stays_in_all_seat_instructions(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.copy_contract_tree(root)
            prompt = root / "prompts/blind_pass.tmpl"
            text = prompt.read_text(encoding="utf-8")
            text = text.replace(
                "A copied Round-0 finding counts once. The referee records any dropped co-raiser",
                "A copied Round-0 finding is ignored. The referee records any dropped co-raiser",
                1,
            )
            prompt.write_text(text, encoding="utf-8")

            result = self.run_check(root)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("round0-independence-contract", result.stderr)

    def test_round0_protocol_requires_the_referee_to_drop_copied_co_raisers(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.copy_contract_tree(root)
            protocol = root / "skills/panel-review-for-agent/references/protocol.md"
            text = protocol.read_text(encoding="utf-8")
            text = text.replace(
                "remove the other\n   co-raiser(s) from `raised_by`",
                "keep every co-raiser in `raised_by`",
                1,
            )
            protocol.write_text(text, encoding="utf-8")

            result = self.run_check(root)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("round0-independence-contract", result.stderr)

    def test_verdict_uses_birth_pass_origins_and_separates_round0_support(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.copy_contract_tree(root)
            protocol = root / "skills/panel-review-for-agent/references/protocol.md"
            text = protocol.read_text(encoding="utf-8")
            text = text.replace(
                "Use the origin record from each issue's birth pass for its \"Flagged by\" list.",
                "Use the Round-0 origins for every issue's \"Flagged by\" list.",
                1,
            )
            protocol.write_text(text, encoding="utf-8")

            result = self.run_check(root)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("round0-independence-contract", result.stderr)

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
            (
                "agy-slash-command-policy",
                "README.md",
                "agy expands leading slash commands in print mode",
                "agy disables leading slash commands in print mode",
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

    def test_agy_prompt_templates_keep_the_prose_contract_first(self):
        for template_name in ("blind_pass.tmpl", "debate.tmpl"):
            with self.subTest(template=template_name), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                self.copy_contract_tree(root)
                target = root / "prompts" / template_name
                target.write_text(
                    "/boost\n" + target.read_text(encoding="utf-8"),
                    encoding="utf-8",
                )

                result = self.run_check(root)

                self.assertNotEqual(result.returncode, 0)
                self.assertIn("agy-prompt-prefix", result.stderr)

    def test_agy_model_pin_drift_is_reported(self):
        """A slug-shaped or duplicated agy pin must fail the checker, not a review.

        The pins are read out of run_agy rather than written here, so bumping a model does not
        need a test edit; what is fixed is the form both pins must keep.
        """
        source = (ROOT / "scripts/run_agy").read_text(encoding="utf-8")
        pins = dict(re.findall(r'(?m)^(PRIMARY_MODEL|FALLBACK_MODEL)="([^"]*)"$', source))
        self.assertEqual(set(pins), {"PRIMARY_MODEL", "FALLBACK_MODEL"})
        # A slug of the pinned model, and a fallback that repeats the primary: the two ways a pin
        # stops selecting the intended second opinion without any syntax error.
        slug = pins["PRIMARY_MODEL"].lower().replace(" (", "-").replace(")", "").replace(" ", "-")
        cases = (
            ("PRIMARY_MODEL", pins["PRIMARY_MODEL"], slug),
            ("FALLBACK_MODEL", pins["FALLBACK_MODEL"], pins["PRIMARY_MODEL"]),
        )

        for pin_name, old, new in cases:
            with self.subTest(pin=pin_name), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                self.copy_contract_tree(root)
                target = root / "scripts/run_agy"
                target.write_text(
                    target.read_text(encoding="utf-8").replace(
                        f'{pin_name}="{old}"', f'{pin_name}="{new}"', 1
                    ),
                    encoding="utf-8",
                )

                result = self.run_check(root)

                self.assertNotEqual(result.returncode, 0)
                self.assertIn("agy-model-pin-form", result.stderr)

    def test_round0_retry_contract_drift_is_reported(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.copy_contract_tree(root)
            protocol = root / "skills/panel-review-for-agent/references/protocol.md"
            text = protocol.read_text(encoding="utf-8")
            required = "Retry each still-down seat once"
            self.assertIn(required, text)
            protocol.write_text(
                text.replace(required, "Treat each still-down seat as unavailable", 1),
                encoding="utf-8",
            )

            result = self.run_check(root)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("round0-retry-contract", result.stderr)


if __name__ == "__main__":
    unittest.main()
