# Agent skills

## Issue tracker

Issues are tracked as indexed Markdown files under `issues/`. See
`docs/agents/issue-tracker.md`.

## Triage labels

Local issues use the canonical triage roles in an optional `Triage:` field. See
`docs/agents/triage-labels.md`.

## Domain docs

This is a single-context repository with `CONTEXT.md` at the root and ADRs under `docs/adr/`. See
`docs/agents/domain.md`.

# What this repo is

`panel-review` is a **Claude Code plugin** (not an app) that runs a three-way **blind** code/design
review: Claude, OpenAI Codex (GPT, via the `codex` CLI), and Google Gemini (via the `agy` CLI) each
review the same scope independently, then re-argue each issue until they agree or hand it to the human.
There is no compiled artifact — the deliverable is the plugin tree itself (bash + Python wrappers,
Markdown skills/agents, prompt templates), installed into the user's Claude config dir.

`README.md` is the authoritative spec — keep it in sync when you change behavior. Per-script ownership
detail and the persistence model live in `.claude/rules/scripts.md` (loads when you edit the plugin
code).

## Install / "build" / run

There is no build or lint framework. Scripts are a mix of **bash and Python**. The Python scripts are
`birth_index`, `check_contracts`, `check_draft`, `decide_degraded_round`, `decide_round`,
`extract_block`, `index`, `merge_payload`, `parse_block`, `read_protocol_phase`,
`read_verdict_artifact`, `round`, `scope_diagnostics`, `seat_contract.py`, `stage_review_profile`, `user_config.py`,
`sweep`, and `write_seat_raw`;
`panel_common.py` is their shared library. The
remaining scripts are bash;
skills/agents are Markdown. `python3`, `jq`, `git` are required.

