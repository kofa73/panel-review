# Durable verdict artifact (`/tmp/<ID>.md`) — design

**Status:** proposed, **deferred** (split out of the subcommands redesign on 2026-06-21 — to be done
later, independently)
**Relation:** independent of `2026-06-21-subcommands-design.md`. It applies equally to the current
single-command tool, so it can land on its own, before or after the plugin split.

## Goal

A clean finish tears down the session (`.panel-review/<ID>/` + `/tmp/<ID>/`), so today the verdict
lives **only** in the conversation transcript. To give the user a durable, movable copy without
polluting the working tree, the referee **writes the verdict to a markdown file under `/tmp/` that
cleanup does not touch**.

## Design

- **Path:** `/tmp/<ID>.md` — a **sibling** of `/tmp/<ID>/`, not inside it, so the `rm -rf /tmp/<ID>`
  in cleanup leaves it intact. The ID already begins with `panel-<timestamp>-…`, so the filename is
  self-identifying and unique.
- **When:** whenever a verdict is **produced**, not only at cleanup — so preserved runs (gated /
  finished-with-leftovers) also get a file, and a `continue` that produces a new verdict refreshes it.
  Decoupling from cleanup means every verdict the user sees has a matching file.
- **Contents:** a self-contained report — a metadata header (scope; instructions/"prompt"; limits;
  seats that engaged + any down; rounds; `created` + finished local times; `diff_hash` for
  correlation; the ID) followed by the verdict markdown verbatim. The **full diff is not embedded** —
  it is large and reproducible from the scope; the `diff_hash` is the reference.
- **Surfacing:** the command (`start`/`resume`/`continue`) appends one line after the verdict — e.g.
  *"Saved to `/tmp/<ID>.md` — move it somewhere permanent to keep it (`/tmp` is cleared on reboot)."*
  The referee writes the file; the command knows the ID, so it prints the path.
- **`discard` writes nothing** — it abandons a session without producing a verdict; any prior verdict
  already has its `/tmp/<ID>.md` from when it was shown.

## Change set

1. **Referee**: at verdict time, **write the verdict report to `/tmp/<ID>.md`** before any teardown.
   Otherwise unchanged.
2. **Commands (`start`/`resume`/`continue`)**: after presenting the verdict, append the one-line
   *"Saved to `/tmp/<ID>.md` …"* pointer (they know the ID).

(If implemented before the plugin split, "commands" is the single `/panel-review` dispatcher instead
of the per-verb skills — the artifact design is unaffected.)
