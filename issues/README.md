# Remaining issues

This directory holds the detailed work that remains after the completed sequence in `pending.md`.
`pending.md` remains the durable session handoff; this file is the authoritative ordered index for
remaining work.

Work through the rows in the order shown. Numeric issue identifiers remain stable, so a later issue
may appear ahead of an older one when a newly discovered defect is demonstrably more severe.
Correctness and executable-contract problems precede documentation and optional polishing.
Completing an item should update its status here, its issue file, and the corresponding entry in
`pending.md`.

| Priority | Status | Issue | Why it is ordered here |
|---:|---|---|---|
| 1 | Completed | [Define and enforce stance semantics](01-stance-contract-semantics.md) | Replaced the contradictory three-name contract with support/reject plus orthogonal revisions. |
| 2 | Completed | [Remove the legacy worktree verdict dependency](02-artifact-only-verdict-persistence.md) | Removed the redundant write so only the durable artifact controls delivery. |
| 3 | Completed | [Correct the referee mutation contract](03-referee-mutation-contract.md) | Scoped seat agreement to consensus decisions and qualifying detail revisions without blocking canonical mechanical updates. |
| 4 | Completed | [Require both Claude debate blocks](04-claude-debate-output-contract.md) | Aligned the Claude role summary with the required-emptyable two-block delivery contract. |
| 5 | Completed | [Establish one source of truth for executable instructions](05-instruction-contract-single-source.md) | Centralized seat contracts, assigned invariant owners, and added semantic consistency checks. |
| 13 | Completed | [Enforce fixed Agent status-stub boundaries](13-enforce-agent-status-stub-boundaries.md) | A `SubagentStop` hook now blocks non-exact Claude-seat/referee returns and validates the referee's expected run ID before either completion reaches its caller. |
| 14 | Completed | [Remove duplicate addendum and commit instructions](14-remove-duplicate-addendum-commit-instructions.md) | The normal debate protocol now leaves merge, commit, and card regeneration exclusively to `round commit --addendum`. |
| 15 | Completed | [Restore event-driven referee seat waiting](15-referee-seat-polling-in-loop.md) | Runs each CLI-barrier/Claude-seat pair as concurrent foreground Agents, keeping all seat waiting out of the referee context. |
| 17 | Pending | [Align Agent and Bash contracts with current Claude Code](17-claude-code-runtime-compatibility.md) | Pins the outer referee foreground, handles session Agent-budget exhaustion, and corrects stale Bash timeout assumptions. |
| 16 | Pending | [Support external review profiles](16-external-review-profiles.md) | Adds a project-neutral profile seam for reusable domain review methods without specializing the panel core. |
| 6 | Completed | [Correct repository documentation](06-repository-documentation-corrections.md) | Current maintainer and user documentation now matches the settled gate, salvage, transaction, trust-boundary, component, and test behavior. |
| 7 | Completed | [Reconstruct architectural evolution and write qualifying ADRs](07-architecture-evolution-and-adrs.md) | Added an evidence-backed ten-milestone history and seven qualifying accepted ADRs without promoting proposed work. |
| 8 | Completed | [Remove low-risk implementation and test duplication](08-maintainability-cleanups.md) | Deduplicated byte-sorted sweep lookup and valid debate-test setup without changing behavior. |
| 9 | Optional | [Evaluate offloading referee judgment](09-referee-judgment-offload-experiment.md) | Re-profile after correctness work; helper cold-start cost may exceed the retained-context saving. |
| 10 | Optional | [Evaluate a referee model change](10-model-selection-ab-test.md) | Cost/performance polish; retain the known-quality model without comparative evidence. |
| 11 | Optional | [Evaluate a compact catalogue of previously catalogued claims](11-prevent-re-emerging-findings.md) | Possible token optimization, but the observed rediscovery materially corrected an accepted issue; measure a blindness-preserving catalogue before changing prompts. |
| 12 | Closed | [Empty Claude `new_findings` block is valid](12-claude-empty-findings-block.md) | The required-emptyable contract deliberately accepts both `[]` and an empty present block. |

## Completed design records

| Status | Record | Purpose |
|---|---|---|
| Completed | [Referee context-cost reduction history](referee-context-cost-history.md) | Preserves the evidence, alternatives, completed Tracks A/C/D, superseded B2 mechanics, measurements, and deliberate non-goals from the retired `fix_plan.md`. |

## Status meanings

- **Pending:** required remaining work.
- **Deferred:** do only after higher-priority behavior and documentation are stable.
- **Optional:** not a release blocker; skip unless its expected value justifies the change.
- **Closed:** triaged with no implementation required; retain the file as the supporting record.
- **Completed:** implemented and verified; retain the file as decision and verification history.
