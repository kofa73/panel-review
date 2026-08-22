# Close the blindness gate's unscanned free-text channels

Priority: 35

Status: Pending

Source: Panel review `panel-20260816-080558-5ab680af` (Claude + Codex + Gemini), 2026-08-16 — raised in debate round 1, accepted unanimously in round 2

Triage: ready-for-agent

## Problem

`decide_round`'s mechanical blindness scan covers two of the free-text channels that reach cards
verbatim. The rest are guarded by prose instruction to the referee alone.

Scanned (`scripts/decide_round:135`): the stance `rationale` (when the stance is a reject or a
revising support) and the four `new_evidence` fields.

Not scanned:

- **`revision.claim`** — `scripts/decide_round:187` copies it verbatim into `advice.prose_revisions`,
  and `protocol.md:559-562` has the referee adopt or merge that text as the issue's new claim. It
  lands on a card every seat then reads.
- **`revision.location`** — free-form text (`seat_contract.py:167` accepts any non-empty string or
  list of strings). It converges into `adopt` (`scripts/decide_round:176`), becomes the payload
  `revise` entry, and `index commit-sweep` writes it as the issue's canonical location.
- **`new_findings`** — validated by `valid_findings`/`diag_findings` (`scripts/parse_block:117`),
  which check schema shape and never inspect the text. `protocol.md:565` has the referee fold every
  materially distinct point into an existing issue as `add_evidence`, so the text reaches the card.
  `scripts/round:805` enumerates the parsed new-finding files only *after* the stance-only decision
  helper has finished, so their free text never passes near the scan.

Where the gate exists it is mechanical; where it does not, `protocol.md:562` substitutes a prose
instruction to the referee ("Never write a claim/evidence string that names or counts seats"). The
invariant is therefore only as reliable as referee compliance on several of its channels, which is
the thing the mechanical gate was introduced to stop depending on.

This is an under-coverage/leak defect. Issue 34 is the opposite failure — over-broad matching on the
channels that *are* scanned — in the same file. They were deliberately kept as separate issues;
fixing them together is fine, but the pattern change from 34 must be decided first, because whatever
pattern survives is what these channels would be scanned with.

## Expected behavior

1. `blindness_errors` also scans `revision.claim` and `revision.location` for every stance whose
   revision is effective.
2. New-finding text is scanned on the same path before it can be promoted — either inside
   `decide_round` (given the parsed findings) or in an equivalent single owner, not re-implemented in
   the referee's judgment step.
3. The referee-facing prose instruction in `protocol.md` stays, but as a restatement of a mechanical
   rule rather than the only enforcement.
4. A stance flagged only on these channels behaves the same way as one flagged on `rationale` —
   whatever failure granularity issue 34 settles on.

## Verification

- `tests/python/test_decide_round.py` gains cases for a marker in `revision.claim`, a marker in
  `revision.location`, and a marker in a `new_findings` item, each rejected.
- A case asserting a *non*-effective revision (an exact no-op) is not scanned, matching the existing
  rationale rule.
- `./tests/run_tests.sh` passes.

## Non-goals

- Do not scan Round-0 findings here. Birth text is a separate channel with a separate cost; see the
  scope discussion in issue 34.
- Do not move claim synthesis out of the referee. The gate checks the seat's proposal; the referee
  keeps the judgment.

## Comments

2026-08-22: issue 34 is decided and implemented, which reframes this one. The scanned channels now
carry only a tally/agreement backstop (`seat_contract.blindness_match`), and the rest of blindness is
an explicit referee rule at `protocol.md`'s commit step. So the question here is no longer "extend a
broad pattern to more channels" — that pattern is gone — but whether the narrow backstop is worth
applying to `revision.claim`, `revision.location` and `new_findings` too. It is cheap (one helper
call per string, no false-positive tail) but it is not the guard those channels lack: the referee
rule is.
