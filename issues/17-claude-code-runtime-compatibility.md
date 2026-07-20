# Align Agent and Bash contracts with current Claude Code

Priority: 17

Status: Completed

Source: Claude Code documentation review `efc54c33..b44396c9`, 2026-07-20

Triage: ready-for-agent

## Decision

Update panel-review for three Claude Code runtime-contract changes and clarifications:

1. make every outer referee Agent invocation explicitly foreground and correct stale command-skill
   wording left behind by the issue-15 foreground migration;
2. fail closed and remain resumable when Claude Code's session-wide Agent-spawn budget is exhausted;
   and
3. correct the CLI-barrier explanation now that timed-out Bash calls move to the background instead
   of being killed.

There is no plugin-schema break. The manifests, plugin-scoped agent names, preloaded referee skill,
`${CLAUDE_PLUGIN_ROOT}` use, `SubagentStop` matcher, and current `stop_hook_active` handling remain
compatible with Claude Code 2.1.215.

This is executable orchestration and recovery-contract work. It belongs immediately after the
release-blocking issue 15 and before the external review-profile feature and optional experiments.

## Implementation state (2026-07-20)

The implementation is complete:

- every outer referee dispatch is explicitly foreground, including the low-severity gate's reuse of
  the same dispatch form;
- the command and referee contracts fail closed on `Subagent spawn limit reached`, preserve the
  checkpoint, forbid role substitution and same-session retry, and direct recovery through `/clear`
  plus `panel-review:resume`;
- the CLI barrier now documents current Bash auto-backgrounding while retaining its explicit
  background launch and sub-timeout sentinel waits;
- `README.md` records the public recovery behavior and delegates timeout mechanism details to the
  barrier agent;
- black-box contract-drift tests and `scripts/check_contracts` cover the new invariants; and
- `.claude-plugin/plugin.json` now carries the marketplace author metadata.

The implementation decisions are resolved:

1. Issue 15 was committed separately as `822e95c`; issue 17 therefore uses version `1.0.15`.
2. The confirmed automated seams are focused contract tests, `scripts/check_contracts --root .`, and
   strict plugin validation.
3. The user explicitly waived deliberate Agent-budget exhaustion and the repeated concurrency smoke.
   Those manual runtime checks do not gate completion or commit. If budget exhaustion occurs
   naturally, its actual runtime recovery behavior should be checked then.

## Pre-implementation evidence

The reviewed Claude Code documentation range is:

```text
efc54c33352080d52529b2756c1d2cfd62021b02..b44396c9f5e8701c7715fca9854dd5a99a7529bf
```

The installed runtime used for validation was Claude Code 2.1.215.

### Outer referee execution was implicit

Claude Code documents foreground subagents as blocking the caller until completion. Subagents run
in the background by default unless Claude decides it needs the result, and a background result is
delivered through a later completion notification.

The pre-implementation tree already pinned the referee's internal `panel-review-cli-barrier` and
Claude-seat Agent calls with `run_in_background: false`. However, the `start`, `resume`, and
`continue` command skills omitted that field when they spawned the outer referee. Those same files
still described "background helper Agents", contradicting the migrated protocol: the internal Agent
calls are foreground calls issued together so that they overlap and return as one barrier.

Artifact-only delivery requires the command skill to block until the referee has persisted or failed
the verdict. Leaving this execution choice implicit permits a later-turn background notification at
the exact seam that requires a single synchronous result.

### Claude Code now has a session Agent-spawn budget

Claude Code 2.1.212 and later allow at most 200 Agent-tool spawns per session by default. Nested,
background, foreground, and completed subagents all count. At exhaustion, the Agent tool fails with
`Subagent spawn limit reached` and its generic recovery advice tells Claude to complete the work
directly.

Panel-review accepts any positive `--max-rounds`, normally spawns a CLI-barrier Agent and a fresh
Claude-seat Agent for each pass, may spawn extra barrier Agents for pagination, and can be invoked
after unrelated subagent activity in the same session. A static panel round cap cannot guarantee
safety because the budget is session-wide and its already-consumed portion is not exposed to the
plugin.

The generic "complete directly" advice is unsafe here. The main conversation cannot replace the
referee, and the referee cannot replace either a blind review seat or the CLI barrier without
breaking role separation, blindness, and the artifact-only contract.

### Timed-out Bash calls now auto-background

Claude Code 2.1.210 and later move a Bash call to the background when its tool timeout expires rather
than killing it. The result identifies the background task and output path. Before implementation,
panel-review said that a long foreground seat/barrier command was killed, truncated, or produced an
empty raw file in:

- `README.md`'s `run_seat` ownership row; and
- `agents/panel-review-cli-barrier.md`'s rationale, wait guidance, and hard rules.

