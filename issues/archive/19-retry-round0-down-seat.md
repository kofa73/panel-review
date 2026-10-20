# Retry a down Round-0 seat once

Priority: 19

Status: Completed

Source: user report, 2026-07-20

Triage: ready-for-agent

## Problem

Round 0 does not retry a seat that clearly failed to produce a review. A zero-byte raw response is
parsed as status 4, recorded as a down seat, and immediately excluded from clustering and issue
birth. The run then continues with the smaller engaged panel.

This differs from the debate contract, which retries every missing, empty, partial, wrong-ID, or
otherwise non-complete batch once before dropping the seat. A transient failure therefore has a
larger and irreversible effect in Round 0 even though Round 0 establishes the initial issue set and
review coverage.

Do not confuse a zero-byte raw response with a valid empty findings response. A present, valid
`findings` block whose body is empty or `[]` is a successful seat pass with no findings and must not
be retried.

## Current behavior

- `run_seat` captures an empty CLI response, receives parse status 4, and performs no retry.
- `await_seats` records the status and settles normally; a down seat is not a barrier failure.
- The Round-0 protocol permits CLI salvage when status 4 contains a real prose review, but treats an
  actual empty/error stub as down for the pass. A missing Claude raw is likewise treated as down.
- `round collect-round0 --final` reports the engaged subset, after which the referee proceeds to
  clustering and `birth_index` without a retry step.
- Debate retries each non-complete batch once before `sweep drop-seat`, so the two phases have
  different transient-failure handling.

## Resume limitation

Resume does not generally repair this after Round 0 has completed. The recovery protocol reruns
missing or empty Round-0 seats only when the index has no issues and therefore treats Round 0 as
incomplete. Once an index has been built, resume proceeds from that index without rerunning the
failed blind pass.

A configured seat may engage in a later debate round, but that is not equivalent to a Round-0
retry: it sees the canonical blind cards rather than independently reviewing the original scope, it
cannot add its independent support to issue birth, and a review that finishes without debate gives
it no later opportunity at all.

The fix therefore needs resumable same-pass retry state. While Round 0 remains interrupted and
uncommitted, every resume may retry a currently available seat that was down in that Round-0 pass:
the earlier failure may have been transient and its cause may have gone away. Resume must preserve
completed seat passes and dispatch only the seats that remain down or incomplete. It should not
retroactively rerun Round 0 after an index has already been installed.

## Expected behavior

Before clustering Round-0 findings:

1. Preserve every successfully engaged seat and do not dispatch it again.
2. Attempt normal CLI shape salvage when a status-4/5 raw contains a completed review. Do not
   re-dispatch merely to repair formatting.
3. Give each genuinely down seat one fresh dispatch using the same saved scope, diff, instructions,
   review profile, prompt contract, and configured seat identity. A zero-byte raw is an unambiguous
   down-seat case. A non-empty status-4 error/refusal stub may use the same retry after the referee
   classifies it as a stub rather than a salvageable review.
4. Recollect the retried seats. If a seat still does not engage, mark it down and continue degraded.
5. Cluster findings and install the index only after all required first attempts and retries have
   settled.

The Claude retry must spawn a fresh Claude seat. CLI retries must continue to use `run_seat` through
the CLI barrier; neither the referee nor the main conversation may substitute for a seat. Retrying
must preserve Round-0 blindness: the retry receives only the original blind-pass material and no
other seat's output or engagement status.

## Implementation requirements

- Put Round-0 retry preparation and attempt bookkeeping behind a deterministic owner rather than
  requiring the referee to hand-roll raw paths, attempt counts, barrier commands, or cleanup.
- Make the retry checkpoint resumable so an interruption between the first collection and retry
  collection dispatches only the unfinished down seats. A later resume of the still-uncommitted
  Round 0 may give a still-down, currently available seat another attempt.
- Keep the distinction between salvage and retry explicit: salvage preserves a completed review's
  conclusions; retry performs a new blind review after an actual failed attempt.
- Record the retry and final down-seat result in Process notes without exposing seat identity or
  engagement information to another seat.
- Do not change the debate retry/drop-seat contract.

## Verification

- A CLI seat that returns zero bytes once and a valid block on retry engages in Round 0, with exactly
  two dispatches for that seat and one for each initially successful seat.
- A CLI seat that returns zero bytes twice is marked down only after the second attempt.
- A missing or empty Claude delivery is retried once through a fresh Claude seat and then either
  engages or is marked down.
- A present valid empty `findings` block engages with zero findings and is dispatched exactly once.
- A salvageable status-4/5 CLI review is recovered without a fresh review dispatch.
- Resume after interruption between attempts retains completed seat passes and dispatches only
  currently available seats that remain down or incomplete, including a seat whose earlier retry
  also failed.
- Resume after index installation does not retroactively rerun Round 0.
- Round-0 birth state, `evaluated_by`, and `fully_vetted` use the final engaged set after retry.
- Update the canonical protocol, `README.md`, `.claude/rules/scripts.md`, contract checks, and test
  documentation to describe the same retry boundary.
- Run focused Round-0/recovery tests, `scripts/check_contracts --root .`, `./tests/run_tests.sh`, and
  `git diff --check`.

## Implementation

- `round prepare-round0` now records deterministic `initial`, single `--retry`, and later `--resume`
  attempts in `/tmp/<ID>/round0.attempts.json` before clearing any retry target.
- The first preparation freezes the configured panel and exact blind prompt. Retry and resume use
  current preflight only as an availability filter over that original panel; newly available seats
  may join later debate but cannot change the interrupted blind pass.
- A complete Round-0 checkpoint binds a non-empty retained raw, status 0, and a parsed-output file.
  Preparation reconstructs that checkpoint from a valid raw written immediately before an
  interruption, so it does not delete and rerun a completed Claude or CLI seat pass.
- Retry preparation returns only the non-null Claude and CLI-barrier inputs needed for currently
  available seats that remain down. A valid empty fenced findings response remains complete and is
  never retried.
- The referee protocol owns salvage judgment, uses `--retry` once in a fresh invocation, uses
  `--resume` for later interrupted-Round-0 recovery, and records each attempt and outcome in Process
  notes from the structured Round-0 attempt history and final statuses returned by `verdict-input`.

## Verification results

- TDD regressions cover selective CLI and Claude retries, zero-byte output, valid empty findings,
  stale success status, valid raw recovery before collection, frozen panel/prompt behavior, a
  completed seat absent from current preflight, one-use fresh retry, and later resume attempts.
- Focused Round-0, protocol-phase, and contract-consistency suites pass (43 tests).
- `scripts/check_contracts --root .` passes and rejects removal of the Round-0 retry contract.
- `./tests/run_tests.sh` passes.
- `claude plugin validate . --strict` passes with synchronized `1.0.17` manifests.
- `git diff --check` passes.
- The required Standards/Spec review found stale tracker status plus attempt-bookkeeping,
  pre-collection checkpoint, frozen-prompt, and verdict Process-note input gaps; all were corrected
  before final verification.
