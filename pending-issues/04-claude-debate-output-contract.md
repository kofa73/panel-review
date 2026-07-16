# Require both Claude debate blocks

Priority: 4

Status: Pending

Source: former `pending.md` item 12

## Problem

The Claude seat is told that `new_findings` is optional during debate, while every downstream
delivery and checkpoint contract requires both `stances` and a required-emptyable `new_findings`
block. Following the agent instruction literally can therefore produce output that its own delivery
helper rejects.

## Verified evidence

- `agents/panel-review-claude-seat.md` calls `new_findings` optional.
- `prompts/debate.tmpl` says the block must always be emitted, using `[]` when there are no new
  findings.
- `prompts/claude_delivery.tmpl` instructs the seat to validate and write both blocks once.
- `scripts/write_seat_raw`, `scripts/sweep`, and the canonical protocol require a complete two-block
  debate checkpoint.

## Required outcome

Make the Claude agent's role summary agree with the required-emptyable contract: every debate result
contains exactly one `stances` block and exactly one `new_findings` block; the latter contains `[]`
when empty.

Keep the agent definition thin. Detailed block schemas and validation commands should stay with the
shared debate/delivery contract rather than being copied into the agent file.

## Verification

- Add a regression that fails when the Claude agent describes either debate block as optional.
- Check an assembled Claude debate prompt and delivery wrapper for the complete contract.
- Verify a no-new-findings Claude response succeeds with `[]`, while a missing block fails closed.
- Run `tests/python/test_write_seat_raw.py`, relevant round/protocol tests, the full suite, and
  `git diff --check`.
