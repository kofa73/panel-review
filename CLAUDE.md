# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

`panel-review` is a **Claude Code plugin** (not an app) that runs a three-way **blind** code/design
review: Claude, OpenAI Codex (GPT, via the `codex` CLI), and Google Gemini (via the `agy` CLI) each
review the same scope independently, then re-argue each issue until they agree or hand it to the
human. There is no compiled artifact — the deliverable is the plugin tree itself (bash wrappers,
Markdown skills/agents, prompt templates), installed into the user's Claude config dir.

`README.md` is the authoritative spec. When changing behavior, keep README.md in sync — it documents
contracts that future readers and the referee protocol depend on.

## Install / "build" / run

There is no build or lint framework. The scripts are bash; the skills/agents are Markdown. There
**is** a regression suite: `./tests/run_tests.sh` (plain bash + `jq`, self-contained fixtures under
`tests/fixtures/`) — run it after changing `parse_block`, `decide_round`, `merge_payload`, `index`'s
`commit-sweep` validator, or the SKILL debate loop.

- **Install (the only "build" step):** `./install.sh` copies the whole tree into `~/.claude/skills/panel-review`
  (override target with `CLAUDE_DIR=/path ./install.sh`). It removes the old pre-plugin layout, sets
  exec bits on `scripts/*`, and warns about project/user-level agent files that would *shadow* the
  plugin's agents. Run `/reload-plugins` (or restart Claude Code) afterward.
- **Run a review** (from inside the repo you want reviewed, after install):
  `panel-review:start --base main` | `--uncommitted` | `--commit <SHA>` | `"<question>"`.
  Other verbs: `panel-review:status` (read-only), `:resume`, `:continue [unresolved|contested]`,
  `:discard`. See README "Using it" for flags (`--issue-rounds`, `--max-rounds`, `--debate-low`,
  `--instructions`).
- **Smoke-testing a script change:** run the wrapper directly, e.g.
  `scripts/preflight`, `scripts/resolve_diff <scope>`, `scripts/diff_hash < file`,
  `scripts/inspect_run --id <ID> --workdir "$PWD"`. They are standalone and require `jq` + `git`.
- **Regression tests:** `./tests/run_tests.sh` (`VERBOSE=1` to list each PASS). Covers the debate
  pipeline (`parse_block` incl. `--diagnose`, `decide_round` through real `commit-sweep`,
  `merge_payload`, the empty-stances guard). Mints throwaway `/tmp/pr-test-*` ids and cleans up.

There is no single-test command because there are no automated tests; verify by exercising the
scripts and by running an actual review.

## Architecture

Four participants, strict role separation:

- **Command skills** (`skills/{start,status,resume,continue,discard}/SKILL.md`) — run in the **main
  conversation**. They parse args, check preconditions, and dispatch the referee. `start`/`resume`/
  `continue`/`discard` are `disable-model-invocation: true` (human-triggered only — critical so the
  model never auto-wipes a session); `status` stays model-invocable.
- **Referee** (`agents/panel-review-referee.md`) — a **separate context** that orchestrates but
  **never reviews code**. Its full procedure lives in the preloaded skill
  `skills/panel-review-for-agent/SKILL.md` (`user-invocable: false`), which is the single source of
  truth for the debate protocol.
- **Claude seat** (`agents/panel-review-claude-seat.md`) — a cold, no-memory reviewer subagent,
  **spawned fresh each pass, never forked** (a fork would inherit the referee's context and destroy
  blindness). Codex and Gemini seats are external CLIs.
- **Wrapper scripts** (`scripts/`) — the referee never hand-rolls flags, writes, index math, or
  parsing; it calls these so operations are byte-exact. Prompt templates are in `prompts/`
  (`blind_pass.tmpl`, `debate.tmpl`, `repair.tmpl`); the Codex profile default is `assets/default-panel-review.config.toml`.

**Issue lifecycle** (see README "How an issue moves"): each seat takes a `support` /
`support_with_revision` / `reject` **stance**; an issue is `open` → `accepted` / `rejected` when all
engaged seats agree, else `contested` (got a ≥2-seat review pass) or `unresolved` (never did) at the
round limit. Unanimity-or-human: no majority vote, no referee fact-checking inside the loop.

### Scripts that own a concern (don't bypass these)

- `index` — the **only** writer of `/tmp/<ID>/index.json`. State/flag/counter math lives here;
  `commit-sweep` applies a whole debate round atomically and idempotently (guarded by
  `committed_rounds`), and writes that round's inspection-only `audit/round-<N>.md` trail as a
  best-effort side effect (the referee no longer hand-writes the audit trail). Never hand-write `index.json`.
- `decide_round` / `decide_degraded_round` — the **only** builders of normal and degraded debate
  `commit-sweep` payloads. They apply the
  Transitions table mechanically (stance counting, `bump`, `peer_reviewed`/`fully_vetted`, enum
  convergence, forced-terminal). The normal path carries evidence verbatim with no seat identity/tally
  (blind); the degraded path does not promote evidence. They do **no** judgment: prose `claim`
  revisions and new-finding clustering come back as "advice"
  for the referee to resolve. Don't hand-build the payload; the referee only adds `add_issues` +
  synthesized claims to it. It **validates** its input (exactly one stance per engaged-seat ×
  open-issue; no unknown/duplicate `_source`) and a plain `support` is read as endorsing the issue
  *as stated* (an enum change is adopted only on full effective-value agreement).
