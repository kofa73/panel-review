# Agent runtimes

This reference records the host and CLI behavior that Panel Review depends on. The
[external CLI baselines](agents/external-cli-baselines.md) mark the changelog commits that have been
reviewed. A version command identifies an installed binary; it does not establish compatibility.

## Installed versions and review baseline

Small version probes on 2026-10-20 reported Claude Code **2.1.304**, codex-cli **0.163.0**, and agy
**1.4.3**. The latest full changelog review was recorded on 2026-10-19 against Claude Code 2.1.303,
codex-cli 0.163.0, and agy 1.4.2. Claude Code 2.1.304 and agy 1.4.3 are therefore one release
beyond their reviewed baselines. The probes on this page do not advance those baselines.

## Claude Code requirements

Start every review session with `CLAUDE_CODE_FORK_SUBAGENT=0`. `preflight` requires this literal
value. Since Claude Code 2.1.232, interactive sessions default to fork mode, which backgrounds
subagents and removes the Agent tool's `run_in_background` parameter. Fork mode also became the
default in `claude -p` and the Agent SDK in 2.1.302. With the setting at `0`, the panel dispatches
the CLI barrier and Claude seat as concurrent foreground Agents and waits for both returns. The
upgrade probe is an isolated Agent-call check; after a change to dispatch behavior, verify
that both calls block and overlap before relying on the protocol again. Measurements are in
[`issue 25`](../issues/archive/25-fork-mode-backgrounds-seat-agents.md) and
[`issue 15`](../issues/archive/15-referee-seat-polling-in-loop.md).

Fork mode changes scheduling, not the type of agents Panel Review spawns. A typed Claude seat stays
a non-fork subagent with a fresh context, its declared tools, and its own model pin. Fork mode makes
the `fork` type available and backgrounds every subagent, including typed agents. Do not use
`CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` as a substitute; it also disables the background Bash call
used by the CLI barrier. Denying `Agent(fork)` prevents fork requests but does not restore foreground
dispatch. These distinctions were checked on 2.1.233 (2026-08-16).

Round-0 recovery is a Panel Review contract: a failed Claude delivery gets a fresh Claude seat,
while CLI seats retry through `run_seat` and the CLI barrier. A valid empty `findings` block is a
complete pass and is not retried. A later debate pass cannot replace a missing blind Round-0 review
because it sees the blind cards instead of the original scope. `round` records the frozen panel and
retry history. The referee first salvages a status-4 or status-5 CLI response only if it contains a
completed review; it retries an actual empty or error response. See
[issue 19](../issues/archive/19-retry-round0-down-seat.md) and the state schema in
[architecture.md](architecture.md).

The referee needs to spawn two nested Agent layers. Claude Code 2.1.217 and 2.1.218 defaulted
`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` to 1. Claude Code 2.1.219 raised the default to 3. Set the
variable to at least 2 on any version or in any organization that overrides the default. Since
2.1.217, the concurrent-subagent limit is 20 by default and is controlled by
`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`; Claude Code 2.1.224 removed the former per-session spawn cap.
Claude docs reviewed on 2.1.261 (2026-09-05) exempted ultracode sessions from the concurrent limit.
The current failure is `Concurrent subagent limit reached`, not `Subagent spawn limit reached`.
Panel Review uses at most three subagents at once, so it reaches this limit only when other agents
already occupy the session's slots.
These limits and their history are recorded in
[`issues 22 and 26`](../issues/archive/22-claude-code-2-1-219-runtime.md) and
[`issue 26`](../issues/archive/26-stale-subagent-spawn-budget-guidance.md).

Other host behavior that affects the panel:

- Since 2.1.198, Claude seat subagents inherit the session's extended-thinking setting. Agent
  `effort:` metadata pins effort but cannot turn thinking on or off for one subagent.
- Claude seat and referee definitions pin `model: opus`. Since 2.1.251,
  `CLAUDE_CODE_SUBAGENT_MODEL` is a default and the definition pin takes precedence. With no forced
  override, an unset or `inherit` value follows the main session model when no agent pin applies.
  Setting `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1` (added in 2.1.257) restores the environment override.
  An organization that restricts the pinned model can also cause Claude Code to use an allowed or
  parent model.
