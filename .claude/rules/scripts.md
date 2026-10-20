---
paths:
  - "bin/**"
  - "scripts/**"
  - "hooks/**"
  - "tests/**"
---

# Editing the panel-review scripts

`README.md` is the authoritative spec. This rule is the quick map for editing the plugin scripts —
which script exclusively owns which concern. Keep README in sync when you change any contract here.
The persistence model these scripts read/write lives in `CLAUDE.md`.

## Scripts that own a concern (don't bypass these)

The referee never hand-rolls flags, writes, index math, or parsing — it calls these so operations are
byte-exact.

- `bin/panel-review-session` — the shell entry point for a review session. It resolves the plugin
  root through PATH symlinks, sets fork mode off for preflight and Claude, calls `preflight`, reports
  only saved `.panel-review/<ID>/` directories with a `.panel-run` marker file, and then execs Claude.
  It does not duplicate prerequisite checks.
- `index` — the **only** writer of `/tmp/<ID>/index.json`; all state/flag/counter math lives here.
  `put` installs the Round-0 index. `commit-sweep` applies a whole debate round atomically and
  idempotently (guarded by `committed_rounds`) and writes that round's inspection-only
  `audit/round-<N>.md` as a best-effort side effect. `reopen` starts a new debate epoch. No
  per-field mutation command bypasses those paths. Its read-only `delivery-status` owns
  low-gate/leftover classification and reports the exact index hash used to reject a stale
  same-epoch report snapshot. Never hand-write `index.json`.
- `decide_round` / `decide_degraded_round` — the **only** builders of normal and degraded debate
  `commit-sweep` payloads. They apply the Transitions table mechanically (stance counting, `bump`,
  `peer_reviewed`/`fully_vetted`, enum convergence, forced-terminal). Normal path carries evidence
  verbatim, withholding (never failing on) the one string that states a reviewer tally or their
  agreement and reporting it as `withheld_text` advice — the rest of blindness is referee judgment,
  since attribution and not vocabulary is the discriminator (issue 34); degraded path does not
  promote evidence. They do **no**
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
  assembles Round 0 with the rendered seat contract and validated saved review-profile reference,
  reads the saved seat timeout through `user_config.py`, and writes it explicitly into every CLI
  barrier command. It marks the workdir as the code root, identifies Round 0's external diff plus the saved profile
  and scratch inputs by full absolute path, and keeps the explicit tool-`cwd` directive in both
  prompts. It freezes that phase's configured panel and exact blind prompt, reconstructs and retains
  complete Round-0 raw/status/parsed checkpoints, records the initial/single-retry/later-resume attempts, and
  selectively prepares only originally configured, currently available down or incomplete seats.
  Round-0 clustering remains referee judgment: only independent discoveries enter `raised_by`; the
  referee records post-drop raisers in `origins/round0.origins.txt`, records copied co-raisers and
  their text evidence in `origins/independence.round0.txt`, and reports each drop as a blindness
  incident in Process notes. For a debate-born issue, it records the same-pass raisers and original
  finding text in `origins/epoch-<epoch>.round-<N>.origins.txt`; the epoch prevents a later
  continuation from overwriting the record. Verdict synthesis uses the issue's birth-pass origin
  record for "Flagged by" and reports zero independent Round-0 support for debate-born issues.
  `verdict-input` returns that attempt history with final Round-0 seat statuses so Process notes
  survive resume and context compaction. It prepares the common one-batch debate with the same
  profile, collects compact engagement/guard status,
  installs a canonical CLI debate side file through `salvage-debate`, selects only complete
  active-plan batches for the normal or degraded decision and atomic commit with an optional referee
  addendum, and renders stable verdict input. It does not absorb judgment: clustering, prose-claim
  resolution, new-finding folds, and verdict prose remain with the referee.
- `merge_payload` — validates the base and referee addendum against the consumed payload keys, then
  folds synthesized claims, `add_issues`, and conditional fold-reopen into the `decide_round` payload
  with the per-key semantics `commit-sweep` needs (`set_state` replace, `revise` field-merge,
  `set_flag` dedup). Unknown keys and malformed consumed containers are exit-2 errors; it does not
  decide whether folded evidence materially conflicts with the current outcome, which remains
  referee judgment.
  `round commit --addendum` is its normal-path caller: the referee supplies only the judgment
  addendum and never invokes this helper or appends a second `set_state`/`revise` itself. A typo or
  malformed structure (including a `revise` entry with a flat `claim` instead of the `fields`
  wrapper) is a hard error (**exit 2** + message), not a traceback; `round` leaves the canonical
  payload and index untouched.
- `project_card` / `regen_cards` — the **only** way to render issue records → blind cards; `regen_cards`
  deletes stale issue cards before rebuilding the current set from the index.
