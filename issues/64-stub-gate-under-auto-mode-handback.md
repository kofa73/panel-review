# Make the status-stub gate work when subagents hand back in auto mode

Priority: 64

Status: Completed

Source: Claude Code changelog and docs review (2.1.262 → 2.1.303), 2026-10-19. Verified with Claude
Code 2.1.304 on 2026-10-20.

Triage: ready-for-agent

## Problem

Since Claude Code 2.1.284, a session that has no configured permission mode starts in **auto mode**.
This covers interactive terminal and VS Code sessions on every plan and provider, except HIPAA
organizations. Before that, the default was Manual. README does not say which permission mode the
panel needs, so any user who never set one now runs the panel in auto mode. The panel has never
been run in auto mode.

In auto mode, a subagent's report no longer arrives as its last message (2.1.271+). Claude Code gives
every locally run, non-fork subagent a `SubagentHandback` tool, and the report is that call's
`message` input. `docs/hooks.md` (SubagentStop) states that `last_assistant_message` "then holds the
subagent's closing text, if any, which is not the delivered report".

`hooks/enforce_agent_status_stub:70` validates `last_assistant_message`. In auto mode it therefore
checks the wrong text, for both gated agents:

- **Claude seat.** The gate is strict, so a closing text that is not the exact stub gets the stop
  blocked, and the seat is asked to correct it. Whether the seat then repeats the stub as text and
  passes, loops until the eight-block cap, or has already delivered a hand-back the gate never saw, is
  unmeasured.
- **Referee.** The first mismatch is blocked. The `stop_hook_active` continuation is then let through
  (`hooks/enforce_agent_status_stub:64-68`), so the gate stops validating the referee's run ID at all.

Auto mode also adds a classifier between the panel and its tools, also unmeasured for this plugin:

- The classifier reviews each hand-back call (2.1.271).
- Read-only shell commands wait for server-side review and are blocked when it flags them (2.1.281).
- Auto mode asks once before the first read outside the working directories (2.1.257; 2.1.284 added
  "Yes, but ask again next time"). Answering "block" writes
  `permissions.blockReadsOutsideWorkingDirectories: true` permanently. `issues/62` covers detecting
  that setting, but with auto mode now the default, far more users will see this prompt during a run.

One fact helps: every hook input carries `permission_mode` (`"auto"` in auto mode), and `PreToolUse`
and `PostToolUse` inputs inside a subagent carry `agent_type`. So a hook can tell when a hand-back is
coming and can see its `tool_input.message`.

## Expected behavior

1. **Measure one full review in auto mode** on the installed Claude Code. Record: whether both gated
   agents use `SubagentHandback`, what `last_assistant_message` the gate receives, how many blocks
   happen and whether the run completes, and which classifier prompts or blocks appear (the
   `/tmp/<ID>/` reads especially).
2. **Choose one of these and state it in README "Requirements":**
   - **Support auto mode (recommended, since it is now the default).** Validate the stub where it is
     delivered: add a `PreToolUse` hook matched on `SubagentHandback` that applies the same exact-stub
     rules (including the referee's expected run ID) to `tool_input.message` for the two gated agent
     types, and denies a non-exact hand-back with the same correction text. The `SubagentStop` gate
     then accepts an empty or free closing text only when `permission_mode` is `"auto"`.
   - **Refuse auto mode.** Name the required mode in README, and have the gate fail loudly with
     instructions when `permission_mode` is `"auto"`. Nothing outside a hook can observe the
     permission mode, so `preflight` cannot do this check.
3. Whichever is chosen, the gate stays bounded runtime enforcement, documented as such (`issues/13`).
   It is not a security boundary.

## Verification

- The auto-mode measurement in item 1 is recorded here with the Claude Code version.
- Hermetic tests feed the gate a `SubagentStop` payload with `permission_mode: "auto"` and a closing
  text, plus (if the first option is chosen) a `PreToolUse` `SubagentHandback` payload with an exact
  stub and with a non-exact one. Each must give the intended allow or block.
- One real review completes in auto mode with all three seats engaged.
- `scripts/check_contracts --root .` and `./tests/run_tests.sh` pass.

## Resolution

Completed 2026-10-20 in plugin version 1.0.26. A `PreToolUse` hook now validates the
`tool_input.message` on `SubagentHandback` for the Claude seat and referee. For the referee, the hook
uses the original task transcript to check the expected run ID. `SubagentStop` accepts empty or
free-form closing text only when `permission_mode` is `auto`; Manual and `bypassPermissions` keep the
exact final-message check. The hook denies at most one invalid hand-back per subagent. If retry state
is unavailable or a later hand-back is still invalid, its message is replaced with
`CLAUDE_SEAT_RAW_FAILED` or `PANEL_REVIEW_FAILED id=<ID>` and allowed, so review text cannot escape
through the terminal path and repeated denials cannot keep the subagent running. If neither the
referee task transcript nor an exact status stub supplies an ID, the hook uses
`PANEL_REVIEW_FAILED id=unavailable`; the caller still validates the saved artifact before delivery.
If no accepted auto-mode hand-back is recorded, `SubagentStop` checks the final text itself.
These paths provide bounded runtime enforcement, not a security boundary.

The installed Claude Code was 2.1.304. A pre-change auto-mode smoke review used all three seats and
paused at the expected low-severity gate. The nested transcripts showed a Claude-seat hand-back with
no closing text and a referee hand-back followed by 102 characters of closing text. The old hook did
not log its input, so its exact input and block count were not recoverable. This matched the documented
`last_assistant_message` behavior. Session records showed 29 classifier accept decisions and one mode
accept, no permission prompts or denials, and 14 tool calls that referenced the run's `/tmp` directory,
including one direct `Read` call.

The post-change smoke review completed with a final report and all three Round-0 seat statuses at
exit 0. A temporary content-free trace recorded exact 23-character Claude-seat and 53-character
referee hand-backs allowed by `PreToolUse`; both `SubagentStop` events received empty closing text and
were allowed, with zero hook blocks. Session records again showed 29 classifier accept decisions and
one mode accept, no permission prompts or denials, and 12 tool calls referencing the run's `/tmp`
directory, including one direct `Read` call. The smoke's temporary seat models verify runtime flow,
not shipped-model quality.

Hermetic tests cover exact and malformed hand-backs, referee run-ID validation, one correction then a
sanitized failure hand-back, closing text after a denied hand-back, auto-mode closing text, unchanged
non-auto checks, hook registration, and installer packaging. The bounded-fallback change was not
smoke-tested in a live Claude Code session. The
`scripts/check_contracts --root .` check passes. `./tests/run_tests.sh` reports
`PASS: 366  FAIL: 0`.

## Non-goals

- Do not write `permissions.defaultMode` or any other key into user or project settings. The plugin
  does not own them (same rule as `issues/62`).
- Do not weaken the Manual and `bypassPermissions` paths, which keep using `last_assistant_message`.
- Do not add guards that assume a seat tampers with the gate (AGENTS.md trust model).
