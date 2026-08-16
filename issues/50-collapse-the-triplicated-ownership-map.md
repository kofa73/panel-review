# Collapse the triplicated ownership map

Priority: 50

Status: Pending

Source: Simplification panel (Opus §1.2), 2026-08-16

Triage: ready-for-agent

## Problem

The same per-script ownership statement exists in three places:

- `README.md:446-482` — a 58-row component table;
- `.claude/rules/scripts.md` — 143 lines, "which script exclusively owns which concern";
- `CONTRACTS.md` — 25 lines, invariant → owner → consumers.

They already disagree. `README.md:461` still describes agy's stale silent-fallback behavior (issue
42), and README's row set has drifted from the script list in `AGENTS.md`. Three copies of one
sentence guarantee that at least one is wrong at any time, and every ownership change costs three
edits.

README is 631 lines. A user reading "how do I run a review" does not need `merge_payload`'s per-key
semantics.

## Expected behavior

One authority per audience:

- **`CONTRACTS.md`** — machine-relevant ownership. It is what `check_contracts` reads. Keep as is.
- **`.claude/rules/scripts.md`** — the editing map, auto-loaded when `scripts/` is touched. Keep as
  is; this is where per-script detail belongs.
- **`README.md`** — replace the 58-row table with a short paragraph naming the coarse boundaries
  (command skills, referee, seats, `round`, `seat_contract.py`, the wrappers) and a pointer to
  `CONTRACTS.md` and `.claude/rules/scripts.md`.

Sequence this after issues 42 and 44 so the removed rows are not corrected twice.

## Verification

- `scripts/check_contracts --root .` passes (its `CONTRACTS.md` ownership-row checks are unaffected).
- No script is described in two documents with different words.
- README's remaining prose still names every hard constraint from its "Design principles" section.

## Non-goals

- Do not delete `.claude/rules/scripts.md`. It is the file that loads exactly when it is needed.
- Do not move the trust model, hard constraints, or session requirements out of README. Those are
  what a user must read before the first run.
