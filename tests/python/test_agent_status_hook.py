"""Black-box coverage for the Agent-to-caller status-stub hook."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
HOOK = ROOT / "hooks" / "enforce_agent_status_stub"
HOOK_CONFIG = ROOT / "hooks" / "hooks.json"


class AgentStatusHookTest(unittest.TestCase):
    def run_hook(
        self,
        agent_type,
        message,
        transcript_path=None,
        stop_hook_active=False,
        permission_mode="default",
        session_id=None,
        agent_id=None,
        state_dir=None,
    ):
        payload = {
            "hook_event_name": "SubagentStop",
            "agent_type": agent_type,
            "last_assistant_message": message,
            "stop_hook_active": stop_hook_active,
            "permission_mode": permission_mode,
        }
        if session_id is not None:
            payload["session_id"] = session_id
        if agent_id is not None:
            payload["agent_id"] = agent_id
        if transcript_path is not None:
            payload["agent_transcript_path"] = str(transcript_path)

        def invoke(tmpdir):
            env = os.environ.copy()
            env["TMPDIR"] = str(tmpdir)
            return subprocess.run(
                [str(HOOK)],
                input=json.dumps(payload),
                text=True,
                capture_output=True,
                check=False,
                env=env,
            )

        if state_dir is None:
            with tempfile.TemporaryDirectory() as tmpdir:
                return invoke(tmpdir)
        return invoke(state_dir)

    def write_referee_transcript(self, directory, content):
        transcript = Path(directory) / "agent-referee.jsonl"
        transcript.write_text(
            json.dumps(
                {
                    "type": "user",
                    "message": {"role": "user", "content": content},
                }
            )
            + "\n",
            encoding="utf-8",
        )
        return transcript

    def run_handback_hook(
        self,
        agent_type,
        message,
        transcript_path=None,
        agent_id="seat-1",
        session_id="session-test",
        stop_hook_active=False,
        state_dir=None,
    ):
        payload = {
            "hook_event_name": "PreToolUse",
            "permission_mode": "auto",
            "agent_type": agent_type,
            "tool_name": "SubagentHandback",
            "tool_input": {"message": message},
            "stop_hook_active": stop_hook_active,
        }
        if session_id is not None:
            payload["session_id"] = session_id
        if agent_id is not None:
            payload["agent_id"] = agent_id
        if transcript_path is not None:
            payload["transcript_path"] = str(transcript_path)

        def invoke(tmpdir):
            env = os.environ.copy()
            env["TMPDIR"] = str(tmpdir)
            return subprocess.run(
                [str(HOOK)],
                input=json.dumps(payload),
                text=True,
                capture_output=True,
                check=False,
                env=env,
            )

        if state_dir is None:
            with tempfile.TemporaryDirectory() as tmpdir:
                return invoke(tmpdir)
        return invoke(state_dir)

    def write_handback_referee_transcript(self, directory, agent_id, content):
        session_transcript = Path(directory) / "session.jsonl"
        agent_transcript = (
            session_transcript.with_suffix("")
            / "subagents"
            / f"agent-{agent_id}.jsonl"
        )
        agent_transcript.parent.mkdir(parents=True)
        agent_transcript.write_text(
            json.dumps(
                {
                    "type": "user",
                    "message": {"role": "user", "content": content},
                }
            )
            + "\n",
            encoding="utf-8",
        )
        return session_transcript

    def test_prose_prefixed_claude_seat_stub_is_blocked(self):
        result = self.run_hook(
            "panel-review:panel-review-claude-seat",
            "The raw file was written.\nCLAUDE_SEAT_RAW_WRITTEN",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        decision = json.loads(result.stdout)
        self.assertEqual(decision["decision"], "block")
        self.assertNotIn("The raw file was written", decision["reason"])
        self.assertIn("CLAUDE_SEAT_RAW_WRITTEN", decision["reason"])

    def test_exact_claude_seat_stubs_are_allowed(self):
        for status in ("CLAUDE_SEAT_RAW_WRITTEN", "CLAUDE_SEAT_RAW_FAILED"):
            with self.subTest(status=status):
                result = self.run_hook("panel-review:panel-review-claude-seat", status)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, "")

    def test_exact_claude_seat_handbacks_are_allowed(self):
        for status in ("CLAUDE_SEAT_RAW_WRITTEN", "CLAUDE_SEAT_RAW_FAILED"):
            with self.subTest(status=status):
                result = self.run_handback_hook("panel-review:panel-review-claude-seat", status)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, "")

    def test_prose_prefixed_claude_seat_handback_is_denied(self):
        result = self.run_handback_hook(
            "panel-review:panel-review-claude-seat",
            "The raw file was written.\nCLAUDE_SEAT_RAW_WRITTEN",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        decision = json.loads(result.stdout)
        self.assertEqual(decision["hookSpecificOutput"]["hookEventName"], "PreToolUse")
        self.assertEqual(decision["hookSpecificOutput"]["permissionDecision"], "deny")
        reason = decision["hookSpecificOutput"]["permissionDecisionReason"]
        self.assertNotIn("The raw file was written", reason)
        self.assertIn("CLAUDE_SEAT_RAW_WRITTEN", reason)

    def test_referee_handback_uses_expected_id_from_agent_transcript(self):
        expected_id = "panel-20260718-120000-1234abcd"
        agent_id = "referee-1"
        with tempfile.TemporaryDirectory() as directory:
            transcript = self.write_handback_referee_transcript(
                directory,
                agent_id,
                "Run the panel-review referee protocol.\n"
                f"id={expected_id}\n"
                "mode=fresh",
            )

            exact = self.run_handback_hook(
                "panel-review:panel-review-referee",
                f"PANEL_VERDICT_READY id={expected_id}",
                transcript,
                agent_id,
            )
            wrong_id = self.run_handback_hook(
                "panel-review:panel-review-referee",
                "PANEL_VERDICT_READY id=panel-20260718-120000-deadbeef",
                transcript,
                agent_id,
            )

        self.assertEqual(exact.returncode, 0, exact.stderr)
        self.assertEqual(exact.stdout, "")
        self.assertEqual(wrong_id.returncode, 0, wrong_id.stderr)
        decision = json.loads(wrong_id.stdout)
        self.assertEqual(decision["hookSpecificOutput"]["permissionDecision"], "deny")
        self.assertIn(expected_id, decision["hookSpecificOutput"]["permissionDecisionReason"])
        self.assertNotIn("deadbeef", decision["hookSpecificOutput"]["permissionDecisionReason"])

    def test_referee_handback_without_task_transcript_is_denied(self):
        result = self.run_handback_hook(
            "panel-review:panel-review-referee",
            "PANEL_VERDICT_READY id=panel-20260718-120000-1234abcd",
            "/missing/session.jsonl",
            "referee-1",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            json.loads(result.stdout)["hookSpecificOutput"]["permissionDecision"],
            "deny",
        )

    def test_unreadable_transcript_failure_handback_gets_one_denial_then_stops(self):
        expected_id = "panel-20260718-120000-1234abcd"
        message = f"PANEL_REVIEW_FAILED id={expected_id}"
        with tempfile.TemporaryDirectory() as state_dir:
            first = self.run_handback_hook(
                "panel-review:panel-review-referee",
                message,
                "/missing/session.jsonl",
                "referee-1",
                session_id="session-bounded",
                stop_hook_active=True,
                state_dir=state_dir,
            )
            self.assertEqual(first.returncode, 0, first.stderr)
            self.assertEqual(
                json.loads(first.stdout)["hookSpecificOutput"]["permissionDecision"],
                "deny",
            )

            for attempt in range(9):
                with self.subTest(attempt=attempt + 2):
                    repeated = self.run_handback_hook(
                        "panel-review:panel-review-referee",
                        message,
                        "/missing/session.jsonl",
                        "referee-1",
                        session_id="session-bounded",
                        stop_hook_active=True,
                        state_dir=state_dir,
                    )
                    self.assertEqual(repeated.returncode, 0, repeated.stderr)
                    decision = json.loads(repeated.stdout)["hookSpecificOutput"]
                    self.assertEqual(decision["permissionDecision"], "allow")
                    self.assertEqual(
                        decision["updatedInput"]["message"],
                        message,
                    )

    def test_stop_gate_does_not_accept_closing_text_after_denied_handback(self):
        expected_id = "panel-20260718-120000-1234abcd"
        session_id = "session-denied-stop"
        agent_id = "referee-stop"
        with tempfile.TemporaryDirectory() as state_dir:
            rejected = self.run_handback_hook(
                "panel-review:panel-review-referee",
                "Review prose instead of a status.",
                "/missing/session.jsonl",
                agent_id,
                session_id=session_id,
                state_dir=state_dir,
            )
            self.assertEqual(
                json.loads(rejected.stdout)["hookSpecificOutput"]["permissionDecision"],
                "deny",
            )

            closing_text = self.run_hook(
                "panel-review:panel-review-referee",
                "Finding details must stay inside the referee.",
                "/missing/agent-transcript.jsonl",
                stop_hook_active=True,
                permission_mode="auto",
                session_id=session_id,
                agent_id=agent_id,
                state_dir=state_dir,
            )
            safe_failure = self.run_hook(
                "panel-review:panel-review-referee",
                f"PANEL_REVIEW_FAILED id={expected_id}",
                "/missing/agent-transcript.jsonl",
                stop_hook_active=True,
                permission_mode="auto",
                session_id=session_id,
                agent_id=agent_id,
                state_dir=state_dir,
            )

        self.assertEqual(closing_text.returncode, 0, closing_text.stderr)
        self.assertEqual(json.loads(closing_text.stdout)["decision"], "block")
        self.assertNotIn("Finding details", closing_text.stdout)
        self.assertEqual(safe_failure.returncode, 0, safe_failure.stderr)
        self.assertEqual(safe_failure.stdout, "")

    def test_terminal_handback_replaces_review_text_with_failure_status(self):
        expected_id = "panel-20260718-120000-1234abcd"
        raw_review = "Finding details must stay inside the referee."
        message = f"{raw_review}\nPANEL_VERDICT_READY id={expected_id}"
        with tempfile.TemporaryDirectory() as directory, tempfile.TemporaryDirectory() as state_dir:
            transcript = self.write_handback_referee_transcript(
                directory,
                "referee-2",
                f"Run the panel-review referee protocol.\nid={expected_id}\nmode=fresh",
            )
            first = self.run_handback_hook(
                "panel-review:panel-review-referee",
                message,
                transcript,
                "referee-2",
                session_id="session-sanitize",
                state_dir=state_dir,
            )
            self.assertEqual(
                json.loads(first.stdout)["hookSpecificOutput"]["permissionDecision"],
                "deny",
            )
            terminal = self.run_handback_hook(
                "panel-review:panel-review-referee",
                message,
                transcript,
                "referee-2",
                session_id="session-sanitize",
                state_dir=state_dir,
            )

        self.assertEqual(terminal.returncode, 0, terminal.stderr)
        decision = json.loads(terminal.stdout)["hookSpecificOutput"]
        self.assertEqual(decision["permissionDecision"], "allow")
        self.assertEqual(
            decision["updatedInput"]["message"],
            f"PANEL_REVIEW_FAILED id={expected_id}",
        )
        self.assertNotIn(raw_review, terminal.stdout)

    def test_terminal_handback_uses_unavailable_id_without_transcript_or_stub_id(self):
        with tempfile.TemporaryDirectory() as state_dir:
            first = self.run_handback_hook(
                "panel-review:panel-review-referee",
                "Review prose with no exact status.",
                "/missing/session.jsonl",
                "referee-3",
                session_id="session-no-id",
                state_dir=state_dir,
            )
            terminal = self.run_handback_hook(
                "panel-review:panel-review-referee",
                "Review prose with no exact status.",
                "/missing/session.jsonl",
                "referee-3",
                session_id="session-no-id",
                state_dir=state_dir,
            )

        self.assertEqual(
            json.loads(first.stdout)["hookSpecificOutput"]["permissionDecision"],
            "deny",
        )
        decision = json.loads(terminal.stdout)["hookSpecificOutput"]
        self.assertEqual(decision["permissionDecision"], "allow")
        self.assertEqual(
            decision["updatedInput"]["message"],
            "PANEL_REVIEW_FAILED id=unavailable",
        )
        self.assertNotIn("Review prose", terminal.stdout)

    def test_missing_agent_identity_uses_terminal_failure_immediately(self):
        message = "Review prose with no exact status."
        result = self.run_handback_hook(
            "panel-review:panel-review-referee",
            message,
            agent_id=None,
            session_id=None,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        decision = json.loads(result.stdout)["hookSpecificOutput"]
        self.assertEqual(decision["permissionDecision"], "allow")
        self.assertEqual(
            decision["updatedInput"]["message"],
            "PANEL_REVIEW_FAILED id=unavailable",
        )
        self.assertNotIn(message, result.stdout)

    def test_terminal_claude_seat_handback_becomes_failure_status(self):
        with tempfile.TemporaryDirectory() as state_dir:
            first = self.run_handback_hook(
                "panel-review:panel-review-claude-seat",
                "Review prose instead of a status.",
                agent_id="seat-2",
                session_id="session-seat-fallback",
                state_dir=state_dir,
            )
            terminal = self.run_handback_hook(
                "panel-review:panel-review-claude-seat",
                "Review prose instead of a status.",
                agent_id="seat-2",
                session_id="session-seat-fallback",
                state_dir=state_dir,
            )

        self.assertEqual(
            json.loads(first.stdout)["hookSpecificOutput"]["permissionDecision"],
            "deny",
        )
        decision = json.loads(terminal.stdout)["hookSpecificOutput"]
        self.assertEqual(decision["permissionDecision"], "allow")
        self.assertEqual(
            decision["updatedInput"]["message"],
            "CLAUDE_SEAT_RAW_FAILED",
        )
        self.assertNotIn("Review prose", terminal.stdout)

    def test_auto_mode_stop_accepts_closing_text_after_handback(self):
        expected_id = "panel-20260718-120000-1234abcd"
        with tempfile.TemporaryDirectory() as state_dir, tempfile.TemporaryDirectory() as transcript_dir:
            for agent_type in (
                "panel-review:panel-review-claude-seat",
                "panel-review:panel-review-referee",
            ):
                with self.subTest(agent_type=agent_type):
                    agent_id = "seat-stop" if agent_type.endswith("claude-seat") else "ref-stop"
                    session_transcript = None
                    agent_transcript = "/missing/agent-transcript.jsonl"
                    status = "CLAUDE_SEAT_RAW_WRITTEN"
                    if agent_type.endswith("referee"):
                        session_transcript = self.write_handback_referee_transcript(
                            transcript_dir,
                            agent_id,
                            f"Run the panel-review referee protocol.\nid={expected_id}\nmode=fresh",
                        )
                        agent_transcript = (
                            session_transcript.with_suffix("")
                            / "subagents"
                            / f"agent-{agent_id}.jsonl"
                        )
                        status = f"PANEL_VERDICT_READY id={expected_id}"

                    for index, closing_text in enumerate(("", "Closing note after the hand-back.")):
                        session_id = f"session-stop-{agent_id}-{index}"
                        accepted = self.run_handback_hook(
                            agent_type,
                            status,
                            session_transcript,
                            agent_id,
                            session_id=session_id,
                            state_dir=state_dir,
                        )
                        self.assertEqual(accepted.returncode, 0, accepted.stderr)
                        self.assertEqual(accepted.stdout, "")
                        result = self.run_hook(
                            agent_type,
                            closing_text,
                            agent_transcript,
                            permission_mode="auto",
                            session_id=session_id,
                            agent_id=agent_id,
                            state_dir=state_dir,
                        )
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertEqual(result.stdout, "")

    def test_other_permission_modes_keep_the_exact_stop_gate(self):
        for permission_mode in ("default", "bypassPermissions"):
            with self.subTest(permission_mode=permission_mode):
                result = self.run_hook(
                    "panel-review:panel-review-claude-seat",
                    "Closing text without the fixed status.",
                    permission_mode=permission_mode,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(result.stdout)["decision"], "block")

    def test_referee_stub_with_wrong_run_id_is_blocked(self):
        expected_id = "panel-20260718-120000-1234abcd"
        with tempfile.TemporaryDirectory() as directory:
            transcript = self.write_referee_transcript(
                directory,
                "Run the panel-review referee protocol.\n"
                f"id={expected_id}\n"
                "mode=fresh",
            )

            result = self.run_hook(
                "panel-review:panel-review-referee",
                "PANEL_VERDICT_READY id=panel-20260718-120000-deadbeef",
                transcript,
            )

        self.assertEqual(result.returncode, 0, result.stderr)
        decision = json.loads(result.stdout)
        self.assertEqual(decision["decision"], "block")
        self.assertIn(expected_id, decision["reason"])
        self.assertNotIn("deadbeef", decision["reason"])

    def test_exact_referee_stubs_are_allowed_and_prefixed_stub_is_blocked(self):
        expected_id = "panel-20260718-120000-1234abcd"
        with tempfile.TemporaryDirectory() as directory:
            transcript = self.write_referee_transcript(
                directory,
                f"mode=fresh\nid={expected_id}\n",
            )
            for status in (
                "PANEL_VERDICT_READY",
                "PANEL_VERDICT_WRITE_FAILED",
                "PANEL_REVIEW_FAILED",
            ):
                with self.subTest(status=status):
                    result = self.run_hook(
                        "panel-review:panel-review-referee",
                        f"{status} id={expected_id}",
                        transcript,
                    )
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout, "")

            prefixed = self.run_hook(
                "panel-review:panel-review-referee",
                f"Verdict summary.\nPANEL_VERDICT_READY id={expected_id}",
                transcript,
            )

        decision = json.loads(prefixed.stdout)
        self.assertEqual(decision["decision"], "block")
        self.assertNotIn("Verdict summary", decision["reason"])

    def test_referee_waiting_stub_is_blocked(self):
        expected_id = "panel-20260718-120000-1234abcd"
        with tempfile.TemporaryDirectory() as directory:
            transcript = self.write_referee_transcript(
                directory,
                f"mode=fresh\nid={expected_id}\n",
            )
            result = self.run_hook(
                "panel-review:panel-review-referee",
                f"PANEL_REVIEW_WAITING id={expected_id}",
                transcript,
            )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["decision"], "block")

    def test_referee_without_readable_task_prompt_is_blocked(self):
        result = self.run_hook(
            "panel-review:panel-review-referee",
            "PANEL_VERDICT_READY id=panel-20260718-120000-1234abcd",
            "/missing/agent-transcript.jsonl",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["decision"], "block")

    def test_invalid_retry_is_blocked_while_stop_hook_is_active(self):
        result = self.run_hook(
            "panel-review:panel-review-claude-seat",
            "Still not exact.\nCLAUDE_SEAT_RAW_WRITTEN",
            stop_hook_active=True,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["decision"], "block")

    def test_invalid_referee_retry_is_allowed_while_stop_hook_is_active(self):
        result = self.run_hook(
            "panel-review:panel-review-referee",
            "Still not exact.\nPANEL_VERDICT_READY id=wrong",
            "/missing/agent-transcript.jsonl",
            stop_hook_active=True,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")

    def test_unrelated_agent_is_unchanged(self):
        result = self.run_hook("Explore", "arbitrary result")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")

    def test_non_handback_pretool_call_is_unchanged(self):
        result = subprocess.run(
            [str(HOOK)],
            input=json.dumps(
                {
                    "hook_event_name": "PreToolUse",
                    "agent_type": "panel-review:panel-review-claude-seat",
                    "tool_name": "Bash",
                    "tool_input": {"command": "echo done"},
                }
            ),
            text=True,
            capture_output=True,
            check=False,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")

    def test_plugin_registers_hook_for_both_status_stub_agents(self):
        config = json.loads(HOOK_CONFIG.read_text(encoding="utf-8"))
        events = config["hooks"]
        groups = events["SubagentStop"]
        handback_groups = events["PreToolUse"]

        self.assertEqual(len(groups), 1)
        self.assertEqual(
            groups[0]["matcher"],
            "^panel-review:(panel-review-claude-seat|panel-review-referee)$",
        )
        self.assertEqual(
            groups[0]["hooks"][0]["command"],
            '"${CLAUDE_PLUGIN_ROOT}/hooks/enforce_agent_status_stub"',
        )
        self.assertEqual(len(handback_groups), 1)
        self.assertEqual(handback_groups[0]["matcher"], "SubagentHandback")
        self.assertEqual(
            handback_groups[0]["hooks"][0]["command"],
            '"${CLAUDE_PLUGIN_ROOT}/hooks/enforce_agent_status_stub"',
        )

    def test_skills_directory_installer_ships_executable_hook(self):
        with tempfile.TemporaryDirectory() as claude_dir:
            env = os.environ.copy()
            env["CLAUDE_DIR"] = claude_dir
            env["PANEL_REVIEW_BIN_DIR"] = str(Path(claude_dir) / "bin")
            result = subprocess.run(
                [str(ROOT / "install.sh")],
                cwd=ROOT,
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )
            installed = (
                Path(claude_dir)
                / "skills"
                / "panel-review"
                / "hooks"
                / "enforce_agent_status_stub"
            )
            installed_launcher = (
                Path(claude_dir)
                / "skills"
                / "panel-review"
                / "bin"
                / "panel-review-session"
            )
            launcher_link = Path(claude_dir) / "bin" / "panel-review-session"

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(installed.is_file())
            self.assertTrue(os.access(installed, os.X_OK))
            self.assertTrue(installed_launcher.is_file())
            self.assertTrue(os.access(installed_launcher, os.X_OK))
            self.assertTrue(launcher_link.is_symlink())
            self.assertEqual(launcher_link.resolve(), installed_launcher.resolve())
            self.assertIn("Linked:", result.stdout)

            rerun = subprocess.run(
                [str(ROOT / "install.sh")],
                cwd=ROOT,
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(rerun.returncode, 0, rerun.stderr)
            self.assertIn("Already linked:", rerun.stdout)

            project = Path(claude_dir) / "project"
            project.mkdir()
            subprocess.run(["git", "init", "-q"], cwd=project, check=True)
            mockbin = Path(claude_dir) / "mockbin"
            mockbin.mkdir()
            (mockbin / "codex").write_text(
                "#!/bin/sh\n"
                'if [ "$1" = login ] && [ "$2" = status ]; then '
                'printf "%s\\n" "Logged in using test account" >&2; fi\n',
                encoding="utf-8",
            )
            (mockbin / "agy").write_text("#!/bin/sh\nexit 1\n", encoding="utf-8")
            capture = Path(claude_dir) / "launcher-capture"
            (mockbin / "claude").write_text(
                "#!/bin/sh\n"
                "printf 'fork=%s\\narg=%s\\n' \"$CLAUDE_CODE_FORK_SUBAGENT\" "
                "\"$1\" > \"$LAUNCH_CAPTURE\"\n",
                encoding="utf-8",
            )
            for command in mockbin.iterdir():
                command.chmod(0o755)
            launch_env = env.copy()
            launch_env["CLAUDE_CONFIG_DIR"] = claude_dir
            launch_env["PATH"] = str(mockbin) + os.pathsep + launch_env["PATH"]
            launch_env["LAUNCH_CAPTURE"] = str(capture)
            launch_env.pop("CLAUDE_CODE_FORK_SUBAGENT", None)
            launched = subprocess.run(
                [str(launcher_link), "--version"],
                cwd=project,
                env=launch_env,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(launched.returncode, 0, launched.stdout + launched.stderr)
            self.assertEqual(capture.read_text(encoding="utf-8"), "fork=0\narg=--version\n")

    def test_skills_directory_installer_can_skip_session_launcher_link(self):
        with tempfile.TemporaryDirectory() as claude_dir:
            env = os.environ.copy()
            env["CLAUDE_DIR"] = claude_dir
            env["PANEL_REVIEW_BIN_DIR"] = str(Path(claude_dir) / "bin")
            env["PANEL_REVIEW_INSTALL_LAUNCHER"] = "0"
            result = subprocess.run(
                [str(ROOT / "install.sh")],
                cwd=ROOT,
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("Skipped the panel-review-session PATH link", result.stdout)
            self.assertFalse((Path(claude_dir) / "bin" / "panel-review-session").exists())

    def test_malformed_hook_input_fails_closed(self):
        result = subprocess.run(
            [str(HOOK)],
            input="not-json",
            text=True,
            capture_output=True,
            check=False,
        )

        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")
        self.assertIn("could not validate", result.stderr)
        self.assertNotIn("Traceback", result.stderr)


if __name__ == "__main__":
    unittest.main()
