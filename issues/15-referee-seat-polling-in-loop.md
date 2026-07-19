# Restore event-driven referee seat waiting

Priority: 15

Status: Pending

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

## Proposed fix

Give the referee a distinct, exact intermediate status and make the hook distinguish it from a
terminal result:

1. Add `PANEL_REVIEW_WAITING id=<ID>` to the referee's internal contract. The referee may emit it
   only after dispatching background seat Agents, or after one child wake while another child is
   still live. It must not poll or narrate before emitting the status.
2. Make `hooks/enforce_agent_status_stub` accept that exact waiting status for the referee while
   retaining the three existing terminal statuses. Wrong IDs, prefixes, suffixes, and arbitrary
   prose remain blocked.
3. Follow Claude Code's `stop_hook_active` liveness rule: after one rejected referee response, do not
   keep blocking the same stop-hook continuation indefinitely. The main command already treats the
   referee result as non-authoritative and validates the durable artifact, so failure to obtain a
   valid terminal stub must remain resumable rather than trigger an unbounded correction loop.
4. Keep the Claude-seat status rules unchanged. This regression is caused by the long-lived referee
   yielding while it owns background children; a Claude seat has no equivalent intermediate state.

The exact waiting status preserves the fixed Agent interface without parsing internal Agent
transcripts or weakening the terminal artifact-only boundary. Under the normal runtime path it does
not reach the main command: Claude Code keeps a subagent with live background children pending and
uses their completion notifications to wake it. If it does escape because no child is live, the main
command's artifact validation rejects the incomplete run and leaves it resumable.

## Verification

- Extend `tests/python/test_agent_status_hook.py` to cover the exact waiting status, wrong IDs,
  surrounding prose, and `stop_hook_active` liveness behavior.
- Add a wording contract requiring the referee to return the waiting status immediately instead of
  polling or narrating after dispatch and after a partial wake.
- Run a focused Claude Code integration smoke test with a referee-like Agent and two staggered
  background child Agents. Verify that the parent receives only the terminal referee status, that
  each child completion causes one wake, and that the referee transcript contains no Bash seat-file
  polling between dispatch and completion.
- Run one real review and compare the referee trace with the failing run: ordinary single-batch
  passes should have two child wakes and zero polling calls.
- Run `scripts/check_contracts --root .`, `python3 -m unittest
  tests.python.test_agent_status_hook -v`, `./tests/run_tests.sh`, and `git diff --check`.

## Non-goals

- Do not remove the CLI barrier or replace event-driven waiting with longer sleeps.
- Do not parse child Agent transcripts or poll raw/status files from the referee.
- Do not weaken artifact validation or make the referee's returned status authoritative.
- Do not change seat review, debate, or consensus semantics.
