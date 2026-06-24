# Panel-review reliability progress report

## Status

The mechanical debate-path work is implemented in the working tree and remains
uncommitted. On 2026-06-24, the current verification suite passed **147/147**
assertions and `git diff --check` passed. Earlier notes that report 45, 54, or
100 assertions are historical checkpoints, not the current result.

The work preserves the intended split of responsibility: scripts own
deterministic state transitions and validation; the referee still owns issue
clustering, claim synthesis, and final verdict prose.

## Implemented changes

### Parse, diagnosis, and repair

- `scripts/parse_block` has a `--diagnose` mode. It uses the same predicates as
  normal validation and reports the first failed constraint for each rejected
  item without changing normal-mode parsing behavior.
- `prompts/repair.tmpl` and the referee protocol retry malformed findings or
  stance blocks with the seat's own output and diagnostic messages. This is a
  reshape-only retry; it does not invent missing facts.
- The protocol distinguishes malformed, absent, empty, and partial stance
  output. An empty Round-0 findings block remains a valid clean result, while
  an empty debate stance block is a non-answer.

### Debate decisions and payload safety

- `scripts/decide_round` mechanically produces normal (two-or-more-seat)
  debate payloads. It enforces one stance per engaged seat per open issue,
  counts rounds and support, applies terminal limits, and only adopts severity,
  location, or category changes after unanimous support.
- A support/reject split can no longer apply one supporter's proposed enum
  revision. At a terminal limit, unresolved detail is marked contested instead.
- `scripts/decide_degraded_round` owns zero- and one-seat outcomes. It emits
  only terminal `unresolved`/`contested` states and eligible `fully_vetted`
  flags; it cannot accept issues, bump rounds, or apply revisions.
- Private `evaluated_by` coverage is included in decision payloads and committed
  atomically with index changes, preventing a crash or manual omission from
  desynchronizing coverage.
- `scripts/merge_payload` merges referee additions with the mechanical payload:
  addendum state wins, revisions deep-merge by issue, flags deduplicate, and
  evidence/new issues append. It prevents duplicate payload keys rejected by
  `index commit-sweep`.

### Blindness and seat-output handling

- `decide_round` rejects the round (exit 5) before it emits a payload if any of
  the seat free text it could carry onto cards names a seat, counts reviewers, or
  states an agreement/tally. The scan covers every stance's `rationale` plus all
  `new_evidence` fields — assertions, preconditions, impacts, and scalar or
  array-valued locations. It is deliberately a superset of what is actually
  promoted: a plain-`support` rationale is dropped rather than promoted, yet is
  still scanned, so a marker there forces a harmless re-dispatch instead of being
  ignored.
- One card-bound field sits outside this scan: the referee-synthesized prose
  `claim`. It reaches cards through the advice channel rather than as promoted
  stance text, so its blindness rests on the protocol rule forbidding the referee
  to name or count seats, not on the machine scan.
- `prompts/debate.tmpl` prohibits cross-reviewer and tally references, and the
  protocol directs a content rewording retry when the scan rejects a response.
  This is defense in depth; semantic wording that evades the marker set remains
  a residual risk.
- Plain-support rationales are intentionally not promoted as card evidence. The
  prompt and script documentation now match that selective-evidence rule.

### Script-owned batch, recovery, and gates

- `scripts/sweep` now owns batch plans, parsing/admission (`ingest-batch`),
  dropped-seat cleanup, and recovery plans. A batch is checkpointed only when
  it has exactly one valid stance for every planned issue; malformed, partial,
  duplicate, missing, and wrong-ID outputs remain retryable.
- Dropped seats' saved stances are excluded before the next decision, so they
  cannot violate the engaged-seat integrity check.
- `scripts/index gate-status` supplies the low-only predicate. The protocol
  applies the low-severity stop gate after Round 0 and after each committed
  round, unless the user explicitly requested low-severity debate.

### Index, diff, preflight, and documentation fixes

- `index commit-sweep` now rejects malformed flags, duplicate added issue IDs,
  invalid evidence sides, and invalid state values before recording a round.
  The direct `index state` command uses the same state allowlist.
- `reopen` advances the run epoch before a fresh continuation can consume sweep
  data, and atomic writes fsync their temporary file rather than invoking a
  whole-filesystem `sync`.
- `resolve_diff uncommitted` produces one combined tracked diff for staged and
  unstaged changes and falls back safely when the repository has no `HEAD`.
- `preflight` uses `codex login status`, eliminating the warning caused by the
  invalid `codex login --check` invocation.
- The debate revision schema exposes `category`, and persistence wording now
  describes workspace visibility for constrained seats generally rather than
  Codex's read-only sandbox specifically.
- Existing continuation support covers `panel-review:continue`, optionally
  limited to `unresolved` or `contested` issues, with a fresh continuation
  epoch/counters.

## Finding disposition

