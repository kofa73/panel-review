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
    def run_hook(self, agent_type, message, transcript_path=None, stop_hook_active=False):
        payload = {
            "hook_event_name": "SubagentStop",
            "agent_type": agent_type,
            "last_assistant_message": message,
            "stop_hook_active": stop_hook_active,
        }
        if transcript_path is not None:
            payload["agent_transcript_path"] = str(transcript_path)
        return subprocess.run(
            [str(HOOK)],
            input=json.dumps(payload),
            text=True,
            capture_output=True,
            check=False,
        )

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

    def test_plugin_registers_hook_for_both_status_stub_agents(self):
        config = json.loads(HOOK_CONFIG.read_text(encoding="utf-8"))
        groups = config["hooks"]["SubagentStop"]

        self.assertEqual(len(groups), 1)
        self.assertEqual(
            groups[0]["matcher"],
            "^panel-review:(panel-review-claude-seat|panel-review-referee)$",
        )
        self.assertEqual(
            groups[0]["hooks"][0]["command"],
            '"${CLAUDE_PLUGIN_ROOT}/hooks/enforce_agent_status_stub"',
        )

    def test_skills_directory_installer_ships_executable_hook(self):
        with tempfile.TemporaryDirectory() as claude_dir:
            env = os.environ.copy()
            env["CLAUDE_DIR"] = claude_dir
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

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(installed.is_file())
            self.assertTrue(os.access(installed, os.X_OK))

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
