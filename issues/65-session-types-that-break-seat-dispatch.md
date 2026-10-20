# Catch the session types that still background the referee or time-limit the CLI barrier

Priority: 65

Status: Pending

Source: Claude Code changelog and docs review (2.1.262 → 2.1.303), 2026-10-19. Installed Claude
Code: 2.1.303.

Triage: ready-for-human

## Problem

`preflight` admits a session when `CLAUDE_CODE_FORK_SUBAGENT=0` (`issues/25`). Two later Claude Code
changes break seat dispatch in sessions that pass that check. README never says the panel needs a
terminal CLI session, so neither case is excluded on paper either.

### 1. Desktop app and VS Code background the referee (2.1.302)

> Changed the desktop app and VS Code to always run the main conversation's subagents in the
> background, as the terminal does, rather than let Claude choose

The referee is a main-conversation subagent, and `start` needs it to block. A VS Code user who sets
`CLAUDE_CODE_FORK_SUBAGENT=0` through `claudeCode.environmentVariables` passes `preflight`, and if the
changelog is right, still gets the backgrounded referee that `issues/25` measured. That failure mode
included one improvised polling loop in four trials.

The documentation does not confirm this. The current `docs/sub-agents.md` "Run subagents in
foreground or background" rules list no desktop or VS Code case, and still say a fork-off session lets
Claude choose the foreground. The two sources disagree, so this needs a measurement.

The same release made fork subagents default-on in `claude -p` and the Agent SDK, while
`docs/sub-agents.md` still says fork mode is off there by default. `preflight` requires the explicit
`0` everywhere, so that change is already covered.

### 2. Unattended sessions time-limit the barrier's background job (2.1.285, 2.1.288)

`agents/panel-review-cli-barrier.md:65-70` starts `await_seats` with `run_in_background: true` and
passes no `timeout`. Since 2.1.285, background commands have a time limit. Since 2.1.288, that limit
applies only in unattended sessions: `-p`, the Agent SDK, CI and cloud sessions
(`docs/tools-reference.md`, "Time limit for background commands"). The defaults are **30 minutes**,
or **10 minutes** in a `-p` run whose prompt is passed as text. An explicit `timeout` can raise it to
2 hours.

The seats legitimately run longer than that: `await_seats` allows 2400 s per seat
(`scripts/await_seats:71`), and the barrier waits up to 26 × 100 s. When the limit kills the
background command, the wrapper never writes the sentinel. The barrier then waits out its whole
budget and reports the CLI seats unavailable for that pass.

Interactive terminal sessions have no limit, so the supported setup is not affected today.

## Expected behavior

1. **Measure item 1** in VS Code (or the desktop app) with `CLAUDE_CODE_FORK_SUBAGENT=0`: does the
   `start` skill's foreground referee call block? Record the result and the version here.
2. **If the backgrounding is confirmed,** README "Requirements" says the panel runs in the terminal
   CLI only. The owner then decides whether `preflight` also checks `CLAUDE_CODE_ENTRYPOINT` (`cli` in
   a terminal session). That variable is visible to subprocesses but undocumented, and `preflight`'s
   own comment (`scripts/preflight:33-38`) rejects an entrypoint check. The reason given there was to
   avoid refusing `-p` sessions, which does not apply to refusing desktop and VS Code. Recommended: a
   warning, not a hard failure, because the variable is undocumented.
3. **Item 2:** the barrier's background launch passes an explicit Bash `timeout` above its own worst
   case and below the 2-hour maximum (for example 2 700 000 ms, 45 minutes). It has no effect in an
   interactive session and makes the documented limit harmless elsewhere. The barrier's text explains
   why the value is there.

## Verification

- The item 1 measurement is recorded with the Claude Code version and surface.
- The barrier text and any `check_contracts` pin on it agree on the new launch form.
- `scripts/check_contracts --root .` and `./tests/run_tests.sh` pass.
- One real terminal review still completes with all three seats engaged.

## Non-goals

- Do not reintroduce a referee-side polling wait to work around backgrounding. `issues/15` removed it.
- Do not make `-p` or the Agent SDK supported entry points here. Item 2 only stops an unattended
  session from losing a pass silently.
- README's general slow-seat guidance stays in `issues/43`.

## Comments

### 2026-10-19 — a workflow may make item 1 moot

`issues/67` measured that a workflow's `parallel()` waits for the Claude seat and the CLI barrier
even with fork mode on. If the rounds move to a workflow, the desktop app and VS Code no longer need
the referee's Agent calls to block, and item 1 applies only to the fallback path. Item 2 (the
barrier's background-command time limit) still applies inside a workflow, because the barrier keeps
its background launch there.
