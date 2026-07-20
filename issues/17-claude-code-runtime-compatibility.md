# Align Agent and Bash contracts with current Claude Code

Priority: 17

Status: Pending

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

## Current state (2026-07-20)

Issue 17 has been investigated against the current Claude Code documentation, but no issue-17 tests
or implementation changes have been written yet. The live tree still has every gap described by
this issue:

- the outer referee dispatches in `start`, `resume`, and `continue` omit
  `run_in_background: false`, including `start`'s low-severity-gate re-dispatch;
- `start` and `resume` still describe the referee's internal calls as background helper Agents;
- neither the main-command nor referee Agent seam handles the exact
  `Subagent spawn limit reached` failure;
- the CLI-barrier agent and README still say a timed-out foreground Bash call is killed or silently
  truncated; and
- `.claude-plugin/plugin.json` still lacks the marketplace's existing author name.

The local Claude Code documentation currently confirms the issue's runtime assumptions:

- `docs/sub-agents.md` says foreground subagents block their caller, subagents otherwise run in the
  background by default, the session limit defaults to 200 spawns, and exhaustion fails with
  `Subagent spawn limit reached`;
- `docs/tools-reference.md` says a Bash call that reaches its timeout is moved to the background
  rather than stopped; and
- `docs/env-vars.md` retains the 120-second default and 600-second maximum Bash timeout values.

Issue 15's replacement orchestration is present as uncommitted work: each pass emits the foreground
CLI-barrier and Claude-seat Agent calls together, allowing them to overlap while the referee remains
blocked. Focused tests, the contract checker, the full local suite, an isolated Claude Code
concurrency smoke, and a full post-change real review passed. Issue 15 is now completed in the local
tracker but remains uncommitted.

The post-change review `panel-20260720-120133-3599d270` reproduced the old run's exact diff and
instructions. Its Round 0 and two debate rounds each ran the paired foreground Agents concurrently;
the referee issued no Bash or other tool call between dispatch and their combined return. The review
finished normally with all seats engaged and persisted a validated report. The same run confirmed
this issue's outer-referee gap: `panel-review:start` omitted `run_in_background: false`, so Claude
Code launched the outer referee asynchronously and delivered its result through a later task
notification.

Reproducing that old review exactly requires the reviewed repository at
`a4e9202fd43bf3d32ff21b45d6f404bf080cbd13`, with base `cfe57f3bbf`, issue-round limit 2,
global-round limit 4, and the saved instructions from the old manifest. That range reproduces the
original diff hash `f604aae91c86c98885b221b8af1cf90367aa259773480b77323d95aa48b646e7`.
The current `/workspace/dt-pr` HEAD is `fd604e8100d4f13c0dea3f3b3db84dde5937edfb`; using the same
base there produces a different diff and is not an exact rerun.

Both manifest versions have now been changed from `1.0.13` to `1.0.14` in the uncommitted
worktree. The plugin manifest still lacks the marketplace's author field.

## Decisions needed before implementation

1. **Choose the issue-15 commit boundary.** The recommended sequence is to commit the completed
   issue-15 work separately before starting issue 17. Its uncommitted changes overlap README, the
   CLI-barrier agent, protocol contracts, and tests needed by issue 17, so issue 17 cannot be cleanly
   committed while they remain uncommitted. Alternatives are to authorize one combined issue-15/17
   commit, or override the requested `implement` workflow's commit requirement and leave both
   uncommitted.
2. **Confirm the TDD seams.** The recommended automated seams are the executable-instruction
   contract exposed by `scripts/check_contracts --root .` and focused contract tests, plus strict
   manifest validation through `claude plugin validate . --strict`. Claude Code's actual Agent
   scheduler is an external runtime boundary and must be covered by isolated manual smoke tests,
   not simulated by repository unit tests.