- `disable-model-invocation: true` prevents a skill from preloading into a subagent. The referee's
  preloaded protocol skill uses `user-invocable: false`.
- `permissions.blockReadsOutsideWorkingDirectories` (2.1.257+) can block Claude's reads of
  `/tmp/<ID>/` even in bypass mode. `preflight` requires an inspectable `/tmp` grant or the
  session-only launch marker described in the README.
- The status-stub hook is bounded runtime enforcement. Claude Code's eight-consecutive-block limit
  was confirmed in its 2.1.222 documentation review; it is not an isolation guarantee.
- Since 2.1.284, sessions without an explicit permission mode may use `auto` outside HIPAA
  organizations. The plugin checks `SubagentHandback` in auto mode and checks final messages in
  other modes. This was exercised in the issue 64 smoke review, not just inferred from docs.

### Versioned Claude Code observations

- On 2.1.222 (2026-08-05), the plugin matcher, plugin-root substitution, agent frontmatter fields,
  and eight-block stop-hook limit were checked against the host documentation. Issue 13's smoke
  captured both Agent boundaries: the hook removed prose before the fixed status stub, while the
  main command still validated the verdict artifact. The smoke's host version was not recorded.
  The eight-block cap bounds correction attempts; it does not prove isolation from a model that
  ignores every correction.
- On 2.1.223, a restricted subagent model began to fall back to the parent model with a warning.
  On 2.1.233, background subagents retained MCP tools but had a filtered built-in tool set; the
  panel's declared seat tools survived. The same release removed `TaskCreate`, `TaskGet`,
  `TaskUpdate`, `TaskList`, and `TodoWrite` from Opus 4.8, Sonnet 5, Fable 5, Mythos 5, and newer
  models. It also stopped re-expanding skill argument values as template markers.
- In 2.1.242, `subagentPromptCacheTtl` and `CLAUDE_CODE_SUBAGENT_PROMPT_CACHE_TTL` could set a
  5-minute or 1-hour prompt-cache TTL; a one-hour TTL changes cache-write costs. In 2.1.246, a
  `maxTurns` return became marked partial. Panel agents do not set `maxTurns`. Claude Code 2.1.261 added
  `--append-subagent-system-prompt-file`; the panel does not need it because prompts are passed as
  task text.
- Between 2.1.240 and 2.1.261, the host began refusing plugin component paths that are symlinks and
  resolving `${CLAUDE_PLUGIN_ROOT}` in hook errors. `bashOutputMaxChars` supports up to 128 KiB and
  supersedes `BASH_MAX_OUTPUT_LENGTH`.
- In 2.1.275, a `SubagentStop` hook with a specific matcher stopped firing for agents with an empty
  type. In 2.1.277, `TaskOutput`, `taskOutputMaxChars`, and `TASK_MAX_OUTPUT_LENGTH` were removed or
  made ineffective, and subagent results gained a result header. The panel barrier waits on a
  sentinel and does not use `TaskOutput`.
- In 2.1.268, task/todo tools were available on Claude 3.x, Opus 4.0–4.7, Sonnet 4.0–4.6, and
  Haiku 4.5 unless `CLAUDE_CODE_ENABLE_TODO_TOOLS=1`. In 2.1.295, a subagent could preload at most
  32 skills. In 2.1.299, an Agent `tools:` list selected only tools from the named MCP server. The
  referee preloads one skill and the Claude seat names its tilth tools explicitly.
- In 2.1.280, the `opus` alias moved to Opus 5.5. Agent `effort:` frontmatter remained the active
  effort setting for the panel. Context-cost measurements made in July 2026 describe the earlier
  model behind `opus`, not Opus 5.5.
- In interactive 2.1.233 trials with fork mode on, a backgrounded parent resumed on each child
  completion. In four dispatch trials, no parent collected early, three yielded on a partial wake,
  and one improvised a shell wait; two of four searched for a blocking primitive. These trials used
  short prompts and 25-second and 110-second children. They show behavioral variance, not an
  observed incorrect collection. The implemented foreground design avoids that partial-wake path.
