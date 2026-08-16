# Close `merge_payload`'s addendum validation gaps

Priority: 37

Status: Pending

Source: Panel review `panel-20260816-080558-5ab680af` (Claude + Codex + Gemini), 2026-08-16 — accepted unanimously

Triage: ready-for-agent

## Problem

`merge_payload` is the failure boundary for the referee's hand-built addendum —
`protocol.md:594` says `round commit` validates the addendum before installing it, and
`shape_error`'s own docstring says it exists so a mis-shaped addendum yields "an actionable message
+ exit 2 here, instead of an uncaught KeyError that prints a traceback". Two gaps break that.

**1. Unknown keys are silently discarded.** `merge` (`scripts/merge_payload:31`) rebuilds a payload
from a fixed key list and never rejects keys present only in the addendum. A misspelled
`add_issue` (singular) therefore drops the referee's intended new issue and the round commits
without it, with no error anywhere. `index`'s payload validator (`scripts/index:84`) cannot catch it
either — it only ever sees the fixed-key object `merge` already returned.

**2. `shape_error` guards four keys; `merge` dereferences seven.** It validates `bump`, `set_state`,
`set_flag` and `revise` and omits `add_evidence`, `add_issues` and `evaluated_by`, all of which
`merge` uses structurally (`scripts/merge_payload:43-48`: two list concatenations and a `**`
unpack). Measured: `{"add_evidence":{"id":"i1"}}`, `{"add_issues":"oops"}` and
`{"evaluated_by":"x"}` each produce a Python traceback instead of exit 2 with a message — precisely
the outcome the docstring says the function prevents.

## Expected behavior

1. An addendum key that `merge` does not consume is a hard error (exit 2) naming the key. Reject
   unknown keys rather than dropping them; the addendum is hand-built by the referee, so a typo is
   the expected failure mode.
2. `shape_error` covers every key `merge` dereferences: `add_evidence` and `add_issues` must be
   lists of objects; `evaluated_by` must be an object. Same exit 2 + message contract.
3. Apply both to the `base` payload as well as the addendum — `shape_error` already runs on both,
   and a malformed base is a `decide_round` bug worth surfacing the same way.
4. `round commit` leaves the canonical payload and index untouched on any of these failures, as it
   already does for the currently guarded keys.

## Verification

- `tests/python/test_merge_payload.py` cases for: an unknown addendum key, `add_evidence` as an
  object, `add_issues` as a string, `evaluated_by` as a string — each exit 2 with a message naming
  the key, no traceback.
- A case asserting a well-formed addendum merges byte-identically to today's output.
- `./tests/run_tests.sh` passes.

## Non-goals

- Do not validate the *semantics* of the addendum's contents here (whether a folded evidence point
  materially conflicts with an issue's outcome). That judgment stays with the referee, per
  `.claude/rules/scripts.md`.
