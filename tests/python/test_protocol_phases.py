"""Coverage for lazy reads from the canonical referee procedure."""

from pathlib import Path
import re
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[2]
READER = ROOT / "scripts" / "read_protocol_phase"
PROTOCOL = ROOT / "skills" / "panel-review-for-agent" / "references" / "protocol.md"
REFEREE = ROOT / "agents" / "panel-review-referee.md"
BOOTSTRAP = ROOT / "skills" / "panel-review-for-agent" / "SKILL.md"
PHASES = ("common", "salvage", "round0", "debate", "degraded", "gate", "recovery", "verdict")


class ProtocolPhasesTest(unittest.TestCase):
    def test_each_phase_is_independently_readable(self):
        source = PROTOCOL.read_text(encoding="utf-8")
        for phase in PHASES:
            with self.subTest(phase=phase):
                result = subprocess.run([str(READER), phase], capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                matches = re.findall(
                    rf"<!-- phase:{phase} -->\n(.*?)<!-- /phase:{phase} -->",
                    source,
                    re.DOTALL,
                )
                self.assertTrue(matches, phase)
                self.assertEqual(result.stdout.strip(), "\n".join(matches).strip())
                self.assertNotIn("<!-- phase:", result.stdout)

    def test_marked_phases_cover_all_canonical_procedure_text(self):
        source = PROTOCOL.read_text(encoding="utf-8")
        outside = source
        emitted = []
        for phase in PHASES:
            pattern = rf"<!-- phase:{phase} -->\n(.*?)<!-- /phase:{phase} -->"
            matches = re.findall(pattern, source, re.DOTALL)
            self.assertTrue(matches, phase)
            emitted.extend(matches)
            outside = re.sub(pattern, "", outside, flags=re.DOTALL)
        self.assertEqual(outside.strip(), "# Panel Review — referee procedure (v10)")
        self.assertTrue(all(text.strip() for text in emitted))

    def test_unknown_phase_is_usage_error(self):
        result = subprocess.run([str(READER), "future"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("usage: read_protocol_phase", result.stderr)

    def test_debate_contract_uses_only_the_coarse_commit_interface(self):
        result = subprocess.run([str(READER), "debate"], capture_output=True, text=True)

        self.assertEqual(result.returncode, 0, result.stderr)
        decision_command = '"$SC/round" commit "$id"'
        self.assertIn(decision_command, result.stdout)
        self.assertIn('round commit "$id" --addendum', result.stdout)
        self.assertNotRegex(result.stdout, r'\$SC/merge_payload\b')
        self.assertNotRegex(result.stdout, r'\$SC/sweep"?[ \t]+commit\b')
        post_decision = result.stdout.partition(decision_command)[2]
        self.assertNotRegex(post_decision, r'\$SC/regen_cards\b')

    def test_referee_return_contract_distinguishes_review_and_write_failures(self):
        referee = REFEREE.read_text(encoding="utf-8")
        bootstrap = BOOTSTRAP.read_text(encoding="utf-8")

        self.assertIn("PANEL_VERDICT_WRITE_FAILED id=<id>", bootstrap)
        self.assertIn("PANEL_REVIEW_FAILED id=<id>", bootstrap)
        self.assertNotIn("PANEL_VERDICT_WRITE_FAILED", referee)
        self.assertNotIn("PANEL_REVIEW_FAILED", referee)


if __name__ == "__main__":
    unittest.main()
