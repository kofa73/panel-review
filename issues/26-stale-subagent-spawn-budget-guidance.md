# Correct the stale subagent-budget guidance and its contract check

Priority: 26

Status: Pending

Source: Claude Code documentation review (2.1.222 → 2.1.233), 2026-08-15

Triage: ready-for-agent

## Problem

`README.md` tells the operator how to recover from an orchestration failure by naming an error
Claude Code no longer produces:

```text
README.md:223  **Agent-budget exhaustion fails closed.** If Claude Code reports `Subagent spawn
               limit reached`, panel-review keeps the current checkpoint and stops …
```

Claude Code **2.1.224 removed** the per-session spawn cap: `CLAUDE_CODE_MAX_SUBAGENTS_PER_SESSION`
is documented as "Removed in v2.1.224 and now a no-op", and the `Subagent spawn limit reached`
failure it produced is gone with it. What still exists are two different limits:

- **Concurrent**: `Concurrent subagent limit reached`, default **20** running subagents,
  `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`, requires 2.1.217+. Panel-review runs at most three
  subagents at once, so it hits this only inside a session that is already running other agents.
- **Depth**: `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` — the floor issue 22 documents.

`scripts/check_contracts` pins the stale wording in place: its `agent-spawn-budget` invariant
requires README to contain the literal `subagent spawn limit reached` (plus `not a down-seat pass`,
`/clear`, `panel-review:resume`). So the check currently guarantees the presence of guidance for an
error that cannot occur, and would reject the corrected text.

The fail-closed *behavior* is right and stays. Only the trigger it names is wrong.

## Expected behavior

1. README's recovery paragraph names the failures that can actually occur — the concurrent-subagent
   limit, and an Agent call that fails for any orchestration reason — instead of the removed
   per-session cap. It keeps the same instruction: preserve the checkpoint, stop, treat it as an
   orchestration failure and not a down-seat pass, `/clear`, `panel-review:resume`.
2. `scripts/check_contracts`'s `agent-spawn-budget` required strings are updated **in the same
   change**, so the invariant keeps protecting the recovery guidance rather than the obsolete
   sentence.
3. No behavioral change to the referee or the skills: nothing in the run loop reads these limits.

## Verification

- `scripts/check_contracts --root .` passes and fails if the recovery guidance is deleted.
- `./tests/run_tests.sh` passes.
- `grep -ri "spawn limit" README.md scripts/` returns only the corrected wording.

## Non-goals

- Do not add a runtime check for either limit; both are session-level conditions panel-review
  cannot read.
- Do not remove the fail-closed guidance; only re-aim it.
- Do not fold in the depth-limit documentation — that is issue 22.
