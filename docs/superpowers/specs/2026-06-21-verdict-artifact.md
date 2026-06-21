# Durable verdict artifact (`/tmp/<ID>.md`) — design

**Status:** implemented (2026-06-21) — `scripts/write_verdict_artifact`, wired into the referee
protocol's two verdict-producing points and into `start`'s Step 5 (inherited by `resume`/`continue`).
**Relation:** independent of `2026-06-21-subcommands-design.md`. It applies equally to the current
single-command tool, so it can land on its own, before or after the plugin split.

### Implementation notes (resolving open questions from the original design)

- **Atomicity:** the write goes through `panel_atomic_write` (temp file in `/tmp`, fsync, rename),
  same helper used for `manifest.json`/`index.json`. A refresh rotates the previous snapshot to
  `/tmp/<ID>.md.bak` first, so one prior verdict survives an overwrite.
- **Header format:** YAML frontmatter (`---` delimited) rather than free-form prose, so the file is
  greppable. Fields: `id`, `scope`, `instructions`, `limits`, `seats`, `rounds`, `created`,
  `finished`, `diff_hash`.
- **No drift between header and body:** `seats`/`rounds` are parsed out of the verdict body's own
  `**Seats:**`/`**Rounds:**` lines rather than passed a second time as separate arguments — avoids two
  copies of the same fact going out of sync.
- **Failure mode:** the referee treats the write as best-effort; if it fails (e.g. `/tmp` full), the
  verdict is still returned to the user without the pointer line. The script itself fails loudly
  (`set -e`) so the caller can detect and skip the pointer.
- **Mutability is surfaced to the user:** the Step 5 pointer line is repeated at gate time and at
  final-finish time, since a `continue`/debate-the-gate path overwrites the same path — the doc's
  "refreshes it" behavior is now stated explicitly in the command text, not left implicit.
- **`cleanup`/`discard` unchanged:** both already only `rm -rf` the `/tmp/<ID>/` directory, which
  never touches the sibling file; `cleanup` got a one-line comment to keep it that way on purpose.

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
