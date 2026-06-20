# Design: Symmetric, optional peer seats

**Date:** 2026-06-20
**Status:** Approved (pending spec review)

## Problem

`preflight` makes the Codex seat a **hard requirement** (`codex` CLI + the
`peer-review` profile), while the Gemini seat (`agy`) is **soft** — absent Gemini
just degrades to 2-way. This asymmetry is a leftover from the upstream
`codex-peer-review` tool, where Claude + Codex were the only two seats, so "no
Codex" genuinely meant "no peer."

Panel Review now has three independent seats (Claude, Codex, Gemini). The Claude
seat is the host/referee platform and is always present; Codex and Gemini are both
just *peers*. There is no reason to treat one peer as mandatory and the other as
optional. A user who has set up only one of the two CLIs should still get the core
feature: Claude + at least one other model, debated blind.

Two further issues surfaced while scoping this:

- **Shared Codex profile.** Both this tool and upstream `agent-peer-review` invoke
  Codex with `--profile peer-review`, reading the same
  `~/.codex/peer-review.config.toml`. Tuning the model for one tool silently
  changes the other. Users running both should be able to tune each independently.
- **Dead summarizer config.** `peer-review-summarizer.config.toml` is referenced
  only in a `run_codex` comment and a soft `preflight` note. Nothing in this repo
  ever sets `CODEX_PROFILE=peer-review-summarizer`; the "distillation" path it
  describes does not exist in this fork. It is dead config inherited from upstream.

## Goals

- Either peer (Codex or Gemini) may be absent; the review runs with whatever seats
  are available, requiring at least Claude + one peer.
- Treat the two peers symmetrically in setup checks, runtime degradation, and docs.
- Give Panel Review its own Codex profile, decoupled from upstream, created
  automatically so the tool works standalone with no manual setup step.

## Non-goals

- Switching the Codex seat to the `codex review` subcommand. `codex exec` is what
  accepts our blind-review prompt on stdin and emits the structured findings block
  the parser expects; `codex review` has its own flow and is out of scope.
- Changing the debate/consensus logic. Runtime degradation is **already** generic
  (see below); only the gating and the wording change.

## Key insight: runtime degradation is already generic

The only thing that blocks Codex-less operation today is the hard-fail at
`preflight:16`. The dispatch path already degrades for any down seat:

- `run_codex` exits 127 when `codex` is missing.
- `parse_block` then returns exit 4 ("no block" → down seat).
- The settle rule needs **≥2 engaged seats**; with Codex down, Claude + Gemini = 2,
  so the review proceeds 2-way and records the down seat.

So this change is mostly **preflight gating + a profile rework + a wording sweep**,
not new degradation logic.

## Design

### 1. `preflight` — relax gating, stay read-only

Hard requirements become:

- `jq`, `git`, inside a git work tree, writable cwd (unchanged — truly core).
- **At least one peer seat present:** `codex` CLI **or** `agy`. If **neither** is
  present, hard-fail (Claude alone is not a panel).

Changes:

- `codex` and the Codex profile are **removed** from the hard-fail list.
- Emit **both** machine-readable availability lines for the referee:
  `CODEX: yes|no` and `GEMINI: yes|no` (today only `GEMINI` is emitted).
- **Remove the summarizer soft-check** (current line 29) — it points users at a
  benefit that does not exist.
- `preflight` continues to **never write config files** (the `panel-review-init`
  skill promises this). Profile creation lives in `run_codex` (below), so preflight
  only checks and reports.
- Codex login stays a soft warning.

### 2. `run_codex` — own profile, auto-created at point of use

- Default profile becomes **`panel-review`** (was `peer-review`):
  `CODEX_PROFILE="${CODEX_PROFILE:-panel-review}"`.
