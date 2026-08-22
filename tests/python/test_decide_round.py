"""Black-box coverage for the decide_round Python port."""

import json
from pathlib import Path
import shutil
import subprocess
import unittest
import uuid


ROOT = Path(__file__).resolve().parents[2]
DECIDE = ROOT / "scripts" / "decide_round"
INDEX = ROOT / "scripts" / "index"
FIXTURES = ROOT / "tests" / "fixtures" / "decide_round"


def issue(issue_id="i1", severity="medium", rounds=0):
    return {
        "id": issue_id,
        "claim": "A concrete claim.",
        "location": "src/file.py:1",
        "category": "correctness",
        "severity": severity,
        "evidence_pro": [{"assertion": "Observed behavior.", "location": "src/file.py:1"}],
        "evidence_contra": [],
        "peer_reviewed": False,
        "fully_vetted": False,
        "detail_contested": False,
        "state": "open",
        "rounds_debated": rounds,
        "card_rev": 0,
    }


# Verbatim claim of issue i1 from run panel-20260816-080558-5ab680af (issue 34): the text a
# seat debating that card must be able to restate.
CARD_I1_CLAIM = (
    "an ordinary repo-wide search by one seat returns another seat's raw findings and "
    "breaks blindness"
)


def stance(issue_id, seat, name="support", **extra):
    return {"id": issue_id, "stance": name, "rationale": "technical observation", "_source": seat, "fid": seat, **extra}


