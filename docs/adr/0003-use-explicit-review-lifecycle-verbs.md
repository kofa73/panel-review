---
status: accepted
---

# Use explicit review lifecycle verbs

Panel Review exposes `start`, `status`, `resume`, `continue`, `result`, and `discard` as distinct
plugin verbs with distinct preconditions. Only `start` accepts a scope and review instructions;
later operations adopt them from the saved run. `resume` continues an interrupted cycle, while
`continue` reopens selected leftovers in the same run with a fresh debate budget and retained
evidence.

This is costly to reverse because the public command surface, manifest identity, persistence model,
and recovery behavior encode these distinctions. It is surprising because one command could infer
intent from disk state. That alternative caused scope and instructions to be retyped byte-for-byte
and conflated changed guidance with changed code. Explicit verbs trade a larger command surface for
deterministic intent and safer mutation boundaries.

## Consequences

- Mutating verbs are human-triggered; read-only `status` and `result` may be model-invoked.
- A continuation is a new cycle within the same run, not a fresh Round 0 or an interrupted resume.
- Scope divergence blocks resume and continuation instead of applying cached evidence to changed
  review material.

## Evidence

- [`docs/evolution.md`, milestones 3 and 4](../evolution.md#3-finished-reviews-became-continuable-review-runs)
- Commits `a34eca6^..6be3f56`, `b201ad8^..6a33aa7`, `c6a3020`, and `c32936e`
- [`docs/superpowers/specs/2026-06-20-continue-leftovers-design.md`](../superpowers/specs/2026-06-20-continue-leftovers-design.md)
- [`docs/superpowers/specs/2026-06-21-subcommands-design.md`](../superpowers/specs/2026-06-21-subcommands-design.md)

