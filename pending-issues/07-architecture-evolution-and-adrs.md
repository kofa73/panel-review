# Reconstruct architectural evolution and write qualifying ADRs

Priority: 7

Status: Deferred

Source: former `pending.md` item 14 and `doc updates`

## Problem

The repository has design history across commits, pending changes, analyses, and design notes, but
that history has not been consolidated into an evidence-based evolution document. Creating ADRs
without first reconstructing that history risks recording inference as accepted rationale.

This work is intentionally below runtime correctness and repository documentation. If it is not done
as a complete evidence-based workflow, leave `CONTEXT.md` out of the implementation change and defer
the whole sequence.

## Required workflow

First:

> `$research` Reconstruct panel-review's architectural evolution from git history, the pending
> worktree, `pending-issues/referee-context-cost-history.md`,
> `pending-issues/09-referee-judgment-offload-experiment.md`, `docs/superpowers/`, `design-notes/`,
> `README.md`, `AGENTS.md`, tests, and working analysis files. Write `docs/evolution.md`. Group changes
> into decision milestones, cite commit ranges and source files, distinguish explicit rationale from
> inference, and identify superseded or still-proposed decisions.

Then:

> `$domain-modeling` Use `docs/evolution.md` and the live tree to create only the ADRs that satisfy all
> three ADR criteria. Add accepted/proposed/superseded status and evidence references. Keep
> `CONTEXT.md` limited to vocabulary.

Finally, use `/grill-with-docs` only for unresolved questions listed by the research pass. This keeps
undocumented guesses from becoming accepted ADR rationale.

## Acceptance criteria

- `docs/evolution.md` separates source-backed rationale from explicit inference.
- Every ADR meets the repository's ADR criteria and cites supporting evidence.
- Superseded and proposed decisions are not presented as accepted current architecture.
- `CONTEXT.md`, if added, contains vocabulary rather than duplicated protocol or ADR content.
- No documentation claims precede the correctness work they are meant to describe.
