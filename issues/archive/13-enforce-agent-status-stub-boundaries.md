# Enforce fixed Agent status-stub boundaries

Priority: 13

Status: Completed

Source: review `panel-20260716-202101-013e59c4`

## Problem

The Claude-seat and referee contracts require their final Agent responses to contain only fixed
status stubs. A live version-1.0.11 run followed the file-based persistence paths successfully but
did not obey either return boundary consistently.

This is an executable-contract defect, not a verdict-delivery failure. The main command still
validated the durable artifact and showed the user only its filename. However, the unexpected Agent
prose entered the caller's model context before that validation, defeating the stated context and
artifact-only internal boundary.

## Verified evidence

Claude seat task notifications in session
`~/.claude/projects/-workspace-dt-pr/272f0d30-3d07-46e4-8bb5-e46208d8d15f.jsonl` show:

- Round 0 returned exactly `CLAUDE_SEAT_RAW_WRITTEN`.
- Round 1 returned `The helper validated and wrote the raw file successfully.` before
  `CLAUDE_SEAT_RAW_WRITTEN`.
- Round 2 returned `The helper validated and atomically wrote the response to the expected
  destination.` before `CLAUDE_SEAT_RAW_WRITTEN`.

No raw finding, evidence, or stance text leaked through those Claude-seat results, and all three raw
files were validated and installed correctly. The defect is the failure of the exact-stub contract.

The referee's final task notification was more significant. Before
`PANEL_VERDICT_READY id=panel-20260716-202101-013e59c4`, it returned:

- artifact-persistence and retention commentary; and
- a summary naming the three issues, their outcomes, severities, and central claims.

That result appeared in the main conversation's task notification. The main command subsequently
ignored the prose, validated `/tmp/panel-20260716-202101-013e59c4.md` through
`read_verdict_artifact --delivery`, and correctly returned only the file pointer plus continuation
status to the user.

The existing instructions are already explicit:

- `prompts/claude_delivery.tmpl` says to return exactly one Claude-seat success/failure stub;
- `agents/panel-review-claude-seat.md` says to return only that fixed stub; and
- `skills/panel-review-for-agent/SKILL.md` and `agents/panel-review-referee.md` prohibit returning
  verdict prose and require one fixed referee status.

Static wording checks therefore cannot establish runtime compliance.

## Required outcome

Make the actual Agent-to-caller boundary match the documented interface:

- a Claude seat result contains exactly `CLAUDE_SEAT_RAW_WRITTEN` or
  `CLAUDE_SEAT_RAW_FAILED`;
- a referee result contains exactly one of `PANEL_VERDICT_READY`,
  `PANEL_VERDICT_WRITE_FAILED`, or `PANEL_REVIEW_FAILED`, with the expected run ID; and
- raw review content and verdict summaries do not enter the caller's model context through Agent
  results.

First determine what Claude Code can enforce at the subagent-return boundary. The current prompts
already state the rule repeatedly, so adding another equivalent sentence is not sufficient evidence
of a fix. If the platform cannot deterministically constrain or transform an Agent's final result,
record that limitation explicitly and redesign the boundary or narrow the guarantee rather than
claiming exact enforcement.

Preserve the existing background-Agent wake behavior and the main command's deterministic artifact
validation. Do not reintroduce verdict-body delivery or raw Claude-seat output as a fallback.

## Scope and non-goals

- Cover both Claude-seat-to-referee and referee-to-main returns.
- Keep `/tmp/<ID>.md` as the sole report delivery surface.
- Keep Claude raw output owned by `write_seat_raw`; status-stub handling must not become a second raw
  transport.
- Do not treat a model instruction as a security boundary or add a guard that a cooperating model
  can trivially bypass while describing it as deterministic enforcement.
- Do not change review findings, stance semantics, or the issue lifecycle.

## Verification

- Add deterministic tests for every enforceable parser, wrapper, hook, or result-normalization seam
  introduced by the fix.
- Run a focused Claude Code smoke test that captures the actual task notification for one Claude
  seat and one referee completion; source scans alone are insufficient.
- Prove that an unexpected prose-prefixed result cannot be mistaken for a valid exact stub.
- Prove that successful artifact validation still produces only the file-pointer delivery response.
- Run `scripts/check_contracts --root .`, the relevant delivery tests, the full suite, and
  `git diff --check`.

## Implementation

Version 1.0.12 adds a plugin `SubagentStop` hook for the two scoped Agent types. The hook accepts
only an exact Claude-seat status, or an exact referee status carrying the run ID recovered from the
original Agent task in `agent_transcript_path`. Any prefix, suffix, wrong ID, missing task ID, or
other response is blocked with a fixed correction that does not repeat the rejected content. Claude
Code continues the same subagent, so completed review and persistence work is not re-run.

This is bounded runtime conformance enforcement, not an absolute security boundary. Claude Code
forcibly stops a subagent after eight consecutive stop-hook blocks. The hook therefore prevents the
observed accidental prose-prefixed returns and keeps correcting a cooperative/confused model, but it
cannot guarantee isolation from a model that ignores every correction through the platform limit.
The durable artifact reader remains the deterministic report-delivery authority.

## Completed verification

- `tests.python.test_agent_status_hook` covers every allowed stub, prose-prefixed Claude-seat and
  referee results, wrong/missing referee IDs, an invalid retry while `stop_hook_active`, malformed
  hook input, unrelated agents, hook registration, and `install.sh` packaging.
- The existing artifact-delivery suite still proves a successful finished review emits only
  `Done. Final report: /tmp/<ID>.md`.
- A focused Claude Code smoke run, session
  `4d555fa2-24ad-4b5e-9418-b27e194d1717`, captured both real plugin Agent boundaries:
  - Claude seat `agent-ab64f445b877e39c5` first returned commentary plus
    `CLAUDE_SEAT_RAW_FAILED`; the hook blocked it and the completion notification contained exactly
    `CLAUDE_SEAT_RAW_FAILED`.
  - Referee `agent-a28a194ec11fee709` first returned failure-path commentary plus
    `PANEL_REVIEW_FAILED id=panel-hook-smoke-missing`; the hook recovered the expected ID, blocked
    the response, and the completion notification contained exactly that status line.
- `scripts/check_contracts --root .`, Claude plugin validation, and `git diff --check` pass.
- `./tests/run_tests.sh`: `PASS: 223`, `FAIL: 0`.
