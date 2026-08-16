# Remove the inert state fields and the orphan-card quarantine

Priority: 45

Status: Pending

Source: Simplification panel (Sol "Small removals"), 2026-08-16 — each field's readers re-checked by
grep

Triage: ready-for-agent

## Problem

Four persisted fields and one preservation branch look like state protection and enforce nothing.

- **`manifest.phase`** — written once by `scripts/init_run:88`. Every live phase decision reads
  `index.phase` (`scripts/round:310`, `read_verdict_artifact:198-222`, `protocol.md:702`,
  `write_verdict_artifact:79-82`). The manifest copy is never re-read and never updated, so it is
  stale duplicate state from the moment Round 0 commits.
- **`manifest.state_version`** — fixed at `1` by `init_run`, read only by `regen_cards:26` to
  interpolate into a card HTML comment. No reader validates it.
- **card `index_rev`** — the value above, rendered into `project_card:62`'s comment. Nothing compares
  it.
- **issue `card_rev`** — created by `birth_index:114` and incremented in eight places in
  `scripts/index`, then rendered into the same comment. No runtime reader compares it either, and
  `protocol.md:154` tells the referee not to hand-edit a field nothing consumes.
- **`.orphan` quarantine** (`scripts/regen_cards:39-44`) — moves stale `issue-*.md` files aside
  instead of deleting them, even though cards are explicitly non-authoritative and regenerable from
  `index.json`.

Together they suggest a stale-card detection scheme that does not exist. A constant, unchecked
revision number is not protection.

## Expected behavior

1. Remove `manifest.phase`, `manifest.state_version`, card `index_rev`, and issue `card_rev`, along
   with their writers, incrementers, card-comment rendering, and the `protocol.md` bullet about them.
2. Replace the `.orphan` quarantine with plain deletion of stale `issue-*.md` files before
   regeneration. This is safe once issue 24 lands and no seat-authored scratch remains under the
   marker directory; sequence it after issue 24.
3. Do this as one schema migration, updating `tests/fixtures/` and `tests/python/` in the same
   commits. A half-removed field is worse than the current state.

## Verification

- `grep -rn "state_version\|index_rev\|card_rev\|manifest.phase\|\.orphan" scripts tests docs
  skills README.md` returns nothing outside issue history.
- `./tests/run_tests.sh` passes, including the round-transition and card-regeneration tests.
- One real review completes and its cards regenerate after an interrupted round.

## Non-goals

- Do **not** remove `run_epoch`, `committed_rounds`, `rounds_debated`, `evaluated_by`, or the
  artifact's `index_hash`. Those are consumed for continuation identity, idempotence, round limits,
  `fully_vetted` coverage, and delivery validation respectively.