3. **Confirm the release/version boundary.** The recommended choice is to treat the current
   uncommitted `1.0.14` bump as the single release containing both issues 15 and 17. If `1.0.14` is
   instead intended to release issue 15 independently, issue 17 needs a later `1.0.15` bump.
4. **Decide whether manual runtime checks gate the issue-17 commit.** Issue 17 requires separate
   low-`CLAUDE_CODE_MAX_SUBAGENTS_PER_SESSION` checks at the outer-referee and internal-seat Agent
   seams, followed by `/clear` and `panel-review:resume` recovery. The recommended choice is to treat
   those checks as completion and commit gates because the failure originates in Claude Code and
   cannot be exercised by deterministic plugin scripts.

The failure policy itself does not need another design decision: the run remains resumable, neither
the main command nor referee substitutes for the missing role, Agent dispatch is not retried against
an exhausted session budget, and timeout handling remains explicitly owned by the CLI barrier.

## Verified evidence

The reviewed Claude Code documentation range is:

```text
efc54c33352080d52529b2756c1d2cfd62021b02..b44396c9f5e8701c7715fca9854dd5a99a7529bf
```

The installed runtime used for validation was Claude Code 2.1.215.

### Outer referee execution remains implicit

Claude Code documents foreground subagents as blocking the caller until completion. Subagents run
in the background by default unless Claude decides it needs the result, and a background result is
delivered through a later completion notification.

The live worktree already pins the referee's internal `panel-review-cli-barrier` and Claude-seat
Agent calls with `run_in_background: false`. However, the `start`, `resume`, and `continue` command
skills omit that field when they spawn the outer referee. Those same files still say the referee
waits through "background helper Agents", contradicting the migrated protocol: the internal Agent
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
than killing it. The result identifies the background task and output path. Panel-review still says
that a long foreground seat/barrier command is killed, truncated, or produces an empty raw file in:

- `README.md`'s `run_seat` ownership row; and
- `agents/panel-review-cli-barrier.md`'s rationale, wait guidance, and hard rules.

The implementation remains sound: deliberately backgrounding `await_seats`, recording its terminal
exit in an atomic sentinel, and using sub-120-second foreground waits avoids depending on implicit
auto-background behavior. Only the runtime explanation and associated failure wording are stale.

### Manifest validation warning

`claude plugin validate .` passes. `claude plugin validate --strict .` fails only because
`.claude-plugin/plugin.json` omits optional author metadata, although the marketplace entry already
contains `"author": {"name": "Kofa"}`.

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

## Verification

- Add contract tests requiring `run_in_background: false` on every referee dispatch in `start`,
  `resume`, and `continue`, including the low-severity gate re-dispatch.
- Add wording checks rejecting the stale "background helper Agents", "killed", "silently
  truncated", and equivalent false timeout descriptions at their former ownership sites.
- Add contract coverage for Agent-budget exhaustion at the main-command and referee seams: neither
  context may take over the missing role, retry indefinitely, or clean the resumable run.
- In an isolated temporary plugin install, set a low positive
  `CLAUDE_CODE_MAX_SUBAGENTS_PER_SESSION` and smoke-test both exhaustion locations. Verify the run is
  retained and succeeds through `panel-review:resume` in a fresh conversation.
- Re-run the foreground two-Agent smoke test from issue 15; confirm the barrier and Claude seat still
  overlap and the referee does not poll.
- Run `claude plugin validate . --strict` and require a clean result.
- Run `scripts/check_contracts --root .`, the focused protocol/hook tests,
  `./tests/run_tests.sh`, and `git diff --check`.

## Non-goals

- Do not change the CLI barrier to rely on Bash timeout auto-backgrounding.
- Do not make the referee or main conversation substitute for a missing review role.
- Do not assume the session's remaining Agent budget can be queried.
- Do not change the fixed Agent status stubs, consensus rules, blindness, or artifact-only verdict
  delivery.
- Do not add plugin dependencies, monitors, MCP servers, or persistent plugin-data state.
