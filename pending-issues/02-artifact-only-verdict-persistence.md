# Remove the legacy worktree verdict dependency

Priority: 2

Status: Pending

Source: artifact-only delivery audit

## Problem

Final delivery is specified as a durable `/tmp/<ID>.md` artifact, but the canonical protocol first
writes a legacy verdict snapshot under the reviewed worktree. That redundant write is still on the
critical path: if it fails, the durable artifact may never be written even though the worktree copy
is not the delivery surface and cleanup deletes it.

## Verified evidence

- `skills/panel-review-for-agent/references/protocol.md` writes
  `$workdir/.panel-review/verdict-$id.md` through `write_card` before calling
  `write_verdict_artifact`.
- The low-severity gate repeats the same worktree-first sequence.
- `scripts/cleanup` deletes the worktree verdict snapshot.
- `README.md` and `skills/start/SKILL.md` describe the durable artifact as the only verdict-delivery
  surface.

The result is an unnecessary failure dependency and a temporary second representation of the same
verdict.

## Required outcome

Make the durable artifact the sole required verdict write. The referee should generate the verdict,
persist `/tmp/<ID>.md` atomically through the owning script, validate success, and only then perform
the existing cleanup/retention decision.

If a worktree snapshot is retained for a specific use, it must be explicitly optional, occur after
durable persistence, and never turn a deliverable verdict into a failed review. The simpler and
recommended result is to remove it.

## Scope and non-goals

- Cover normal completion, the Round-0 low-only gate, later finalized low-only gates, contested or
  unresolved retention, persistence failure, resume, result retrieval, cleanup, and discard.
- Remove stale documentation and cleanup code that exist only for the legacy snapshot.
- Do not change the rule that the referee returns only a fixed status stub.
- Do not move the durable artifact inside `/tmp/<ID>/`; its sibling location is what lets it survive
  cleanup and discard.

## Verification

- A simulated inability to write the worktree cache must not prevent durable artifact delivery.
- A failed durable write must leave resumable state intact and return the documented failure state.
- Successful completion, gate retention, `result`, cleanup, and discard tests must identify exactly
  one delivery artifact.
- Run `tests/python/test_verdict_artifact.py`, related command tests, the full suite, and
  `git diff --check`.
