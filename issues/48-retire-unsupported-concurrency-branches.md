# Retire the unsupported-concurrency and silent-repair branches

Priority: 48

Status: Pending

Source: Simplification panel (Opus §3.2-3.4, Sol "Risks that are theoretical"), 2026-08-16 — file
modes measured on the leftover run in this workdir

Triage: ready-for-human

## Problem

Three mechanisms implement behavior the README explicitly declares out of scope, and one advertises a
guarantee it only half delivers.

**1. `init_run`'s concurrent-start convergence.** `scripts/init_run:96-112` takes an exclusive
`flock` on `.panel-review/.init.lock`, scans for an existing winner marker, and if it finds one
deletes its own freshly-minted `/tmp/<ID>` and prints the winner's ID. `README.md:491-495` says, in
bold, that running two sessions against the same workdir simultaneously is not supported and that
this "isn't a race to work around; it's an explicit scope boundary". The code works around it anyway.
`mkdir "$marker"` on line 113 already fails atomically for the loser, which is the honest behavior.
Removing the flock also removes the `.init.lock` file that `scripts/cleanup:52-58` then needs a
special `rm -rf` for.

**2. `resume_check`'s silent index repair.** `scripts/resume_check:60-65` detects an invalid
`index.json`, and if `index.json.bak` happens to parse, overwrites the live index with it — silently,
inside a check the caller believes is read-only. `inspect_run` reports the same condition as stale.
Atomic same-directory replacement already covers process interruption, so this branch only fires
after corruption the write path is supposed to make impossible, and it hides a mutation in a
diagnostic.

**3. `discard`'s invalid-marker-name partition.** `scripts/discard` maintains `removed` and `skipped`
lists so a marker directory whose name fails `panel_valid_id` is reported in a different sentence.
That state is reachable only if someone hand-creates a directory under `.panel-review/`; the
whole-directory `rm -rf` on line 79 already handles it. Roughly 15 lines for a distinct message.

**4. `/tmp` privacy is inconsistent.** `scripts/init_run:28-33` sets `umask 077` with a comment about
a shared `/tmp` leaving state world-readable. Measured on the leftover run in this workdir:

```
drwx------  /tmp/panel-<ID>/                 # init_run's umask applied
drwxr-xr-x  /tmp/panel-<ID>/guard/           # repo_guard mkdir -p — 0755
-rw-r--r--  /tmp/panel-<ID>/f.gemini.json    # run_seat redirect — 0644
```

The umask covers only what `init_run` itself creates. Everything a seat or a later script writes
lands world-readable. Half a guarantee reads as a whole one, which is worse than neither.

## Expected behavior

1. Remove the flock/winner-adoption block from `init_run`; let `mkdir "$marker"` be the atomic
   arbiter and fail the second starter with a clear message. Drop `cleanup`'s `.init.lock` special
   case. Centralize the "exactly one valid marker" check in one place.
2. Make `resume_check` report a corrupt index as stale, and move recovery to an explicit
   `repair-index` diagnostic if it is ever wanted. An action path must not silently mutate state.
3. Collapse `discard`'s two lists into the single `rm -rf` it already performs.
4. For item 4, choose one: apply the umask consistently across every writer under `/tmp/<ID>/`, or
   drop the umask line and the comment. Do not leave the partial version.

## Verification

- Starting a second run against the same workdir fails with a clear, single message; no `/tmp` state
  is left behind by the loser.
- A corrupt `index.json` yields `stale` from both `inspect_run` and `resume_check`, and neither
  rewrites the file.
- `ls -la /tmp/<ID>/` after a complete run shows uniform modes.
- `./tests/run_tests.sh` passes.

## Non-goals

- Keep `index`'s `fcntl.flock` on every mutation. It is three lines, costs nothing, and makes the
  single-writer claim structural rather than conventional.
- Keep atomic writes, validated run IDs before any recursive delete, and marker-last publication.
  Those are general safeguards against ordinary crashes and path mistakes, not concurrency support.
- Symlink hardening in `panel_atomic_write` is issue 40's call; do not fold it in here.

## Comments

Marked `ready-for-human`: item 4 is a maintainer decision about what the project claims, and item 1
changes the observable behavior of a second concurrent start from "converge" to "refuse".
