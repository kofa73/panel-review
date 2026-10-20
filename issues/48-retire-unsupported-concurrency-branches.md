# Retire the unsupported-concurrency and silent-repair branches

Priority: 48

Status: Pending

Source: Simplification panel (Opus §3.2-3.4, Sol "Risks that are theoretical"), 2026-08-16 — file
modes measured on the leftover run in this workdir

Triage: ready-for-human

## Problem

Three mechanisms implement behavior the README explicitly declares out of scope, and one advertises a
guarantee it only half delivers.

**1. `init_run`'s concurrent-start convergence.** `scripts/init_run:97-112` takes an exclusive
`flock` on `.panel-review/.init.lock`, scans for an existing winner marker, and if it finds one
deletes its own freshly-minted `/tmp/<ID>` and prints the winner's ID. `README.md:583-587` says, in
bold, that running two sessions against the same workdir simultaneously is not supported and that
this "isn't a race to work around; it's an explicit scope boundary". The code works around it anyway.
However, `mkdir "$marker"` on line 113 does not arbitrate between starts: each start mints a
different ID and therefore a different marker path. Removing the lock and winner scan would allow
both marker directories to be published. `cleanup` removes the whole `.panel-review/` tree when no
run directories remain; its whole-tree removal also clears `.init.lock`.

**2. `resume_check`'s silent index repair.** `scripts/resume_check:58-61` detects an invalid
`index.json`, and if `index.json.bak` happens to parse, overwrites the live index with it — silently,
inside a check the caller believes is read-only. `inspect_run` reports the same condition as stale.
Atomic same-directory replacement already covers process interruption, so this branch only fires
after corruption the write path is supposed to make impossible, and it hides a mutation in a
diagnostic. After the check was made read-only, the `start`, `resume`, and `continue` skills still
treated `stale` as permission to call `cleanup`, deleting a valid backup and other recoverable files.

**3. `discard`'s invalid-marker-name partition.** `scripts/discard` maintains `removed` and `skipped`
lists so a marker directory whose name fails `panel_valid_id` is reported in a different sentence.
That state is reachable only if someone hand-creates a directory under `.panel-review/`; the
whole-directory `rm -rf` already handles it. Roughly 15 lines for a distinct message.

**4. Later writers use different mode bits under `/tmp/<ID>/`.** `scripts/init_run:28-33` sets
`umask 077`, but later writers do not inherit that process umask. Measured on the leftover run in
this workdir:

```
drwx------  /tmp/panel-<ID>/                 # init_run's umask applied
drwxr-xr-x  /tmp/panel-<ID>/guard/           # repo_guard mkdir -p — 0755
-rw-r--r--  /tmp/panel-<ID>/f.gemini.json    # run_seat redirect — 0644
```

The child mode bits differ, but the `0700` run directory prevents other UIDs from traversing to any
child. The measurements do not show that later files are world-readable. They do show that a claim
of uniform child modes would be false after later writers run.

## Expected behavior

1. Resolve the concurrent-start behavior with the owner. Keep current convergence, add a shared
   per-workdir gate that refuses the second start, or remove coordination and accept that concurrent
   starts can publish multiple markers. A per-ID `mkdir "$marker"` cannot refuse the second start.
2. Make `resume_check` and `inspect_run` report a corrupt index as stale without repair. The
   `start`, `resume`, and `continue` action paths must preserve existing stale state for manual
   recovery or explicit discard; they must not route it through `cleanup`.
3. Collapse `discard`'s two lists into the single `rm -rf` it already performs.
4. For item 4, decide whether to require restrictive modes on every child written under `/tmp/<ID>/`
   or to rely on the private `0700` run directory and clarify the `init_run` comment. Do not remove
   the umask without accepting that a default `0755` run directory exposes its contents to other UIDs.

## Verification

- Starting a second run against the same workdir fails with a clear, single message; no `/tmp` state
  is left behind by the loser.
- A corrupt `index.json` yields `stale` from both `inspect_run` and `resume_check`, and neither
  rewrites the file.
- `start`, `resume`, and `continue` preserve an existing stale run, including a parseable `.bak`;
  only explicit `panel-review:discard` abandons it.
- `discard`'s skill presents the script's single summary verbatim, with no promised itemization.
- `ls -la /tmp/<ID>/` after a complete run shows uniform modes.
- `./tests/run_tests.sh` passes.

## Non-goals

- Keep `index`'s `fcntl.flock` on every mutation. It is three lines, costs nothing, and makes the
  single-writer claim structural rather than conventional.
- Keep atomic writes, validated run IDs before any recursive delete, and marker-last publication.
  Those are general safeguards against ordinary crashes and path mistakes, not concurrency support.
- Symlink hardening in `panel_atomic_write` is issue 40's call; do not fold it in here.

## Comments

Marked `ready-for-human`: item 4 is a maintainer decision about the mode policy, and item 1 changes
the observable behavior of a second concurrent start. The proposed `mkdir "$base/$id"` is not an
atomic arbiter between starts because each start mints a different `$id` and therefore creates a
different path.

## Implemented so far

- `resume_check` and `inspect_run` now report a malformed `index.json` as stale without rewriting it
  from a valid `.bak`. Tests cover both checks and verify that neither file changes.
- `start`, `resume`, and `continue` now preserve stale marker and `/tmp` state for manual recovery or
  explicit discard. `resume` also preserves state when its manifest is missing.
- `discard` no longer keeps separate removed and skipped lists. It validates names before mapping
  them to `/tmp`, clears the marker tree once, and prints one summary; the skill now presents that
  output verbatim.

## Open questions for the owner

1. **What should a second concurrent start do?**
   - Keep the current behavior: serialize publication and return the already-published run ID.
   - Refuse the second start with a clear message. This needs a shared per-workdir gate or lock; the
     current per-ID `mkdir` cannot arbitrate because each start has a different path.
   - Remove coordination and leave simultaneous starts unsupported, accepting that two unique
     markers can be published and a later check can report `ambiguous`.

   Recommended: refuse the second start with a shared gate if a clear failure is required. It matches
   the expected behavior while avoiding the current winner-adoption behavior. Keep the README's
   unsupported-concurrency boundary either way.

2. **What mode policy should `/tmp/<ID>/` use?**
   - Apply restrictive umasks in every writer so child directories and files also have private mode
     bits.
   - Keep `umask 077` for creation of the run directory and clarify that its `0700` mode protects
     descendants, even when their own mode bits are broader.
   - Remove the umask and comment, accepting that the run directory may be `0755` under a common
     default umask.

   Recommended: keep the restrictive run-directory umask and correct the comment. The existing
   `0700` parent blocks other UIDs from reaching descendants; uniform child modes add no current
   cross-user access protection.
