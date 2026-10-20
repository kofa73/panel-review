"""Coverage for check_draft — the seat-facing pre-emit validator.

check_draft wraps `parse_block --diagnose` and the shared seat-contract rules; these
tests pin its seat-facing contract (exit codes, dropped-field diagnostics,
bare-JSONL vs fenced input, stdin vs file) and,
crucially, that it CATCHES the mixed valid/invalid block that parse_block's normal
mode silently accepts by dropping the bad lines.
"""

import unittest
import subprocess
import os
import tempfile
import json

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CHECK = os.path.join(ROOT, "scripts", "check_draft")
PARSE = os.path.join(ROOT, "scripts", "parse_block")

VALID_FINDING = ('{"claim":"ok","location":"f.c:1","category":"correctness",'
                 '"severity":"high","points":[{"assertion":"x","location":"f.c:1"}]}')
# missing `claim` — schema-invalid but syntactically valid JSON
INVALID_FINDING = ('{"location":"f.c:2","category":"correctness","severity":"high",'
                   '"points":[{"assertion":"x","location":"f.c:2"}]}')
VALID_STANCE = '{"id":"i1","stance":"support","rationale":"ok"}'
VALID_FULL_STANCE = ('{"id":"i1","stance":"support","revision":{"severity":"high",'
                     '"category":"correctness","claim":"corrected","location":"f.c:1"},'
                     '"new_evidence":{"assertion":"x","location":"f.c:2"}}')
INVALID_STANCE = '{"id":"i2","stance":"maybe","rationale":"bad enum"}'
# issue 34: a tally in text the referee promotes verbatim onto a card
TALLY_STANCE = ('{"id":"i3","stance":"reject",'
                '"rationale":"2 of 3 seats agree the bound is wrong"}')
# the same rationale minus the tally — domain vocabulary alone is not a leak
DOMAIN_STANCE = ('{"id":"i4","stance":"reject",'
                 '"rationale":"the Claude seat prompt anchors another seat\'s path"}')


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

    def test_valid_revision_and_evidence_keep_the_existing_ok_summary(self):
        res = self.run_stdin(["stances"], VALID_FULL_STANCE + "\n")
        self.assertEqual(res.returncode, 0)
        self.assertEqual(
            res.stdout,
            "OK — 1 item(s), 0 invalid. Safe to emit your ```stances block.\n",
        )

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

    def test_tally_rationale_is_flagged_before_the_seat_emits(self):
        res = self.run_stdin(["stances"], TALLY_STANCE + "\n")
        self.assertEqual(res.returncode, 1)
        self.assertIn("will not be promoted", res.stdout)

    def test_domain_vocabulary_rationale_passes(self):
        res = self.run_stdin(["stances"], DOMAIN_STANCE + "\n")
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)

    def test_invalid_revision_severity_is_reported_even_when_other_revision_fields_survive(self):
        draft = ('{"id":"i1","stance":"support","revision":{"severity":"moderate",'
                 '"claim":"corrected"}}\n')
        res = self.run_stdin(["stances"], draft)
        self.assertEqual(res.returncode, 1)
        self.assertIn("invalid `revision.severity`", res.stdout)
        self.assertIn("would be dropped", res.stdout)

    def test_invalid_new_evidence_reports_missing_location(self):
        draft = ('{"id":"i1","stance":"support","new_evidence":{"assertion":"new fact"}}\n')
        res = self.run_stdin(["stances"], draft)
        self.assertEqual(res.returncode, 1)
        self.assertIn("invalid `new_evidence` will be discarded", res.stdout)
        self.assertIn("missing `location`", res.stdout)

    def test_reject_revision_is_reported_before_it_is_discarded(self):
        draft = ('{"id":"i1","stance":"reject","rationale":"counter-evidence",'
                 '"revision":{"severity":"high"}}\n')
        res = self.run_stdin(["stances"], draft)
        self.assertEqual(res.returncode, 1)
        self.assertIn("`revision` will be discarded from a reject stance", res.stdout)

    def test_all_invalid_revision_and_evidence_fields_are_reported(self):
        draft = ('{"id":"i1","stance":"support","revision":{"severity":"moderate",'
                 '"extra":"x"},"new_evidence":{"assertion":"new fact"},'
                 '"evidence":{"location":"f.c:3"}}\n')
        res = self.run_stdin(["stances"], draft)
        self.assertEqual(res.returncode, 1)
        for expected in (
            "invalid `revision.severity`",
            "unknown `revision.extra` field",
            "`revision` would be removed",
            "invalid `new_evidence` will be discarded",
            "invalid `evidence` will be discarded",
        ):
            with self.subTest(expected=expected):
                self.assertIn(expected, res.stdout)

    def test_partial_point_loss_is_reported_and_parse_still_keeps_the_valid_point(self):
        invalid = '{"assertion":"missing location"}'
        draft = VALID_FINDING[:-2] + "," + invalid + "]}"
        res = self.run_stdin(["findings"], draft + "\n")
        self.assertEqual(res.returncode, 1)
        self.assertIn("1 point(s) in `points[]` would be dropped", res.stdout)
        self.assertIn("point 2: missing `location`", res.stdout)

        with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as tf:
            tf.write(f"```findings\n{draft}\n```\n")
            tmp = tf.name
        try:
            parsed = subprocess.run([PARSE, "findings", tmp, "claude"], capture_output=True, text=True)
            self.assertEqual(parsed.returncode, 0, parsed.stderr)
            normalized = json.loads(parsed.stdout)
            self.assertEqual(len(normalized["points"]), 1)
        finally:
            os.remove(tmp)

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
