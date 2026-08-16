# Remove the referee's dead `TaskCreate` progress-reporting section

Priority: 41

Status: Pending

Source: Simplification panel (Opus, Sol, Gemini Pro, Gemini Flash), 2026-08-16 — raised independently
by Opus (§4.2) and Sol (§3); verified in the working tree

Triage: ready-for-agent

## Problem

`agents/panel-review-referee.md:58-68` instructs the referee to call `TaskCreate` at the start of
every run and to update `activeForm` with six status strings.

Claude Code 2.1.233 removed `TaskCreate`/`TaskGet`/`TaskUpdate`/`TaskList`/`TodoWrite` from Opus 4.8,
Sonnet 5, Fable 5, Mythos 5 and newer (`claude-code-docs/docs/changelog.md`,
`docs/tools-reference.md`) unless `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` is set. The referee pins
`model: opus`, which resolves to `claude-opus-5`. So the instruction points the referee at an absent
tool in its first turn — before any run state exists — costing a wasted turn or a tool-not-found
error at the worst point in the run.

`issues/22-claude-code-2-1-219-runtime.md:106-108` already records the removal but states
"Panel-review never uses them". That statement is false; `agents/panel-review-referee.md:60` is the
counter-example.

## Expected behavior

1. Delete the "Progress reporting" section from `agents/panel-review-referee.md`. The user already
   sees the subagent row while the foreground Agent call blocks; the six `activeForm` strings are
   ceremony, not review correctness.
2. Correct the claim in `issues/22-claude-code-2-1-219-runtime.md` so the record does not assert
   something the tree contradicts.
3. If `check_contracts` or `tests/run_tests.sh` pins any of the removed strings, drop those
   assertions with the section.

## Verification

- `grep -rn "TaskCreate\|TodoWrite\|activeForm" agents skills scripts tests` returns nothing outside
  `issues/`.
- `scripts/check_contracts --root .` and `./tests/run_tests.sh` pass.

## Non-goals

- Do not add `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` to the session requirements to keep the section
  working. The session already carries one mandatory environment requirement
  (`CLAUDE_CODE_FORK_SUBAGENT=0`); a second one bought for a progress spinner is not worth it.