class DecideRoundTest(unittest.TestCase):
    def setUp(self):
        self.run_id = f"py-decide-{uuid.uuid4().hex}"
        self.run_dir = Path("/tmp") / self.run_id
        self.run_dir.mkdir()
        self.stances_path = self.run_dir / "stances.jsonl"
        self.write_run([issue()])

    def tearDown(self):
        shutil.rmtree(self.run_dir, ignore_errors=True)

    def write_run(self, issues, *, evaluated_by=None, limits=None):
        index = {"issues": issues, "round": 0, "phase": "debate", "committed_rounds": [], "run_epoch": 0}
        if evaluated_by is not None:
            index["evaluated_by"] = evaluated_by
        (self.run_dir / "index.json").write_text(json.dumps(index), encoding="utf-8")
        if limits is not None:
            (self.run_dir / "manifest.json").write_text(json.dumps({"limits": limits}), encoding="utf-8")
        else:
            (self.run_dir / "manifest.json").unlink(missing_ok=True)

    def write_stances(self, entries):
        self.stances_path.write_text("".join(json.dumps(entry) + "\n" for entry in entries), encoding="utf-8")

    def run_decide(self, *, round_number=1, configured="codex gemini claude", engaged="codex gemini claude", advice=None):
        command = [
                str(DECIDE),
                "--id",
                self.run_id,
                "--round",
                str(round_number),
                "--configured",
                configured,
                "--engaged",
                engaged,
                "--stances",
                str(self.stances_path),
            ]
        if advice is not None:
            command.extend(["--advice", str(advice)])
        return subprocess.run(
            command,
            text=True,
            capture_output=True,
            check=False,
        )

    def payload(self, **kwargs):
        result = self.run_decide(**kwargs)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_round_one_fixtures_keep_unconverged_enum_open(self):
        index = json.loads((FIXTURES / "index.round0.json").read_text(encoding="utf-8"))
        index["evaluated_by"] = json.loads((FIXTURES / "evaluated.round0.json").read_text(encoding="utf-8"))
        (self.run_dir / "index.json").write_text(json.dumps(index), encoding="utf-8")
        shutil.copy(FIXTURES / "manifest.json", self.run_dir / "manifest.json")
        shutil.copy(FIXTURES / "stances.round1.json", self.stances_path)

        payload = self.payload()
        self.assertEqual(payload["bump"], ["i1", "i3", "i4", "i5", "i6"])
        self.assertEqual(
            [change["id"] for change in payload["set_state"] if change["state"] == "accepted"],
            ["i1", "i3", "i5"],
        )
        self.assertNotIn("i4", [change["id"] for change in payload["set_state"]])
        self.assertNotIn("revise", payload)

    def test_round_two_limit_adopts_unanimous_enum_and_contests_mixed(self):
        self.write_run([issue("i4", rounds=1), issue("i6", rounds=1)], limits={"issue_rounds": 2, "max_rounds": 4})
        self.write_stances(
            [
                *(stance("i4", seat, revision={"severity": "low"}) for seat in ("codex", "gemini", "claude")),
                stance("i6", "codex", "reject"),
                stance("i6", "gemini"),
                stance("i6", "claude"),
            ]
        )
        payload = self.payload()
        self.assertEqual({item["id"]: item["state"] for item in payload["set_state"]}, {"i4": "accepted", "i6": "contested"})
        self.assertEqual(payload["revise"], [{"id": "i4", "fields": {"severity": "low"}}])

    def test_enum_conflict_at_ceiling_sets_detail_contested_without_revision(self):
        self.write_run([issue("i1")])
        self.write_stances(
            [
                stance("i1", "codex", revision={"severity": "low"}),
                stance("i1", "gemini"),
                stance("i1", "claude", revision={"severity": "low"}),
            ]
        )
        payload = self.payload(round_number=4)
        self.assertEqual(payload["set_state"], [{"id": "i1", "state": "accepted"}])
        self.assertIn({"id": "i1", "flag": "detail_contested", "value": True}, payload["set_flag"])
        self.assertNotIn("revise", payload)

    def test_true_unanimity_adopts_enum(self):
        self.write_stances(
            [
                *(stance("i1", seat, revision={"severity": "low"}) for seat in ("codex", "gemini", "claude")),
            ]
        )
        payload = self.payload()
        self.assertEqual(payload["set_state"], [{"id": "i1", "state": "accepted"}])
        self.assertEqual(payload["revise"], [{"id": "i1", "fields": {"severity": "low"}}])

    def test_support_claim_revision_is_returned_for_referee_judgment(self):
        revised_claim = "The concrete claim occurs only on the fallback path."
        self.write_stances(
            [
                stance("i1", "codex", revision={"claim": revised_claim}),
                stance("i1", "gemini"),
                stance("i1", "claude"),
            ]
        )
        advice_path = self.run_dir / "advice.json"

        result = self.run_decide(advice=advice_path)

        self.assertEqual(result.returncode, 0, result.stderr)
        advice = json.loads(advice_path.read_text(encoding="utf-8"))
        self.assertEqual(
            advice,
            {
                "prose_revisions": [{"id": "i1", "proposals": [{"seat": "codex", "claim": revised_claim}]}],
                "withheld_text": [],
            },
        )

    def test_effective_support_revision_promotes_its_rationale(self):
        rationale = "The failure requires a fallback and therefore has medium impact."
        self.write_stances(
            [
                stance("i1", "codex", rationale=rationale, revision={"severity": "low"}),
                stance("i1", "gemini"),
                stance("i1", "claude"),
            ]
        )

        payload = self.payload()

        self.assertIn(
            {"id": "i1", "side": "contra", "point": {"location": "analysis", "assertion": rationale}},
            payload["add_evidence"],
        )

    def test_noop_revision_and_support_rationale_are_inert(self):
        self.write_stances(
            [
                stance(
                    "i1",
                    "codex",
                    rationale="all three seats agree",
                    revision={"severity": "medium", "claim": "A concrete claim."},
                ),
                stance("i1", "gemini"),
                stance("i1", "claude"),
            ]
        )
        advice_path = self.run_dir / "advice.json"

        result = self.run_decide(advice=advice_path)

        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertNotIn("revise", payload)
        self.assertNotIn("add_evidence", payload)
        self.assertEqual(
            json.loads(advice_path.read_text(encoding="utf-8")),
            {"prose_revisions": [], "withheld_text": []},
        )

    def test_split_support_reject_stays_open_without_revision(self):
        self.write_stances(
            [
                stance("i1", "codex", revision={"severity": "low"}),
                stance("i1", "gemini", "reject"),
                stance("i1", "claude"),
            ]
        )
        payload = self.payload()
        self.assertNotIn("set_state", payload)
        self.assertNotIn("revise", payload)

    def test_integrity_gate_rejects_duplicate_missing_and_unknown_sources(self):
        base = [stance("i1", seat) for seat in ("codex", "gemini", "claude")]
        cases = [
            (base + [stance("i1", "codex")], "duplicate"),
            ([entry for entry in base if entry["_source"] != "claude"], "missing"),
            (base + [stance("i1", "mistral")], "unknown"),
        ]
        for entries, label in cases:
            with self.subTest(label=label):
                self.write_stances(entries)
                result = self.run_decide()
                self.assertEqual(result.returncode, 3)
                self.assertEqual(result.stdout, "")
                self.assertIn("stance-integrity violation", result.stderr)

    def test_integrity_gate_rejects_removed_stance_in_retained_checkpoint(self):
        self.write_stances(
            [
                stance("i1", "codex", "support_with_revision", revision={"severity": "low"}),
                stance("i1", "gemini"),
                stance("i1", "claude"),
            ]
        )

        result = self.run_decide()

        self.assertEqual(result.returncode, 3)
        self.assertIn("invalid stance", result.stderr)
        self.assertIn("support_with_revision", result.stderr)

    def test_integrity_gate_rejects_retained_reject_without_rationale(self):
        self.write_stances(
            [
                stance("i1", "codex", "reject", rationale=""),
                stance("i1", "gemini", "reject"),
                stance("i1", "claude", "reject"),
            ]
        )

        result = self.run_decide()

        self.assertEqual(result.returncode, 3)
        self.assertIn("reject requires non-empty rationale", result.stderr)

    def test_dropped_seat_decides_but_withholds_fully_vetted(self):
        self.write_stances([stance("i1", "codex"), stance("i1", "claude")])
        payload = self.payload(engaged="codex claude")
        self.assertEqual(payload["set_state"], [{"id": "i1", "state": "accepted"}])
        self.assertNotIn({"id": "i1", "flag": "fully_vetted", "value": True}, payload["set_flag"])

    def test_domain_vocabulary_is_promoted_verbatim(self):
        # Issue 34: the gate no longer matches bare product names or role nouns. Every string
        # here is a technical fact about this repository, and CARD_I1_CLAIM is the verbatim claim
        # of issue i1 from run panel-20260816-080558-5ab680af — a seat asked to debate that card
        # has to be able to restate it.
        cases = [
            ("rationale", CARD_I1_CLAIM),
            ("rationale", "run_agy pins the label Gemini 3.7 Flash (High)."),
            ("rationale", "The protocol dispatches all three seats every debate round."),
            ("assertion", "The Claude seat's prompt anchors the wrong path."),
            ("location", "agents/panel-review-claude-seat.md:12"),
        ]
        for field, value in cases:
            with self.subTest(field=field, value=value):
                first = stance("i1", "codex", "reject")
                if field == "rationale":
                    first["rationale"] = value
                else:
                    evidence = {"location": "src/file.py:2", "assertion": "the loop stops early"}
                    evidence[field] = value
                    first["new_evidence"] = evidence
                self.write_stances([first, stance("i1", "claude")])
                advice_path = self.run_dir / "advice.json"
                result = self.run_decide(engaged="codex claude", advice=advice_path)

                self.assertEqual(result.returncode, 0, result.stderr)
                payload = json.loads(result.stdout)
                promoted = json.dumps(payload.get("add_evidence", []), ensure_ascii=False)
                self.assertIn(value, promoted)
                advice = json.loads(advice_path.read_text(encoding="utf-8"))
                self.assertEqual(advice["withheld_text"], [])

    def test_matching_evidence_location_is_exempt(self):
        # A path is not prose. Contrived so it would match the surviving pattern, which pins the
        # exemption itself rather than the fact that real paths happen not to match.
        evidence = {"location": "docs/2 of 3 seats agree.md:1", "assertion": "the loop stops early"}
        self.write_stances(
            [stance("i1", "codex", new_evidence=evidence), stance("i1", "claude")]
        )
        advice_path = self.run_dir / "advice.json"
        result = self.run_decide(engaged="codex claude", advice=advice_path)

        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertIn({"id": "i1", "side": "pro", "point": evidence}, payload["add_evidence"])
        self.assertEqual(
            json.loads(advice_path.read_text(encoding="utf-8"))["withheld_text"], []
        )

    def test_tally_rationale_is_withheld_and_reported_without_failing_the_round(self):
        leak = "2 of 3 seats agree on high severity."
        self.write_stances(
            [
                stance("i1", "codex", "reject", rationale=leak),
                stance("i2", "codex", "reject", rationale="the bound is off by one"),
                stance("i1", "claude", "reject"),
                stance("i2", "claude", "reject"),
            ]
        )
        self.write_run([issue("i1"), issue("i2")])
        advice_path = self.run_dir / "advice.json"
        result = self.run_decide(engaged="codex claude", advice=advice_path)

        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertNotIn(leak, json.dumps(payload, ensure_ascii=False))
        # The stance still counts: both issues are decided, including the flagged one, and the
        # unflagged issue keeps its evidence.
        self.assertEqual(
            sorted(payload["set_state"], key=lambda entry: entry["id"]),
            [{"id": "i1", "state": "rejected"}, {"id": "i2", "state": "rejected"}],
        )
        self.assertIn(
            {"id": "i2", "side": "contra", "point": {"location": "analysis", "assertion": "the bound is off by one"}},
            payload["add_evidence"],
        )
        advice = json.loads(advice_path.read_text(encoding="utf-8"))
        self.assertEqual(
            advice["withheld_text"],
            [{"seat": "codex", "id": "i1", "field": "rationale", "match": "2 of 3 seats"}],
        )
        self.assertIn("withheld", result.stderr)

    def test_agreement_verb_in_new_evidence_withholds_the_whole_point(self):
        evidence = {
            "location": "src/file.py:2",
            "assertion": "the loop stops early",
            "impact": "the reviewers agree that output is truncated",
        }
        self.write_stances(
            [stance("i1", "codex", new_evidence=evidence), stance("i1", "claude")]
        )
        advice_path = self.run_dir / "advice.json"
        result = self.run_decide(engaged="codex claude", advice=advice_path)

        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertNotIn("add_evidence", payload)
        self.assertEqual(payload["set_state"], [{"id": "i1", "state": "accepted"}])
        advice = json.loads(advice_path.read_text(encoding="utf-8"))
        self.assertEqual(
            advice["withheld_text"],
            [{"seat": "codex", "id": "i1", "field": "new_evidence.impact", "match": "reviewers agree"}],
        )

    def test_evaluated_by_is_sorted_unique_and_commits(self):
        self.write_run([issue("i1")], evaluated_by={"i1": ["gemini", "codex"]})
        self.write_stances([stance("i1", "codex"), stance("i1", "claude")])
        payload = self.payload(engaged="codex claude")
        self.assertEqual(payload["evaluated_by"], {"i1": ["claude", "codex", "gemini"]})
        result = subprocess.run(
            [str(INDEX), "commit-sweep", self.run_id, "1", "0"],
            input=json.dumps(payload),
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        index = json.loads((self.run_dir / "index.json").read_text(encoding="utf-8"))
        self.assertEqual(index["evaluated_by"], {"i1": ["claude", "codex", "gemini"]})


if __name__ == "__main__":
    unittest.main()
