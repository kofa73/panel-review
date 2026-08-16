# Stop the blindness scan from failing a whole round on legitimate domain vocabulary

Priority: 34

Status: Pending

Source: Panel review `panel-20260816-080558-5ab680af` (Claude + Codex + Gemini), 2026-08-16 — accepted; severity `detail_contested` (two seats `high`, one `medium`)

Triage: ready-for-human

## Problem

`decide_round`'s blindness gate cannot tell a seat-identity leak from an ordinary technical fact
about the tools this repository integrates, and one match aborts the entire round rather than the
single offending stance.

```text
scripts/decide_round:16   BLINDNESS_PATTERN = r"\b(codex|gpt|gemini|claude)\b|…"   (re.IGNORECASE)
```

The pattern has five alternatives. Measured against real strings (2026-08-16):

| Text | Verdict | Matched |
|---|---|---|
| "…an ordinary repo-wide search by one seat returns **another seat's** raw findings and breaks blindness" | BLOCK | `another seat` |
| "A seat could read or rewrite **another seat's** raw output." (`AGENTS.md:132` verbatim) | BLOCK | `another seat` |
| "The protocol dispatches **all three seats** every debate round." | BLOCK | `all three seats` |
| "`run_agy` pins the label **Gemini** 3.7 Flash (High)." | BLOCK | `Gemini` |
| "The **Claude** seat's prompt anchors the wrong path." | BLOCK | `Claude` |
| `agents/panel-review-**claude**-seat.md:12` (an evidence location) | BLOCK | `claude` |
| "**The other seat flagged** this too." | BLOCK — correct | `other seat` |
| "**2 of 3 seats** agree on high severity." | BLOCK — correct | `2 of 3 seats` |
| "**Both reviewers** converged on medium." | BLOCK — correct | `Both reviewers` |
| "As **Codex** noted, the timeout is unbounded." | BLOCK — correct | `Codex` |
| "The **agy** command line drops `--model`." | pass | — |

The first row is the claim of **issue i1 from this repository's own completed run**, promoted onto a
card by the referee at Round 0 (where the gate does not run). A seat asked to debate that card cannot
restate the card's own text without losing the round.

So the defect is **not** confined to product names. Three of the five alternatives are pure
vocabulary matches — `(codex|gpt|gemini|claude)`, `(an)?other (reviewer|seat|model|ai)`, and
`(all|both|two|the other) (seats|reviewers|models|ais)` — and all three fire on ordinary,
blindness-preserving statements about a codebase whose subject matter *is* multi-seat AI review. Only
the last two alternatives (agreement verbs, numeric tallies) discriminate.

Two further defects compound:

**1. The vocabulary alternatives cannot discriminate.** They fire on correct, blindness-preserving
statements — "Claude Code 2.1.232 turns fork mode on by default", "`run_agy` pins the label
`Gemini 3.7 Flash (High)`", "`assets/default-panel-review.config.toml` names model `gpt-5.5`". The
scan also covers `new_evidence.location` (`scripts/decide_round:148`), and **19 of this repository's
148 tracked files** match — `agents/panel-review-claude-seat.md`, `scripts/run_codex`,
`tests/fixtures/parse_block/*`, and so on. An accurate evidence location for 13% of the repository
is a hard error.

**2. One match aborts the whole round.** `scripts/decide_round:343` raises `SystemExit(5)` with no
payload, and `scripts/round` invokes it expecting exit 0 only, so no issue in the round commits —
not just the flagged issue, and not just the flagged seat.

Recovery is expensive and can loop: `protocol.md:543` tells the referee to re-dispatch that one seat
for a content reword, which for a CLI seat is a fresh 15–40 minute pass, and the reworded text still
has to name the tool it is talking about. The failure is also undetectable at draft time —
`seat_contract.py:136`'s `diag_stances` (what `check_draft` runs) validates only id, stance value and
reject rationale, and never applies the marker regex — so the round-wide abort is first reached after
every seat pass has already been paid for.

`tests/python/test_decide_round.py:266` exercises only true positives.

### Scope of the impact

