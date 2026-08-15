# Restore blocking seat dispatch under Claude Code fork mode

Priority: 25

Status: Pending

Source: Claude Code documentation review (2.1.222 → 2.1.233), 2026-08-15

Triage: ready-for-human

## Problem

Claude Code 2.1.232 turned **fork mode on by default in interactive sessions**. Where fork mode is
on, Claude Code runs **every** subagent in the background — forks and non-forks alike — and
**removes the Agent tool's `run_in_background` parameter**, so the model cannot ask for a foreground
subagent at all.

Panel-review's entire seat-dispatch design depends on foreground Agent calls that block:

- the referee issues the `panel-review-cli-barrier` Agent and the Claude-seat Agent **in one
  response with `run_in_background: false`**, and resumes only after both return
  (`skills/panel-review-for-agent/SKILL.md`, `references/protocol.md`, `agents/panel-review-cli-barrier.md`);
- `start` / `resume` / `continue` dispatch the referee the same way and "await its single return";
- the protocol forbids polling or narrating between dispatch and the combined return, precisely
  because the two foreground calls are the wait mechanism (issue 15).

On a session with fork mode on, that mechanism is gone: the instruction to pass
`run_in_background: false` names a parameter that no longer exists, and the seat Agents return
through completion notifications in later turns instead. The referee can therefore reach its
collection step before any seat has written its raw file, which the pipeline reads as a
**down-seat pass** — a false degraded round, a wrong `fully_vetted=false` label, and in the worst
case a verdict synthesized from no seat output at all.

## Evidence

`docs/sub-agents.md` (Claude Code docs, 2026-08-15):

> Where fork mode is on, as it is by default in an interactive session, Claude Code runs the
> subagent in the background, forks and non-fork subagents alike, and Claude can't ask for the
> foreground.

> Claude Code also removes the Agent tool's `run_in_background` parameter, so Claude can't ask for
> the foreground.

> Claude Code turns fork mode on by default in interactive sessions and leaves it off by default in
> non-interactive mode with `-p` and in the Agent SDK. The interactive default requires Claude Code
> v2.1.232 or later.

Observed directly on this machine (Claude Code **2.1.233**, interactive session): the Agent tool
exposed to the model has **no `run_in_background` parameter**, and its description states that
subagents run in the background and notify on completion.

## `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` is not the fix

It does force every subagent to the foreground in every session type, but it also disables
background Bash tasks — and `agents/panel-review-cli-barrier.md` step 1 **requires** a Bash call
with `run_in_background: true` to launch `await_seats` detached with its completion sentinel.
Turning it on trades one broken half of the barrier for the other.

## Candidate fixes

**A. Require fork mode off for panel-review runs.** `CLAUDE_CODE_FORK_SUBAGENT=0` turns fork mode
off in every kind of session, which restores `run_in_background` and the "foreground when Claude
needs the result" behavior the protocol assumes. Documented in README requirements next to the
nested-subagent floor from issue 22, and optionally surfaced by `scripts/preflight` as an advisory
(it can read the environment variable, though not a `settings.json` value that a session already
resolved). Cheapest, and leaves the protocol untouched.

**B. Make the protocol background-tolerant.** Dispatch both Agents, end the turn, and let the
completion notifications resume the referee. This is a real redesign of the wait mechanism issue 15
established, and it must not reintroduce polling; the barrier's sentinel loop and the
"no turns between dispatch and the combined return" rule both assume blocking calls.

Recommended: **A now**, with B evaluated only if Anthropic removes the fork-mode override.

## Expected behavior

- Whatever is chosen, a panel review either runs with a blocking seat dispatch or refuses to start
  with a message naming the setting to change — never silently proceeds to read seat files that
  cannot exist yet.
- The requirement (or the new mechanism) is stated once, in README, with the protocol and the
  barrier agent pointing at it rather than restating it.
- The blindness constraint is unaffected: the Claude seat is still spawned fresh by type and is
  **never** `subagent_type: "fork"`. Fork mode being on makes that constraint newly reachable — a
  fork would inherit the referee's context — so it stays a hard constraint, not an optimization.

## Verification

- With `CLAUDE_CODE_FORK_SUBAGENT=0`, confirm the Agent tool schema again carries
  `run_in_background`, and that a real review keeps the referee blocked until both branches return
  (no referee turns between dispatch and the combined return in the transcript).
- With fork mode on (the 2.1.232+ default), reproduce the failure once and record what the referee
  actually did, so the failure mode is documented rather than inferred.
- `scripts/check_contracts --root .` and `./tests/run_tests.sh` pass.

## Non-goals

- Do not adopt `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` (see above).
- Do not convert any seat to a fork to "work with" fork mode.
- Do not add polling of seat status files as a substitute for the blocking return.
