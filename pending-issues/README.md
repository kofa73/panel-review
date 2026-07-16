# Remaining issues

This directory holds the detailed work that remains after the completed sequence in `pending.md`.
`pending.md` remains the durable session handoff; this file is the authoritative ordered index for
remaining work.

Work through the numbered files in order unless a newly discovered defect is demonstrably more
severe. Correctness and executable-contract problems precede documentation and optional polishing.
Completing an item should update its status here, its issue file, and the corresponding entry in
`pending.md`.

| Priority | Status | Issue | Why it is ordered here |
|---:|---|---|---|
| 1 | Completed | [Define and enforce stance semantics](01-stance-contract-semantics.md) | Replaced the contradictory three-name contract with support/reject plus orthogonal revisions. |
| 2 | Pending | [Remove the legacy worktree verdict dependency](02-artifact-only-verdict-persistence.md) | A redundant write can prevent delivery of the durable artifact. |
| 3 | Pending | [Correct the referee mutation contract](03-referee-mutation-contract.md) | A top-level agent instruction contradicts valid state transitions. |
| 4 | Pending | [Require both Claude debate blocks](04-claude-debate-output-contract.md) | The Claude agent permits output rejected by its delivery path. |
| 5 | Pending | [Establish one source of truth for executable instructions](05-instruction-contract-single-source.md) | Cross-layer duplication has already produced several contradictory contracts. |
| 6 | Pending | [Correct repository documentation](06-repository-documentation-corrections.md) | Documentation must describe the settled implementation, after behavior contracts are fixed. |
| 7 | Deferred | [Reconstruct architectural evolution and write qualifying ADRs](07-architecture-evolution-and-adrs.md) | Valuable design history, but it does not affect current runtime correctness. |
| 8 | Optional | [Remove low-risk implementation and test duplication](08-maintainability-cleanups.md) | Maintainability-only cleanup with no known behavior defect. |
| 9 | Optional | [Evaluate offloading referee judgment](09-referee-judgment-offload-experiment.md) | Re-profile after correctness work; helper cold-start cost may exceed the retained-context saving. |
| 10 | Optional | [Evaluate a referee model change](10-model-selection-ab-test.md) | Cost/performance polish; retain the known-quality model without comparative evidence. |

## Completed design records

| Status | Record | Purpose |
|---|---|---|
| Completed | [Referee context-cost reduction history](referee-context-cost-history.md) | Preserves the evidence, alternatives, completed Tracks A/C/D, superseded B2 mechanics, measurements, and deliberate non-goals from the retired `fix_plan.md`. |

## Status meanings

- **Pending:** required remaining work.
- **Deferred:** do only after higher-priority behavior and documentation are stable.
- **Optional:** not a release blocker; skip unless its expected value justifies the change.
- **Completed:** implemented and verified; retain the file as decision and verification history.
