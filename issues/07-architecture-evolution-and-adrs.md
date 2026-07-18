# Reconstruct architectural evolution and write qualifying ADRs

Priority: 7

Status: Completed

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
> worktree, `issues/referee-context-cost-history.md`,
> `issues/09-referee-judgment-offload-experiment.md`, `docs/superpowers/`, `design-notes/`,
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

## Implementation

Completed 2026-07-18 as an evidence-reconstruction and domain-modeling change:

- `docs/evolution.md` reconstructs ten architectural milestones through commit `5082f6e`. Every
  milestone separates evidence, explicit rationale, inference, and current status, and the final
  sections distinguish retained, superseded, and still-proposed decisions.
- Seven accepted ADRs under `docs/adr/` record only decisions that are costly to reverse,
  surprising without context, and the result of a documented trade-off: review/referee separation
  and unanimity, symmetric peers, explicit lifecycle verbs and continuation cycles, deterministic
  mechanics, the seat trust model, file-backed context boundaries, and artifact-only report
  delivery.
- No ADR was created for the CLI wake-barrier mechanism, prompt repair/schema iterations,
  marketplace path, or optional model/helper experiments. They are replaceable mechanisms, lack
  recorded rationale, or remain unmeasured proposals.
- `docs/agents/domain.md` now routes historical questions to `docs/evolution.md` while retaining
  `CONTEXT.md` as the vocabulary-only current domain glossary. `CONTEXT.md` required no change.
- No grilling pass was needed. Research found no unresolved question that blocked ADR
  classification; the undocumented marketplace rationale and unproven prompt-size causality were
  explicitly excluded from accepted ADR rationale.

## Completed verification

- All 84 local Markdown links in `docs/evolution.md`, `docs/adr/`, and `docs/agents/domain.md`
  resolve.
- Every commit named by the ADRs resolves to a commit in the repository.
- `scripts/check_contracts --root .`: `instruction contracts: OK`.
- `./tests/run_tests.sh`: `PASS: 223`, `FAIL: 0`.
- `git diff --check` and a trailing-whitespace scan passed.
