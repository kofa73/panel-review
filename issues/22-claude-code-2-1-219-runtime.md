# Record the Claude Code 2.1.219+ runtime constraints

Priority: 22

Status: Pending

Source: Claude Code documentation review (2.1.215 → 2.1.222), 2026-08-05; extended with the
2.1.223 → 2.1.233 review, 2026-08-15 (see section 5)

Triage: ready-for-agent

## Problem

Issue 17 aligned the Agent and Bash contracts with Claude Code 2.1.215. Three runtime facts have
appeared since, one of which can stop panel-review from running at all, and none of which is
recorded anywhere in the repository.

Successor to issue 17. This is documentation work: no executable contract changes.

## 1. Nested subagent spawning has a version floor and an off switch

`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` is the number of subagent layers allowed below the main
conversation. In **2.1.217 and 2.1.218 its default was 1**, which forbids a subagent from spawning
its own subagents; **2.1.219 raised the default to 3**.

Panel-review's referee is itself a subagent and spawns both the Claude seat and the CLI barrier, so
it needs at least two layers. On those two releases the plugin cannot work with default settings,
and on any release a user or an organization that sets the variable to `1` breaks it the same way.

`README.md` currently says only "use the latest version of Claude Code — panel-review spawns nested
subagents". That is true but does not name the floor or the setting, so a user who hits the failure
has nothing to search for.

Expected: `README.md`'s requirements note names the concrete floor (2.1.219 or later for the default
to suffice) and names `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` as the setting that must allow at least
two layers.

Rejected alternative: a `scripts/preflight` version check. Preflight cannot read the effective
setting, `claude` need not be on `PATH` inside every install, and parsing a version string to
hard-fail a run trades a clear runtime error for a brittle gate. Documentation is the proportionate
fix.

## 2. The Claude seat inherits the session's extended-thinking setting

Since 2.1.198 a subagent inherits the main conversation's extended-thinking configuration, and there
is no per-subagent thinking field — `effort:` is pinnable in agent frontmatter (the seat already
pins `xhigh`), thinking on/off is not.

Consequence for a blind panel: the Claude seat's reasoning depth varies with the operator's session
toggle (`Alt+T`, or `alwaysThinkingEnabled` in settings), while the Codex and Gemini seats are
unaffected. The same review run by two people, or by one person on two days, is not necessarily the
same Claude seat. That is a real asymmetry in a design whose whole point is three comparable
independent reviews.

Expected: one entry in `AGENTS.md` "Non-obvious facts (hard-won)" stating the inheritance, the
absent per-subagent control, and the resulting variance. No code change — there is nothing to pin.

## 3. The `opus` alias moved to a different model

2.1.219 made `claude-opus-5` the default `opus`, so `agents/panel-review-referee.md` and
`agents/panel-review-claude-seat.md` silently changed model. Nothing is tuned to a specific Opus
version, so nothing breaks; the effect is that the measurements in
`issues/referee-context-cost-history.md` and issue 10's baseline were taken on a different model
than the one now running.

Expected: a dated line in `issues/referee-context-cost-history.md` and in issue 10 recording which
model the existing numbers describe, so a future comparison is not made against them by accident.

Explicitly **not** a reason to re-measure now, and **not** a context-window change: Opus has
supported the 1M window since 4.6, and 4.7 and later always run with it on the Anthropic API.

## 4. Trap worth recording: `disable-model-invocation` blocks subagent preloading

`disable-model-invocation: true` also prevents a skill from being preloaded into a subagent. The
referee's protocol skill `skills/panel-review-for-agent/SKILL.md` correctly uses
`user-invocable: false` for the same "humans don't call this" intent. "Hardening" it to
`disable-model-invocation` would silently break the referee's preload.

Expected: one line in `AGENTS.md` "Conventions" next to the `${CLAUDE_PLUGIN_ROOT}` entry.

## Verified on 2.1.222 (2026-08-05) — no action needed

- `claude plugin validate . --strict` passes, including the marketplace-name warnings added in
  2.1.221.
- The `SubagentStop` matcher, `${CLAUDE_PLUGIN_ROOT}` substitution, plugin-scoped agent names, and
  the eight-consecutive-continuation stop-hook cap described in `AGENTS.md` are all still accurate.
- Subagent frontmatter still supports every field the three agent files use (`model`, `effort`,
  `tools`, `color`, `skills`).

## 5. Additions from the 2.1.223 → 2.1.233 review (2026-08-15)

Documentation-only leftovers from the next docs review. The blocking finding from that review —
fork mode backgrounding the seat Agents — is its own ticket, **issue 25**, because it can stop a run
from working; the stale spawn-budget guidance is **issue 26**.

- **A restricted subagent model falls back to the parent model.** 2.1.223 added a warning when a
  requested subagent model is restricted and the parent model runs instead. Both
  `agents/panel-review-referee.md` and `agents/panel-review-claude-seat.md` pin `opus`, so under an
  organization model restriction the Claude seat can silently run a different model than the pin
  says. Record next to item 3; there is nothing to enforce from inside the plugin.
- **Background subagents keep a reduced built-in tool set.** A background subagent keeps every MCP
  tool but only `Read`, `Grep`, `Glob`, `Bash`, `Edit`, `Write`, `WebFetch`, `WebSearch`, `Skill`,
  `ToolSearch`, `Monitor`, `SendMessage`, `Artifact` and a few others. The Claude seat's declared
  tools all survive that filter, so tool availability is **not** a blocker for issue 25 — only the
  blocking-return semantics are.