- `run_codex` / `run_agy` — the **only** way to call the Codex / Gemini seats; they pin the
  model/profile and the flags that let MCP/tilth run (`run_codex` bypasses the Codex sandbox, `run_agy`
  passes `--dangerously-skip-permissions`). Never call `codex`/`agy` raw. `run_codex`'s profile pin is
  a request Codex can overrule — cwd/tree/repo config layers sit above the profile — so it also
  **records** the binding Codex reports for itself into `CODEX_SEAT_MODEL_FILE` (issue 47). Detection
  belongs to `preflight`, asking to `start`, recording here; none of the three overrides the user's
  own `.codex/config.toml`. `run_agy` likewise records the label agy logged as bound into
  `AGY_SEAT_MODEL_FILE` after a successful attempt (issue 63; best effort, nothing depends on it),
  and `preflight` reports a `run_agy` pin that `agy models` no longer lists.
- `repo_guard` — protects the code under review. `snapshot` records tracked worktree content (a
  `git stash create` SHA + sha256 manifest) and the index's path/mode/object/stage entries; `verify
  --restore` after each seat pass reverts and reports worktree or index drift. Guards tracked state
  only — leaves untracked scratch and the `.panel-review/` cache alone. A dirty tracked tree with no
  valid stash baseline fails closed instead of falling back to HEAD. Legacy snapshots without saved
  entries derive clean indexes from the baseline commit (including merge commits), and use the second
  parent only for a baseline with the stash-create structure; ambiguous stash-like baselines fail closed.
- `run_seat` — dispatch wrapper for the two **CLI** seats: dispatch → `parse_block`; prints the parse
  status. **It does not repair.** Salvaging a slipped block (a malformed fence, or a real review the
  seat forgot to fence) is referee-owned — the seat that wrote it has exited, so any re-dispatch is a
  fresh cold model with the same on-disk input the referee has, and judging stub-vs-review is an LLM
  call, not a grep heuristic (see SKILL "Salvage"). The Claude seat is a subagent, not a CLI, so the
  referee drives it directly (never via `run_seat`).
- `seat_contract.py` — the authoritative seat-output contract. Its structured phase definitions,
  stance values, examples, and validators drive both rendered Round-0/debate instructions and
  runtime parsing. Use its `render` command only for exceptional manual prompt assembly; normal
  prompt preparation goes through `round`. Do not add a second prompt schema or stance enum.
- `check_contracts` — the repository-level consistency gate for `CONTRACTS.md` ownership rows, public
  `index`/`sweep` verbs, prompt sentinels, rendered seat-contract blocks against the runtime parser,
  referee dispatch and artifact-delivery interfaces, the normal debate transaction boundary,
  status-stub ownership, barrier command shape, agy model-pin form, and script-owned cache/index
  invariants. Failures name the invariant and location.
- `check_draft` — the **seat-facing** pre-emit validator (spliced into prompts as `{{CHECK}}`; the
  referee never calls it). Wrapper over `parse_block --diagnose` and the shared seat-contract
  normalizers — don't re-implement the finding/stance checks. Reports rejected items and retained
  items whose points, revision fields, or evidence objects would be silently dropped by normal parsing.
- `write_seat_raw` — the Claude seat's sole write outside its scratch directory. It derives the
  expected Round-0 or debate raw path from a validated run ID/round/batch, requires the phase's exact
  block set and every item to pass the shared seat-contract validation, and only then atomically
  installs the complete raw response. It never accepts an arbitrary destination path.
- `hooks/enforce_agent_status_stub` — the plugin's `PreToolUse` gate for `SubagentHandback` and its
  `SubagentStop` return gate for the Claude seat and referee. It validates exact fixed status stubs
  before an auto-mode hand-back executes, deriving the referee's expected run ID from its original
  Agent task transcript. `SubagentStop` accepts empty or free-form closing text after a hand-back
  passes; if no accepted auto-mode hand-back is recorded, it checks the final message itself. Other
  permission modes keep the exact final-message check. The hook denies at most one
  invalid hand-back per subagent; if retry state is unavailable or
  a later hand-back is still invalid, it replaces the message with a fixed failure stub and allows it.
  If the referee task ID and an exact stub ID are unavailable, the hook uses
  `PANEL_REVIEW_FAILED id=unavailable`; the command still validates the saved artifact before
  delivery. An already-active referee stop-hook continuation may stop so correction cannot
  become an unbounded loop. These hooks provide bounded runtime enforcement, not a security boundary.
- `await_seats` — the barrier that owns CLI-seat waiting; runs every CLI seat concurrently (each via
  `run_seat`) in ONE job with an explicit per-seat timeout, writes per-seat status + a combined
  `--done` summary, and ignores inherited timeout variables. **Run it via the
  `panel-review-cli-barrier` Agent, never as a referee-backgrounded Bash job.** The Agent derives its
  detached Bash timeout and sentinel-wait count from the saved seat timeout plus a completion margin.
  The referee issues that barrier and the Claude-seat Agent
  together in one assistant response, both with `run_in_background: false`; the calls run
  concurrently and block the referee until both return. There are no referee
  `date`/`ps`/`cat status.*`/narration turns between dispatch and the combined return.
- `birth_index` — the **only** builder of the Round-0 `index.json` from the referee's clustered
  finding-to-issue map; assigns birth state/flags/`evaluated_by` by the birth-unanimity rule (referee
  still owns the clustering). It imports the issue enums and evidence predicates from
  `panel_common.py`, so the builder does not maintain a second issue schema. Output installs via
  `index put`.
- `resolve_instructions` — resolves `manifest.instructions` for the deterministic verbatim/none cases;
  returns the compose sentinel (exit 3) for `auto` (the only case the referee composes).
- `user_config.py` — the only loader and validator for the XDG versioned config. It resolves new-run
  profile selectors and execution-setting defaults, reads and updates saved execution settings
  without reloading defaults, and supplies action-time cleanup retention. `cleanup` and `discard`
  call it before deleting state.
- `stage_review_profile` — resolves one source path, requires a readable regular non-empty UTF-8
  file of at most 64 KiB, atomically snapshots its exact bytes, and returns source-path/size/SHA-256
  metadata. `init_run` is its only lifecycle caller; resumes never reload the source path.
- `resolve_diff` — the single place that turns a scope token into diff text; `diff_hash` hashes it.
- `assemble` — the **only** builder of a reviewer prompt: maps each `{{KEY}}` sentinel line to a file's
  bytes verbatim (whole-line, literal). `panel_common.py` owns the shared fence scan used by
  `parse_block` and the `extract_block` CLI shim; `--present` distinguishes empty from missing.
  Never re-implement the fence scan/substitution inline.
- `read_protocol_phase` — the referee's lazy protocol interface. It emits one marked section from the
  single canonical `references/protocol.md`, so inactive branches stay out of context without
  duplicating protocol prose across files.
- `reopen` — engine behind `panel-review:continue`: revives a finished run's leftover
  (`unresolved`/`contested`) issues via `index reopen` (bumps `run_epoch`, clears `committed_rounds`)
  then clears `/tmp/<ID>/sweeps/`. Counterpart to `init_run`.
- `write_card` — atomically installs referee-owned origin records from stdin through
  `panel_atomic_write`; card files go through `project_card` or `regen_cards`.
- `write_verdict_artifact` — atomically writes the durable verdict to the `/tmp/<ID>.md` sibling.
  Because that file is the only final-report delivery surface, artifact failure keeps the run
  resumable and blocks cleanup. The verdict writer stamps the continuation epoch and whether the
  canonical index was finished or incomplete; `start -- Finish here` uses its explicit `--final`
  mode before cleanup.
- `read_verdict_artifact` — validates the durable artifact's ID, metadata, and optional expected
  scope/diff hash/continuation epoch. Its default mode requires a finished artifact and emits the
  verdict body for `panel-review:result <ID>`; `--delivery` verifies any retained index through
  `index delivery-status`, then emits only the fixed filename plus minimal gate/continuation status.
  It is the sole final-return interface for `start`/`resume`/`continue`.
- `init_run` / `resume_check` / `cleanup` / `discard` / `inspect_run` / `set_limits` — run lifecycle
  and resume/diverged/stale classification. `cleanup.keep_tmp` makes `cleanup`/`discard` keep
  `/tmp/<id>/` (diagnostics) while still removing the workspace marker/cards/git-exclude. `init_run`
  resolves profile names through `user_config.py` and publishes the marker only after
  the profile snapshot, uncommitted-scope divergence snapshot, manifest, and index exist.
  `scope_diagnostics` owns that tracked-diff/untracked-path snapshot and its read-only comparison;
  `inspect_run`, `resume_check`, and `round` report the results without weakening the hash gate.
  `inspect_run` and `resume_check` leave a malformed `index.json` untouched and report the run as
  stale, even when `index.json.bak` parses. The `start`, `resume`, and `continue` skills retain stale
  marker and `/tmp/<id>/` state for manual recovery or explicit discard; they do not route stale
  state through `cleanup`. `discard` removes all marker directories together and maps a marker name
  to `/tmp/<id>/` only after `panel_valid_id` accepts it; its command skill presents the single
  summary verbatim.
- `_panel_common.sh` (bash) / `panel_common.py` (Python) — shared-helper libraries: validated run IDs,
  atomic writes, and git-exclude helpers; Python additionally owns issue/evidence predicates, fence
  extraction, and shared debate stance-integrity validation. Python scripts import `panel_common.py`;
  bash scripts source `_panel_common.sh`.
