import json
import os
import subprocess
import tempfile
import unittest

class TestDecideDegradedRound(unittest.TestCase):
    def setUp(self):
        self.maxDiff = None
        self.script = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../scripts/decide_degraded_round"))

    def run_script(self, args, id_val, index_content, stances_content):
        # Create tmp dir
        tmp_dir = f"/tmp/{id_val}"
        os.makedirs(tmp_dir, exist_ok=True)
        try:
            with open(os.path.join(tmp_dir, "index.json"), "w") as f:
                json.dump(index_content, f)

            with tempfile.NamedTemporaryFile("w", delete=False) as st:
                for line in stances_content:
                    st.write(json.dumps(line) + "\n")
                stances_file = st.name

            cmd = [self.script] + args + ["--stances", stances_file]
            result = subprocess.run(cmd, capture_output=True, text=True)
            return result
        finally:
            # Cleanup
            import shutil
            shutil.rmtree(tmp_dir, ignore_errors=True)
            if 'stances_file' in locals() and os.path.exists(stances_file):
                os.remove(stances_file)

    def test_one_engaged_seat(self):
        index = {
            "issues": [
                {"id": "old", "state": "open", "peer_reviewed": True},
                {"id": "new", "state": "open", "peer_reviewed": False}
            ],
            "evaluated_by": {
                "old": ["claude", "codex"],
                "new": ["codex"]
            }
        }
        stances = [
            {"_source": "gemini", "id": "old", "stance": "support"},
            {"_source": "gemini", "id": "new", "stance": "reject", "rationale": "The issue is not established."}
        ]

        args = [
            "--id", "test1",
            "--round", "1",
            "--configured", "codex claude gemini",
            "--engaged", "gemini"
        ]

        res = self.run_script(args, "test1", index, stances)
        self.assertEqual(res.returncode, 0, f"Failed: {res.stderr}")
        out = json.loads(res.stdout)

        self.assertIn("set_state", out)
        states = {s["id"]: s["state"] for s in out["set_state"]}
        self.assertEqual(states["old"], "contested")
        self.assertEqual(states["new"], "unresolved")

        self.assertIn("set_flag", out)
        self.assertEqual(len(out["set_flag"]), 1)
        self.assertEqual(out["set_flag"][0]["id"], "old")
        self.assertEqual(out["set_flag"][0]["flag"], "fully_vetted")
        self.assertEqual(out["set_flag"][0]["value"], True)

        self.assertIn("evaluated_by", out)
        self.assertEqual(sorted(out["evaluated_by"]["old"]), ["claude", "codex", "gemini"])
        self.assertEqual(sorted(out["evaluated_by"]["new"]), ["codex", "gemini"])

    def test_zero_engaged_seats(self):
        index = {
            "issues": [
                {"id": "old", "state": "open", "peer_reviewed": True},
                {"id": "new", "state": "open", "peer_reviewed": False}
            ],
            "evaluated_by": {}
        }
        stances = []
        args = [
            "--id", "test2",
            "--round", "1",
            "--configured", "codex claude",
            "--engaged", ""
        ]
        res = self.run_script(args, "test2", index, stances)
        self.assertEqual(res.returncode, 0, f"Failed: {res.stderr}")
        out = json.loads(res.stdout)

        states = {s["id"]: s["state"] for s in out["set_state"]}
        self.assertEqual(states["old"], "unresolved")
        self.assertEqual(states["new"], "unresolved")
        self.assertNotIn("set_flag", out)

    def test_two_engaged_seats(self):
        index = {"issues": []}
        stances = []
        args = [
            "--id", "test3",
            "--round", "1",
            "--configured", "codex claude",
            "--engaged", "codex claude"
        ]
        res = self.run_script(args, "test3", index, stances)
        self.assertEqual(res.returncode, 2)
        self.assertIn("requires zero or one engaged seat", res.stderr)

    def test_integrity_unknown_source(self):
        index = {
            "issues": [
                {"id": "old", "state": "open", "peer_reviewed": True}
            ],
            "evaluated_by": {}
        }
        stances = [
            {"_source": "gemini", "id": "old", "stance": "support"}
        ]
        args = [
            "--id", "test4",
            "--round", "1",
            "--configured", "codex claude",
            "--engaged", "codex"
        ]
        res = self.run_script(args, "test4", index, stances)
        self.assertEqual(res.returncode, 3)
        self.assertIn("unknown _source: gemini", res.stderr)

    def test_integrity_wrong_stance_count(self):
        index = {
            "issues": [
                {"id": "old", "state": "open", "peer_reviewed": True}
            ],
            "evaluated_by": {}
        }
        stances = [
            {"_source": "codex", "id": "old", "stance": "support"},
            {"_source": "codex", "id": "old", "stance": "reject", "rationale": "The issue is not established."}
        ]
        args = [
            "--id", "test5",
            "--round", "1",
            "--configured", "codex claude",
            "--engaged", "codex"
        ]
        res = self.run_script(args, "test5", index, stances)
        self.assertEqual(res.returncode, 3)
        self.assertIn("expected exactly 1 stance for seat=codex issue=old, got 2", res.stderr)

    def test_integrity_zero_seat_with_stances(self):
        index = {
            "issues": [
                {"id": "old", "state": "open", "peer_reviewed": True}
            ],
            "evaluated_by": {}
        }
        stances = [
            {"_source": "gemini", "id": "old", "stance": "support"}
        ]
        args = [
            "--id", "test6",
            "--round", "1",
            "--configured", "codex claude",
            "--engaged", ""
        ]
        res = self.run_script(args, "test6", index, stances)
        self.assertEqual(res.returncode, 3)
        self.assertIn("zero-seat round has stances", res.stderr)

if __name__ == "__main__":
    unittest.main()
