# Name what diverged instead of reporting only a hash mismatch

Priority: 38

Status: Completed

Source: Panel review `panel-20260816-080558-5ab680af` (Claude + Codex + Gemini), 2026-08-16 — accepted; severity/location `detail_contested` (`medium`/`resolve_diff:47` held against a proposed `low`/`inspect_run:64`)

Triage: ready-for-agent

## Problem

Under the `uncommitted` scope, `resolve_diff` appends the full contents of every untracked,
non-ignored file, excluding only `.panel-review/**` (`scripts/resolve_diff:47`). So one stray
untracked file anywhere in the repository changes the resolved diff hash. Measured: adding a single
untracked `seat_scratch.py` at a scratch repo root moved the hash from `e9d8dc57…` to `983b8a5d…`.

**The hash change itself is correct.** The reviewed input really did change, and the snapshot must
not silently cover different bytes. The panel narrowed the finding to this: the *diagnostics* give
the user nothing to act on.

- `scripts/round:341` (`prepare-round0 --resume`) re-resolves the scope and raises "resolved diff
  hash does not match the manifest".
- `scripts/resume_check:87` runs the same comparison in every phase, so a run interrupted mid-debate
  is blocked identically and already-paid debate rounds are stranded too.
- `scripts/inspect_run:65` reports state `diverged`, and `skills/status/SKILL.md:64` tells the user a
  diverged run "can't be resumed or continued — `panel-review:discard` before `panel-review:start`".

Nothing prints the resolved diff or names the path that changed. An accidental stray file is
therefore indistinguishable from a deliberate scope change, and the documented remedy is to discard
the run. The recovery that actually works — delete the stray file and the hash returns byte-for-byte,
because `resolve_diff`'s output is a pure function of tree state — is never suggested.

Seats are told to keep scratch under `.panel-review/` (`prompts/blind_pass.tmpl:26`), which is
excluded, so this is not the normal path. But `repo_guard` deliberately leaves untracked files alone
(`scripts/repo_guard:10`), a seat that strays is exactly the failure mode this project keeps
observing, and the user's own editor droppings count too.

## Expected behavior

1. When `inspect_run` or `resume_check` reports `diverged`, it also reports **what** diverged: at
   minimum the set of untracked paths now included that were not at snapshot time, and whether
   tracked content changed. Enough to tell "you left a file behind" apart from "the branch moved".
2. `skills/status/SKILL.md`'s divergence guidance offers the non-destructive path first — remove or
   add the listed stray file(s) to `.git/info/exclude` and retry — with `discard` as the fallback
   for a genuine scope change. Editing a tracked `.gitignore` changes the resolved uncommitted diff
   too, so it may not restore the saved hash.
3. The manifest retains whatever is needed to compute item 1 (e.g. the untracked path list at
   snapshot time). The stored diff already exists under `/tmp/<ID>/`, so a path-level comparison is
   available without new snapshotting if that file is still present.

## Verification

- A test that adds an untracked file after `init_run` under an `uncommitted` scope and asserts the
  divergence report names that path.
- A test that removing the file restores the original hash and the run resumes.
- `./tests/run_tests.sh` passes.

## Non-goals

- Do not exclude untracked files from the `uncommitted` scope. Their contents are new code the
  reviewers must see; hiding them would be a worse defect than the one this issue describes.
- Do not make a diverged run resumable without the user's involvement. The gate is correct; only its
  reporting is not.

## Resolution

`init_run` now records the uncommitted tracked-diff hash and untracked paths in the manifest.
`inspect_run`, `resume_check`, and the Round-0 hash check report new/removed untracked paths and
tracked-content changes while preserving the original hash gate. Older runs use the saved diff's
path list when possible and mark unavailable details explicitly. Status, start, resume, and continue
recommend removing a stray file or using `.git/info/exclude` first.

Verification: `./tests/run_tests.sh` passed, including a case that adds a stray untracked file after
`init_run`, verifies the path appears in both divergence reports, removes it, checks the original
hash returns, and confirms `resume_check` allows the run to resume.
