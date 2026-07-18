"""End-to-end coverage for coarse normal-path round operations."""

import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import uuid


ROOT = Path(__file__).resolve().parents[2]
ROUND = ROOT / "scripts" / "round"
RESOLVE_DIFF = ROOT / "scripts" / "resolve_diff"
SWEEP = ROOT / "scripts" / "sweep"
WRITE_RAW = ROOT / "scripts" / "write_seat_raw"
PARSE_BLOCK = ROOT / "scripts" / "parse_block"

FINDING = {
    "claim": "new value is ignored",
    "location": "a.txt:1",
    "category": "correctness",
    "severity": "high",
    "points": [{"assertion": "the changed line is not read", "location": "a.txt:1"}],
}


def issue():
    return {
        "id": "i1",
        "claim": FINDING["claim"],
        "location": FINDING["location"],
        "category": FINDING["category"],
        "severity": FINDING["severity"],
        "evidence_pro": FINDING["points"],
        "evidence_contra": [],
        "peer_reviewed": False,
        "fully_vetted": False,
        "detail_contested": False,
        "state": "open",
        "rounds_debated": 0,
        "card_rev": 0,
    }


def debate_response(stance):
    return (
        f"```stances\n{json.dumps(stance)}\n```\n"
        "```new_findings\n[]\n```\n"
    )


