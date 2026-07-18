# Agent skills

## Issue tracker

Issues are tracked as indexed Markdown files under `pending-issues/`. See
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
`check_contracts`, `check_draft`, `decide_degraded_round`, `decide_round`, `index`, `merge_payload`,
`parse_block`, `read_protocol_phase`, `read_verdict_artifact`, `round`, `seat_contract.py`, `sweep`,
and `write_seat_raw`; `panel_common.py` is their shared library. The remaining scripts are bash;
skills/agents are Markdown. `python3`, `jq`, `git` are required.

- **Install (two paths):**
  - `./install.sh` copies the tree into `~/.claude/skills/panel-review` (override with
    `CLAUDE_DIR=/path`). It removes the old pre-plugin layout, sets exec bits on `scripts/*`, and warns
    about agent files that would *shadow* the plugin's. Run `/reload-plugins` afterward.
  - `.claude-plugin/marketplace.json` lets the repo double as its own local marketplace: `/plugin
    marketplace add /path` then `/plugin install panel-review@panel-review` (installs into
    `~/.claude/plugins/cache`, independent of `install.sh`'s target — keep both working).
- **Run a review** (from inside the repo under review, after install):
  `panel-review:start --base main` | `--uncommitted` | `--commit <SHA>` | `"<question>"`. Other verbs:
  `:status` (read-only), `:resume`, `:continue [unresolved|contested]`, `:result <ID>` (read-only),
  `:discard`. See README
  "Using it" for flags (`--issue-rounds`, `--max-rounds`, `--debate-low`, `--instructions`).
- **Tests:** `./tests/run_tests.sh` (`VERBOSE=1` lists each PASS) runs bash asserts then the Python
  `unittest` suite (`tests/python/`, fixtures in `tests/fixtures/`). Run it after changing
  `seat_contract.py`, `check_contracts`, `parse_block`, `decide_round`, `merge_payload`, `sweep`,
  `round`, `write_seat_raw`, `read_protocol_phase`, `read_verdict_artifact`,
  `hooks/enforce_agent_status_stub`, `index`'s `commit-sweep` validator, or the canonical protocol.
  Single module:
  `python3 -m unittest tests.python.test_index -v` from repo root.
- **Smoke-test a script** by running the wrapper directly, e.g. `scripts/preflight`,
  `scripts/resolve_diff <scope>`, `scripts/inspect_run --id <ID> --workdir "$PWD"` (standalone; need
  `jq` + `git`). Beyond the suite, verify by running an actual review.

## Architecture

Four participants — three review seats and one referee — with strict role separation and supporting
command/orchestration layers (full per-script map in `.claude/rules/scripts.md`):

- **Command skills** (`skills/{start,status,resume,continue,result,discard}/SKILL.md`) — run in the **main
  conversation**; parse args, check preconditions, dispatch the referee. `start`/`resume`/`continue`/
  `discard` are `disable-model-invocation: true` (human-triggered only, so the model never auto-wipes a
  session); the read-only `status` and `result` stay model-invocable.
- **Referee** (`agents/panel-review-referee.md`) — a **separate context** that orchestrates but
  **never reviews code**. Its preloaded skill `skills/panel-review-for-agent/SKILL.md`
  (`user-invocable: false`) loads only the active marked phase from the canonical protocol through
  `read_protocol_phase`.
- **Claude seat** (`agents/panel-review-claude-seat.md`) — a cold, no-memory reviewer subagent,
  **spawned fresh each pass, never forked** (a fork would inherit the referee's context and destroy
  blindness). It atomically writes its validated raw block through `write_seat_raw` and returns only
  a fixed status stub. A plugin `SubagentStop` hook blocks non-exact returns and asks the same
  subagent to correct them; Claude Code's eight-block cap makes this bounded conformance enforcement,
  not an absolute security boundary. Codex and Gemini seats are external CLIs.
- **CLI barrier** (`agents/panel-review-cli-barrier.md`) — a thin non-reviewing helper the referee
  spawns as a **background Agent** each pass to run `await_seats` and return when both CLI seats settle
  (a background Agent reliably re-wakes the referee; a background Bash job does not).
- **Wrapper scripts** (`scripts/`) — the referee never hand-rolls flags, writes, index math, or
  parsing; it calls these so operations are byte-exact. The coarse `round` module owns normal-path
  preparation, collection, commit, and verdict input. `seat_contract.py` owns seat fields, stance
  values, phase block cardinality, validation, and the rendered instruction fragments. Prompt
  templates in `prompts/` are filled by `assemble` (whole-line literal substitution).

**Issue lifecycle** (README "How an issue moves"): each seat takes a `support` / `reject` **stance**;
support may independently propose revised issue fields. An issue is `open` → `accepted`/`rejected` when all
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
- Seats are instructed not to modify tracked code. `repo_guard snapshot` records the initial tracked
  tree and `verify --restore` detects and reverts honest tracked-file drift after every seat pass;
  reverted drift is flagged in the verdict's Process notes. This is restoration, not confinement: it
  does not protect untracked files or anything outside the repository.
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

## Non-obvious facts (hard-won)

- **Seat working directory.** The Claude seat (a referee subagent) and the Codex seat (`run_codex` →
  `codex exec`) both inherit the referee's cwd = workdir (repo root). **agy is the exception**: it runs
  its tools inside its own managed sandbox (`~/.gemini/antigravity-cli/scratch`) and *guesses* the repo
  root each run — `cd`-ing the wrapper cannot move it. So an agy prompt needs an **absolute** path
  anchor (and ideally an explicit "set the tool `cwd` to `<workdir>`" directive) or it can drift
  (observed: anchored `/home/developer` instead of the workdir under a very large prompt).
- **Seat engagement is per-round, not sticky.** `--configured` = the fixed `preflight` panel;
  `--engaged` = whoever returned a parseable block *this pass* (`parse_block` exit 0). Every configured
  seat is re-dispatched every round; a seat that fails or times out one round is retried the next. The
  only persistent effect of a down-round is the informational `fully_vetted=false` label (never
  re-flipped). "Down" means down *for that pass*, not excluded from the run.
- **CLI salvage is referee-owned.** `run_seat` dispatches and parses but never repairs or re-dispatches
  a seat. On parse status 4 (missing block) or 5 (malformed block), the referee may salvage a genuine
  completed CLI review without changing its conclusions. Debate salvage re-emits both required blocks
  to the canonical `.salvaged` side file and installs it through `round salvage-debate`, so the
  original raw is never overwritten. A failed Claude delivery is retried or dropped instead because
  `write_seat_raw` validates the complete response before installation.
- **Prompt size correlates with agy prose-not-JSONL failures.** Empirically, `round0.prompt` >~99 KB
  (a huge inlined diff diluting attention, contract buried at the end) yielded prose-without-fence from
  the Gemini seat; ≤~87 KB yielded valid blocks. Not code-proven, but keep prompts lean and the output
  contract salient.

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