- **Task/todo tools are gone on current models.** 2.1.233 removed `TaskCreate`/`TaskGet`/
  `TaskUpdate`/`TaskList`/`TodoWrite` from Opus 4.8, Sonnet 5, Fable 5, Mythos 5 and newer.
  The referee's "Progress reporting" section did call `TaskCreate`; that section was deleted
  by `issues/41-referee-taskcreate-instructions-are-dead.md`, so the tree no longer uses any of
  them. Recorded so the absence is not investigated again.
- **Skill argument substitution no longer re-expands argument values as template markers**
  (2.1.233). Relevant to `panel-review:start "<question>"`, where a question containing something
  like `${CLAUDE_PLUGIN_ROOT}` could previously be re-expanded. Upstream fix, no action.

## Verification

- `README.md` names the version floor and the environment variable; the existing "use the latest
  Claude Code" advice is kept, not replaced.
- Each new fact appears exactly once; `scripts/check_contracts --root .` passes.
- `./tests/run_tests.sh` and `git diff --check` pass.

## Non-goals

- Do not add a runtime version or environment check to `preflight`.
- Do not change any agent or skill frontmatter.
- Do not re-run the referee cost measurements as part of this issue.

## 6. Additions from the 2.1.240 → 2.1.261 review (2026-09-05)

Baseline reviewed: `docs/agents/external-cli-baselines.md` records 2.1.239; installed is **2.1.261**.
Facts below are documentation-only for this issue; the ones that need work of their own are filed
separately and named.

**Subagent model resolution changed under the panel.** Before 2.1.251, `CLAUDE_CODE_SUBAGENT_MODEL`
overrode both a per-spawn model and an agent definition's `model:` field. From 2.1.251 it is only a
*default*, and the definition's `model:` and an explicit per-spawn model take precedence. New
`CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1` (2.1.257+) restores the old override behavior for every
subagent. This matters to the panel in both directions: the seat and referee agents pin
`model: opus` in their own frontmatter, so on 2.1.251+ that pin now wins by default — but a user who
sets `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` silently overrides the Claude seat's model and makes results
incomparable between runs, exactly the failure the model pins exist to prevent. Worth a `preflight`
line in the same spirit as `issues/62`, or at minimum a README note.

**Prompt-cache TTL is now configurable for subagents.** `subagentPromptCacheTtl` /
`CLAUDE_CODE_SUBAGENT_PROMPT_CACHE_TTL` (`5m` or `1h`, 2.1.242+), plus per-agent
`experimental.cacheTtl` in agent frontmatter. Relevant to `issues/09` and the referee context-cost
record: the referee is spawned once and runs for the whole review, so a 1-hour subagent TTL changes
the cost profile of a long panel. Measure before adopting — 1-hour cache *writes* bill higher.

**Output-size settings replaced the env vars.** `bashOutputMaxChars` (up to 128K) supersedes
`BASH_MAX_OUTPUT_LENGTH`, and `taskOutputMaxChars` supersedes `TASK_MAX_OUTPUT_LENGTH`; when the
setting is present the variable is ignored. Any guidance the panel gives about seat or barrier
output limits should name the settings first.

**`maxTurns` returns are now marked partial (2.1.246+).** A subagent that hits its `maxTurns` limit
returns its output "marked as partial, with a hint to continue it via `SendMessage`", instead of
appearing finished. No panel agent sets `maxTurns`, so this is latent — but if one ever does, a
partial return is a non-exact status stub and the `SubagentStop` hook (`issues/13`) will block it.
Record the interaction rather than adding a guard for a configuration the plugin does not ship.

**`--append-subagent-system-prompt-file` (2.1.261)** reads a subagent system prompt from a file, for
prompts too large for the command line. Not needed — the panel delivers seat prompts as task text,
not as system-prompt appendices — but it is the flag to reach for if prompt size ever forces a
change (see the prompt-size fact in `AGENTS.md`).

**Plugin component paths that are symlinks are now refused (in the 2.1.240–2.1.261 range):** "Fixed
plugins being able to read files outside their own directory through a declared command, agent,
skill, hooks or other component path that is a symlink; such paths are now refused with an error."
This is host-side evidence for `issues/40` — the harness now does its own symlink refusal on the
plugin tree — but it does not touch `panel_atomic_write`, which guards *run state* under `/tmp`, not
plugin components. It does not settle that issue; it only narrows what the plugin has to worry about.

**`${CLAUDE_PLUGIN_ROOT}` in hook error messages is now resolved** rather than printed literally.
Cosmetic, but it means a hook failure report from `hooks/enforce_agent_status_stub` will now name a
real path.

**Confirms `issues/26`.** The current `docs/sub-agents.md` still names the error `Concurrent
subagent limit reached` (20 concurrent subagents by default,
`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`), not the `Subagent spawn limit reached` wording README and
`check_contracts` still pin. Re-confirmed at 2.1.261; that issue's fix is still needed.

**Filed separately from this review:** `issues/62` (reads outside the working directories can be
blocked outright, 2.1.257+) and the update to `issues/43` (the 60-minute subagent background-shell
cap may have been removed in 2.1.260, with the docs contradicting the changelog).
