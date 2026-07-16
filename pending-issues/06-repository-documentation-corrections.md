# Correct repository documentation

Priority: 6

Status: Pending

Source: former `pending.md` item 13

## Problem

Repository-maintainer documentation does not yet describe all scripts and tests added by the pending
implementation. A retained `CONTEXT.md` also needs precise low-severity gate semantics.

This follows the executable-contract work because documentation should describe the final behavior,
not an intermediate design.

## Required outcome

- Update `AGENTS.md`'s Python-script list for `round`, `write_seat_raw`, and
  `read_protocol_phase`.
- Update `tests/README.md` for those scripts and their new Python test modules.
- If `CONTEXT.md` is retained, define the low-severity gate as applying after Round 0 and after
  committed debate rounds.
- If `CONTEXT.md` is retained, state that an explicitly finalized low-only gate is a finished review
  even though low issues remain open.
- Incorporate any documentation changes required by issues 01–05 after their behavior is settled.

## Verification

- Compare script ownership and test listings against the live filesystem rather than copying the
  old inventory.
- Check gate wording against the tested command/protocol behavior.
- Run documentation-specific checks, the full suite, and `git diff --check`.
