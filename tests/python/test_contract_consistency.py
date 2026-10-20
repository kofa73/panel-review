"""Black-box coverage for executable-instruction ownership checks."""

from pathlib import Path
import os
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

    def test_session_launcher_must_delegate_prerequisites_to_preflight(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.copy_contract_tree(root)
            launcher = root / "bin/panel-review-session"
            text = launcher.read_text(encoding="utf-8")
            launcher.write_text(
                text.replace('"$plugin_root/scripts/preflight"', ":", 1),
                encoding="utf-8",
            )

            result = self.run_check(root)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("session-launcher-contract", result.stderr)
            self.assertIn("runs the shared preflight", result.stderr)

    def test_session_launcher_must_ignore_directories_without_run_markers(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.copy_contract_tree(root)
            launcher = root / "bin/panel-review-session"
            text = launcher.read_text(encoding="utf-8")
            launcher.write_text(
                text.replace('[ -f "$marker/.panel-run" ] || continue', ":", 1),
                encoding="utf-8",
            )

            result = self.run_check(root)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("session-launcher-contract", result.stderr)
            self.assertIn("ignores directories without a run marker", result.stderr)

    def test_stale_entrypoints_cannot_delete_run_state(self):
        cases = (
            ("start", "- **`stale`**"),
            ("resume", "- **`stale $id`**"),
            ("continue", "- **`stale $id`**"),
        )
        for name, label in cases:
            with self.subTest(command=name), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                self.copy_contract_tree(root)
                skill = root / f"skills/{name}/SKILL.md"
                text = skill.read_text(encoding="utf-8")
                start = text.index(label)
                following = re.search(r"(?m)^\s*-\s+\*\*", text[start + len(label) :])
                end = start + len(label) + following.start()
                branch = text[start:end]
                self.assertIn("panel-review:discard", branch)
                branch = branch.replace("panel-review:discard", "$SC/cleanup", 1)
                skill.write_text(text[:start] + branch + text[end:], encoding="utf-8")

                result = self.run_check(root)

                self.assertNotEqual(result.returncode, 0)
                self.assertIn("stale-run-handoff", result.stderr)

    def test_resume_missing_manifest_guard_cannot_delete_run_state(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.copy_contract_tree(root)
            skill = root / "skills/resume/SKILL.md"
            text = skill.read_text(encoding="utf-8")
            marker = '[ -s "$man" ] || {'
            self.assertIn(marker, text)
            skill.write_text(
                text.replace(
                    marker,
                    marker + '\n  "$SC/cleanup" --id "$id" --workdir "$PWD"',
                    1,
                ),
                encoding="utf-8",
            )

            result = self.run_check(root)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("stale-run-handoff", result.stderr)

    def test_resume_and_continue_stop_when_saved_setting_update_fails(self):
        for name in ("resume", "continue"):
            with self.subTest(command=name), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                self.copy_contract_tree(root)
                skill = root / f"skills/{name}/SKILL.md"
                text = skill.read_text(encoding="utf-8")
                guarded_call = '"$SC/set_limits" "${SETTING_ARGS[@]}" || {'
                self.assertIn(guarded_call, text)
                skill.write_text(text.replace(guarded_call, '"$SC/set_limits" "${SETTING_ARGS[@]}"', 1), encoding="utf-8")

                result = self.run_check(root)

                self.assertNotEqual(result.returncode, 0)
                self.assertIn("saved-setting-update-guard", result.stderr)

    def test_multi_batch_barrier_dispatch_passes_saved_timeout(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.copy_contract_tree(root)
            protocol = root / "skills/panel-review-for-agent/references/protocol.md"
            text = protocol.read_text(encoding="utf-8")
            timeout_field = "`seat_timeout_seconds=$seat_timeout_seconds`"
            self.assertIn(timeout_field, text)
            protocol.write_text(text.replace(timeout_field, "`workdir=<repo root>`", 1), encoding="utf-8")

            result = self.run_check(root)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("multi-batch-barrier-timeout", result.stderr)

    def test_card_cache_contract_rejects_metadata_and_late_cleanup(self):
        cases = [
            ("scripts/project_card", "printf '<!-- panel stale -->\\n'\\n"),
            ("scripts/regen_cards", "rm -f -- \"$card\""),
        ]
        for relative_path, drift in cases:
            with self.subTest(path=relative_path), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                self.copy_contract_tree(root)
                target = root / relative_path
                text = target.read_text(encoding="utf-8")
                if relative_path.endswith("project_card"):
                    target.write_text(text + drift, encoding="utf-8")
                else:
                    target.write_text(text.replace(drift, ":", 1), encoding="utf-8")

                result = self.run_check(root)

                self.assertNotEqual(result.returncode, 0)
                self.assertIn("card-cache-projection", result.stderr)

    def test_card_cache_contract_rejects_run_marker_management(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.copy_contract_tree(root)
            regen_cards = root / "scripts/regen_cards"
            regen_cards.write_text(
                regen_cards.read_text(encoding="utf-8") + '\ntouch "$dir/.panel-run"\n',
                encoding="utf-8",
            )

            result = self.run_check(root)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("card-cache-projection", result.stderr)

    def test_run_marker_discovery_contract_requires_marker_file(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.copy_contract_tree(root)
            resume_check = root / "scripts/resume_check"
            text = resume_check.read_text(encoding="utf-8")
            text = text.replace('[ -f "$d/.panel-run" ] || continue', "continue", 1)
            resume_check.write_text(text, encoding="utf-8")

            result = self.run_check(root)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("run-marker-discovery", result.stderr)

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

    def test_shared_python_helpers_remain_the_authoritative_owners(self):
        cases = (
            ("scripts/birth_index", "valid_point", "shared-point-validation"),
            ("scripts/parse_block", "extract_fenced_block", "shared-fence-scan"),
            ("scripts/extract_block", "extract_fenced_block", "shared-fence-scan"),
            ("scripts/decide_round", "stance_integrity_problems", "shared-stance-integrity"),
            (
                "scripts/decide_degraded_round",
                "stance_integrity_problems",
                "shared-stance-integrity",
            ),
        )
        for relative_path, helper, invariant in cases:
            with self.subTest(path=relative_path), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                self.copy_contract_tree(root)
                target = root / relative_path
                text = target.read_text(encoding="utf-8")
                self.assertIn(helper, text)
                target.write_text(text.replace(helper, "retired_helper"), encoding="utf-8")

                result = self.run_check(root)

                self.assertNotEqual(result.returncode, 0)
                self.assertIn(invariant, result.stderr)

    def test_retired_commands_and_installer_migration_are_rejected(self):
        cases = [
            (
                "scripts/index",
                "usage: index {get|put|issue|gate-status|delivery-status|commit-sweep|reopen}",
                "usage: index {get|put|issue|state|gate-status|delivery-status|commit-sweep|reopen}",
            ),
            (
                "scripts/sweep",
                "usage: sweep {begin|plan|plan-scaffold|extend-plan|ingest-batch|drop-seat|resume-plan|has|done|commit}",
                "usage: sweep {begin|record|plan|plan-scaffold|extend-plan|ingest-batch|drop-seat|resume-plan|has|done|commit}",
            ),
            (
                "skills/panel-review-for-agent/references/protocol.md",
                '"$SC/index"   {get|put|issue|gate-status|delivery-status|reopen}',
                '"$SC/index"   {get|put|issue|gate-status|delivery-status|commit-sweep|reopen}',
            ),
            (
                "skills/panel-review-for-agent/references/protocol.md",
                '"$SC/sweep"   {begin|plan|plan-scaffold|extend-plan|ingest-batch|drop-seat|resume-plan|has|done}',
                '"$SC/sweep"   {begin|plan|plan-scaffold|extend-plan|ingest-batch|drop-seat|resume-plan|has|done|commit}',
            ),
        ]
        for relative_path, current, retired in cases:
            with self.subTest(path=relative_path), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                self.copy_contract_tree(root)
                target = root / relative_path
                text = target.read_text(encoding="utf-8")
                self.assertIn(current, text)
                target.write_text(text.replace(current, retired, 1), encoding="utf-8")

                result = self.run_check(root)

                self.assertNotEqual(result.returncode, 0)
                self.assertIn("retired-script-surface", result.stderr)

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.copy_contract_tree(root)
            installer = root / "install.sh"
            installer.write_text(installer.read_text(encoding="utf-8") + "\nfor old_skill in obsolete; do\n", encoding="utf-8")

            result = self.run_check(root)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("retired-script-surface", result.stderr)

    def test_installer_warns_when_a_project_agent_shadows_the_plugin(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            workdir = root / "project"
            shadow = workdir / ".claude/agents/panel-review-referee.md"
            shadow.parent.mkdir(parents=True)
            shadow.write_text("name: panel-review-referee\n", encoding="utf-8")
            config_dir = root / "claude-config"
            environment = os.environ.copy()
            environment["CLAUDE_DIR"] = str(config_dir)
            environment["PANEL_REVIEW_BIN_DIR"] = str(config_dir / "bin")

            result = subprocess.run(
                [str(ROOT / "install.sh")],
                cwd=workdir,
                env=environment,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("WARNING:", result.stdout)
            self.assertIn(str(shadow), result.stdout)
            self.assertTrue((config_dir / "skills/panel-review/agents/panel-review-referee.md").is_file())

    def copy_contract_tree(self, root):
        for name in ("agents", "skills", "prompts", "hooks"):
            shutil.copytree(ROOT / name, root / name)
        (root / "scripts").mkdir()
        shutil.copy2(ROOT / "scripts/read_protocol_phase", root / "scripts/read_protocol_phase")
        shutil.copy2(ROOT / "scripts/resume_check", root / "scripts/resume_check")
        shutil.copy2(ROOT / "scripts/round", root / "scripts/round")
        shutil.copy2(ROOT / "scripts/user_config.py", root / "scripts/user_config.py")
        for name in ("init_run", "cleanup", "discard", "await_seats"):
            shutil.copy2(ROOT / "scripts" / name, root / "scripts" / name)
        shutil.copy2(ROOT / "scripts/merge_payload", root / "scripts/merge_payload")
        shutil.copy2(ROOT / "scripts/repo_guard", root / "scripts/repo_guard")
        for name in (
            "birth_index",
            "decide_degraded_round",
            "decide_round",
            "extract_block",
            "index",
            "parse_block",
            "sweep",
            "panel_common.py",
            "seat_contract.py",
            "project_card",
            "regen_cards",
        ):
            shutil.copy2(ROOT / "scripts" / name, root / "scripts" / name)
        # run_agy carries the agy model pins the checker shape-validates.
        shutil.copy2(ROOT / "scripts/run_agy", root / "scripts/run_agy")
        shutil.copy2(ROOT / "CONTRACTS.md", root / "CONTRACTS.md")
        shutil.copy2(ROOT / "README.md", root / "README.md")
        shutil.copytree(ROOT / "bin", root / "bin")
        rules = root / ".claude" / "rules"
        rules.mkdir(parents=True)
        shutil.copy2(ROOT / ".claude/rules/scripts.md", rules / "scripts.md")
        shutil.copy2(ROOT / "install.sh", root / "install.sh")

    def test_direct_normal_debate_transaction_helpers_are_rejected(self):
        commands = (
            '"$SC/merge_payload" /tmp/base.json < /tmp/addendum.json',
            '"$SC/sweep" commit "$id" "$round" "$epoch" < /tmp/payload.json',
            '"$SC/index" commit-sweep "$id" "$round" "$epoch" < /tmp/payload.json',
            '"$SC/decide_round" --id "$id"',
            '"$SC/decide_degraded_round" --id "$id"',
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

    def test_inline_transaction_helper_after_round_commit_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.copy_contract_tree(root)
            protocol = root / "skills/panel-review-for-agent/references/protocol.md"
            text = protocol.read_text(encoding="utf-8")
            prefix, marker, suffix = text.rpartition("<!-- /phase:debate -->")
            self.assertTrue(marker)
            injected = (
                '\n\nAfter the transaction: `"$SC/sweep" commit "$id" "$round" '
                '"$epoch" < /tmp/payload.json`.\n\n<!-- /phase:debate -->'
            )
            protocol.write_text(prefix + injected + suffix, encoding="utf-8")

            result = self.run_check(root)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("normal-debate-transaction-owner", result.stderr)

    def test_internal_transaction_commands_stay_out_of_protocol_instructions(self):
        commands = (
            '"$SC/merge_payload" /tmp/base.json < /tmp/addendum.json',
            '"$SC/index" commit-sweep "$id" "$round" "$epoch" < /tmp/payload.json',
            '"$SC/sweep" commit "$id" "$round" "$epoch" < /tmp/payload.json',
            '"$SC/decide_round" --id "$id"',
        )
        for command in commands:
            with self.subTest(command=command), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                self.copy_contract_tree(root)
                protocol = root / "skills/panel-review-for-agent/references/protocol.md"
                text = protocol.read_text(encoding="utf-8")
                start = text.index("```bash")
                end = text.index("```", start + 3)
                text = text[:end] + command + "\n" + text[end:]
                protocol.write_text(text, encoding="utf-8")

                result = self.run_check(root)

                self.assertNotEqual(result.returncode, 0)
                self.assertIn("model-instruction-transaction-owner", result.stderr)

    def test_round0_retry_and_recovery_resume_flags_are_command_contracts(self):
        cases = (
            ('prepare-round0 "$id" --retry', 'prepare-round0 "$id"'),
            ('prepare-round0 "$id" --resume', 'prepare-round0 "$id"'),
        )
        for current, replacement in cases:
            with self.subTest(attempt=current), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                self.copy_contract_tree(root)
                protocol = root / "skills/panel-review-for-agent/references/protocol.md"
                text = protocol.read_text(encoding="utf-8")
                self.assertIn(current, text)
                protocol.write_text(text.replace(current, replacement, 1), encoding="utf-8")

                result = self.run_check(root)

                self.assertNotEqual(result.returncode, 0)
                self.assertIn("round0-prepare-command-shape", result.stderr)

    def test_claude_specific_consumers_cannot_redefine_seat_blocks(self):
        cases = (
            ("prompts/claude_delivery.tmpl", "\nEmit only a `stances` block.\n"),
            ("agents/panel-review-claude-seat.md", "\n```findings\n[]\n```\n"),
        )
        for relative_path, injected in cases:
            with self.subTest(path=relative_path), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                self.copy_contract_tree(root)
                target = root / relative_path
                target.write_text(target.read_text(encoding="utf-8") + injected, encoding="utf-8")

                result = self.run_check(root)

                self.assertNotEqual(result.returncode, 0)
                self.assertIn("seat-contract-owner", result.stderr)

    def test_normal_debate_requires_round_commit(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.copy_contract_tree(root)
            protocol = root / "skills/panel-review-for-agent/references/protocol.md"
            text = protocol.read_text(encoding="utf-8")
            command = '   "$SC/round" commit "$id"\n'
            self.assertIn(command, text)
            protocol.write_text(text.replace(command, "   true\n", 1), encoding="utf-8")

            result = self.run_check(root)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("normal-debate-transaction-owner", result.stderr)

    def test_common_debate_requires_coarse_round_preparation_and_collection(self):
        for operation in ("prepare-debate", "collect-debate"):
            with self.subTest(operation=operation), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                self.copy_contract_tree(root)
                protocol = root / "skills/panel-review-for-agent/references/protocol.md"
                text = protocol.read_text(encoding="utf-8")
                command = f'"$SC/round" {operation} "$id"'
                self.assertIn(command, text)
                protocol.write_text(text.replace(command, f'"$SC/{operation}" "$id"', 1), encoding="utf-8")

                result = self.run_check(root)

                self.assertNotEqual(result.returncode, 0)
                self.assertIn("normal-debate-transaction-owner", result.stderr)

    def test_command_dispatch_must_remain_a_foreground_referee_call(self):
        mutations = (
            (
                "subagent_type: panel-review:panel-review-referee",
                "subagent_type: panel-review:panel-review-cli-barrier",
            ),
            ("run_in_background: false", "run_in_background: true"),
        )
        for original, replacement in mutations:
            with self.subTest(field=original), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                self.copy_contract_tree(root)
                skill = root / "skills/start/SKILL.md"
                text = skill.read_text(encoding="utf-8")
                self.assertIn(original, text)
                skill.write_text(text.replace(original, replacement, 1), encoding="utf-8")

                result = self.run_check(root)

                self.assertNotEqual(result.returncode, 0)
                self.assertIn("outer-referee-agent-contract", result.stderr)

    def test_protocol_seat_dispatch_fields_are_preserved(self):
        mutations = (
            (
                "subagent_type: panel-review:panel-review-claude-seat",
                "subagent_type: panel-review:wrong-seat",
            ),
            ("run_in_background: false", "run_in_background: true"),
        )
        for original, replacement in mutations:
            with self.subTest(field=original), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                self.copy_contract_tree(root)
                protocol = root / "skills/panel-review-for-agent/references/protocol.md"
                text = protocol.read_text(encoding="utf-8")
                self.assertIn(original, text)
                protocol.write_text(text.replace(original, replacement), encoding="utf-8")

                result = self.run_check(root)

                self.assertNotEqual(result.returncode, 0)
                self.assertIn("inner-seat-agent-dispatch", result.stderr)

    def test_round_keeps_the_diff_as_an_external_prompt_reference(self):
        for marker in (
            'panel_atomic_write(str(directory / "diff_info.txt")',
            '"DIFFINFO": directory / "diff_info.txt"',
        ):
            with self.subTest(marker=marker), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                self.copy_contract_tree(root)
                round_script = root / "scripts/round"
                text = round_script.read_text(encoding="utf-8")
                self.assertIn(marker, text)
                round_script.write_text(text.replace(marker, "missing_reference", 1), encoding="utf-8")

                result = self.run_check(root)

                self.assertNotEqual(result.returncode, 0)
                self.assertIn("diff-reference-assembly", result.stderr)

    def test_explanatory_prose_can_be_reworded(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.copy_contract_tree(root)
            readme = root / "README.md"
            text = readme.read_text(encoding="utf-8")
            start = text.index("Settlement uses only stances from")
            end = text.index("that seat is absent.", start) + len("that seat is absent.")
            readme.write_text(
                text[:start] + "Consensus uses the reviewers available for this pass." + text[end:],
                encoding="utf-8",
            )

            result = self.run_check(root)

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_template_sentinels_and_block_ownership_are_structural(self):
        cases = (
            (
                "prompts/debate.tmpl",
                "{{SEAT_CONTRACT}}",
                "seat-contract-owner",
            ),
            (
                "prompts/blind_pass.tmpl",
                "\n```findings\n```\n",
                "seat-contract-owner",
            ),
        )
        for relative_path, mutation, invariant in cases:
            with self.subTest(path=relative_path), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                self.copy_contract_tree(root)
                target = root / relative_path
                text = target.read_text(encoding="utf-8")
                if mutation == "{{SEAT_CONTRACT}}":
                    text = text.replace(mutation, mutation + "\n" + mutation, 1)
                else:
                    text += mutation
                target.write_text(text, encoding="utf-8")

                result = self.run_check(root)

                self.assertNotEqual(result.returncode, 0)
                self.assertIn(invariant, result.stderr)

    def test_referee_status_stub_stays_in_its_owner(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.copy_contract_tree(root)
            referee = root / "agents/panel-review-referee.md"
            referee.write_text(
                referee.read_text(encoding="utf-8") + "\nPANEL_VERDICT_READY id=<id>\n",
                encoding="utf-8",
            )

            result = self.run_check(root)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("referee-return-status", result.stderr)

    def test_command_skill_requires_public_artifact_delivery(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.copy_contract_tree(root)
            skill = root / "skills/start/SKILL.md"
            skill.write_text(
                re.sub(
                    r'(\$SC/read_verdict_artifact["`]?[ \t\n]+)--delivery\b',
                    r"\1--unvalidated",
                    skill.read_text(encoding="utf-8"),
                ),
                encoding="utf-8",
            )

            result = self.run_check(root)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("public-artifact-delivery", result.stderr)

    def test_barrier_shell_shape_rejects_long_foreground_wait(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.copy_contract_tree(root)
            barrier = root / "agents/panel-review-cli-barrier.md"
            text = barrier.read_text(encoding="utf-8")
            barrier.write_text(text.replace("timeout 100 bash -c", "timeout 540 bash -c", 1), encoding="utf-8")

            result = self.run_check(root)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("cli-barrier-command-shape", result.stderr)

    def test_claude_seat_tool_surface_rejects_write_access(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.copy_contract_tree(root)
            seat = root / "agents/panel-review-claude-seat.md"
            text = seat.read_text(encoding="utf-8")
            seat.write_text(text.replace("mcp__tilth__tilth_read", "mcp__tilth__tilth_write", 1), encoding="utf-8")

            result = self.run_check(root)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("claude-seat-tool-surface", result.stderr)

    def test_agy_prompt_templates_keep_the_seat_contract_first(self):
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

if __name__ == "__main__":
    unittest.main()
