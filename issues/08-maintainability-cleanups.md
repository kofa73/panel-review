# Remove low-risk implementation and test duplication

Priority: 8

Status: Completed

Source: former `pending.md` item 15

## Problem

Two small areas retained repetitive implementation or test setup. Neither area had a known
correctness impact, so the cleanup was optional and had to preserve behavior exactly.

## Implementation

- Added the private `_sorted_open_issue_ids` helper in `scripts/sweep` and used it from
  `cmd_plan_scaffold` and `cmd_extend_plan`. The helper retains `sorted_ids` byte ordering and the
  original filtering; each command still owns its no-open-issues failure.
- Added `debate_response`, `install_claude_debate`, and `install_codex_debate` helpers in
  `tests/python/test_round.py` for repeated valid-response setup. The names and separate installation
  paths keep Claude's validated `write_seat_raw` delivery distinct from direct canonical CLI raw.
- Kept missing-block, malformed, stale, multi-batch, and salvaged-response bytes inline where their
  exact shape is part of the assertion. No on-disk fixtures or general test harness were added.

## Preserved constraints

- Preserve behavior exactly.
- Preserve `scripts/sweep`'s `sorted_ids` byte ordering, filtering to string IDs on dictionary issues
  whose state is `open`, and command-specific failure messages.
- Do not move the lookup into `panel_common.py` or reuse `scripts/round`'s order-preserving helper;
  the cleanup should remain local to the batch-plan owner.
- Preserve the delivery distinction in `test_round.py`: Claude raw must pass through
  `write_seat_raw`, while CLI raw is installed at the canonical CLI path for collection or salvage.
- Keep malformed, missing-block, stale, and salvaged response bytes inline so the behavioral
  difference remains visible. Do not turn these synthetic edge cases into shared on-disk fixtures.
- Do not broaden either cleanup into a production interface change or a general test harness.

## Verification

- `python3 -m unittest tests.python.test_sweep tests.python.test_round -v` — 27 tests passed.
- `test_plan_scaffold_round_trip` still proves accepted issues are excluded and open IDs are
  byte-sorted even when index order differs.
- The round tests still exercise `write_seat_raw` for Claude and direct canonical raw files for CLI
  seats, including the missing/malformed/salvaged variants.
- `./tests/run_tests.sh` — `PASS: 223`, `FAIL: 0`.
- `git diff --check` — passed.
