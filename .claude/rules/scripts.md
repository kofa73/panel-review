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
  side effect. Its read-only `delivery-status` owns low-gate/leftover classification and reports the
  exact index hash used to reject a stale same-epoch report snapshot. Never hand-write `index.json`.
- `decide_round` / `decide_degraded_round` — the **only** builders of normal and degraded debate
  `commit-sweep` payloads. They apply the Transitions table mechanically (stance counting, `bump`,
  `peer_reviewed`/`fully_vetted`, enum convergence, forced-terminal). Normal path carries evidence
  verbatim with no seat identity/tally (blind); degraded path does not promote evidence. They do **no**
  judgment: prose `claim` revisions and new-finding clustering come back as "advice" for the referee.
  They **validate** input (exactly one canonical `support`/`reject` stance per engaged-seat ×
  open-issue; reject rationale present; no unknown/duplicate `_source`); `support` affirms issue
  existence and may independently propose revised fields (enum
  change adopted only on full effective-value agreement). Exact no-op revisions do not mutate the
  issue or promote their rationale.
- `sweep` — owns batch plans, including generating the common single-batch shape from open issue IDs
  and the referee-supplied current panel; reports the exact rejected plan field, safely extends an
  interrupted common plan by adding unplanned seats or reactivating already-planned dropped seats
  that return to the current panel, and owns two-block parsing/expected-ID complete checkpoint
  admission, source provenance, dropped-seat cleanup, and recovery plans. A batch is
  complete only when its retained raw, exact-ID stances, parsed `new_findings`, zero parse status,
  expected IDs, and source record were installed together. A published `.out` completion marker with
  any missing companion is corrupt and fails closed. Don't reconstruct batch eligibility from raw
  files or hand-write the common plan.
- `round` — the referee's coarse normal-path module over the owners in this list. It resolves and
  assembles Round 0, prepares the common one-batch debate, collects compact engagement/guard status,
  installs a canonical CLI debate side file through `salvage-debate`, selects only complete
  active-plan batches for the normal or degraded decision and atomic commit with an optional referee
  addendum, and renders stable verdict input. It does not absorb judgment: clustering, prose-claim
  resolution, new-finding folds, and verdict prose remain with the referee.
- `merge_payload` — folds the referee's addendum (synthesized claims, `add_issues`, conditional
  fold-reopen) into the `decide_round` payload with the per-key semantics `commit-sweep` needs
  (`set_state` replace, `revise` field-merge, `set_flag` dedup). It does not decide whether folded
  evidence materially conflicts with the current outcome; that judgment remains with the referee.
  The referee must **never append** a second
  `set_state`/`revise` for one id — merge through here or `commit-sweep` rejects the round. A
  mis-shaped addendum (e.g. a `revise` entry with a flat `claim` instead of the `fields` wrapper) is a
  hard error (**exit 2** + message), not a traceback — so the SKILL's `> tmp && mv tmp payload` guard
  leaves the good `decide_round` payload untouched instead of committing an empty round.
- `project_card` / `regen_cards` — the **only** way to render issue records → blind cards.
- `run_codex` / `run_agy` — the **only** way to call the Codex / Gemini seats; they pin the
  model/profile and the flags that let MCP/tilth run (`run_codex` bypasses the Codex sandbox, `run_agy`
  passes `--dangerously-skip-permissions`). Never call `codex`/`agy` raw.
- `repo_guard` — protects the code under review. `snapshot` records the tracked tree (a
  `git stash create` SHA + sha256 manifest) at the start; `verify --restore` after each seat pass
  reverts and reports tracked-file drift. Guards tracked content only — leaves untracked scratch and
  the `.panel-review/` cache alone.
- `run_seat` — dispatch wrapper for the two **CLI** seats: dispatch → `parse_block`; prints the parse
  status. **It does not repair.** Salvaging a slipped block (a malformed fence, or a real review the
  seat forgot to fence) is referee-owned — the seat that wrote it has exited, so any re-dispatch is a
  fresh cold model with the same on-disk input the referee has, and judging stub-vs-review is an LLM
  call, not a grep heuristic (see SKILL "Salvage"). The Claude seat is a subagent, not a CLI, so the
  referee drives it directly (never via `run_seat`).
- `check_draft` — the **seat-facing** pre-emit validator (spliced into prompts as `{{CHECK}}`; the
  referee never calls it). Thin wrapper over `parse_block --diagnose` — don't re-implement the
  finding/stance checks. Lets a seat catch bad items before emitting (closes `parse_block`'s
  silent-drop of individual malformed lines).
- `write_seat_raw` — the Claude seat's sole write outside its scratch directory. It derives the
  expected Round-0 or debate raw path from a validated run ID/round/batch, requires every requested
  fenced block to pass `parse_block --diagnose`, and only then atomically installs the complete raw
  response. It never accepts an arbitrary destination path.
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
- `read_protocol_phase` — the referee's lazy protocol interface. It emits one marked section from the
  single canonical `references/protocol.md`, so inactive branches stay out of context without
  duplicating protocol prose across files.
- `reopen` — engine behind `panel-review:continue`: revives a finished run's leftover
  (`unresolved`/`contested`) issues via `index reopen` (bumps `run_epoch`, clears `committed_rounds`)
  then clears `/tmp/<ID>/sweeps/`. Counterpart to `init_run`.
- `write_card` / `write_verdict_artifact` — atomic-write CLIs over `panel_atomic_write`: one card;
  the durable verdict to the `/tmp/<ID>.md` sibling. Because that file is the only final-report
  delivery surface, artifact failure keeps the run resumable and blocks cleanup. The verdict writer
  stamps the continuation epoch and whether the canonical index was finished or incomplete;
  `start -- Finish here` uses its explicit `--final` mode before cleanup.
- `read_verdict_artifact` — validates the durable artifact's ID, metadata, and optional expected
  scope/diff hash/continuation epoch. Its default mode requires a finished artifact and emits the
  verdict body for `panel-review:result <ID>`; `--delivery` verifies any retained index through
  `index delivery-status`, then emits only the fixed filename plus minimal gate/continuation status.
  It is the sole final-return interface for `start`/`resume`/`continue`.
- `init_run` / `resume_check` / `cleanup` / `discard` / `inspect_run` / `set_limits` — run lifecycle
  and resume/diverged/stale classification. `PANEL_REVIEW_KEEP_TMP=true` makes `cleanup`/`discard` keep
  `/tmp/<id>/` (diagnostics) while still removing the workspace marker/cards/git-exclude.
- `_panel_common.sh` (bash) / `panel_common.py` (Python) — parallel shared-helper libs kept in sync:
  `panel_valid_id`/`panel_require_id` (ID validation guarding `rm -rf` paths), `panel_atomic_write`
  (temp + fsync + rename, `.bak` rotation), git-exclude helpers. Python scripts import
  `panel_common.py`; bash scripts source `_panel_common.sh`.