The gate runs **only** on debate-round stances, never on Round-0 findings, so an issue whose claim
and birth evidence name a seat is born and carded normally. This run is the proof: it produced ten
issues that name all four words and committed two debate rounds without tripping the gate. What is
blocked is the debate channel — a `reject` rationale, a revising `support`'s rationale, and any
`new_evidence` field.

That still bites this repository specifically, because reviewing panel-review means naming Claude,
Codex and Gemini in evidence, and describing what one seat can see of another. Note the word list
does **not** include `agy`, `antigravity`, `run_agy` or `run_codex`, so "the agy command line" passes
while "the Gemini seat" does not — the gate's coverage of the domain is arbitrary rather than
principled.

### What the seats are actually told

`scripts/seat_contract.py:228-231` renders exactly one sentence about the panel:

> The configured panel has {N} reviewer seats, including you. Seats work independently and never
> receive origins or stance tallies.

**No vendor is ever named to a seat.** A seat therefore cannot honestly attribute a point to "Codex"
or "Gemini" — it was never told they are on the panel, and would have to guess the composition to
write "as Codex noted". Under ADR-0005 the guards target honest accident and model confusion, not
guessing; so the one true-positive class that alternative 1 uniquely catches is outside the class
this gate exists to catch. The Claude seat knows it is Claude, but naming *itself* is not a leak of
who raised a point.

## Expected behavior

The design tension is real and needs a maintainer decision, so this issue is `ready-for-human`.

**The discriminator is attribution, not vocabulary.** "The Claude seat's prompt anchors the wrong
path" is a fact about the code; "the Claude seat flagged this" reveals who raised the point. The noun
phrase is identical in both. No word list can separate them, because in this domain every one of
those words is also a legitimate subject of a technical claim.

### Rejected: co-occurrence

An earlier draft of this issue proposed keeping the product names but requiring them to co-occur with
a seat-ish word (`the claude seat`, `codex said`). That is wrong and would have made things worse:
`the claude seat` **is** a thing in this codebase — `agents/panel-review-claude-seat.md` is a file,
and a finding about its prompt naturally says "the Claude seat". The co-occurrence rule fires on the
most likely legitimate phrasing while looking more principled than the bare match. Do not implement
it.

### Options

1. **Narrow the failure blast radius** (uncontested, cheap, do this first whatever else is decided):
   a marker match rejects the offending *stance* — reported with seat, issue id and field — and the
   referee re-dispatches only that seat, rather than discarding a whole round's payload. Everything
   below is survivable once a false positive costs one seat instead of a round.
2. **Give the judgment to the referee outright** (recommended). Delete the vocabulary alternatives
   and state the criterion as a referee rule at the commit step: promoted text must not attribute a
   point to a seat or state a tally; reword or drop what does. Three things support this over any
   pattern:

   - **The project already works this way on most of the surface.** Issue 35 documents that
     `revision.claim`, `revision.location` and all `new_findings` text reach cards verbatim guarded
     by `protocol.md:562`'s prose instruction alone. The scripted gate covers the minority of
     channels. Making referee judgment the explicit single mechanism is consistency, not a downgrade.
   - **The referee has demonstrated the capability on a harder version of the task.** In run
     `panel-20260816-080558-5ab680af` it detected that the Gemini seat had copied Codex's findings
     byte-for-byte and dropped them as not independent, unprompted — a semantic judgment no regex
     could make. Issue 55 turns that behavior into a rule.
   - **It is the only actor that can judge it.** Attribution is the discriminator, and the referee is
     the sole participant holding the origins map.

   Keep alternatives 4-5 (agreement verbs, numeric tallies) as a cheap deterministic backstop if
   wanted: "2 of 3 seats agree" is never a technical fact about any codebase, so that pair has
   essentially no false-positive tail. The vocabulary alternatives do, and cannot be repaired.

   Cost, stated plainly: a model guard fails silently and no test can prove it held. That is already
   true of the current arrangement — the existing tests prove the regex matches strings, not that
   blindness holds — and it is true of the majority of channels today.