- **Create-if-missing guard:** before invoking Codex, if
  `~/.codex/panel-review.config.toml` is absent, `mkdir -p ~/.codex` and **copy a
  shipped template** into place (`cp` without overwriting an existing file). The
  default config is a real, separate file — not a heredoc inside the script — so it
  can be edited, diffed, and reviewed on its own:

  - Template: **`skills/panel-review/templates/default-panel-review.config.toml`**

    ```toml
    model = "gpt-5.5"
    model_reasoning_effort = "xhigh"
    ```

  - `run_codex` resolves its own location to find the template:
    `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`, template at
    `$SCRIPT_DIR/../templates/default-panel-review.config.toml`.

  Idempotent and cheap; runs on every call. After the guard the file always
  exists, so Codex is always invoked with `--profile panel-review` — no
  "omit `--profile`" branch.
- Rationale for placing creation here, not in `preflight`:
  - `run_codex` is the only sanctioned way to call Codex, so the profile is
    guaranteed present exactly when needed, including any standalone call.
  - Keeps `preflight` read-only.
  - Single source of truth; no two-places-must-agree.
- Rationale for a template file over an inline heredoc: the default config lives in
  a real `.toml` that is editable/diffable/lintable without touching shell, and a
  `templates/` sibling dir keeps it clear of `install.sh`'s `chmod +x scripts/*`
  (no exec bit on a data file, no special-casing).
- Remove the `peer-review-summarizer` mention from the `run_codex` comment.

### 3. Drop the summarizer profile entirely

No code path uses it. Remove its `preflight` check and the `run_codex` comment
reference. Do not create it.

### 4. Wording sweep

Replace "2-way (Claude + Codex)" / "if Gemini is unavailable" framing with the
symmetric rule everywhere it appears:

- **README.md** — graceful-degradation bullet (~line 32) and the "Degrade
  gracefully" rule (~line 199): any one peer may be absent or fail; the review runs
  with whatever ≥2 seats engage and says which seat was down. Required to start =
  Claude + ≥1 peer.
- **`skills/panel-review-for-agent/SKILL.md`** — "full panel" / degrade notes that
  single out Gemini; generalize to either peer.
- **`agents/panel-review-referee.md`** — the `2-way degrade` reference and the
  preflight description; mention both `CODEX`/`GEMINI` status lines.
- **`skills/panel-review-init/SKILL.md`** — update the preflight comment
  (`core (codex/jq/profile)` → reflect new gating), the `GEMINI: yes|no` tail (now
  also `CODEX: yes|no`), and **replace** the "Codex profile files are owned by
  `/codex-peer-review init` — do not write them here" note: Panel Review now owns
  `panel-review.config.toml`, auto-created by `run_codex`.

## Consequences / accepted trade-offs

- **Profile migration.** Existing users who tuned `peer-review.config.toml` will
  get a fresh default `panel-review.config.toml` and won't inherit that tuning.
  This is the intended decoupling; the auto-create makes it seamless (no manual
  step), and they can re-tune the new file. Accepted.
- Default model/effort values live in a shipped template file
  (`templates/default-panel-review.config.toml`), copied on first use. Editable on
  its own, no setup step.

## Affected files

- `skills/panel-review/scripts/preflight`
- `skills/panel-review/scripts/run_codex`
- `skills/panel-review/templates/default-panel-review.config.toml` (new)
- `README.md`
- `skills/panel-review-for-agent/SKILL.md`
- `agents/panel-review-referee.md`
- `skills/panel-review-init/SKILL.md`

## Testing

- `preflight` with: both peers present; only `codex`; only `agy`; neither
  (expect the single hard-fail); missing `jq`/`git`/non-writable cwd still fail.
  Verify the `CODEX:`/`GEMINI:` tail lines.
- `run_codex` with the profile absent: confirm it copies the template to
  `~/.codex/panel-review.config.toml` and runs; with it present: confirm it is not
  overwritten. Confirm the shipped template carries no exec bit after `install.sh`.
- Confirm a review with `codex` absent but `agy` present runs end-to-end 2-way and
  labels Codex as the down seat (not "fully vetted").
