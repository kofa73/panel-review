# CLAUDE.md

## What this repo is

`panel-review` is a **Claude Code plugin** (not an app) that runs a three-way **blind** code/design
review: Claude, OpenAI Codex (GPT, via the `codex` CLI), and Google Gemini (via the `agy` CLI) each
review the same scope independently, then re-argue each issue until they agree or hand it to the human.
There is no compiled artifact — the deliverable is the plugin tree itself (bash + Python wrappers,
Markdown skills/agents, prompt templates), installed into the user's Claude config dir.

`README.md` is the authoritative spec — keep it in sync when you change behavior. Per-script ownership
detail and the persistence model live in `.claude/rules/scripts.md` (loads when you edit the plugin
code).

## Install / "build" / run

There is no build or lint framework. Scripts are a mix of **bash and Python** (the debate-core scripts
— `index`, `decide_round`, `decide_degraded_round`, `merge_payload`, `parse_block`, `sweep` — are
Python; the rest bash); skills/agents are Markdown. `python3`, `jq`, `git` are required.

- **Install (two paths):**
  - `./install.sh` copies the tree into `~/.claude/skills/panel-review` (override with
    `CLAUDE_DIR=/path`). It removes the old pre-plugin layout, sets exec bits on `scripts/*`, and warns
    about agent files that would *shadow* the plugin's. Run `/reload-plugins` afterward.
  - `.claude-plugin/marketplace.json` lets the repo double as its own local marketplace: `/plugin
    marketplace add /path` then `/plugin install panel-review@panel-review` (installs into
    `~/.claude/plugins/cache`, independent of `install.sh`'s target — keep both working).
- **Run a review** (from inside the repo under review, after install):
  `panel-review:start --base main` | `--uncommitted` | `--commit <SHA>` | `"<question>"`. Other verbs:
  `:status` (read-only), `:resume`, `:continue [unresolved|contested]`, `:discard`. See README
  "Using it" for flags (`--issue-rounds`, `--max-rounds`, `--debate-low`, `--instructions`).
- **Tests:** `./tests/run_tests.sh` (`VERBOSE=1` lists each PASS) runs bash asserts then the Python
  `unittest` suite (`tests/python/`, fixtures in `tests/fixtures/`). Run it after changing
  `parse_block`, `decide_round`, `merge_payload`, `sweep`, `index`'s `commit-sweep` validator, or the
  SKILL debate loop. Single module: `python3 -m unittest tests.python.test_index -v` from repo root.
- **Smoke-test a script** by running the wrapper directly, e.g. `scripts/preflight`,
  `scripts/resolve_diff <scope>`, `scripts/inspect_run --id <ID> --workdir "$PWD"` (standalone; need
  `jq` + `git`). Beyond the suite, verify by running an actual review.

## Architecture

Four participants, strict role separation (full per-script map in `.claude/rules/scripts.md`):

- **Command skills** (`skills/{start,status,resume,continue,discard}/SKILL.md`) — run in the **main
  conversation**; parse args, check preconditions, dispatch the referee. `start`/`resume`/`continue`/
  `discard` are `disable-model-invocation: true` (human-triggered only, so the model never auto-wipes a
  session); `status` stays model-invocable.
- **Referee** (`agents/panel-review-referee.md`) — a **separate context** that orchestrates but
  **never reviews code**. Its procedure lives in the preloaded skill
  `skills/panel-review-for-agent/SKILL.md` (`user-invocable: false`), the single source of truth for
  the debate protocol.
- **Claude seat** (`agents/panel-review-claude-seat.md`) — a cold, no-memory reviewer subagent,
  **spawned fresh each pass, never forked** (a fork would inherit the referee's context and destroy
  blindness). Codex and Gemini seats are external CLIs.
- **CLI barrier** (`agents/panel-review-cli-barrier.md`) — a thin non-reviewing helper the referee
  spawns as a **background Agent** each pass to run `await_seats` and return when both CLI seats settle
  (a background Agent reliably re-wakes the referee; a background Bash job does not).
- **Wrapper scripts** (`scripts/`) — the referee never hand-rolls flags, writes, index math, or
  parsing; it calls these so operations are byte-exact. Prompt templates in `prompts/` are filled by
  `assemble` (whole-line literal substitution).

**Issue lifecycle** (README "How an issue moves"): each seat takes a `support` /
`support_with_revision` / `reject` **stance**; an issue is `open` → `accepted`/`rejected` when all
engaged seats agree, else `contested` (got a ≥2-seat review pass) or `unresolved` (never did) at the
round limit. Unanimity-or-human: no majority vote, no referee fact-checking inside the loop.

**Persistence model:** `/tmp/<ID>/` is the **single source of truth** (manifest, index, sweeps, raw
seat output, origins, audit). Cards under `<workdir>/.panel-review/<ID>/` are a regenerable,
git-excluded cache (kept so a seat in a constrained/read-only workspace can still read them); seats
write throwaway scratch under `.panel-review/<ID>/work/`. The per-workdir **marker** is the
`.panel-review/<ID>/` dir itself; `init_run` writes `/tmp` state first and the marker **last**, so a
marker always implies valid state. The verdict is also saved to `/tmp/<ID>.md` — a **sibling** of
`/tmp/<ID>/`, outside it so cleanup/discard never delete it. **Single-user, single-session:** one
workdir holds exactly one review; concurrent runs against the same workdir are unsupported by design.

## Hard constraints (from README — don't break)

- Seats called only via `run_codex` / `run_agy`, never raw. `run_codex` runs the sandbox bypassed
  (MCP/tilth + scratch); the code under review is protected by `repo_guard`, not the sandbox.
- Never hand-create/edit/delete `~/.codex/config.toml`; `run_codex` owns
  `~/.codex/panel-review.config.toml`.
- `index.json` written only via `index`/`sweep`; cards only via `project_card`/`regen_cards`.
- The code under review is never modified: `repo_guard snapshot` at the start, `verify --restore` after
  every seat pass; reverted drift is flagged in the verdict's Process notes.
- Claude seat is spawned fresh (`panel-review:panel-review-claude-seat`), never forked.
- The referee returns **only** the synthesized verdict — never raw seat output, card text, or per-round
  transcripts. No seat ever sees who raised a point or the stance tally (blindness).

## Conventions

- `${CLAUDE_PLUGIN_ROOT}` in SKILL.md files is substituted at skill-load time; it is **not** a runtime
  shell env var (empty in the shell). Keep the literal verbatim. Scripts find their own dir via
  `here="$(cd "$(dirname "$0")" && pwd)"`.
- Bash scripts use `set -euo pipefail`; both bash and Python scripts validate run IDs through
  `panel_require_id` before touching any filesystem path.
- Never pipe a command that can fail into one that succeeds on empty input (e.g. `resolve_diff |
  diff_hash` — resolve to a file and check the exit code separately).
- Per user instructions (`~/.claude/CLAUDE.md`): do not commit or push unless explicitly asked.

# Important reference material
Claude Code documentation: ~/github-repos-for-agents/claude-code-docs/
Agent Skills standard: ~/github-repos-for-agents/agentskills/
