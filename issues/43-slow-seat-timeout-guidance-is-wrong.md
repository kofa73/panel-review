# Rewrite README's slow-seat timeout guidance around the ceiling that actually applies

Priority: 43

Status: Pending

Source: Simplification panel (Opus §4.3), 2026-08-16 — verified in the working tree

Triage: ready-for-agent

## Problem

`README.md:271-298` ("Slow seats and timeouts") tells a user who raises `PANEL_REVIEW_SEAT_TIMEOUT`
to add `CLAUDE_ASYNC_AGENT_STALL_TIMEOUT_MS` to `settings.json`. That variable is documented as the
stall timeout for **background subagents** (`claude-code-docs/docs/env-vars.md`). Since `preflight`
now hard-requires `CLAUDE_CODE_FORK_SUBAGENT=0` and the protocol dispatches every Agent with
`run_in_background: false`, panel-review has no background subagents and the variable never applies.
The advice is inert.

The ceiling that does apply is unmentioned anywhere in the repository:
**`CLAUDE_SUBAGENT_BG_SHELL_MAX_MS`, default 3 600 000 ms (60 min)** — the maximum lifetime of a
background shell command started by a subagent (`claude-code-docs/docs/env-vars.md`). That is exactly
what the CLI barrier does in its step 1. Current budgets fit (`await_seats` ≈ 40 min worst case,
barrier waits ≈ 43 min), but raising `PANEL_REVIEW_SEAT_TIMEOUT` past roughly 55 min gets the
barrier's background job killed by the harness rather than by any panel-review timeout — the exact
failure the section is meant to prevent, with no diagnostic pointing at the cause.

The section is also structurally broken: the JSON block is indented as if it were step 3 of a list
that has no steps 1-2, leftover from an earlier edit.

## Expected behavior

1. Replace the `CLAUDE_ASYNC_AGENT_STALL_TIMEOUT_MS` block with `CLAUDE_SUBAGENT_BG_SHELL_MAX_MS`,
   stating the 60-minute default, the roughly 55-minute practical `PANEL_REVIEW_SEAT_TIMEOUT` ceiling
   it implies, and that raising the seat timeout past that also requires raising this variable.
2. Fix the orphaned list indentation so the block reads as part of the surrounding prose.
3. Keep the existing, correct guidance: the barrier retry cap in
   `agents/panel-review-cli-barrier.md` step 2 must still be raised alongside the seat timeout, and
   `BASH_DEFAULT_TIMEOUT_MS`/`BASH_MAX_TIMEOUT_MS` still do nothing here.

## Verification

- No occurrence of `CLAUDE_ASYNC_AGENT_STALL_TIMEOUT_MS` remains outside issue history.
- The three interacting budgets (per-seat timeout, barrier retry cap, harness background-shell
  ceiling) are stated together in one place with their defaults.

## Non-goals

- Do not change any default. Current values fit under the ceiling; this issue is about documenting
  the ceiling before someone raises a value into it.

## Comments

### 2026-09-05 — the ceiling this issue is written around may no longer exist

Claude Code 2.1.260's changelog says:

> Removed the one-hour time limit on background commands started by subagents; they now run until
> they exit or are stopped, matching the main session

That is precisely the `CLAUDE_SUBAGENT_BG_SHELL_MAX_MS` ceiling this issue exists to document. **The
documentation contradicts the changelog on the installed version (2.1.261)**, so neither can be
trusted without a measurement:

- `docs/tools-reference.md` "Background commands" no longer mentions any 60-minute cap. It keeps
  only the rule that matters more here: *a command started by a **foreground** subagent stops when
  that subagent gives its final response.*
- `docs/env-vars.md` still documents `CLAUDE_SUBAGENT_BG_SHELL_MAX_MS` with "Default `3600000`
  (60 minutes)", and `docs/interactive-mode.md` still says subagent-owned background commands "are
  instead terminated after 60 minutes".

Resolve this before rewriting the guidance, or the rewrite pins a second wrong number. Measure on
the installed version rather than picking a doc to believe.

Note that the CLI barrier is unaffected either way while it stays a **blocking foreground** Agent:
the cap only ever applied to *background* shells. The rewrite should say that explicitly — it is the
reason the panel has not hit the ceiling in practice, and it is the property that would be lost if
anyone reintroduced a backgrounded wait.
