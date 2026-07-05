"""Coverage for check_draft — the seat-facing pre-emit validator.

check_draft is a thin wrapper over `parse_block --diagnose`; these tests pin the
seat-facing contract (exit codes, bare-JSONL vs fenced input, stdin vs file) and,
crucially, that it CATCHES the mixed valid/invalid block that parse_block's normal
mode silently accepts by dropping the bad lines.
"""

import unittest
import subprocess
import os
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CHECK = os.path.join(ROOT, "scripts", "check_draft")
PARSE = os.path.join(ROOT, "scripts", "parse_block")

VALID_FINDING = ('{"claim":"ok","location":"f.c:1","category":"correctness",'
                 '"severity":"high","points":[{"assertion":"x","location":"f.c:1"}]}')
# missing `claim` — schema-invalid but syntactically valid JSON
INVALID_FINDING = ('{"location":"f.c:2","category":"correctness","severity":"high",'
                   '"points":[{"assertion":"x","location":"f.c:2"}]}')
VALID_STANCE = '{"id":"i1","stance":"support","rationale":"ok"}'
INVALID_STANCE = '{"id":"i2","stance":"maybe","rationale":"bad enum"}'


class TestCheckDraft(unittest.TestCase):
    def run_stdin(self, args, draft):
        return subprocess.run([CHECK] + args, input=draft, capture_output=True, text=True)

    # --- happy paths -----------------------------------------------------
    def test_all_valid_bare_jsonl_stdin(self):
        res = self.run_stdin(["findings"], VALID_FINDING + "\n")
        self.assertEqual(res.returncode, 0)
        self.assertIn("Safe to emit", res.stdout)

    def test_all_valid_stances(self):
        res = self.run_stdin(["stances"], VALID_STANCE + "\n")
        self.assertEqual(res.returncode, 0)
        self.assertIn("Safe to emit", res.stdout)

    def test_new_findings_uses_findings_rules(self):
        res = self.run_stdin(["new_findings"], VALID_FINDING + "\n")
        self.assertEqual(res.returncode, 0)

    def test_empty_draft_is_ok(self):
        # an empty findings block is a legitimate "found nothing"
        res = self.run_stdin(["findings"], "")
        self.assertEqual(res.returncode, 0)
        self.assertIn("empty findings block", res.stdout)

    def test_already_fenced_input_passthrough(self):
        draft = f"```findings\n{VALID_FINDING}\n```\n"
        res = self.run_stdin(["findings"], draft)
        self.assertEqual(res.returncode, 0)
        self.assertIn("Safe to emit", res.stdout)

    # --- failure paths ---------------------------------------------------
    def test_invalid_finding_fails_with_reason(self):
        res = self.run_stdin(["findings"], INVALID_FINDING + "\n")
        self.assertEqual(res.returncode, 1)
        self.assertIn("missing or non-string field `claim`", res.stdout)
        self.assertIn("FAIL", res.stderr)

    def test_invalid_stance_enum_fails(self):
        res = self.run_stdin(["stances"], INVALID_STANCE + "\n")
        self.assertEqual(res.returncode, 1)
        self.assertIn("missing/invalid `stance`", res.stdout)

    def test_bad_tag_is_usage_error(self):
        res = self.run_stdin(["bogus"], "")
        self.assertEqual(res.returncode, 2)

    def test_no_args_is_usage_error(self):
        res = subprocess.run([CHECK], capture_output=True, text=True)
        self.assertEqual(res.returncode, 2)

    # --- the whole point: the silent-drop gap ----------------------------
    def test_mixed_block_caught_where_parse_block_drops_silently(self):
        """3 valid + 2 invalid: parse_block's normal mode exits 0 (drops the two
        bad lines with only a stderr note); check_draft flags them (exit 1)."""
        lines = [VALID_FINDING, INVALID_FINDING, VALID_FINDING, INVALID_FINDING, VALID_FINDING]
        draft = "\n".join(lines) + "\n"

        # check_draft catches it
        res = self.run_stdin(["findings"], draft)
        self.assertEqual(res.returncode, 1)
        self.assertIn("2 invalid", res.stderr)

        # parse_block normal mode would have silently accepted it
        with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as tf:
            tf.write(f"```findings\n{draft}```\n")
            tmp = tf.name
        try:
            pb = subprocess.run([PARSE, "findings", tmp, "claude"], capture_output=True, text=True)
            self.assertEqual(pb.returncode, 0)  # survives — the gap check_draft closes
            self.assertIn("skipped 2 malformed line(s)", pb.stderr)
        finally:
            os.remove(tmp)

    # --- file argument (vs stdin) ---------------------------------------
    def test_file_argument(self):
        with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as tf:
            tf.write(INVALID_FINDING + "\n")
            tmp = tf.name
        try:
            res = subprocess.run([CHECK, "findings", tmp], capture_output=True, text=True)
            self.assertEqual(res.returncode, 1)
            self.assertIn("missing or non-string field `claim`", res.stdout)
        finally:
            os.remove(tmp)

    def test_missing_file_is_usage_error(self):
        res = subprocess.run([CHECK, "findings", "/no/such/file.txt"], capture_output=True, text=True)
        self.assertEqual(res.returncode, 2)


if __name__ == "__main__":
    unittest.main()
