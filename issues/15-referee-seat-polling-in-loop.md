# Restore event-driven referee seat waiting

Priority: 15

Status: Completed

Source: review `panel-20260719-073553-0dd5c908`

Triage: ready-for-agent

## Decision

This is a valid, release-blocking orchestration regression. The review still completed and its seat
results were usable, but the referee reverted to repeated polling turns while waiting for background
Agents. That is the same high-cost behavior the CLI barrier and two-wake design were introduced to
remove.

The defect belongs ahead of the optional referee/model cost experiments. It is an executable
liveness and resource-consumption problem in the normal review path, not a speculative
optimization.

## Problem

The referee must temporarily stop after dispatching the background CLI-barrier and Claude-seat
Agents. Claude Code retains the referee while it has live background children and wakes it when a
child finishes. The protocol therefore requires two Agent wakes per ordinary pass and explicitly
prohibits polling or narrating the wait.

Commit `177f48f` added a `SubagentStop` hook that treats every referee stop as terminal. The hook
accepts only `PANEL_VERDICT_READY`, `PANEL_VERDICT_WRITE_FAILED`, or `PANEL_REVIEW_FAILED`. When the
referee tried to yield with a waiting response while its background children were still running,
the hook blocked the stop and told the same referee to return a terminal status. The re-invoked
referee checked the seat files, found them pending, narrated the wait, and attempted to stop again.
The hook blocked it again, producing the polling loop.

The hook's current handling of `stop_hook_active` makes the loop unbounded in practice. It continues
to block an invalid retry even though Claude Code's hook guidance says an active stop-hook
continuation must be allowed to stop. The documented eight-consecutive-block cap does not protect
this path because each intervening Bash poll counts as progress and resets the consecutive-block
sequence.

## Verified evidence

The referee transcript is:

`~/.claude/projects/-workspace-dt-pr/2c9a6570-e38d-456f-a791-25d260c2125c/subagents/agent-a07996ddc8c4f923c.jsonl`

The run state retained at `/tmp/panel-20260719-073553-0dd5c908/` confirms that all three passes
eventually completed and that the polling was not caused by missing seat output.

Across Round 0 and debate Rounds 1-2, the waiting windows contain:

- 279 referee Bash polling calls;
- 432 polling or wait-narration model calls after deduplicating the JSONL by `message.id`;
- 52,092,919 cache-read input tokens in those calls; and
- 81,518 cache-creation input tokens in those calls.

The complete referee transcript contains 537 deduplicated model calls and 60,505,864 cache-read
input tokens, so the wait loop accounts for about 86% of its cache-read traffic. The raw transcript
has 666 assistant records, but 129 repeat an existing `message.id` and must not be counted again.

Round 2 alone contains 70 Bash polls and 94 polling or wait-narration calls, consuming 15,857,584
cache-read input tokens. The short loop quoted in the original report was therefore only a small
visible portion of the actual repetition.

The transcript repeatedly includes the hook correction:

> Return exactly PANEL_VERDICT_READY, PANEL_VERDICT_WRITE_FAILED, or PANEL_REVIEW_FAILED followed by
> the run ID, with no surrounding text.

Those corrections occur between the referee's waiting responses and its next seat-file poll. The
polling begins after commit `177f48f` introduced the hook; the no-poll contract predates it in commit
`5747dc3`. The issue-13 smoke test exercised terminal failure returns without live child Agents, so
it did not cover the referee's required intermediate stopped/waiting state.

## Implemented fix

The originally proposed `PANEL_REVIEW_WAITING` status was rejected after an isolated Claude Code
smoke test showed that accepting it completes the referee Agent; later child notifications reach the
main session instead of resuming the referee. The implemented orchestration removes the need for an
intermediate referee stop:

1. Each pass emits the foreground CLI-barrier Agent and foreground Claude-seat Agent calls together
   in one assistant response, both with `run_in_background: false`.
2. Claude Code runs those foreground calls concurrently and returns control to the referee only
   after both have completed. The referee therefore does not stop, poll, or narrate while seats are
   live.
3. The CLI barrier retains the long Bash/sentinel wait loop in its small context; no seat-wait loop
   moves back into the referee.
4. `PANEL_REVIEW_WAITING` remains invalid. The three terminal referee statuses and the Claude-seat
   statuses remain unchanged.
5. An invalid referee correction received with `stop_hook_active=true` is allowed to stop rather
   than enter an unbounded hook-correction loop. The Claude-seat gate remains strict.

README, the protocol, the referee bootstrap, the CLI-barrier agent, script ownership guidance, and
the existing hook/protocol tests now describe and enforce this model.

## Verification

- TDD coverage in `tests/python/test_agent_status_hook.py`,
  `tests/python/test_protocol_phases.py`, and `tests/run_tests.sh` requires paired foreground Agent
  dispatch, prohibits referee polling, rejects `PANEL_REVIEW_WAITING`, and covers
  `stop_hook_active` liveness.
- The isolated foreground-concurrency smoke passed: the barrier and Claude-seat calls overlapped,
  and their parent returned only after both completed.
- The full local suite passed with `PASS: 223, FAIL: 0`; `scripts/check_contracts --root .`, the
  focused hook/protocol tests, and `git diff --check` also passed.
- Real review `panel-20260720-120133-3599d270` reproduced the failing run's exact diff hash
  `f604aae91c86c98885b221b8af1cf90367aa259773480b77323d95aa48b646e7`. Round 0 and both debate
  rounds each dispatched the CLI-barrier and Claude-seat Agents together with
  `run_in_background: false`; their execution intervals overlapped, and the referee issued no Bash
  or other tool call between the paired dispatch and the combined return.
- The real review completed normally with all three seats engaged, a clean repository guard, two
  converged debate rounds, a persisted finished artifact, and exact artifact-only delivery at
  `/tmp/panel-20260720-120133-3599d270.md`.

## Non-goals

- Do not remove the CLI barrier or replace event-driven waiting with longer sleeps.
- Do not parse child Agent transcripts or poll raw/status files from the referee.
- Do not weaken artifact validation or make the referee's returned status authoritative.
- Do not change seat review, debate, or consensus semantics.
