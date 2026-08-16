# Stop `repo_guard verify --restore` from rewriting the user's git index

Priority: 33

Status: Pending

Source: Panel review `panel-20260816-080558-5ab680af` (Claude + Codex + Gemini), 2026-08-16 — accepted, 2 of 3 seats at Round 0

Triage: ready-for-agent

## Problem

`repo_guard verify --restore` repairs seat drift with

```text
scripts/repo_guard:129   git -C "$workdir" checkout "$baseline" -- "$f"
```

`git checkout <tree-ish> -- <path>` writes **both** the worktree and the index. There is no
companion `git reset -- "$f"`, so restoring a drifted file also stages it. The guard's own header
promises the tree is left "byte-for-byte unchanged" and that a dirty baseline "restores the DIRTY
bytes (the state at snapshot time)" — the index is neither snapshotted nor restored, so both
promises are false whenever the run starts on a dirty tree.

Three distinct failures, all measured by the panel:

1. **Unstaged work becomes staged.** With an unstaged modification present at snapshot time, after
   seat drift and `verify --restore`, `git status --porcelain` moved from `" M a.txt"` to
   `"M  a.txt"`. A later `git commit` then picks up work the user never staged.
2. **A distinct staged version is destroyed.** With committed A / staged B / worktree C, after
   `verify --restore` `git show :a.txt` returns C. B is gone from the index. It is not *lost* —
   `git stash create` records the index as the stash commit's **second parent**, so the baseline
   commit still holds it — but nothing in `repo_guard` ever reads that parent, and the user is not
   told the object exists.
3. **Index-only drift is invisible.** `hash_tracked` (`scripts/repo_guard:69`) hashes worktree bytes
   only. Measured: after a snapshot, `git add a.txt` left `verify --restore` at exit 0 with no drift
   printed. A seat that stages a change is neither reported nor reverted.

Related, lower severity: for a path newly added to the index after the snapshot,
`git checkout <baseline> -- <path>` fails (the path is not in the baseline tree) and
`scripts/repo_guard:127` deliberately leaves it in place, so a seat can leave a new file staged
after a "successful" restore. That case is at least reported as drift.

`tests/run_tests.sh:319` covers only an unstaged dirty file, so none of this is caught.

## Expected behavior

1. `verify --restore` restores the worktree bytes **and** the index entry that existed at snapshot
   time, or — if full index restoration is judged out of scope — it must at minimum not *change*
   index state it did not snapshot. `git checkout` followed by `git reset -- <path>` un-stages, but
   that is also wrong when the path was legitimately staged before the run; restoring from the
   snapshot is the only correct behaviour.
2. `snapshot` already has the data it needs: the stash commit's tree is the worktree state and its
   **second parent's** tree is the index state (measured: committed A / staged B / worktree C gives
   `git show <stash>:a.txt` = C and `git show <stash>^2:a.txt` = B). Only the restore path ignores
   the second parent.
3. Drift detection covers index-only changes, or `repo_guard`'s header states plainly that it does
   not and why.
4. The header contract is corrected to match whatever is implemented. If index state stays out of
   scope, say so explicitly instead of promising "byte-for-byte unchanged".

## Verification

- A regression test in `tests/run_tests.sh` that sets up committed A / staged B / worktree C, drifts
  the file from a simulated seat, runs `verify --restore`, and asserts `git show :a.txt` is B and the
  worktree is C.
- A regression test asserting that an unstaged-dirty file is still unstaged after restore.
- A test for index-only drift (`git add` after snapshot) matching whichever behaviour item 3 selects.
- `./tests/run_tests.sh` passes.

## Non-goals

- Do not extend the guard to untracked files; that boundary is deliberate (`repo_guard:10`).
- Do not make the guard a confinement mechanism. It reverts honest drift; a tampering seat is out of
  the trust model (`AGENTS.md`, "No security theatre").

## Comments

**2026-08-16 — historical scan: the destructive branch has never fired.** Before scheduling this
issue, every surviving run record was scanned for a real restore. Nothing was found, so the two
data-loss modes are latent, not active, and this issue was reordered below the cheap fixes (41, and
34's uncontested options 1 and 5). It stays Pending: nothing prevents the failure, seats have simply
not drifted a tracked file yet.

What was scanned:

1. **Guard drift logs — 69 files, every one zero bytes.** `round.verify_guard` (`scripts/round:454`)
   appends `verify --restore`'s stdout to `/tmp/<ID>/origins/guard.round0.txt`, and the referee
   appends the debate call to `guard.debate.txt` (`protocol.md:483`). `repo_guard` prints one
   `modified:`/`deleted:`/`added:` line per drifted path *before* reaching the `git checkout` loop
   (`repo_guard:120-135`), so an empty log proves the loop never ran. Covers 64 run directories,
   2026-06-28 to 2026-08-16; the five 2026-06-27 runs have `origins/` but no guard files because they
   predate the guard.
2. **40 surviving verdict artifacts** (`/tmp/<ID>.md`, which outlive `cleanup`/`discard`, so they also
   cover runs whose `/tmp/<ID>/` is gone). Every Process-notes guard line reports no drift; none
   reports a revert.
3. **All Claude session transcripts** under `~/.claude/projects` (68 MB, every project, including the
   darktable workdirs). The only drift-shaped output anywhere is `modified: a.txt`, in two subagent
   transcripts of session `2fd9e77c` — this panel's own synthetic reproduction in a scratch repo.

Earliest surviving record is 2026-06-21 against an initial commit of 2026-06-20, so coverage is
effectively the project's whole life.

**Caveat, and the reason this is not downgraded further:** failure mode 3 (index-only drift is
invisible) leaves no trace by construction. `hash_tracked` (`repo_guard:69`) hashes worktree bytes
only, so a seat that ran `git add` would be neither reported nor reverted, and the empty logs above
cannot rule that out. The likelihood is low — staging without changing content is an odd thing for a
seat to do — but the scan is silent on it rather than negative.