- **Install (two paths):**
  - `./install.sh` copies the tree into `~/.claude/skills/panel-review` (override with
    `CLAUDE_DIR=/path`). It replaces that plugin tree, sets exec bits on `scripts/*`, and warns about
    agent files that would *shadow* the plugin's. It leaves other loose skills and agents alone, so
    remove any reported stale agent files yourself. Run `/reload-plugins` afterward.
  - `.claude-plugin/marketplace.json` lets the repo double as its own local marketplace: `/plugin
    marketplace add /path` then `/plugin install panel-review@panel-review` (installs into
    `~/.claude/plugins/cache`, independent of `install.sh`'s target — keep both working).
- **Session requirement:** a review only runs in a session started with
  **`CLAUDE_CODE_FORK_SUBAGENT=0 claude`**. `preflight` hard-blocks otherwise, and it cannot be fixed
  from inside a running session. Fork mode (on by default interactively since 2.1.232) backgrounds
  every subagent and removes `run_in_background`, so the referee's blocking seat dispatch stops
  blocking. Rationale and measurements: README "Start the session with fork mode off" and
  `issues/archive/25-fork-mode-backgrounds-seat-agents.md`.
- **Run a review** (from inside the repo under review, after install):
  `panel-review:start --base main` | `--uncommitted` | `--commit <SHA>` | `"<question>"`. Other verbs:
  `:status` (read-only), `:resume`, `:continue [unresolved|contested]`, `:result <ID>` (read-only),
  `:discard`. See README
  "Using it" for flags (`--issue-rounds`, `--max-rounds`, `--debate-low`, `--instructions`).
- **Tests:** `./tests/run_tests.sh` (`VERBOSE=1` lists each PASS) runs bash asserts then the Python
  `unittest` suite (`tests/python/`, fixtures in `tests/fixtures/`). Run it after changing
  `seat_contract.py`, `panel_common.py`, `birth_index`, `extract_block`, `check_contracts`,
  `parse_block`, `decide_round`, `merge_payload`, `sweep`, `round`, `write_seat_raw`,
  `read_protocol_phase`, `read_verdict_artifact`, `user_config.py`,
  `hooks/enforce_agent_status_stub`, `index`'s `commit-sweep` validator, or the canonical protocol.
  Single module:
  `python3 -m unittest tests.python.test_index -v` from repo root.
- **Smoke-test a script** by running the wrapper directly, e.g. `scripts/preflight`,
  `scripts/resolve_diff <scope>`, `scripts/inspect_run --id <ID> --workdir "$PWD"` (standalone; need
  `jq` + `git`). Beyond the suite, verify by running an actual review.

## Architecture

Panel Review separates command skills, the non-reviewing referee, three independent review seats, and
script-owned state transitions. [`docs/architecture.md`](docs/architecture.md) is the reference for
component boundaries, saved-state ownership, and schemas. The canonical referee procedure is
`skills/panel-review-for-agent/references/protocol.md`.

## Hard constraints (from README — don't break)

- Seats called only via `run_codex` / `run_agy`, never raw. `run_codex` runs the sandbox bypassed
  (MCP/tilth + scratch); the code under review is protected by `repo_guard`, not the sandbox.
- Never hand-create/edit/delete `~/.codex/config.toml`; `run_codex` owns
  `~/.codex/panel-review.config.toml`.
- `index.json` written only via `index`/`sweep`; cards only via `project_card`/`regen_cards`.
- Seats are instructed to write nothing inside the repository under review — tracked or not, which
  rules out builds (`make`, `ninja`, `cargo build`, …); write-free checks are encouraged instead.
  Only the tracked half is enforced: `repo_guard snapshot` records the initial tracked
  tree and `verify --restore` detects and reverts honest tracked-file drift after every seat pass;
  reverted drift is flagged in the verdict's Process notes. This is restoration, not confinement: it
  does not protect untracked files or anything outside the repository
  (`issues/archive/57-seats-rebuild-the-repository-under-review.md`).
- Claude seat is spawned fresh (`panel-review:panel-review-claude-seat`), never forked.
- The referee persists the synthesized verdict artifact and returns **only** a fixed ready/failure
  stub — never the verdict body, raw seat output, card text, or per-round transcripts. The main
  conversation validates the artifact and reports its filename. No seat ever sees who raised a point
  or the stance tally (blindness).

## Design principles / trust model

- **No security theatre.** The three seats run **unconstrained by design** (`run_codex` bypasses the
  Codex sandbox, `run_agy` passes `--dangerously-skip-permissions`); safety rests on the **disposable
  container** plus `repo_guard` reverting *honest* tracked-file drift. A seat could, in principle, read
  or rewrite the prompts, scripts, another seat's raw output, the diff, or any hash meant to check them.
  Therefore **do not add guards that assume a tampering seat** — any such guard is defeatable by the
  same actor and is pure theatre (e.g. hash-verifying the diff file, read-attestation schemes, chmod as
  a "control"). Guards must target **honest accidents and model confusion** — prompt-size dilution, seat
  disorientation, misformatted output, a truncated read, the harness clobbering its own files — never
  malice. If a guard only works when the seat cooperates, label it a convenience, not a control.

## Runtime reference

[`docs/agent-runtimes.md`](docs/agent-runtimes.md) is the single reference for dated Claude Code,
Codex, and agy requirements, measurements, known limits, and upgrade probes. Read it before changing
runtime-facing behavior. [`docs/agents/external-cli-baselines.md`](docs/agents/external-cli-baselines.md)
records the changelog review cutoffs; a version probe alone does not advance them. Follow the README
for the required session launch settings.

## Conventions

- `${CLAUDE_PLUGIN_ROOT}` in SKILL.md files is substituted at skill-load time; it is **not** a runtime
  shell env var (empty in the shell). Keep the literal verbatim. Scripts find their own dir via
  `here="$(cd "$(dirname "$0")" && pwd)"`.
- `disable-model-invocation: true` prevents a skill from being preloaded into a subagent. For a
  skill intended only for agent preloading, use `user-invocable: false` instead.
- Bash scripts use `set -euo pipefail`; both bash and Python scripts validate run IDs through
  `panel_require_id` before touching any filesystem path.
- Never pipe a command that can fail into one that succeeds on empty input (e.g. `resolve_diff |
  diff_hash` — resolve to a file and check the exit code separately).
- Per user instructions (`~/.claude/CLAUDE.md`): do not commit or push unless explicitly asked.

# Important reference material

The commit each of these was last reviewed at is in `docs/agents/external-cli-baselines.md`. Read it
first when asked what changed in the external CLIs, and update it when you finish such a review.

Claude Code documentation: ~/github-repos-for-agents/claude-code-docs/
Codex: ~/github-repos-for-agents/codex/
Gemini, Antigravity (agy) - `CHANGELOG.md` at the repo root is the release record: ~/github-repos-for-agents/antigravity/
  The agy model-pin bug this repository works around is recorded in `issues/archive/20-agy-model-pin-contract.md`
  (measurements for agy 1.1.10 and 1.1.13); `tests/live/agy_model_binding.sh` re-checks it on demand.
Agent Skills standard: ~/github-repos-for-agents/agentskills/
