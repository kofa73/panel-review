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

    def test_stances_revision_invalid_subfield_stripped(self):
        content = """```stances
{"id":"i1","stance":"support_with_revision","revision":{"severity":"low","category":"bogus","claim":123,"location":"f.c:1"}}
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
{"id":"i1","stance":"support_with_revision","revision":{"category":"bogus"}}
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