- Two earlier 2.1.233 parent trials found the same wake pattern: the parent resumed after a child
  completion, and a parent with two staggered children woke twice. Each variant was run once.
- In 2.1.233, an Agent call with `run_in_background: false` blocked for a child that ran about 20
  seconds, taking 26.5 seconds end to end. A second probe with
  `CLAUDE_CODE_FORK_SUBAGENT=0` in `settings.json` propagated the value to Bash and also blocked,
  but settings-wide scope is not documented as a review-only launch option. A `PANEL_REVIEW_WAITING`
  return completed the referee Agent instead of resuming it when child notifications arrived.
- In the issue 15 review (Claude Code version not recorded), the old hook/polling combination
  produced 279 referee Bash polls and 432 deduplicated polling or wait-narration calls across three
  passes, consuming 52,092,919 cache-read and 81,518 cache-creation input tokens. The loop accounted
  for about 86% of the transcript's cache-read tokens. The foreground-pair implementation now
  returns only after the CLI barrier and Claude seat both finish, with no referee polling in the
  interval. Its hook also allows an invalid referee retry to stop when `stop_hook_active` is true,
  preventing the correction loop from blocking the wait path.
- The 2.1.303 review (2026-10-19) found no change to nesting or the concurrent-subagent limit. The
  installed 2.1.304 binary has only had a version probe (2026-10-20); its changelog delta and
  foreground behavior remain to be reviewed.

## Codex CLI requirements

Call the Codex seat only through `scripts/run_codex`. It uses human output mode because `codex exec`
prints its resolved model, reasoning effort, and session ID to stderr in that mode. `-o` writes the
last assistant message in both human and JSON output modes. With `--json`, the config summary is
replaced by a `thread.started` event that contains only a thread ID.

The `--profile panel-review` pin is not authoritative. The reviewed repository's `.codex/config.toml`
and higher-scope cwd/tree configuration can override it. On 2026-09-05, codex-cli 0.153.4 bound a
repo-local `gpt-5.6-luna`/`max` setting over the profile's `gpt-5.6-sol`/`high` setting in a live
probe. `preflight` reports that condition, `start` asks whether to proceed, and `run_codex` records
the model Codex reports. Panel Review does not overwrite the reviewed repository's config. See
[`issue 47`](../issues/archive/47-codex-model-pin-is-not-authoritative.md).

The installed codex-cli reported 0.163.0 on 2026-10-20, matching the 2026-10-19 changelog baseline.
Only the version was probed during this documentation update; no live `codex exec` was run.

## agy CLI requirements and measurements

Call the Gemini seat only through `scripts/run_agy`. Pin an exact model display label, including its
effort, and keep `--effort` out of the invocation. Do not copy a slug from `agy models`. On agy
1.1.10 (measured 2026-08-05), the listed slug `gemini-3.1-pro-high` bound Gemini 3.6 Flash (High),
while an unknown label silently selected the user's `settings.json` model. A bare `--effort` also
resolved against the user's default model rather than the selected label. Piped `agy models` output
contained only slugs; its TTY output also showed model labels. On 1.1.13 (measured 2026-08-15), spot
checks showed slugs binding as expected, an unknown label became a hard error, and piped `agy models`
printed slug and label columns. `agy models --output-format json` was unsupported on 1.1.13. The label
remains the contract because slug behavior changed across releases. See
[`issue 20`](../issues/archive/20-agy-model-pin-contract.md).

The configured labels became unavailable. On agy 1.4.2 (measured 2026-10-20), neither
`Gemini 3.1 Pro (High)` nor `Gemini 3.7 Flash (High)` appeared in `agy models`; an unlisted label
failed at startup. A direct call confirmed `Gemini 4 Argon (High)` bound, but the owner has not
selected replacement pins. A 2026-10-20 `agy models` probe on 1.4.3 again listed Gemini 4 Argon
(Low, Medium, and High) and Gemini 3.8 Flash (Low, Medium, and High), not the configured labels.
The next action belongs to [issue 63](../issues/63-gemini-seat-pins-gone-from-agy-1-4.md). The
listing alone does not prove that a replacement label binds.

`run_agy` handles these observed print-timeout shapes:

- On versions through 1.1.18, the CLI could exit 0 with `Error: timed out waiting for response` on
  stdout.
