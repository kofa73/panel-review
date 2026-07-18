---
status: accepted
---

# Treat external seats as symmetric optional peers

Codex and Gemini occupy the same peer-seat role. A review may start with Claude plus either external
peer; neither named CLI is mandatory, and availability or failure is reported per seat. Settlement
still requires a quorum, while full-panel coverage is tracked separately.

This is costly to reverse because preflight, panel rendering, coverage, degradation, and report
semantics all use the configured panel. It is surprising because the upstream two-model tool made
Codex mandatory and Gemini optional. Panel Review rejected that inherited asymmetry: once both are
independent peers, requiring one particular provider prevents otherwise valid blind panels without
improving consensus semantics.

## Consequences

- Preflight requires at least one external peer, not a particular provider.
- A down seat affects coverage for that pass but is retried on later passes.
- `run_codex` owns a Panel Review-specific profile so its model tuning is independent of upstream
  tools.

## Evidence

- [`docs/evolution.md`, milestone 2](../evolution.md#2-symmetric-optional-peer-seats)
- Commits `9aa417c^..8cb49aa`
- [`docs/superpowers/specs/2026-06-20-optional-peer-seats-design.md`](../superpowers/specs/2026-06-20-optional-peer-seats-design.md)
- Current [`scripts/preflight`](../../scripts/preflight) and [`scripts/run_codex`](../../scripts/run_codex)

