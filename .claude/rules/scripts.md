---
paths:
  - "scripts/**"
  - "tests/**"
---

# Editing the panel-review scripts

`README.md` is the authoritative spec. This rule is the quick map for editing the plugin scripts —
which script exclusively owns which concern. Keep README in sync when you change any contract here.
The persistence model these scripts read/write lives in `CLAUDE.md`.

## Scripts that own a concern (don't bypass these)

The referee never hand-rolls flags, writes, index math, or parsing — it calls these so operations are
byte-exact.

- `index` — the **only** writer of `/tmp/<ID>/index.json`; all state/flag/counter math lives here.
  `commit-sweep` applies a whole debate round atomically and idempotently (guarded by
  `committed_rounds`) and writes that round's inspection-only `audit/round-<N>.md` as a best-effort
  side effect. Never hand-write `index.json`.
- `decide_round` / `decide_degraded_round` — the **only** builders of normal and degraded debate
  `commit-sweep` payloads. They apply the Transitions table mechanically (stance counting, `bump`,
  `peer_reviewed`/`fully_vetted`, enum convergence, forced-terminal). Normal path carries evidence
  verbatim with no seat identity/tally (blind); degraded path does not promote evidence. They do **no**
  judgment: prose `claim` revisions and new-finding clustering come back as "advice" for the referee.
  They **validate** input (exactly one stance per engaged-seat × open-issue; no unknown/duplicate
  `_source`); a plain `support` endorses the issue *as stated* (enum change adopted only on full
  effective-value agreement).
- `sweep` — owns batch plans, parsing/expected-ID checkpoint admission, dropped-seat cleanup, and
  recovery plans. Don't reconstruct batch eligibility from raw files.
- `merge_payload` — folds the referee's addendum (synthesized claims, `add_issues`, fold-reopen) into
  the `decide_round` payload with the per-key semantics `commit-sweep` needs (`set_state` replace,
  `revise` field-merge, `set_flag` dedup). The referee must **never append** a second
  `set_state`/`revise` for one id — merge through here or `commit-sweep` rejects the round.
- `project_card` / `regen_cards` — the **only** way to render issue records → blind cards.
- `run_codex` / `run_agy` — the **only** way to call the Codex / Gemini seats; they pin the
  model/profile and the flags that let MCP/tilth run (`run_codex` bypasses the Codex sandbox, `run_agy`
  passes `--dangerously-skip-permissions`). Never call `codex`/`agy` raw.
- `repo_guard` — protects the code under review. `snapshot` records the tracked tree (a
  `git stash create` SHA + sha256 manifest) at the start; `verify --restore` after each seat pass
  reverts and reports tracked-file drift. Guards tracked content only — leaves untracked scratch and
  the `.panel-review/` cache alone.
- `run_seat` — dispatch/retry wrapper for the two **CLI** seats: dispatch → `parse_block` → one-shot
  `repair.tmpl` retry on a malformed block; prints the final parse status. The Claude seat is a
  subagent, not a CLI, so the referee drives it directly (never via `run_seat`).
- `check_draft` — the **seat-facing** pre-emit validator (spliced into prompts as `{{CHECK}}`; the
  referee never calls it). Thin wrapper over `parse_block --diagnose` — don't re-implement the
  finding/stance checks. Lets a seat catch bad items before emitting (closes `parse_block`'s
  silent-drop of individual malformed lines).
- `await_seats` — the barrier that owns CLI-seat waiting; runs every CLI seat concurrently (each via
  `run_seat`) in ONE job with a per-seat outer timeout, writes per-seat status + a combined `--done`
  summary. **Run it via the `panel-review-cli-barrier` Agent, never as a referee-backgrounded Bash
  job** — a background Agent reliably re-wakes the referee, a background Bash job does not (its
  completion is dropped and the referee stalls forever). The referee spawns two background Agents per
  pass (CLI barrier + Claude seat) for two reliable wakes; **no `date`/`ps`/`cat status.*`/narration
  turns between dispatch and the wakes.**
- `birth_index` — the **only** builder of the Round-0 `index.json` from the referee's clustered
  finding-to-issue map; assigns birth state/flags/`evaluated_by` by the birth-unanimity rule (referee
  still owns the clustering). Output installs via `index put`.
- `resolve_instructions` — resolves `manifest.instructions` for the deterministic verbatim/none cases;
  returns the compose sentinel (exit 3) for `auto` (the only case the referee composes).
- `resolve_diff` — the single place that turns a scope token into diff text; `diff_hash` hashes it.
- `assemble` — the **only** builder of a reviewer prompt: maps each `{{KEY}}` sentinel line to a file's
  bytes verbatim (whole-line, literal). `extract_block` is its inverse — pulls one fenced ` ```<tag> `
  block byte-exactly (`--present` distinguishes empty from missing). Never re-implement the fence
  scan/substitution inline.
- `reopen` — engine behind `panel-review:continue`: revives a finished run's leftover
  (`unresolved`/`contested`) issues via `index reopen` (bumps `run_epoch`, clears `committed_rounds`)
  then clears `/tmp/<ID>/sweeps/`. Counterpart to `init_run`.
- `write_card` / `write_verdict_artifact` — atomic-write CLIs over `panel_atomic_write`: one card;
  the durable verdict to the `/tmp/<ID>.md` sibling (best-effort — its failure must not block the
  verdict).
- `init_run` / `resume_check` / `cleanup` / `discard` / `inspect_run` / `set_limits` — run lifecycle
  and resume/diverged/stale classification. `PANEL_REVIEW_KEEP_TMP=true` makes `cleanup`/`discard` keep
  `/tmp/<id>/` (diagnostics) while still removing the workspace marker/cards/git-exclude.
- `_panel_common.sh` (bash) / `panel_common.py` (Python) — parallel shared-helper libs kept in sync:
  `panel_valid_id`/`panel_require_id` (ID validation guarding `rm -rf` paths), `panel_atomic_write`
  (temp + fsync + rename, `.bak` rotation), git-exclude helpers. Python scripts import
  `panel_common.py`; bash scripts source `_panel_common.sh`.
