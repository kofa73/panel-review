---
status: accepted
---

# Deliver reports through a durable validated artifact

The canonical report is `/tmp/<ID>.md`, a sibling of the run-state directory so cleanup and discard
do not remove it. The referee must persist it before eligible cleanup and returns only a fixed
status. Command skills validate the artifact against its run identity, continuation epoch, scope,
diff, and canonical index state, then report its filename; `result` provides read-only retrieval by
exact ID. No worktree verdict copy or conversation-body delivery is required.

This is costly to reverse because cleanup, resume, continuation, recovery, status returns, and user
delivery all depend on one report boundary. It is surprising because the simplest Agent workflow
would return verdict Markdown directly. That design lost discoverability when a completed referee
response failed and coupled delivery to model compliance. A durable validated artifact trades an
extra persistence and validation layer for recoverable, context-bounded delivery independent of the
final model response.

## Consequences

- Artifact-write failure retains resumable state and prevents cleanup.
- File existence alone is insufficient; readers validate metadata and retained index state.
- `/tmp` is durable across run cleanup but not permanent storage across host reboot.

## Evidence

- [`docs/evolution.md`, milestone 5](../evolution.md#5-verdict-delivery-moved-from-conversation-text-to-a-durable-report-boundary)
- Commits `8d4c8ed`, `c32936e`, `65762e0`, `b845d9f`, and `177f48f`
- [`docs/superpowers/specs/2026-06-21-verdict-artifact.md`](../superpowers/specs/2026-06-21-verdict-artifact.md)
- [`pending-issues/02-artifact-only-verdict-persistence.md`](../../pending-issues/02-artifact-only-verdict-persistence.md)