- On 1.1.20, the CLI exited 1 with `Error: timeout waiting for response` on stderr.
- Since 1.1.28, a mid-turn timeout can exit 0 with partial output and a warning on stderr. On 1.4.3,
  one probe recorded `[agy] print timeout after 6s with turn in progress; returning partial output`.

The wrapper captures stderr, detects all three observed forms, and suppresses partial output after
both models fail. See [`issue 59`](../issues/archive/59-agy-print-timeout-shape-changed.md).

Other print-mode changes matter when judging a seat result. Starting in 1.1.20, tool execution
errors and permission denials no longer necessarily produce a non-zero exit. agy 1.1.27 added a
`denied_actions` notice, but its stream and all-denied exit behavior have not been measured on 1.4.3.
agy 1.2.6 changed agent and model API failures to exit 3 with an `AGY_ERROR` line on stderr. In
1.2.10, an error after partial output also began exiting 3. The default print timeout became
unlimited in 1.2.6; `run_agy` supplies its own 15-minute limit. Since 1.3.6, a connection silent for
five minutes is cancelled and retried. These observations come from the 2026-10-19 changelog review
and remain version-specific; issue 61's denied-action measurement is open.

agy runs tools in its own managed sandbox at `~/.gemini/antigravity-cli/scratch` and infers the
repository root. The 1.1.12 changelog claimed improved detection for nested Git repositories,
worktrees, and submodules. On 1.4.3 (2026-10-20), a short unanchored print-mode probe from
`/workspace/panel-review` reported that path for both `pwd` and `git rev-parse --show-toplevel`.

An earlier large-prompt probe returned `/home/developer`, but its version and prompt size were not
retained. A Round-0 prompt larger than about 99 KB once produced prose without a fenced block, while
prompts at or below about 87 KB produced valid blocks. The 1.1.13 changelog's trajectory-truncation
fix is a possible explanation, not a measurement. Neither the realistic-size root comparison nor the
large-prompt replay has been run on 1.4.3. Keep the absolute path and lean prompt until those tests
run. See [issue 27](../issues/27-recheck-agy-workarounds-on-1-1-13.md).

agy's `/tmp` write behavior was confirmed in a wrapper-shaped probe on 1.1.18 (2026-08-22), then
confirmed in three real reviews on 2026-08-16, 2026-08-19, and 2026-08-22. The last review used
1.1.18. All three seats wrote scratch under `/tmp/<ID>/work/`; Codex's scratch included a 614 MiB
build in one review and an 831 MiB build in another. This removes accidental search hits from the reviewed repository but
does not prevent a seat from reading shared run state. Recheck
external-sandbox writes after a material agy permission change. See
[`issue 24`](../issues/archive/24-seat-scratch-outside-workdir.md).

On agy 1.4.3 (2026-10-20), a short stdin probe confirmed that a leading slash command expands in
print mode. The Gemini prompt keeps slash-command expansion enabled and puts the prose seat contract
first. Denied tool-action exit and stream behavior remain unmeasured, as does the realistic-size
repo-root test. See [issue 61](../issues/61-agy-print-mode-semantics-1-1-27.md).

## Upgrade probes

Run these probes after a host or CLI upgrade that can affect the corresponding boundary. Read the
new changelog range first and record versions and dates with the results.

| Runtime | Probe |
|---|---|
| Claude Code | Check `claude --version` and the changelog delta. In a new session with `CLAUDE_CODE_FORK_SUBAGENT=0`, dispatch two foreground Agents together and verify that both run concurrently and return before the caller continues. Check the effective nested-spawn depth and run the status-stub hook cases in the current permission mode. |
| Codex | Check `codex --version`. Use a tiny `codex exec` to confirm that human output still reports its bound model and reasoning effort on stderr while `-o` captures the final assistant message. Compare `--json` only if the wrapper's output mode changes. |
| agy | Check `agy --version` and `agy models`. Run `tests/live/agy_model_binding.sh` after the owner chooses listed pins. Recheck timeout stderr and exit behavior, slash-command expansion, `/tmp` scratch writes, and the realistic-size root and historical large-prompt cases when those questions are in scope. |
