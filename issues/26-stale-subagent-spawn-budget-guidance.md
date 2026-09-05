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

## Comments

Re-raised independently by all three seats at Round 0 of panel review
`panel-20260816-080558-5ab680af` (2026-08-16). The panel enumerated the five instruction sites that
must change together: `README.md:264`, `skills/start/SKILL.md:165`, `skills/resume/SKILL.md:134`,
`skills/continue/SKILL.md:96`, `skills/panel-review-for-agent/SKILL.md:126` — plus the three
`scripts/check_contracts` assertions (lines 181, 225, 284) that pin the wording.

### 2026-09-05 — re-confirmed on Claude Code 2.1.261

`docs/sub-agents.md` "Concurrent subagent limit" still reads: "when 20 subagents are running in a
session, spawning another with the Agent tool fails with `Concurrent subagent limit reached`, and the
error tells Claude not to retry", configurable with `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`, with
ultracode sessions exempt. The `Subagent spawn limit reached` wording README and `check_contracts`
pin has not returned in the 2.1.240–2.1.261 range. This issue's fix is still needed and its target
wording is still correct.
