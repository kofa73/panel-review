# Shrink the active documentation and backlog surface

Priority: 53

Status: Pending

Source: Simplification panel (Sol, "Documentation and backlog simplification"), 2026-08-16

Triage: ready-for-human

## Problem

Three separate bodies of text read as current instruction while only part of each is:

- **README (631 lines)** mixes operator instructions, behavior specification, the wrapper catalogue,
  state schemas, and implementation rationale. A first-time user and a maintainer changing
  `merge_payload` need almost disjoint subsets.
- **`docs/superpowers/plans/` (919 lines across two files)** holds superseded implementation plans
  that look like current instructions. `2026-06-20-continue-leftovers.md:72` still gives step-by-step
  edits against `index flag`, a verb issue 44 deletes.
- **`issues/`** keeps completed incident narratives in the active directory. Of 41 files, 13 are
  Completed or Closed, and the index table is long enough that the actual work queue is hard to see.

## Expected behavior

A smaller active surface:

- **README** — installation, required session settings, public commands, lifecycle, trust model,
  hard constraints. (The wrapper catalogue leaves with issue 50.)
- **`docs/architecture.md`** — current component and state ownership, plus the schemas.
- **`docs/agent-runtimes.md`** — one place for the current Claude Code / Codex / agy requirements,
  each observation dated and version-qualified, plus the upgrade probes to re-run.
- **`CONTRACTS.md`** — unchanged: the concise executable ownership index.
- **ADRs and `docs/evolution.md`** — decisions and history.
- **`issues/README.md`** — active required work only, with completed records moved to an
  archive/history subdirectory and linked.

Move `docs/superpowers/plans/*` under `docs/history/` or mark each file explicitly historical in its
first line.

## Verification

- Every runtime fact currently in `issues/13, 15, 19, 20, 22, 24, 25, 26, 27` appears in
  `docs/agent-runtimes.md` **before** those narratives are archived.
- `scripts/check_contracts --root .` passes (it reads several of these files).
- A `grep` for each moved file's old path finds no live reference.

## Non-goals

- **Do not delete completed issues.** Issues 13, 15, 19, 20, 24, 25, and 26 contain the evidence that
  distinguishes an earned mechanism from folklore. Extract the current runtime facts first, then
  archive the narrative — the file stays.
- Do not restructure while issues 41-50 are open against the same files; sequence this last.

## Comments

Related backlog triage from the same panel, recorded here rather than as separate issues:

- **Issue 18 (user configuration)** — do not implement the full versioned XDG schema, named profile
  registry, selector grammar, timeout persistence, cleanup policy, unknown-key handling, and legacy
  migration until repeated use proves the need. If one default is genuinely repeated (most likely a
  default review-profile path), add that one value through issue 51's controller.
- **Issues 9, 10, 11** — leave parked until there is a measured quality or cost problem.
- **Issues 23, 28, 29** — better as one short runtime-upgrade checklist in `docs/agent-runtimes.md`
  than as three open-ended feature decisions.
- **Issue 22 and the documentation half of issue 27** — belong in `docs/agent-runtimes.md`.