class RoundTest(unittest.TestCase):
    def setUp(self):
        self.run_id = f"py-round-{uuid.uuid4().hex}"
        self.run_dir = Path("/tmp") / self.run_id
        self.run_dir.mkdir()
        self.workdir = Path(tempfile.mkdtemp(prefix="panel-round-work-"))
        subprocess.run(["git", "init", "-q"], cwd=self.workdir, check=True)
        subprocess.run(["git", "config", "user.name", "Test"], cwd=self.workdir, check=True)
        subprocess.run(["git", "config", "user.email", "test@example.invalid"], cwd=self.workdir, check=True)
        (self.workdir / "a.txt").write_text("old\n", encoding="utf-8")
        subprocess.run(["git", "add", "a.txt"], cwd=self.workdir, check=True)
        subprocess.run(["git", "commit", "-qm", "initial"], cwd=self.workdir, check=True)
        (self.workdir / "a.txt").write_text("new\n", encoding="utf-8")
        diff = subprocess.run(
            [str(RESOLVE_DIFF), "uncommitted"],
            cwd=self.workdir,
            capture_output=True,
            check=True,
        ).stdout
        manifest = {
            "id": self.run_id,
            "workdir": str(self.workdir),
            "scope": "uncommitted",
            "limits": {"issue_rounds": 2, "max_rounds": 4},
            "diff_hash": hashlib.sha256(diff).hexdigest(),
            "instructions": "",
            "phase": "round0",
            "state_version": 1,
            "created": "2026-07-14 00:00:00",
        }
        self.write_json(self.run_dir / "manifest.json", manifest)
        self.write_json(
            self.run_dir / "index.json",
            {"issues": [], "round": 0, "phase": "round0", "committed_rounds": [], "evaluated_by": {}},
        )

    def tearDown(self):
        shutil.rmtree(self.run_dir, ignore_errors=True)
        shutil.rmtree(self.workdir, ignore_errors=True)

    def write_json(self, path, value):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value), encoding="utf-8")

    def run_round(self, *args):
        return subprocess.run([str(ROUND), *map(str, args)], capture_output=True, text=True, check=False)

    def install_claude_debate(self, raw):
        result = subprocess.run(
            [str(WRITE_RAW), "--id", self.run_id, "--round", "1", "--batch", "1"],
            input=raw,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def install_codex_debate(self, raw):
        path = self.run_dir / "raw" / "round1.codex.1.txt"
        path.write_text(raw, encoding="utf-8")
        return path

    def prepare_round0(self, *seats):
        result = self.run_round(
            "prepare-round0", self.run_id, *(seats or ("claude", "codex"))
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def install_open_index(self):
        self.write_json(
            self.run_dir / "index.json",
            {
                "issues": [issue()],
                "round": 0,
                "phase": "debate",
                "committed_rounds": [],
                "run_epoch": 0,
                "evaluated_by": {"i1": ["claude"]},
            },
        )

    def prepare_prose_judgment(self):
        self.prepare_round0()
        self.install_open_index()
        prepared = self.run_round("prepare-debate", self.run_id, "claude", "codex")
        self.assertEqual(prepared.returncode, 0, prepared.stderr)
        raw = debate_response(
            {
                "id": "i1",
                "stance": "support",
                "rationale": "the mechanism is narrower",
                "revision": {"claim": "narrower claim"},
            }
        )
        self.install_claude_debate(raw)
        self.install_codex_debate(raw)
        collected = self.run_round("collect-debate", self.run_id, "--final")
        self.assertEqual(collected.returncode, 0, collected.stderr)

        needs_judgment = self.run_round("commit", self.run_id)
        self.assertEqual(needs_judgment.returncode, 3, needs_judgment.stderr)
        self.assertEqual(json.loads(needs_judgment.stdout)["status"], "needs_judgment_addendum")
        return needs_judgment

    def test_prepare_round0_builds_common_and_claude_delivery_prompts(self):
        prepared = self.prepare_round0()

        self.assertEqual(prepared["status"], "prepared")
        common = Path(prepared["prompt"]).read_text(encoding="utf-8")
        claude = Path(prepared["claude_prompt"]).read_text(encoding="utf-8")
        self.assertNotIn("CLAUDE_SEAT_RAW_WRITTEN", common)
        self.assertIn("CLAUDE_SEAT_RAW_WRITTEN", claude)
        self.assertIn(str(self.run_dir / "raw" / "round0.claude.txt"), claude)
        barrier = Path(prepared["command"]).read_text(encoding="utf-8")
        self.assertIn("--seat codex", barrier)
        self.assertNotIn("--seat claude", barrier)
        self.assertTrue((self.run_dir / "guard" / "manifest.sha256").is_file())

    def test_prepare_round0_renders_the_configured_panel_size(self):
        prepared = self.prepare_round0("claude", "codex")
        prompt = Path(prepared["prompt"]).read_text(encoding="utf-8")

        self.assertIn("configured panel has 2 reviewer seats, including you", prompt)
        self.assertNotIn("two other AIs", prompt)

    def test_prepare_round0_renders_the_full_panel_size(self):
        prepared = self.prepare_round0("claude", "codex", "gemini")
        prompt = Path(prepared["prompt"]).read_text(encoding="utf-8")

        self.assertIn("configured panel has 3 reviewer seats, including you", prompt)

    def test_rendered_round0_contract_example_passes_runtime_validation(self):
        prepared = self.prepare_round0()

        parsed = subprocess.run(
            [str(PARSE_BLOCK), "--diagnose", "findings", prepared["prompt"]],
            capture_output=True,
            text=True,
            check=False,
        )

        self.assertEqual(parsed.returncode, 0, parsed.stdout + parsed.stderr)

    def test_collect_round0_parses_claude_raw_and_returns_compact_summary(self):
        self.prepare_round0()
        raw = f"```findings\n{json.dumps(FINDING)}\n```\n"
        written = subprocess.run(
            [str(WRITE_RAW), "--id", self.run_id, "--round", "0"],
            input=raw,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(written.returncode, 0, written.stderr)
        (self.run_dir / "status.codex").write_text("0\n", encoding="utf-8")
        (self.run_dir / "f.codex.json").write_text(json.dumps({**FINDING, "_source": "codex"}) + "\n", encoding="utf-8")

        result = self.run_round("collect-round0", self.run_id, "--final")

        self.assertEqual(result.returncode, 0, result.stderr)
        summary = json.loads(result.stdout)
        self.assertEqual(summary["engaged"], ["claude", "codex"])
        self.assertEqual(summary["finding_counts"], {"claude": 1, "codex": 1})
        self.assertTrue(summary["guard_clean"])

    def test_debate_prepare_collect_commit_and_verdict_input(self):
        self.prepare_round0()
        self.install_open_index()

        prepared_result = self.run_round("prepare-debate", self.run_id, "claude", "codex")
        self.assertEqual(prepared_result.returncode, 0, prepared_result.stderr)
        prepared = json.loads(prepared_result.stdout)
        claude_prompt = Path(prepared["claude_prompt"]).read_text(encoding="utf-8")
        self.assertIn("## Stance output", claude_prompt)
        self.assertIn("## New findings (ALWAYS emit this block)", claude_prompt)
        self.assertIn("For any multi-block response, put", claude_prompt)
        self.assertIn(
            "every requested block in that file and invoke this command once",
            claude_prompt,
        )
        self.assertIn("CLAUDE_SEAT_RAW_WRITTEN", claude_prompt)
        raw = debate_response({"id": "i1", "stance": "support", "rationale": "confirmed"})
        self.install_claude_debate(raw)
        self.install_codex_debate(raw)

        collected_result = self.run_round("collect-debate", self.run_id, "--final")
        self.assertEqual(collected_result.returncode, 0, collected_result.stderr)
        collected = json.loads(collected_result.stdout)
        self.assertEqual(collected["engaged"], ["claude", "codex"])

        committed_result = self.run_round("commit", self.run_id)
        self.assertEqual(committed_result.returncode, 0, committed_result.stderr)
        committed = json.loads(committed_result.stdout)
        self.assertEqual(committed["states"], {"accepted": 1})
        self.assertEqual(committed["gate"], {"open": 0, "low_only": False})

        origins = self.run_dir / "origins"
        origins.mkdir(exist_ok=True)
        (origins / "clusters.txt").write_text("i1: claude codex\n", encoding="utf-8")
        (origins / "round0.claude.raw.txt").write_text("large raw\n", encoding="utf-8")
        verdict_result = self.run_round("verdict-input", self.run_id)
        self.assertEqual(verdict_result.returncode, 0, verdict_result.stderr)
        verdict = json.loads(verdict_result.stdout)
        self.assertEqual(verdict["configured"], ["claude", "codex"])
        self.assertEqual(verdict["index"]["issues"][0]["state"], "accepted")
        self.assertEqual(verdict["origins"]["clusters.txt"], "i1: claude codex\n")
        self.assertNotIn("round0.claude.raw.txt", verdict["origins"])

    def test_missing_new_findings_block_prevents_debate_engagement(self):
        self.prepare_round0()
        self.install_open_index()
        prepared = self.run_round("prepare-debate", self.run_id, "claude", "codex")
        self.assertEqual(prepared.returncode, 0, prepared.stderr)
        stance = {"id": "i1", "stance": "support", "rationale": "confirmed"}
        self.install_claude_debate(debate_response(stance))
        (self.run_dir / "raw" / "round1.codex.1.txt").write_text(
            f"```stances\n{json.dumps(stance)}\n```\n",
            encoding="utf-8",
        )

        collected_result = self.run_round("collect-debate", self.run_id, "--final")

        self.assertEqual(collected_result.returncode, 0, collected_result.stderr)
        collected = json.loads(collected_result.stdout)
        self.assertEqual(collected["engaged"], ["claude"])
        codex = next(item for item in collected["batches"] if item["seat"] == "codex")
        self.assertEqual(codex["status"], "missing_new_findings")
        self.assertEqual(codex["new_findings_status"], 4)

    def test_salvaged_cli_debate_raw_survives_coarse_recollection_and_commit(self):
        self.prepare_round0()
        self.install_open_index()
        prepared = self.run_round("prepare-debate", self.run_id, "claude", "codex")
        self.assertEqual(prepared.returncode, 0, prepared.stderr)
        stance = {"id": "i1", "stance": "support", "rationale": "confirmed"}
        valid = debate_response(stance)
        self.install_claude_debate(valid)
        raw = self.run_dir / "raw" / "round1.codex.1.txt"
        malformed = f"```stances\n{json.dumps(stance)}\n```\n```new_findings\nnot-json\n```\n"
        raw.write_text(malformed, encoding="utf-8")

        first_collection = self.run_round("collect-debate", self.run_id)
        self.assertEqual(first_collection.returncode, 0, first_collection.stderr)
        codex = next(
            item for item in json.loads(first_collection.stdout)["batches"] if item["seat"] == "codex"
        )
        self.assertEqual(codex["status"], "malformed_new_findings")

        salvaged = Path(f"{raw}.salvaged")
        salvaged.write_text(
            f"```stances\n{json.dumps(stance)}\n```\n```new_findings\n[]\n```\n",
            encoding="utf-8",
        )
        salvage_result = self.run_round("salvage-debate", self.run_id, "codex", "1", salvaged)
        self.assertEqual(salvage_result.returncode, 0, salvage_result.stderr)
        self.assertEqual(json.loads(salvage_result.stdout)["status"], "complete")
        source = json.loads(
            (self.run_dir / "sweeps" / "round-1" / "codex.1.source.json").read_text(encoding="utf-8")
        )
        self.assertEqual(source, {"raw": str(salvaged), "salvaged": True})

        recollected_result = self.run_round("collect-debate", self.run_id)
        self.assertEqual(recollected_result.returncode, 0, recollected_result.stderr)
        recollected = json.loads(recollected_result.stdout)
        second_collection_result = self.run_round("collect-debate", self.run_id)
        self.assertEqual(second_collection_result.returncode, 0, second_collection_result.stderr)
        second_collection = json.loads(second_collection_result.stdout)
        committed_result = self.run_round("commit", self.run_id)

        self.assertEqual(
            {
                "engaged": recollected["engaged"],
                "second_engaged": second_collection["engaged"],
                "second_batches": second_collection["batches"],
                "commit_returncode": committed_result.returncode,
                "commit_status": (
                    json.loads(committed_result.stdout).get("status")
                    if committed_result.returncode == 0
                    else None
                ),
                "original_raw": raw.read_text(encoding="utf-8"),
            },
            {
                "engaged": ["claude", "codex"],
                "second_engaged": ["claude", "codex"],
                "second_batches": recollected["batches"],
                "commit_returncode": 0,
                "commit_status": "committed",
                "original_raw": malformed,
            },
        )

    def test_failed_cli_debate_salvage_leaves_no_stance_checkpoint(self):
        self.prepare_round0()
        self.install_open_index()
        prepared = self.run_round("prepare-debate", self.run_id, "claude", "codex")
        self.assertEqual(prepared.returncode, 0, prepared.stderr)
        stance = {"id": "i1", "stance": "support", "rationale": "confirmed"}
        self.install_claude_debate(debate_response(stance))
        raw = self.run_dir / "raw" / "round1.codex.1.txt"
        raw.write_text(
            f"```stances\n{json.dumps(stance)}\n```\n```new_findings\nnot-json\n```\n",
            encoding="utf-8",
        )
        first_collection = self.run_round("collect-debate", self.run_id)
        self.assertEqual(first_collection.returncode, 0, first_collection.stderr)

        salvaged = Path(f"{raw}.salvaged")
        salvaged.write_text(
            f"```stances\n{json.dumps(stance)}\n```\n```new_findings\nstill-not-json\n```\n",
            encoding="utf-8",
        )
        salvage_result = self.run_round("salvage-debate", self.run_id, "codex", "1", salvaged)
        self.assertEqual(salvage_result.returncode, 0, salvage_result.stderr)
        self.assertEqual(json.loads(salvage_result.stdout)["status"], "malformed_new_findings")

        checkpoint = subprocess.run(
            [str(SWEEP), "has", self.run_id, "1", "codex", "1"],
            capture_output=True,
            text=True,
            check=False,
        )
        recollected_result = self.run_round("collect-debate", self.run_id)
        self.assertEqual(recollected_result.returncode, 0, recollected_result.stderr)
        recollected = json.loads(recollected_result.stdout)

        self.assertEqual(checkpoint.returncode, 1)
        self.assertFalse((self.run_dir / "sweeps" / "round-1" / "codex.1.stances.json").exists())
        self.assertEqual(recollected["engaged"], ["claude"])
        (self.run_dir / "sweeps" / "round-1" / "codex.1.stances.json").write_text(
            json.dumps({"id": "i1", "stance": "support", "rationale": "stray", "_source": "codex"})
            + "\n",
            encoding="utf-8",
        )
        committed_result = self.run_round("commit", self.run_id)
        self.assertEqual(committed_result.returncode, 0, committed_result.stderr)

    def test_salvage_debate_rejects_claude_and_noncanonical_raw(self):
        self.prepare_round0()
        self.install_open_index()
        prepared = self.run_round("prepare-debate", self.run_id, "claude", "codex")
        self.assertEqual(prepared.returncode, 0, prepared.stderr)
        wrong_raw = self.run_dir / "wrong.salvaged"
        wrong_raw.write_text("not used\n", encoding="utf-8")

        claude = self.run_round("salvage-debate", self.run_id, "claude", "1", wrong_raw)
        codex = self.run_round("salvage-debate", self.run_id, "codex", "1", wrong_raw)

        self.assertEqual(claude.returncode, 2)
        self.assertIn("requires a CLI seat", claude.stderr)
        self.assertEqual(codex.returncode, 2)
        self.assertIn("raw must be", codex.stderr)

    def test_multi_batch_cli_salvage_engages_only_after_every_batch_is_complete(self):
        self.prepare_round0()
        second_issue = issue()
        second_issue["id"] = "i2"
        self.write_json(
            self.run_dir / "index.json",
            {
                "issues": [issue(), second_issue],
                "round": 0,
                "phase": "debate",
                "committed_rounds": [],
                "run_epoch": 0,
                "evaluated_by": {"i1": ["claude"], "i2": ["claude"]},
            },
        )
        begin = subprocess.run(
            [str(SWEEP), "begin", self.run_id, "1", "0"],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(begin.returncode, 0, begin.stderr)
        plan_path = self.run_dir / "multi-batch-plan.json"
        self.write_json(
            plan_path,
            {
                "batches": [
                    {"seat": seat, "batch": batch, "expected_ids": [issue_id]}
                    for seat in ("claude", "codex")
                    for batch, issue_id in (("a", "i1"), ("b", "i2"))
                ]
            },
        )
        planned = subprocess.run(
            [str(SWEEP), "plan", self.run_id, "1", "0", str(plan_path)],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(planned.returncode, 0, planned.stderr)
        (self.run_dir / "batch.1.a.ids").write_text("i1\n", encoding="utf-8")
        (self.run_dir / "batch.1.b.ids").write_text("i2\n", encoding="utf-8")

        for seat in ("claude", "codex"):
            for batch, issue_id in (("a", "i1"), ("b", "i2")):
                stance = json.dumps(
                    {"id": issue_id, "stance": "support", "rationale": "confirmed"}
                )
                new_findings = "not-json" if (seat, batch) == ("codex", "b") else "[]"
                raw = f"```stances\n{stance}\n```\n```new_findings\n{new_findings}\n```\n"
                path = self.run_dir / "raw" / f"round1.{seat}.{batch}.txt"
                path.parent.mkdir(exist_ok=True)
                path.write_text(raw, encoding="utf-8")

        first_collection_result = self.run_round("collect-debate", self.run_id)
        self.assertEqual(first_collection_result.returncode, 0, first_collection_result.stderr)
        first_collection = json.loads(first_collection_result.stdout)
        self.assertEqual(first_collection["engaged"], ["claude"])

        codex_b = self.run_dir / "raw" / "round1.codex.b.txt"
        stance = json.dumps({"id": "i2", "stance": "support", "rationale": "confirmed"})
        salvaged = Path(f"{codex_b}.salvaged")
        salvaged.write_text(
            f"```stances\n{stance}\n```\n```new_findings\n[]\n```\n",
            encoding="utf-8",
        )
        salvage_result = self.run_round("salvage-debate", self.run_id, "codex", "b", salvaged)
        self.assertEqual(salvage_result.returncode, 0, salvage_result.stderr)

        second_collection_result = self.run_round("collect-debate", self.run_id)
        self.assertEqual(second_collection_result.returncode, 0, second_collection_result.stderr)
        second_collection = json.loads(second_collection_result.stdout)
        self.assertEqual(second_collection["engaged"], ["claude", "codex"])
        committed = self.run_round("commit", self.run_id)
        self.assertEqual(committed.returncode, 0, committed.stderr)
        self.assertEqual(json.loads(committed.stdout)["states"], {"accepted": 2})

    def test_prepare_debate_removes_uncheckpointed_claude_raw(self):
        self.prepare_round0()
        self.install_open_index()
        raw_path = self.run_dir / "raw" / "round1.claude.1.txt"
        raw_path.parent.mkdir(exist_ok=True)
        stance = json.dumps({"id": "i1", "stance": "support", "rationale": "stale"})
        raw_path.write_text(
            f"```stances\n{stance}\n```\n```new_findings\n[]\n```\n",
            encoding="utf-8",
        )

        prepared = self.run_round("prepare-debate", self.run_id, "claude", "codex")

        self.assertEqual(prepared.returncode, 0, prepared.stderr)
        self.assertFalse(raw_path.exists())
        collected = self.run_round("collect-debate", self.run_id)
        self.assertEqual(collected.returncode, 0, collected.stderr)
        self.assertNotIn("claude", json.loads(collected.stdout)["engaged"])

    def test_prepare_debate_renders_two_stance_contract(self):
        self.prepare_round0()
        self.install_open_index()

        result = self.run_round("prepare-debate", self.run_id, "claude", "codex")

        self.assertEqual(result.returncode, 0, result.stderr)
        prompt_path = json.loads(result.stdout)["prompt"]
        prompt = Path(prompt_path).read_text(encoding="utf-8")
        self.assertIn("configured panel has 2 reviewer seats, including you", prompt)
        self.assertIn("support|reject", prompt)
        self.assertIn("support may include a `revision`", prompt)
        self.assertNotIn("support_with_revision", prompt)

        for tag in ("stances", "new_findings"):
            with self.subTest(tag=tag):
                parsed = subprocess.run(
                    [str(PARSE_BLOCK), "--diagnose", tag, prompt_path],
                    capture_output=True,
                    text=True,
                    check=False,
                )
                self.assertEqual(parsed.returncode, 0, parsed.stdout + parsed.stderr)

    def test_prepare_debate_does_not_redispatch_checkpointed_seats(self):
        self.prepare_round0()
        self.install_open_index()
        first = self.run_round("prepare-debate", self.run_id, "claude", "codex")
        self.assertEqual(first.returncode, 0, first.stderr)
        raw = debate_response({"id": "i1", "stance": "support", "rationale": "confirmed"})
        self.install_claude_debate(raw)
        self.install_codex_debate(raw)
        self.assertEqual(self.run_round("collect-debate", self.run_id).returncode, 0)

        resumed = self.run_round("prepare-debate", self.run_id, "claude", "codex")

        self.assertEqual(resumed.returncode, 0, resumed.stderr)
        prepared = json.loads(resumed.stdout)
        self.assertIsNone(prepared["claude_prompt"])
        self.assertEqual(prepared["barriers"], [])

    def test_prepare_debate_reconciles_changed_panel_without_replacing_plan(self):
        self.prepare_round0()
        self.install_open_index()
        first = self.run_round("prepare-debate", self.run_id, "claude", "codex")
        self.assertEqual(first.returncode, 0, first.stderr)
        raw = debate_response({"id": "i1", "stance": "support", "rationale": "confirmed"})
        self.install_claude_debate(raw)
        self.assertEqual(self.run_round("collect-debate", self.run_id).returncode, 0)

        resumed = self.run_round("prepare-debate", self.run_id, "claude", "gemini")

        self.assertEqual(resumed.returncode, 0, resumed.stderr)
        prepared = json.loads(resumed.stdout)
        self.assertIsNone(prepared["claude_prompt"])
        self.assertEqual(len(prepared["barriers"]), 1)
        barrier = Path(prepared["barriers"][0]["command"]).read_text(encoding="utf-8")
        self.assertIn("--seat gemini", barrier)
        plan = json.loads(
            (self.run_dir / "sweeps" / "round-1" / "plan.json").read_text(encoding="utf-8")
        )
        self.assertEqual(plan["dropped_seats"], ["codex"])
        self.assertEqual([entry["seat"] for entry in plan["batches"]], ["claude", "codex", "gemini"])
        panel = json.loads((self.run_dir / "panel.json").read_text(encoding="utf-8"))
        self.assertEqual(panel["configured"], ["claude", "gemini"])

        collected = self.run_round("collect-debate", self.run_id)
        self.assertEqual(collected.returncode, 0, collected.stderr)
        summary = json.loads(collected.stdout)
        self.assertEqual(summary["engaged"], ["claude"])
        self.assertEqual(
            next(item for item in summary["batches"] if item["seat"] == "codex")["status"],
            "dropped",
        )

    def test_prepare_debate_restores_dropped_seat_that_returns_on_later_resume(self):
        self.prepare_round0()
        self.install_open_index()
        first = self.run_round("prepare-debate", self.run_id, "claude", "codex")
        self.assertEqual(first.returncode, 0, first.stderr)
        raw = debate_response({"id": "i1", "stance": "support", "rationale": "confirmed"})
        self.install_claude_debate(raw)
        self.assertEqual(self.run_round("collect-debate", self.run_id).returncode, 0)

        resumed_without_codex = self.run_round(
            "prepare-debate", self.run_id, "claude", "gemini"
        )
        self.assertEqual(resumed_without_codex.returncode, 0, resumed_without_codex.stderr)
        resume_plan = subprocess.run(
            [str(SWEEP), "resume-plan", self.run_id],
            capture_output=True,
            text=True,
            check=True,
        )
        first_statuses = {
            item["seat"]: item["status"] for item in json.loads(resume_plan.stdout)["batches"]
        }
        self.assertEqual(first_statuses["codex"], "dropped")

        resumed_with_codex = self.run_round(
            "prepare-debate", self.run_id, "claude", "codex", "gemini"
        )

        self.assertEqual(resumed_with_codex.returncode, 0, resumed_with_codex.stderr)
        prepared = json.loads(resumed_with_codex.stdout)
        self.assertEqual(len(prepared["barriers"]), 1)
        barrier = Path(prepared["barriers"][0]["command"]).read_text(encoding="utf-8")
        self.assertIn("--seat codex", barrier)
        self.assertIn("--seat gemini", barrier)
        resume_plan = subprocess.run(
            [str(SWEEP), "resume-plan", self.run_id],
            capture_output=True,
            text=True,
            check=True,
        )
        second_statuses = {
            item["seat"]: item["status"] for item in json.loads(resume_plan.stdout)["batches"]
        }
        self.assertEqual(second_statuses["codex"], "missing")
        panel = json.loads((self.run_dir / "panel.json").read_text(encoding="utf-8"))
        self.assertEqual(panel["configured"], ["claude", "codex", "gemini"])

        self.install_codex_debate(raw)
        collected = self.run_round("collect-debate", self.run_id)
        self.assertEqual(collected.returncode, 0, collected.stderr)
        self.assertEqual(json.loads(collected.stdout)["engaged"], ["claude", "codex"])

    def test_prepare_debate_preserves_completed_seat_absent_from_current_panel(self):
        self.prepare_round0()
        self.install_open_index()
        first = self.run_round("prepare-debate", self.run_id, "claude", "codex")
        self.assertEqual(first.returncode, 0, first.stderr)
        raw = debate_response({"id": "i1", "stance": "support", "rationale": "confirmed"})
        self.install_claude_debate(raw)
        codex_raw = self.install_codex_debate(raw)
        self.assertEqual(self.run_round("collect-debate", self.run_id).returncode, 0)

        resumed = self.run_round("prepare-debate", self.run_id, "claude", "gemini")

        self.assertEqual(resumed.returncode, 0, resumed.stderr)
        prepared = json.loads(resumed.stdout)
        self.assertIsNone(prepared["claude_prompt"])
        barrier = Path(prepared["barriers"][0]["command"]).read_text(encoding="utf-8")
        self.assertIn("--seat gemini", barrier)
        self.assertNotIn("--seat codex", barrier)
        plan = json.loads(
            (self.run_dir / "sweeps" / "round-1" / "plan.json").read_text(encoding="utf-8")
        )
        self.assertEqual(plan["dropped_seats"], [])
        self.assertTrue(codex_raw.is_file())
        panel = json.loads((self.run_dir / "panel.json").read_text(encoding="utf-8"))
        self.assertEqual(panel["configured"], ["claude", "gemini", "codex"])

        collected = self.run_round("collect-debate", self.run_id)
        self.assertEqual(collected.returncode, 0, collected.stderr)
        self.assertEqual(json.loads(collected.stdout)["engaged"], ["claude", "codex"])

    def test_commit_addendum_merges_judgment_commits_once_and_regenerates_cards(self):
        self.prepare_prose_judgment()
        index = json.loads((self.run_dir / "index.json").read_text(encoding="utf-8"))
        self.assertEqual(index["round"], 0)
        self.assertEqual(index["committed_rounds"], [])
        card = self.workdir / ".panel-review" / self.run_id / "issue-i1.md"
        self.assertNotIn("synthesized claim", card.read_text(encoding="utf-8"))

        addendum = self.run_dir / "addendum.1.json"
        self.write_json(
            addendum,
            {"revise": [{"id": "i1", "fields": {"claim": "synthesized claim"}}]},
        )
        committed = self.run_round("commit", self.run_id, "--addendum", addendum)

        self.assertEqual(committed.returncode, 0, committed.stderr)
        self.assertEqual(json.loads(committed.stdout)["states"], {"accepted": 1})
        index = json.loads((self.run_dir / "index.json").read_text(encoding="utf-8"))
        self.assertEqual(index["round"], 1)
        self.assertEqual(index["committed_rounds"], [1])
        self.assertEqual(index["issues"][0]["claim"], "synthesized claim")
        self.assertIn("**Claim:** synthesized claim", card.read_text(encoding="utf-8"))

    def test_failed_addendum_preserves_canonical_payload_and_index(self):
        self.prepare_prose_judgment()
        payload = self.run_dir / "payload.1.json"
        payload_before = payload.read_bytes()
        index = self.run_dir / "index.json"
        index_before = index.read_bytes()
        addendum = self.run_dir / "addendum.1.json"
        self.write_json(addendum, {"revise": [{"id": "i1", "claim": "invalid shape"}]})

        rejected = self.run_round("commit", self.run_id, "--addendum", addendum)

        self.assertNotEqual(rejected.returncode, 0)
        self.assertIn('addendum .revise entry missing "fields"', rejected.stderr)
        self.assertEqual(payload.read_bytes(), payload_before)
        self.assertEqual(index.read_bytes(), index_before)


if __name__ == "__main__":
    unittest.main()
