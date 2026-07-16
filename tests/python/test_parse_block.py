import unittest
import subprocess
import os
import tempfile
import json

class TestParseBlock(unittest.TestCase):
    def setUp(self):
        self.script_path = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', 'scripts', 'parse_block'))
        self.fixtures_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'fixtures', 'parse_block'))

    def run_script(self, args):
        return subprocess.run([self.script_path] + args, capture_output=True, text=True)

    def test_empty_findings_block(self):
        # round0.codex.empty.txt -> exit 0
        fixture = os.path.join(self.fixtures_dir, 'round0.codex.empty.txt')
        res = self.run_script(['findings', fixture, 'codex'])
        self.assertEqual(res.returncode, 0)
        self.assertEqual(res.stdout, '')

    def test_empty_vs_real_stances_block(self):
        # SKILL idiom: an empty stances block is present-but-empty -> exit 0, no
        # output (the referee skips recording it); a real one emits >=1 object.
        with tempfile.TemporaryDirectory() as d:
            empty = os.path.join(d, 'empty.txt')
            with open(empty, 'w') as f:
                f.write('```stances\n```\n')
            res = self.run_script(['stances', empty, 'gemini'])
            self.assertEqual(res.returncode, 0)
            self.assertEqual(res.stdout, '')
            real = os.path.join(d, 'real.txt')
            with open(real, 'w') as f:
                f.write('```stances\n{"id":"i1","stance":"support","rationale":"ok"}\n```\n')
            res = self.run_script(['stances', real, 'gemini'])
            self.assertEqual(res.returncode, 0)
            self.assertTrue(res.stdout.strip())

    def test_empty_array_block_is_valid_not_malformed(self):
        # Concern F: an explicit `[]` block is a legitimate "nothing" (required-
        # emptyable new_findings), NOT malformed. It must exit 0 in BOTH normal and
        # diagnose mode so a seat that validated `[]` via check_draft is not then
        # falsely repaired by run_seat. Regression: it used to exit 5 in normal mode.
        for tag in ("findings", "new_findings"):
            with tempfile.TemporaryDirectory() as d:
                p = os.path.join(d, "arr.txt")
                with open(p, "w") as f:
                    f.write(f"```{tag}\n[]\n```\n")
                res = self.run_script([tag, p, "codex"])
                self.assertEqual(res.returncode, 0, f"normal mode, tag={tag}")
                self.assertEqual(res.stdout, "")
                res = self.run_script(["--diagnose", tag, p])
                self.assertEqual(res.returncode, 0, f"diagnose mode, tag={tag}")

    def test_content_present_but_all_unparseable_still_exit_5(self):
        # The exit-5 reservation: content present but nothing valid survives.
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "junk.txt")
            with open(p, "w") as f:
                f.write("```findings\n{not json}\n```\n")
            res = self.run_script(["findings", p, "codex"])
            self.assertEqual(res.returncode, 5)

    def test_response_mode_rejects_duplicate_required_blocks(self):
        finding = json.dumps({
            "claim": "x",
            "location": "f.c:1",
            "category": "correctness",
            "severity": "high",
            "points": [{"assertion": "x", "location": "f.c:1"}],
        })
        with tempfile.NamedTemporaryFile(mode="w", delete=False, suffix=".txt") as tmp:
            tmp.write(f"```findings\n{finding}\n```\n```findings\n{finding}\n```\n")
            tmp_path = tmp.name
        try:
            res = self.run_script(["--response", "round0", "findings", tmp_path])
            self.assertEqual(res.returncode, 5)
            self.assertIn("expected exactly one `findings` block, got 2", res.stderr)
        finally:
            os.remove(tmp_path)

    def test_response_mode_requires_both_debate_blocks(self):
        with tempfile.NamedTemporaryFile(mode="w", delete=False, suffix=".txt") as tmp:
            tmp.write('```stances\n{"id":"i1","stance":"support"}\n```\n')
            tmp_path = tmp.name
        try:
            res = self.run_script(["--response", "debate", "stances", tmp_path])
            self.assertEqual(res.returncode, 4)
            self.assertIn("expected exactly one `new_findings` block, got 0", res.stderr)
        finally:
            os.remove(tmp_path)

    def test_flat_shape_findings(self):
        # round0.claude.flat.txt -> exit 5
        fixture = os.path.join(self.fixtures_dir, 'round0.claude.flat.txt')
        res = self.run_script(['findings', fixture, 'claude'])
        self.assertEqual(res.returncode, 5)

    def test_no_block(self):
        # round0.gemini.timeout.txt -> exit 4
        fixture = os.path.join(self.fixtures_dir, 'round0.gemini.timeout.txt')
        res = self.run_script(['findings', fixture, 'gemini'])
        self.assertEqual(res.returncode, 4)

    def test_stances_byte_identical(self):
        for seat in ['codex', 'gemini', 'claude']:
            fixture = os.path.join(self.fixtures_dir, f'round1.{seat}.stances.txt')
            expected_file = os.path.join(self.fixtures_dir, f'expected.{seat}.stances.json')
            with open(expected_file, 'r', encoding='utf-8') as f:
                expected = f.read()
            res = self.run_script(['stances', fixture, seat])
            self.assertEqual(res.returncode, 0)
            self.assertEqual(res.stdout, expected, f"Failed for {seat}")

    def test_diagnose_reasons_and_exit_5(self):
        # diagnose pinpoints each reason on a synthetic block
        content = """```findings
{"claim":"ok","location":"f.c:1","category":"correctness","severity":"high","points":[{"assertion":"x","location":"f.c:1"}]}
{"location":"f.c:2","category":"correctness","severity":"high","points":[{"assertion":"x","location":"f.c:2"}]}
{"claim":"x","location":"f.c:3","category":"bogus","severity":"high","points":[{"assertion":"x","location":"f.c:3"}]}
{"claim":"x","location":"f.c:4","category":"correctness","severity":"epic","points":[{"assertion":"x","location":"f.c:4"}]}
{"claim":"x","location":"f.c:5","category":"correctness","severity":"high","points":[{"impact":"no assertion"}]}
{not json}
```"""
        with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.txt') as tmp:
            tmp.write(content)
            tmp_path = tmp.name

        try:
            res = self.run_script(['--diagnose', 'findings', tmp_path])
            self.assertEqual(res.returncode, 5)
            stdout = res.stdout

            self.assertIn("item 2: missing or non-string field `claim`", stdout)
            self.assertIn("item 3: missing/invalid `category`", stdout)
            self.assertIn("item 4: missing/invalid `severity`", stdout)
            self.assertIn("item 5: no valid `points[]`", stdout)
            self.assertIn("item 6: not valid JSON", stdout)
        finally:
            os.remove(tmp_path)

    def test_diagnose_valid_stances_exit_0(self):
        # valid stances -> exit 0, no stdout
        fixture = os.path.join(self.fixtures_dir, 'round1.codex.stances.txt')
        res = self.run_script(['--diagnose', 'stances', fixture])
        self.assertEqual(res.returncode, 0)
        self.assertEqual(res.stderr.strip(), "parse_block --diagnose 'stances': 5 item(s), 0 invalid")
        self.assertEqual(res.stdout, '')

    def test_removed_support_with_revision_stance_is_rejected(self):
        content = """```stances
{"id":"i1","stance":"support_with_revision","revision":{"severity":"low"}}
```"""
        with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.txt') as tmp:
            tmp.write(content)
            tmp_path = tmp.name
        try:
            res = self.run_script(['--diagnose', 'stances', tmp_path])
            self.assertEqual(res.returncode, 5)
            self.assertIn("one of: support, reject", res.stdout)
        finally:
            os.remove(tmp_path)

    def test_reject_requires_nonempty_rationale(self):
        content = """```stances
{"id":"i1","stance":"reject","rationale":"   "}
```"""
        with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.txt') as tmp:
            tmp.write(content)
            tmp_path = tmp.name
        try:
            res = self.run_script(['--diagnose', 'stances', tmp_path])
            self.assertEqual(res.returncode, 5)
            self.assertIn("reject requires non-empty `rationale`", res.stdout)
        finally:
            os.remove(tmp_path)

    def test_support_rationale_is_optional(self):
        content = """```stances
{"id":"i1","stance":"support"}
```"""
        with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.txt') as tmp:
            tmp.write(content)
            tmp_path = tmp.name
        try:
            res = self.run_script(['stances', tmp_path])
            self.assertEqual(res.returncode, 0, res.stderr)
            self.assertEqual(json.loads(res.stdout), {"id": "i1", "stance": "support"})
        finally:
            os.remove(tmp_path)

    def test_reject_revision_is_discarded(self):
        content = """```stances
{"id":"i1","stance":"reject","rationale":"The path is unreachable.","revision":{"severity":"low"}}
```"""
        with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.txt') as tmp:
            tmp.write(content)
            tmp_path = tmp.name
        try:
            res = self.run_script(['stances', tmp_path])
            self.assertEqual(res.returncode, 0, res.stderr)
            self.assertNotIn("revision", json.loads(res.stdout))
        finally:
            os.remove(tmp_path)

    def test_stances_revision_invalid_subfield_stripped(self):
        content = """```stances
{"id":"i1","stance":"support","revision":{"severity":"low","category":"bogus","claim":123,"location":"f.c:1"}}
```"""
        with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.txt') as tmp:
            tmp.write(content)
            tmp_path = tmp.name
        try:
            res = self.run_script(['stances', tmp_path])
            self.assertEqual(res.returncode, 0)
            obj = json.loads(res.stdout.strip())
            self.assertIn("revision", obj)
            self.assertEqual(obj["revision"], {"severity":"low","location":"f.c:1"})
        finally:
            os.remove(tmp_path)

    def test_stances_revision_empty_after_stripping(self):
        content = """```stances
{"id":"i1","stance":"support","revision":{"category":"bogus"}}
```"""
        with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.txt') as tmp:
            tmp.write(content)
            tmp_path = tmp.name
        try:
            res = self.run_script(['stances', tmp_path])
            self.assertEqual(res.returncode, 0)
            obj = json.loads(res.stdout.strip())
            self.assertNotIn("revision", obj)
        finally:
            os.remove(tmp_path)

if __name__ == '__main__':
    unittest.main()