- `sweep` — owns batch plans, parsing/expected-ID checkpoint admission, dropped-seat cleanup, and
  recovery plans. Do not reconstruct batch eligibility from raw files.
- `merge_payload` — folds the referee's addendum (synthesized claims, `add_issues`, fold-reopen)
  into the `decide_round` payload with the per-key semantics `commit-sweep` needs (`set_state`
  replace, `revise` field-merge, `set_flag` dedup). The referee must **never append** a second
  `set_state`/`revise` for one id — that makes `commit-sweep` reject the round; merge through here.
- `project_card` / `regen_cards` — the **only** way to render issue records → blind cards.
- `run_codex` / `run_agy` — the **only** way to call the Codex / Gemini seats (they pin the
  model/profile, and the flags that let MCP/tilth run: `run_codex` bypasses the Codex sandbox,
  `run_agy` passes `--dangerously-skip-permissions`). Never call `codex` or `agy` raw.
- `repo_guard` — protects the **code under review**. `snapshot` records the tracked tree (a
  `git stash create` SHA + sha256 manifest) at the start; `verify --restore` after each seat pass
  reverts and reports any tracked-file drift. Replaces the per-seat read-only sandbox (seats now write
  scratch); it guards tracked content only, leaving untracked scratch and the `.panel-review/` cache alone.
- `run_seat` — dispatch/retry wrapper for the two **CLI** seats (Codex, Gemini): dispatch →
  `parse_block` → one-shot `repair.tmpl` retry on a malformed block; prints the final parse status.
  The Claude seat is a subagent, not a CLI, so the referee drives it directly (never via `run_seat`).
- `birth_index` — the **only** builder of the Round-0 `index.json` from the referee's clustered
  finding-to-issue map; assigns birth state/flags/`evaluated_by` by the birth-unanimity rule (the
  referee still owns the clustering judgment). Output installs via `index put`.
- `resolve_instructions` — resolves `manifest.instructions` for the deterministic verbatim/none
  cases; returns the compose sentinel (exit 3) for `auto` (the only case the referee composes).
- `resolve_diff` — the single place that turns a scope token into diff text; `diff_hash` hashes it.
- `init_run` / `resume_check` / `cleanup` / `discard` / `inspect_run` / `set_limits` — run lifecycle
  and the resume/diverged/stale classification. `PANEL_REVIEW_KEEP_TMP=true` makes `cleanup`/`discard`
  keep `/tmp/<id>/` (diagnostics) while still removing the workspace marker/cards/git-exclude.
- `_panel_common.sh` — sourced (not executable) shared helpers: `panel_valid_id` (ID validation
  guarding `rm -rf` paths), `panel_atomic_write` (temp + fsync + rename, `.bak` rotation), git-exclude
  helpers.

### Persistence model

`/tmp/<ID>/` is the **single source of truth** (manifest, index, sweeps, raw seat output, origins,
audit); cards under `<workdir>/.panel-review/<ID>/` are a regenerable cache (kept in the repo so any
seat running in a constrained/sandboxed workspace — e.g. an externally-imposed read-only mount — can
read them; git-excluded). Seats also write throwaway scratch under `.panel-review/<ID>/work/` (a
git-ignored subtree of the marker, removed with it at cleanup). The per-workdir **marker** is the
`.panel-review/<ID>/` dir itself. `init_run` writes `/tmp` state first and the marker **last**, so a
marker always implies valid state. The verdict is also saved to `/tmp/<ID>.md` — a **sibling** of
`/tmp/<ID>/`, deliberately outside it so cleanup/discard never delete it.

**Single-user, single-session:** one workdir holds exactly one review; concurrent runs against the
same workdir are unsupported by design.

## Hard constraints (from README — don't break)

- Seats called only via `run_codex` / `run_agy`, never raw. `run_codex` runs the sandbox bypassed
  (MCP/tilth + scratch); the code under review is protected by `repo_guard`, not the sandbox.
- Never hand-create/edit/delete `~/.codex/config.toml`; `run_codex` owns
  `~/.codex/panel-review.config.toml`.
- `index.json` written only via `index`/`sweep`; cards only via `project_card`/`regen_cards`.
- The code under review is never modified: `repo_guard snapshot` at the start, `verify --restore`
  after every seat pass; reverted drift is flagged in the verdict's Process notes.
- Claude seat is spawned fresh (`panel-review:panel-review-claude-seat`), never forked.
- The referee returns **only** the synthesized verdict — never raw seat output, card text, or
  per-round transcripts. No seat ever sees who raised a point or the stance tally (blindness).

## Conventions

- `${CLAUDE_PLUGIN_ROOT}` in SKILL.md files is substituted at skill-load time; it is **not** a
  runtime shell env var (it is empty in the shell). Keep the literal verbatim — don't read it at
  runtime. Scripts find their own dir via `here="$(cd "$(dirname "$0")" && pwd)"`.
- All scripts use `set -euo pipefail` and validate run IDs through `panel_require_id` before touching
  any filesystem path. Never pipe a command that can fail into one that succeeds on empty input (the
  README/skills call this out repeatedly, e.g. `resolve_diff | diff_hash` — resolve to a file and
  check the exit code separately).
- Per user instructions (`~/.claude/CLAUDE.md`): do not commit or push unless explicitly asked.
</content>
</invoke>
