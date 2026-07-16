# Remove low-risk implementation and test duplication

Priority: 8

Status: Optional

Source: former `pending.md` item 15

## Problem

Two small areas retain repetitive implementation or test setup. Neither has a known correctness
impact, so they should not be mixed into higher-priority fixes.

## Optional changes

- Extract the repeated open-issue-ID lookup in `scripts/sweep` if the resulting helper makes the
  ownership and failure behavior clearer.
- Introduce small debate/Claude-response fixtures for repeated setup in
  `tests/python/test_round.py` if they improve test readability without hiding relevant inputs.

## Constraints

- Preserve behavior exactly.
- Do not introduce a general abstraction for only one or two call sites unless it makes an invariant
  explicit.
- Keep fixture data close enough to each test that the behavioral difference remains visible.

## Verification

- Existing focused tests must pass unchanged in meaning.
- Review the diff for reduced duplication and improved readability; revert the cleanup if it merely
  moves complexity.
- Run the full suite and `git diff --check`.