The implementation remains sound: deliberately backgrounding `await_seats`, recording its terminal
exit in an atomic sentinel, and using sub-120-second foreground waits avoids depending on implicit
auto-background behavior. Only the runtime explanation and associated failure wording are stale.

### Manifest validation warning

Before implementation, `claude plugin validate .` passed and `claude plugin validate --strict .`
failed only because `.claude-plugin/plugin.json` omitted optional author metadata, although the
marketplace entry already contained `"author": {"name": "Kofa"}`.

This is not a runtime incompatibility, but copying the existing author metadata into `plugin.json`
is a small, appropriate cleanup while touching the release manifest.

## Proposed fix

### 1. Pin the outer referee foreground

In `skills/start/SKILL.md`, `skills/resume/SKILL.md`, and `skills/continue/SKILL.md`:

- add `run_in_background: false` to every shown referee Agent invocation, including any gate-time
  re-dispatch in `start`;
- describe the referee call as blocking until the artifact is persisted or the run fails; and
- replace "background helper Agents" and child-wake guidance with the current invariant: each pass
  issues the foreground CLI-barrier and Claude-seat calls together, and the referee resumes only
  after both return.

Keep the prohibition on `SendMessage` nudges, re-dispatch, and polling.

### 2. Define spawn-budget exhaustion as resumable failure

Add an explicit contract for the exact `Subagent spawn limit reached` failure at both Agent seams:

- If the main command cannot spawn the referee, do not perform referee work in the main context.
  Leave the minted or resumed run intact and report that the user must start a fresh conversation
  (normally `/clear`) and invoke `panel-review:resume`.
- If the referee cannot spawn a barrier or Claude seat, do not perform that agent's work itself and
  do not keep retrying Agent calls against the exhausted budget. Preserve the current checkpoint,
  return the fixed resumable review-failure status, and let the main command report the same
  `/clear` then `panel-review:resume` recovery.
- Do not convert budget exhaustion into an ordinary down-seat pass. It affects the orchestration
  mechanism globally and repeated retry/drop-seat behavior would spend turns without restoring the
  required panel.
- Do not impose a fixed maximum round count as the primary fix. The unknown shared session usage,
  retries, continuations, and exceptional pagination make such a cap neither necessary nor
  sufficient.

Keep the exact error handling local to the Agent invocation instructions. Deterministic scripts do
not own or receive Claude Code's Agent-tool failure.

### 3. Correct and localize timeout behavior

Update `agents/panel-review-cli-barrier.md` to state:

- Bash has a two-minute default and configurable ten-minute maximum tool timeout;
- a timed-out call is auto-backgrounded on current Claude Code rather than killed;
- panel-review explicitly backgrounds `await_seats` so it owns the launch and completion-sentinel
  lifecycle instead of relying on implicit timeout conversion; and
- each `timeout 100` sentinel wait deliberately completes before auto-backgrounding can occur.

Update `README.md` to state only the panel invariant and point to the barrier agent for the detailed
mechanism. Avoid repeating the full Claude Code timeout description in the README, protocol, script
rules, and tests; duplicated runtime prose makes future documentation changes require shotgun edits.

### 4. Clear strict manifest validation

Add the existing marketplace author name to `.claude-plugin/plugin.json`. Keep the plugin manifest
version and its marketplace plugin-entry version equal, and bump both when this executable change is
released.

## Verification results

- TDD regressions cover explicit outer foreground dispatch, current paired-Agent wording,
  resumable Agent-budget failure at both boundaries, Bash auto-background semantics, and matching
  manifest author metadata.
- `scripts/check_contracts --root .` passes and rejects representative runtime-contract drift.
- Focused contract-consistency, manifest, and protocol-phase tests pass (12 tests).
- `claude plugin validate . --strict` passes with the author metadata and synchronized `1.0.15`
  versions.
- `./tests/run_tests.sh` passes.
- JSON validation and `git diff --check` pass.
- Per user decision, deliberate Agent-budget exhaustion and the repeated foreground-concurrency smoke
  were not run and do not gate this issue.
- The required Standards/Spec reviews found a duplicated-test smell, a nested-failure propagation
  gap, and an overbroad artifact-delivery bypass; all were corrected before final verification.

## Non-goals

- Do not change the CLI barrier to rely on Bash timeout auto-backgrounding.
- Do not make the referee or main conversation substitute for a missing review role.
- Do not assume the session's remaining Agent budget can be queried.
- Do not change the fixed Agent status stubs, consensus rules, blindness, or artifact-only verdict
  delivery.
- Do not add plugin dependencies, monitors, MCP servers, or persistent plugin-data state.
