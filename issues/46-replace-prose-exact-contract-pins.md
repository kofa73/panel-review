# Replace the prose-exact contract pins with structural checks

Priority: 46

Status: Pending

Source: Simplification panel — raised by all four reviewers (Opus §1.1, Sol "Reduce brittle
instruction-contract checks", both Gemini reports), 2026-08-16

Triage: ready-for-human

## Problem

`scripts/check_contracts` (423 lines) contains seven `for required in (…)` / `for stale in (…)`
loops pinning roughly 45 literal English phrases that must or must not appear in Markdown, e.g.:

```python
# check_contracts:242-256
for required in ("2 minutes by default", "10-minute maximum",
                 "moves the call to the background instead of stopping it", …):
    if required not in barrier_lower: fail(…)
for stale in ("killed by the harness", "would be killed", "silently truncated"):
```

`tests/run_tests.sh` adds 89 `assert_file_contains` calls of the same shape.

Three costs, all already realised:

1. **It blocks its own fixes.** Issue 26 cannot be implemented without editing `check_contracts` in
   the same commit, because the checker *requires* README to contain `Subagent spawn limit reached`
   — an error Claude Code removed in 2.1.224. The invariant now guarantees the presence of wrong
   guidance.
2. **It tests the wrong thing.** `"2 minutes by default"` appearing in a Markdown file proves nothing
   about the barrier's behavior; the behavior lives in `timeout 100`, which nothing asserts.
3. **It taxes every documentation edit.** Rewording a sentence for clarity breaks the build, which
   is why several of the corrections in issues 41-43 are larger changes than their content warrants.

## Expected behavior

Keep every check that is structural or executable; drop the ones that freeze wording.

**Keep:**

- `check_rendered_contracts` — renders the contract, feeds it through `response_problem`/`get_rules`.
  It proves the prompt the seats see parses under the parser the referee uses.
- Template sentinel counts (`{{SEAT_CONTRACT}}`, `{{PROFILEINFO}}` exactly once) and the rule that a
  template must not restate a seat block (`^```findings`).
- `CONTRACTS.md` ownership rows exist (a presence check, not a phrase check).
- `agy-model-pin-form` — display-label regex, primary ≠ fallback. A real invariant with a measured
  failure mode (issue 20).
- Status-stub literals in their three owners (`PANEL_VERDICT_*`, `CLAUDE_SEAT_RAW_*`) and their
  absence elsewhere. These *are* the interface; `hooks/enforce_agent_status_stub` matches them
  byte-exactly at runtime.
- The Agent-dispatch assertions: required subagent type and `run_in_background: false`. Fork mode off
  only restores the *ability* to block; the instruction is what uses it (see issue 25).
- The `round`/`sweep` verb greps in the rendered protocol (`round commit`, no direct `merge_payload`)
  — they protect the transaction-owner boundary of ADR-0004.

**Drop, replacing with a structural equivalent where one exists:**

- All seven English-phrase loops.
- `"Step 4 form" not in commands["start"].partition(…)` — brittle prose slicing.
- The `barrier-completion-signal` sentence scanner (`re.split(r"[.\n]")` hunting for "watch" and
  `--done`) and the `absolute-seat-paths` regex — heuristic NLP over the project's own prose.
- The `broad_failure` 100-character proximity regex.
- The Markdown `assert_file_contains` block in `tests/run_tests.sh`.

Structural replacements worth adding in their place: command skills invoke only the public delivery
interface; the referee protocol invokes only coarse `round` operations on normal paths; legacy
low-level commands stay absent from model instructions.

Land issue 26's wording fix in the same change, not before it.

## Verification

- `scripts/check_contracts --root .` and `./tests/run_tests.sh` pass.
- Deliberately reword one explanatory sentence in README and confirm nothing fails.
- Deliberately break one structural invariant (remove `run_in_background: false` from a dispatch
  block) and confirm `check_contracts` still fails, naming it.

## Non-goals

- **This is not "a hobby project does not need tests".** The functional suites in `tests/python/`
  stay in full, including every incident regression at the lifecycle, round, and runtime seams. The
  target is exactly the checks that assert on English wording rather than on behavior.
- Do not replace a stale pinned string with a fresh pinned string. If a fact matters, assert the
  behavior; if only the explanation matters, let it be prose.

## Comments

Marked `ready-for-human`: which explanatory sentences deserve an executable guard is a maintainer
judgment, and the "keep" list above is a proposal, not a settled boundary.
