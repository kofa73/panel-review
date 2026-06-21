---
name: status
description: Show the saved panel-review session(s) for this workdir — creation time, scope, instructions, limits, state and progress. Read-only; also reports seat prerequisites (Codex/Gemini availability).
argument-hint: ""
---

# panel-review:status

You are a **read-only reporter**. This command never mutates anything and never dispatches the
referee — it is the user's window into the saved state. Run from the repo root.

```bash
# CLAUDE_PLUGIN_ROOT is substituted into this text at skill-load — it is NOT a
# shell env var (it's empty in the shell). Keep the literal verbatim; don't
# build it dynamically or read $CLAUDE_PLUGIN_ROOT at runtime.
SC="${CLAUDE_PLUGIN_ROOT}/scripts"
```

## Step 1 — prerequisites

```bash
"$SC/preflight"
```
Show its output (core prereqs, plus `CODEX: yes|no` / `GEMINI: yes|no`). Unlike `start`, a failure
here does **not** stop this command — report it **alongside** the saved state below, not instead of
it: a missing prerequisite doesn't make the saved review disappear.

## Step 2 — enumerate every marker and inspect each

```bash
base="$PWD/.panel-review"
ids=(); names=(); if [ -d "$base" ]; then
  for d in "$base"/*/; do
    [ -d "$d" ] || continue
    n="$(basename "$d")"
    if [ -f "$d/.panel-run" ]; then ids+=("$n"); else names+=("$n"); fi
  done
fi
```

- `names` (dirs with no `.panel-run` marker file) are stray/garbage — note them as unrecognized
  paths under `.panel-review/`, nothing more (don't classify or inspect them).
- For each entry in `ids`, run:
  ```bash
  "$SC/inspect_run" --id "$id" --workdir "$PWD"
  ```
  and collect the JSON. `inspect_run` is **pure** — it never repairs, never writes, never cleans up a
  stale marker (that's the action commands' job). If `inspect_run`'s own validity check on the id
  fails, treat that entry like a `names` stray.

## Step 3 — report

- **Zero entries** (`ids` and `names` both empty, i.e. no `.panel-review/` or it's empty) →
  > No saved review; `panel-review:start <scope>` to start one.

- **Exactly one entry in `ids`** → the normal case. Show its creation time (the manifest's stored
  local wall-clock value), scope, instructions, limits, and state + progress. Omit the ID — it's
  internal noise in the single-session case. Per `state`:
  - `interrupted` (≥1 `open`) → show progress (`round`, counts by state). Append: "Pick it up with
    `panel-review:resume`."
  - `continuable` (`0` open, ≥1 `unresolved`/`contested`) → show leftover counts. Append: "Push it
    further with `panel-review:continue [unresolved|contested]`."
  - `diverged` → "the working tree diverged from the reviewed snapshot (the code under review was
    modified since this review started); it can't be resumed or continued —
    `panel-review:discard` before `panel-review:start`."
  - `stale` → the marker's `/tmp/<ID>/` state is gone. **Do not say you cleared it** — you are
    read-only. Report it as remaining stale and name `.panel-review/<ID>/`: "a stale marker remains at
    `.panel-review/<ID>/` (its `/tmp` state is gone); `panel-review:start`/`resume`/`continue` will
    clean it, or remove it yourself."

- **More than one entry in `ids`, or any entry in `names`** → flag the abnormal state explicitly:
  > More than one saved review (only possible if `.panel-review/`/`/tmp/` was edited out of band —
  > multiple reviews aren't supported).
  List **each** `ids` entry with its creation time, scope, instructions, limits, state/progress, **and**
  its `.panel-review/<ID>/` + `/tmp/<ID>/` paths (so the user can tell them apart and remove a specific
  one by hand). List each `names` stray as an unrecognized path under `.panel-review/`. Then:
  > `panel-review:discard` clears them all, or remove individual `.panel-review/<ID>/` + `/tmp/<ID>/`
  > pairs by hand.

## Notes

- This command never writes — not a `.bak` repair, not a stale-marker cleanup, nothing.
- It shows **machine state only**, not the last verdict text — that was already shown in the
  transcript when the run produced it, and the files are on disk if you want to read them directly.
