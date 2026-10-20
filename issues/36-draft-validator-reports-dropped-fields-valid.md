# Make `check_draft` report the fields the pipeline will silently drop

Priority: 36

Status: Completed

Source: Panel review `panel-20260816-080558-5ab680af` (Claude + Codex + Gemini), 2026-08-16 — accepted unanimously

Triage: ready-for-agent

## Problem

`check_draft`'s header states the invariant it exists for: **"valid here == kept by the pipeline"**
(`scripts/check_draft:7`). It does not hold, because the diagnostic functions and the keep functions
in `seat_contract.py` check different things.

- `diag_stances` (`scripts/seat_contract.py:136`) validates only `id`, `stance` and a non-empty
  reject rationale. `valid_stances` then silently deletes an invalid `revision` field and an invalid
  `new_evidence` object. A seat's intended correction, or an evidence item, disappears — and for a
  support stance, dropping the revision changes the effective stance from "support with a proposed
  change" to a plain endorsement.
- `normalize_points` (`scripts/seat_contract.py:84`) filters invalid point objects while `ok_points`
  accepts the finding as long as **any** point survives, so a finding passes validation having lost
  part of its evidence.
- `check_draft:76` delegates its success decision to `parse_block --diagnose`, so the seat is shown
  an all-items-valid result.

Measured by the panel: on a draft with one stance carrying `revision {"severity":"moderate"}`
(not a valid severity) and one carrying a `new_evidence` object with no `location`, `check_draft`
printed `OK - 2 item(s), 0 invalid`, while `valid_stances` returned both objects with `revision` and
`new_evidence` deleted.

This defeats the purpose of the seat-facing validator. The seat is told its draft is clean, emits,
exits — and the loss is only visible, if at all, as a missing revision in the committed round.

## Expected behavior

1. `diag_stances` reports every field `valid_stances` would drop, naming the field and why:
   an invalid `revision` key or value, a `new_evidence`/`evidence` object that fails `valid_point`.
2. `diag_findings` reports dropped points rather than passing on the survivors — either as an error
   or as an explicit "n point(s) dropped" line the seat can act on.
3. `check_draft` exits non-zero, or at minimum prints a distinct non-OK summary, whenever anything
   would be dropped. A silent `0 invalid` for a lossy draft is the specific behaviour to remove.
4. The header invariant either becomes true, or is rewritten to state exactly what the check does
   and does not guarantee.

## Verification

- `tests/python/` cases for: a stance with an out-of-enum `revision.severity`, a stance with a
  `new_evidence` object missing `location`, and a finding with one valid and one invalid point —
  each surfaced by `check_draft` rather than reported as clean.
- A case asserting a fully valid draft still reports OK unchanged.
- `./tests/run_tests.sh` passes.

## Non-goals

- Do not make `parse_block` reject a whole block because one item is lossy. The silent-drop
  behaviour at parse time is deliberate (a partial block still beats a discarded round); this issue
  is about telling the seat *before* it emits.

## Resolution

Completed 2026-10-20: diagnostics now report invalid revision fields, rejected revisions, invalid
evidence objects, and finding points that normal parsing would discard. The shared revision
normalizer keeps diagnostics aligned with runtime filtering; tests confirm partial finding parsing
still retains valid points.
