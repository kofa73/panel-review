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

## What fork mode does and does not change

The name misleads: turning fork mode on does **not** convert this plugin's typed subagents into
forks. A seat spawned by type (`panel-review:panel-review-claude-seat`) stays a **non-fork**
subagent, which is exactly what panel-review needs and already uses:

| | Fork | Non-fork subagent |
|---|---|---|
| Context | full parent conversation | fresh, from the prompt passed |
| System prompt / tools | same as parent | from the definition file, filtered for background runs |
| Model | same as parent | from the definition's `model` field |
| Prompt cache | shared with parent | separate |

Both non-fork properties are load-bearing. **Fresh context** *is* the blindness constraint: a fork of
the referee would inherit the other seats' raw output and the stance tally. **Independent model
control** is in active use — the Claude seat pins `model: opus, effort: xhigh` while the CLI barrier
pins `model: sonnet, effort: low` so the ~43-minute wait loop runs cheaply in its own small context;
a fork would run both on the referee's model with the referee's full tool pool.

Fork mode changes only two things (`docs/sub-agents.md`): it makes the `fork` subagent type
*available* for the model to request, and it schedules **every** subagent in the background,
removing `run_in_background`. Subagents spawned from a definition otherwise "work as usual". Only
the scheduling change breaks panel-review. So this issue is a **wait-mechanism** problem, not a
fork-contamination problem: context, model pinning, and blindness are untouched.

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

## An `Agent(fork)` deny rule is not the fix either

Fork mode can be left on with the `fork` subagent type denied by an `Agent(fork)` permission rule,
but the docs are explicit that "subagents still run in the background". That removes the
newly-reachable footgun of the referee requesting a fork; it does nothing about the collection race,
which is the actual defect. At most it is belt-and-braces alongside fix A.

## Measured: what a backgrounded subagent's parent actually experiences

Two experiments on this machine (Claude Code 2.1.233, interactive session, fork mode at its default;
level-1 and level-2 agents both `general-purpose` on Sonnet). Each child returned a random token that
existed **only** in its final message — never written to disk — so a parent could not have obtained
it any other way.

**1. A parent is resumed by its background child; it does not die at end of turn.** The level-1 agent
dispatched one child (~90 s), then ended its turn with no tool call. It was re-invoked with the
child's result and reported `RESUMED=yes … CHILD_TOKEN=<hex>`, 117 s after dispatch. Its own Agent
tool also had no `run_in_background` parameter, so the backgrounding is involuntary one level down
as well. **Notification is therefore not what panel-review loses — blocking is.**

**2. The parent is woken once per child completion, not once after all children settle.** The
level-1 agent dispatched two children in one response (~30 s and ~120 s) and ended its turn after
every wake until it held both tokens. Result: `WAKE_COUNT=2 WAKE_LOG=T0+65s,T0+138s`, matching the
two children's runtimes; at the first wake it held only the fast child's token and had to end its
turn again. Corroborating detail: the *outer* session received exactly one completion notification
for the level-1 agent, because a notification fires only when an agent stops with **no live
background children** — the first, partial wake stayed internal.

Caveats: n=1 per variant, both on Sonnet, and the wake count is self-reported (the `WAKE_LOG`
timestamps corroborate it independently).

## Candidate fixes

**A. Require fork mode off for panel-review runs.** `CLAUDE_CODE_FORK_SUBAGENT=0` turns fork mode
off in every kind of session, which restores `run_in_background` and the "foreground when Claude
needs the result" behavior the protocol assumes. Documented in README requirements next to the
nested-subagent floor from issue 22, and optionally surfaced by `scripts/preflight` as an advisory
(it can read the environment variable, though not a `settings.json` value that a session already
resolved). Cheapest, and leaves the protocol untouched. It also removes the `fork` subagent type
from the referee's Agent tool entirely, so the never-fork constraint becomes unreachable rather than
merely forbidden by prose.

**B. Make the protocol background-tolerant.** Dispatch both Agents, end the turn, and let the
completion notifications resume the referee. This is a real redesign of the wait mechanism issue 15
established, and it must not reintroduce polling; the barrier's sentinel loop and the
"no turns between dispatch and the combined return" rule both assume blocking calls.

The measurements above show B is mechanically possible but weaker than it first appears:

- The referee would have to be **re-entrant**: on every wake, determine whether *all* dispatched
  seats have settled and, if not, end its turn again with no tool call.
- The natural failure on a partial wake is to proceed to `round collect-*` — the exact false
  degraded round this issue is about. B does not remove the defect; it downgrades it from "always"
  to "whenever the referee mishandles a partial wake".
- Partial wakes would be the **normal** case, not an edge case: the Claude seat and the CLI barrier
  have very different runtimes (the barrier alone budgets ~43 minutes), so they will essentially
  never settle together.
- The resulting wait is enforced only by prose. The current design made waiting a *mechanical*
  property of a blocking call, which is why issue 15 forbade polling in the first place.

Recommended: **A now**. It restores a wait that cannot be got wrong, whereas B makes correctness
depend on the referee reliably recognizing an incomplete wake. Revisit B only if Anthropic removes
the fork-mode override.

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
