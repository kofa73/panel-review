# Remaining issues

This directory is the authoritative ordered index and detailed record for repository work.

Work through the rows in the order shown. Numeric issue identifiers remain stable, so a later issue
may appear ahead of an older one when a newly discovered defect is demonstrably more severe.
Correctness and executable-contract problems precede documentation and optional polishing.
Completing an item should update its status here and in its issue file.

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
| 17 | Completed | [Align Agent and Bash contracts with current Claude Code](17-claude-code-runtime-compatibility.md) | Pins the outer referee foreground, fails closed on session Agent-budget exhaustion, and documents current Bash timeout behavior. |
| 16 | Completed | [Support external review profiles](16-external-review-profiles.md) | Added a project-neutral, snapshotted profile seam and extracted the reusable darktable review method without specializing the panel core. |
| 19 | Completed | [Retry a down Round-0 seat once](19-retry-round0-down-seat.md) | Round 0 now retries actual down responses once, preserves complete seat passes, and can retry still-down configured seats on later resume attempts. |
| 25 | Completed | [Restore blocking seat dispatch under Claude Code fork mode](25-fork-mode-backgrounds-seat-agents.md) | Fork mode, on by default in interactive sessions since 2.1.232, backgrounds every subagent and removes the Agent tool's `run_in_background`. Measured: a backgrounded referee never collected early in 4 trials, but 1 of 4 improvised a polling wait. `preflight` now hard-blocks unless `CLAUDE_CODE_FORK_SUBAGENT=0`; README documents the alias/wrapper. |
| 24 | Pending | [Move seat scratch out of the repository under review](24-seat-scratch-outside-workdir.md) | Seat scratch inside the workdir leaks one seat's raw findings to another through an ordinary repo-wide search; observed corrupting a completed run's Round 0. |
| 26 | Pending | [Correct the stale subagent-budget guidance and its contract check](26-stale-subagent-spawn-budget-guidance.md) | README's fail-closed recovery names `Subagent spawn limit reached`, removed in 2.1.224, and `check_contracts` pins that wording in place. |
| 27 | Pending | [Re-verify the two agy workarounds against agy 1.1.13](27-recheck-agy-workarounds-on-1-1-13.md) | agy 1.1.12 improved repository detection and 1.1.13 fixed long-input truncation — the two behaviors behind the prompt anchor and the prompt-size limit; measure before changing either. |
| 20 | Completed | [Correct the agy model-pin contract](20-agy-model-pin-contract.md) | The label-pin contract is stated once in `run_agy` and `AGENTS.md`, enforced by `check_contracts`' `agy-model-pin-form`, and provable on demand through `tests/live/agy_model_binding.sh` instead of a log-parsing guard inside the run loop. |
| 21 | Pending | [Refresh the shipped seat model defaults](21-refresh-seat-model-defaults.md) | agy pins updated to `Gemini 3.7 Flash (High)` / `Gemini 3.1 Pro (High)` on 2026-08-15; the Codex profile asset still names an earlier-generation model, and that value is the panel owner's call. |
| 18 | Pending | [Add user configuration and stable run defaults](18-user-configuration-and-run-defaults.md) | Adds named/default profiles, durable round and timeout settings, and explicit cleanup policy without specializing the shared plugin or relying on behavioral environment variables. |
| 22 | Pending | [Record the Claude Code 2.1.219+ runtime constraints](22-claude-code-2-1-219-runtime.md) | Successor to issue 17: names the nested-subagent version floor and its off switch, plus the thinking-inheritance and `opus`-alias facts. Documentation only. |
| 6 | Completed | [Correct repository documentation](06-repository-documentation-corrections.md) | Current maintainer and user documentation now matches the settled gate, salvage, transaction, trust-boundary, component, and test behavior. |
| 7 | Completed | [Reconstruct architectural evolution and write qualifying ADRs](07-architecture-evolution-and-adrs.md) | Added an evidence-backed ten-milestone history and seven qualifying accepted ADRs without promoting proposed work. |
| 8 | Completed | [Remove low-risk implementation and test duplication](08-maintainability-cleanups.md) | Deduplicated byte-sorted sweep lookup and valid debate-test setup without changing behavior. |
| 9 | Optional | [Evaluate offloading referee judgment](09-referee-judgment-offload-experiment.md) | Re-profile after correctness work; helper cold-start cost may exceed the retained-context saving. |
| 10 | Optional | [Evaluate a referee model change](10-model-selection-ab-test.md) | Cost/performance polish; retain the known-quality model without comparative evidence. |
| 11 | Optional | [Evaluate a compact catalogue of previously catalogued claims](11-prevent-re-emerging-findings.md) | Possible token optimization, but the observed rediscovery materially corrected an accepted issue; measure a blindness-preserving catalogue before changing prompts. |
| 23 | Optional | [Evaluate new agy CLI capabilities](23-evaluate-new-agy-flags.md) | Records the decision per new agy flag so the analysis is not redone at the next CLI update; two candidates need a measurement before adoption. |
| 28 | Optional | [Evaluate new codex exec capabilities](28-evaluate-new-codex-exec-flags.md) | Codex counterpart of issue 23: every flag `run_codex` uses still works on 0.147.0, so this only records a decision per new flag (hooks/trust, `--ignore-rules`, `--ephemeral`, `--output-schema`). |
| 29 | Optional | [Evaluate agy's API-key auth and print-mode probes](29-evaluate-agy-api-key-and-print-probes.md) | `GEMINI_API_KEY` auth and quota-free `-p "/model"` probes could harden the seat's weakest link, but both touch user config or preflight and need a decision first. |
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
