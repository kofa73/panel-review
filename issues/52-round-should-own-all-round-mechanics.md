# Make `round` the complete round interface

Priority: 52

Status: Deferred

Source: Simplification panel (Sol, "Boundary 2"), 2026-08-16

Triage: ready-for-human

## Problem

`.claude/rules/scripts.md:43-54` already names `round` the referee's coarse normal-path module, but
the protocol still hands the referee lower-level mechanics in two places.

**1. Round-0 commit.** Clustering findings into issues is semantic judgment and must stay with the
referee. Installing the clustered map, creating birth records and origins, publishing the index, and
regenerating cards are mechanical, and the referee performs them step by step from prose.

**2. Exceptional multi-batch debate.** `scripts/round:529-531` refuses an existing exceptional batch
plan outright — "existing exceptional batch plan requires manual recovery" — while
`skills/panel-review-for-agent/references/protocol.md:397-500` gives the referee roughly 140 lines of
hand-run planning, prompting, barrier dispatch, ingest, retry, and drop-seat instructions to cover
the same case. The deterministic half of that (pagination by severity then file+line, per-batch id
files, partial-response detection) is exactly what a script does better than a model at the end of a
long run.

## Expected behavior

The public referee surface becomes approximately:

- `round prepare-round0`, `collect-round0`, `commit-round0`
- `round prepare-debate`, `collect-debate`, `salvage-debate`, `commit`
- `round verdict-input`

Specifically:

1. Add `round commit-round0`, taking the referee's clustered map and origin input and owning the
   birth-record, origin, index-publish, and card-regeneration writes.
2. Teach `round` deterministic multi-batch planning, preparation, and recovery. Pagination stays
   available; the referee stops hand-assembling it, and the corresponding protocol steps are deleted
   rather than duplicated.

The referee keeps every judgment: whether raw CLI prose is a genuine review worth salvaging, how to
cluster new findings, how to resolve conflicting prose revisions, and the verdict itself. Those must
not be hidden inside grep or jq heuristics.

## Verification

- Interruption, malformed-output, dropped-seat, re-engagement, and continuation tests for the
  multi-batch path, which currently has none.
- The protocol's exceptional-batch section shrinks by roughly the amount `round` gains.
- `./tests/run_tests.sh` and `scripts/check_contracts --root .` pass; one real review with a forced
  over-budget round completes.

## Non-goals

- Do not merge the modules behind the boundary. `round`, `sweep`, `decide_round`, `merge_payload`,
  and `index` stay separately tested; the boundary this issue moves is the agent-facing one.
- Do not replace Python-to-Python subprocess calls with imports as part of this. Process count is not
  the reliability problem; model-visible procedural surface is. Do it opportunistically afterwards.

## Comments

`Deferred` for the same reason as issue 51: land the correctness work first so a new boundary does
not preserve current defects.
