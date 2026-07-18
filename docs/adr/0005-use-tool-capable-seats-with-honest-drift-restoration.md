---
status: accepted
---

# Use tool-capable seats with honest-drift restoration

Review seats run with the tool and filesystem access needed for code intelligence and throwaway
analysis; Codex and Gemini are intentionally unconstrained by their wrappers. Safety depends on a
disposable execution environment, seat instructions, and `repo_guard` detecting and restoring
honest tracked-tree drift after each pass. This is restoration, not confinement, and it does not
protect untracked files or paths outside the repository.

This is costly to reverse because wrapper flags, seat workflows, scratch space, and repository
guarding all assume this trust boundary. It is surprising because a read-only review would normally
suggest sandbox enforcement. The project instead chose reviewer capability over preventive
confinement: MCP/tilth and scratch scripts materially help review, while any cooperative hash,
permission, or attestation could be defeated by the same malicious seat it purported to constrain.

## Consequences

- Guards target honest accidents and model confusion, never a malicious seat.
- Controls that rely on seat cooperation must be described as conveniences or conformance checks,
  not security boundaries.
- The plugin must run only where broad seat access is acceptable, normally a disposable container.

## Evidence

- [`docs/evolution.md`, milestone 7](../evolution.md#7-tool-capable-seats-tracked-tree-restoration-and-prompt-robustness)
- Commit `ef7c9a7` and robustness commits `b32b20c^..1e45ec1`
- Current [`AGENTS.md`](../../AGENTS.md) trust model and [`scripts/repo_guard`](../../scripts/repo_guard)
- [`design-notes/blind-pass-robustness.md`](../../design-notes/blind-pass-robustness.md)