3. **Or keep a gate, but advisory.** Report matches to the referee with
   seat, issue id, field and the matched span; the referee decides whether to reword, drop the
   stance, or promote it as written. This is the ADR-0004 split — the script flags deterministically,
   the model judges — and the referee is the only participant who holds the origins map and can
   therefore actually tell an attribution leak from a technical fact. It also lets the pattern stay
   broad, catching true positives the current one misses, without any false positive costing a round.
4. **Or keep a hard gate, narrowed.** Delete alternatives 1-3 (bare
   product names, bare role nouns) and keep 4-5 (agreement verbs, numeric tallies). This loses one
   real case — "the other seat flagged this too" — which can be recovered by replacing the bare noun
   alternative with noun **plus a closed list of attribution verbs** (`said`, `flagged`, `raised`,
   `noted`, `reported`, `found`, `objected`, `agreed`). That is a narrower and more defensible rule
   than co-occurrence, because it keys on the predicate that does the leaking rather than on a noun
   the domain uses innocently. It still has a false-positive tail, which is why option 1 comes first.
5. **Exempt `new_evidence.location` outright.** A path is not prose and cannot carry a tally; 19 of
   this repository's 148 tracked paths currently match. Uncontested regardless of the above.
6. **Move whatever survives into `diag_stances`**, so `check_draft` catches it before a seat emits
   and the round is never paid for twice.

### Considered and not recommended: accept that panel-review cannot review itself

This is the only option needing no code change, and it should be recorded as considered — but the
evidence is against it:

- **Self-review demonstrably works today.** The gate runs only on debate stances. Run
  `panel-20260816-080558-5ab680af` produced ten issues naming all four words and committed two debate
  rounds without tripping it. The current state is not "cannot review itself" but "loses a debate
  round at random", which is strictly worse than either clean alternative.
- **It forfeits the highest-value findings in the tracker.** Issues 24, 33-40 came from panel-review
  reviewing panel-review. Issue 24 (blindness broken by in-workdir scratch) is exactly the class of
  defect only a self-review finds.
- **It is not enforceable.** Nothing detects "the repository under review is AI tooling", and the
  same false positives hit any codebase that integrates these CLIs — the codex plugin, tilth, and
  most of what this user reviews.

If it is nonetheless chosen, it must be written down as a supported limitation in README with the
debate-only scope stated, not left as an undocumented intermittent failure.

Whichever is chosen, add false-positive tests to `tests/python/test_decide_round.py` next to the
existing true-positive cases.

## Verification

- `tests/python/test_decide_round.py` gains cases for: a domain-legitimate product name in a
  rationale, the phrase `another seat's raw output` in a rationale, `all three seats` in a rationale,
  a matching path in `new_evidence.location`, and a genuine tally leak (still rejected).
- A regression fixture built from card i1 of run `panel-20260816-080558-5ab680af`: a stance whose
  rationale restates that card's own claim must not be refused.
- A test that a single offending stance does not discard the other issues' decisions.
- `./tests/run_tests.sh` passes.

## Non-goals

- Do not drop the blindness gate. Its true-positive cases (naming another reviewer, stating a tally)
  are what keeps promoted evidence blind.
- Do not scan Round-0 findings as a side effect of this change; if that is wanted it is a separate
  decision with its own cost, and issue 35 covers the channels the gate currently misses.

## Comments

Second-order note from the run that found this: the finding's own claim and evidence name all four
words, so it could only have been raised at Round 0. A seat that discovered it during debate could
not have said so.

2026-08-16, maintainer input (2): proposed replacing the scripted checks with a referee instruction,
citing the referee's unprompted non-independence call in this run. Recorded as option 2 above and, for
the Round-0 channel, as issue 55.

2026-08-16, maintainer input: the co-occurrence proposal was rejected (see above) on the grounds that
"the claude seat" is legitimate phrasing here. Measuring that objection showed the same failure in
the two role-noun alternatives, which no longer look safer than the product names — including on the
text of a card produced by this repository's own run. The issue was rewritten around attribution
rather than vocabulary, and the "cannot review itself" option recorded as considered.
