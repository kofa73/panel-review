---
status: accepted
---

# Keep bulk review content out of long-lived contexts

The long-lived referee receives compact status and judgment inputs rather than bulk review content.
The protocol is loaded by active phase, coarse `round` operations replace repeated low-level model
turns, and the Claude seat validates and writes its raw response directly before returning a fixed
status. Agent status hooks enforce exact returns within the platform's bounded retry limit; internal
transcript extraction is not a normal or recovery dependency.

This is costly to reverse because prompt assembly, phase routing, raw-file ownership, Agent returns,
and normal round orchestration share this boundary. It is surprising because passing subagent output
through the parent conversation is the obvious Agent pattern. Measurements showed that repeatedly
replaying the accumulated referee context dominated usage, while duplicate raw delivery and script
reconstruction added avoidable turns. File-backed interfaces trade extra persistence machinery for
bounded parent context and deterministic recovery.

## Consequences

- Bulk findings, stances, and report prose travel through owned files, not Agent final messages.
- Fixed status enforcement is bounded conformance protection, not a malicious-agent security
  boundary.
- Further helper-agent offload remains an experiment and requires evidence of a net saving without
  worse review quality.

## Evidence

- [`docs/evolution.md`, milestones 8 and 9](../evolution.md#8-reliable-asynchronous-seat-completion-without-referee-polling)
- Commits `c32936e`, `65762e0`, and `177f48f`
- [`issues/referee-context-cost-history.md`](../../issues/referee-context-cost-history.md)
- [`issues/13-enforce-agent-status-stub-boundaries.md`](../../issues/13-enforce-agent-status-stub-boundaries.md)