Implemented findings include malformed payload rejection, blind-card leak
blocking, partial-batch retry/admission, dropped-seat cleanup, split-vote
revision suppression, atomic coverage persistence, low-only gating, combined
diff generation, and the preflight login correction.

The following were deliberately not changed:

- Gemini remains able to write or run commands. This is accepted because seats
  may need to generate test data or exercise reviewed code; it is not treated
  as a read-only security boundary.
- Cleanup may remove the `.panel-review` entry from `.git/info/exclude`. The
  tool is considered the sole owner of that line.
- Changing `decide_round` from `peer_now` to `peer_ever` was not applied: the
  normal decision script requires at least two engaged seats, making that
  proposed line change a no-op. The real one-seat coverage case is handled by
  `decide_degraded_round`.
- Concurrent fresh review invocations are outside the single-developer usage
  model.

## Remaining todo

### Decisions and live validation

- Decide model effort levels: proposed configuration is Claude seat `high` to
  `xhigh`, and referee `xhigh` to `medium` while retaining `opus`.
- Run a real multi-seat review to verify that the protocol's CLI-seat dispatch
  placeholders are filled correctly and that retry/remediation behavior works
  against live model output.

### Deterministic automation (added)

All five items below are now implemented and covered by the regression suite.

- **`scripts/birth_index`** — turns the referee's clustered Round-0
  finding-to-issue map into a complete `index.json`, assigning each issue's birth
  state, vetting flags, and `evaluated_by` coverage by the birth-unanimity rule
  (all available seats and ≥2 raised it → `accepted`/`peer_reviewed`, `fully_vetted`
  only on a full panel, `detail_contested` from `detail_divergence`; otherwise
  `open`). It validates shape, unknown raisers, duplicate ids, and rejects a
  `severity:style` issue (kept aside for the Style section). The referee still owns
  the clustering judgment itself.
- **`scripts/run_seat`** — dispatch/retry wrapper for the two external CLI seats
  (Codex, Gemini). It dispatches the seat, parses the block, and runs the one-shot
  shape repair automatically (diagnose → `repair.tmpl` with the seat's own output →
  re-dispatch → re-parse), printing the final parse status. Repair fires only on a
  malformed block (exit 5), at most once; a no-block result (exit 4) stays down. The
  Claude seat is a subagent, not a CLI, so the referee still drives it directly.
- **`scripts/resolve_instructions`** — resolves `manifest.instructions` for the two
  deterministic cases (verbatim author text, or the standard "(none …)" line, exit
  0) and returns the compose sentinel `__PANEL_COMPOSE_INSTRUCTIONS__` (exit 3) for
  `auto`, the only case that needs the referee to write neutral context.
- **Repair extended to `new_findings`** — `run_seat --tag new_findings` (and the
  protocol's Claude-seat path) now apply the same one-shot shape repair to a
  malformed new-findings block that Round-0 findings already get; `parse_block
  --diagnose new_findings` drives it.
- **`PANEL_REVIEW_KEEP_TMP=true`** — `cleanup` and `discard` preserve `/tmp/<id>/`
  (manifest, index, sweeps, raw, audit) for post-mortem inspection while still
  removing the workspace state (cards, marker, git-exclude line). The durable
  `/tmp/<id>.md` verdict survives regardless.

### Documentation, maintenance, and test follow-up

- Document state/data files with real examples: `manifest.json`, `index.json`,
  issue cards, round payloads, seat findings/stances, and `.epr-run`. This
  awaits a representative real three-seat run.
- Explain the diff/hash lifecycle clearly: resolve scope to a diff, store its
  hash, then recompute and compare it before resuming.
- Remove or explicitly deprecate the unused `index commit-round` path and sync
  related command comments.
- Keep prompt schema text aligned with `parse_block`; a canonical generated
  schema would remove the remaining drift risk.
- Extend tests for the remaining helpers and for full live dispatch/repair,
  Round-0 birth indexing, and crash/recovery paths.

## Suggested maintenance direction: selective Python migration

Do not rewrite every shell script. The current scripts are mostly command
orchestration plus `jq`; a wholesale port would add a Python runtime requirement
and regression risk without improving simple Git/CLI wrappers.

Migrate incrementally only where stateful logic has become difficult to reason
about in Bash: `index`, `sweep`, `decide_round`, `decide_degraded_round`, and
possibly `parse_block`. Python functions and standard-library `unittest` would
make their data validation, decision transitions, and coverage calculations
easier to test directly.

Keep installation, external CLI invocation, Git/diff handling, and small
utilities in Bash. Preserve each command's current command-line interface and
the 100 existing black-box assertions during a port. Before the first migration,
make Python 3 an explicit installation/preflight requirement; it is not a
documented runtime dependency today.

## Verification command

```bash
./tests/run_tests.sh
git diff --check
```

No commit or push has been made.
