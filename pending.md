# Pending handoff: finish non-P0 `analysis-codex.md` work

## Purpose

This file is the durable handoff for the current uncommitted work in `/workspace/panel-review`.
Assume the conversation that produced it is unavailable. Read this file, `AGENTS.md`, and
`analysis-codex.md` before changing anything.

The user said the P0 findings in `analysis-codex.md` were already implemented and asked to do the
rest. The verified CLI debate-salvage blocker is now fixed in the working tree. A representative
version-1.0.8 review supplied the previously missing measurement and exposed one additional
final-delivery fidelity issue. Do not commit or push unless the user explicitly asks.

## User decisions already made

- Do **not** add recommendation 9's narrow-review/focus-only mode. The observed scope leak was a
  one-off caused by contradictory commit IDs in `--base` and the author request, not a missing product
  mode.
- Recommendation 8's soft batching/search experiment was measured on the same frozen diff and did
  not reduce Claude-seat turns or API calls. The explicit batch-independent and multi-symbol lookup
  preferences are reverted; retain only redundant-read avoidance, sufficient-evidence stopping, and
  no hard call cap.
- Do **not** switch the referee from Opus yet. The measurement supplies no model-quality A/B evidence,
  and the existing controller changes already reduced referee traffic substantially.
- Do **not** prioritize or change the CLI barrier. Its measured cost was small and its wake-up role is
  intentional.
- Treat the durable verdict file as the sole final-report delivery surface. The user does not need the
  verdict body restated in the main conversation; `Done. Final report: /tmp/<ID>.md` is sufficient.
  Do **not** add a `MessageDisplay` hook. Minor inaccuracies in a screen restatement do not matter,
  and removing that restatement is simpler than making it byte-faithful.
- No commit or push has been authorized.

## Source artifacts

- `analysis-codex.md` is the authoritative measured analysis and recommendation list.
- Version-1.0.8 benchmark state and durable verdict:
  `/tmp/panel-20260714-170100-13096e7d/` and
  `/tmp/panel-20260714-170100-13096e7d.md`. Its Claude session is
  `~/.claude/projects/-workspace-dt-pr/0a2b1330-4fe7-4993-befc-d74ca5a6924e.jsonl`
  plus that session's `subagents/` directory.
- Version-1.0.9 same-diff rerun state and durable verdict:
  `/tmp/panel-20260715-170356-97b133b8/` and
  `/tmp/panel-20260715-170356-97b133b8.md`. Its Claude session is
  `~/.claude/projects/-workspace-dt-pr/a3f4d979-a7c4-4123-b331-9ff4d79e4570.jsonl`
  plus that session's `subagents/` directory.
- Earlier same-branch-family comparator:
  `/tmp/panel-20260711-124945-2c70d80f/` and
  `/tmp/panel-20260711-124945-2c70d80f.md`. Its Claude session is
  `~/.claude/projects/-workspace-dt-master/ff5dc7d7-b16d-4fcf-b386-6b77cc65df68.jsonl`
  plus that session's `subagents/` directory.
- `pending-issues/referee-context-cost-history.md` preserves the earlier referee-cost design context,
  completed work, rejected alternatives, and measurements. `design-notes/blind-pass-robustness.md`
  contains separate earlier design context. Both predate some live-tree changes; verify claims against
  current scripts before relying on them.
- `AGENTS.md`, `README.md`, and `.claude/rules/scripts.md` define current repository constraints and
  ownership.

## Implemented in the pending working tree

### Recommendation 7: Claude seat-owned raw output

- New `scripts/write_seat_raw` accepts only a validated run ID plus round/batch, derives the destination
  under `/tmp/<id>/raw/`, validates every required fenced block with `parse_block --diagnose`, and
  atomically installs the complete raw response.
- New `prompts/claude_delivery.tmpl` tells the Claude seat to write the complete response through that
  helper and return only `CLAUDE_SEAT_RAW_WRITTEN` or `CLAUDE_SEAT_RAW_FAILED`; raw findings/stances no
  longer return through the long-lived referee context.
- `agents/panel-review-claude-seat.md`, `agents/panel-review-referee.md`, `README.md`, `AGENTS.md`, and
  `.claude/rules/scripts.md` document the helper as the sole Claude-seat write outside scratch.
- Before a fresh Claude dispatch, `scripts/round` removes any uncheckpointed old Claude raw/status so a
  failed write cannot engage stale output. Completed debate checkpoints are not redispatched.

### Recommendation 4: coarse deterministic round operations

- New `scripts/round` exposes:
  - `prepare-round0`
  - `collect-round0`
  - `prepare-debate`
  - `collect-debate`
  - `commit`
  - `verdict-input`
- It owns normal-path diff resolution, guard setup/verification, prompt and CLI-barrier generation,
  debate plan/card preparation, batch ingestion, normal/degraded decision invocation, optional judgment
  addendum merge, atomic sweep commit, card regeneration, gate status, and compact verdict facts.
- Judgment remains with the referee: Round-0 clustering, ambiguous new-finding folds, prose-claim
  synthesis, and final verdict prose.
- `round commit` fails closed with exit 3 and `status=needs_judgment_addendum` before index mutation when
  prose revisions or new findings require referee judgment. An explicit `{}` addendum records that the
  judgment was performed but no mutation was needed.
- New findings considered by commit are restricted to seats engaged in that pass.

### Resume/checkpoint behavior added during review

- `scripts/sweep` now has `extend-plan`, limited to matching common single-batch plans. It atomically
  adds unplanned seats or reactivates already-planned dropped seats without replacing existing
  checkpoints.
- `round prepare-debate` reconciles an interrupted common plan with current preflight:
  - completed planned seats are preserved even if currently unavailable and remain in that interrupted
    round's effective configured panel;
  - unavailable incomplete seats are dropped through `sweep drop-seat`;
  - newly available seats are added or reactivated through `sweep extend-plan` and dispatched;
  - completed seats are not redispatched;
  - `panel.json` is updated only after reconciliation succeeds.
- `collect-debate` handles dropped plan entries without trying to ingest them.
- An exceptional multi-batch plan remains on the documented manual recovery path.

### Recommendation 5: lazy phase-specific protocol loading

- New `scripts/read_protocol_phase` emits marked portions of the single canonical
  `skills/panel-review-for-agent/references/protocol.md`.
- Valid phases are `common`, `round0`, `debate`, `degraded`, `gate`, `recovery`, `salvage`, and `verdict`.
  Repeated phase fragments are concatenated, allowing gate/debate sections to remain in their natural
  document order.
- `skills/panel-review-for-agent/SKILL.md` is now a compact bootstrap that loads only the active phase.
  Salvage, degraded, gate, recovery, and verdict instructions are loaded only when needed.
- Tests verify every phase is readable and that the marked phases cover all canonical procedure text.

### Packaging and documentation

- Plugin version remains 1.0.9 in `.claude-plugin/plugin.json` and the plugin entry in
  `.claude-plugin/marketplace.json` until the user performs the separately owned 1.0.10 bump.
  Version 1.0.8 was the representative pre-batching benchmark; 1.0.9 contained the measured
  batching experiment plus the delivery-fidelity changes.
- README/script ownership docs and tests were updated for `round`, `write_seat_raw`,
  `read_protocol_phase`, and `sweep extend-plan`.

## Resolved verified blocker: CLI debate salvage

Gemini 3.1 Pro (High), invoked through `scripts/run_agy` for a read-only adversarial review of all
pending changes, found this blocker. The main agent rechecked it against the live scripts and agreed
with the core issue. Step 4 fixed it through the deterministic interface designed below.

### Pre-fix failure path

1. A CLI debate seat returns a real but malformed `stances` or `new_findings` block.
2. The protocol correctly requires preserving the original raw and rewriting both coherent blocks to
   `<raw>.salvaged`.
3. Manual `sweep ingest-batch ... <raw>.salvaged` can create a valid checkpointed `.stances.json`.
4. The pre-fix `scripts/round:cmd_collect_debate` hardcoded the original
   `raw/round<N>.<seat>.<batch>.txt` for both `sweep ingest-batch` and `parse_block new_findings`.
5. Re-running `collect-debate` therefore re-reads the malformed original, writes a failing
   `status.nf.*`, and excludes the seat from `debate_engaged` even though its salvaged stances
   checkpoint is complete.
6. The pre-fix `round commit` globbed all checkpointed `*.stances.json`, including the salvaged seat,
   but passed an
   engaged list that excludes it. `decide_round` then rejects the source with
   `unknown _source (not an engaged seat)`; `decide_degraded_round` similarly rejects unknown sources.

Even without recollection, the pre-fix salvage phase did not give a precise deterministic command for
installing the salvaged `new_findings` output and `status.nf.*` state expected by `round commit`. The
coarse normal path therefore had no complete supported salvage transition.

Pre-fix code/protocol locations (line numbers moved after the implementation):

- `scripts/round`, `cmd_collect_debate`, around lines 460-504: hardcoded original raw and `status.nf`.
- `scripts/round`, `cmd_commit`, around lines 518-529: engaged calculation plus glob of every stances
  checkpoint.
- `skills/panel-review-for-agent/references/protocol.md`, salvage around lines 197-243 and debate
  two-block salvage around lines 576-619.
- `scripts/decide_round` around lines 84-87 and `scripts/decide_degraded_round` around lines 74-82:
  explicit rejection of a stance source outside `engaged`.

### Required properties of the fix

Prefer a deterministic coarse interface rather than instructing the referee to hand-write status
files. The exact CLI can be designed, but it must guarantee all of the following:

- Preserve the original malformed raw for inspection; do not overwrite it in place.
- Register or supply the salvaged side file explicitly.
- Use the **same repaired raw** for both stance ingestion and `new_findings` parsing.
- Atomically/consistently update the checkpoint, parsed new findings, and `status.nf.*` so engagement
  cannot disagree with retained stances.
- Make recollection idempotent; a later `collect-debate` must not silently revert to the original raw.
- Work per seat/batch and remain correct for exceptional multi-batch plans.
- Apply only to CLI seats. Claude output is validated before installation and is retried/dropped, never
  salvaged by the referee.
- Ensure `round commit` cannot concatenate stance sources that are outside its engaged set, even after
  partial recovery.

Add an end-to-end regression in `tests/python/test_round.py` covering malformed CLI debate raw →
salvaged side file → coarse recollection → seat remains engaged → commit succeeds. Also cover an
idempotent second collection and a failed/partial salvage that does not leave a retained stance with
failed `status.nf`.

### Step 3 design decision: one coarse salvage command, one complete batch checkpoint

Step 3 is complete. Step 4 implemented this referee-facing interface:

```text
round salvage-debate <id> <codex|gemini> <batch> <salvaged-raw>
```

`round salvage-debate` is the only new coarse command. It derives the active round and epoch, requires
the seat/batch pair to exist in the active plan, rejects Claude, and requires `<salvaged-raw>` to be
the exact canonical side path
`/tmp/<id>/raw/round<round>.<seat>.<batch>.txt.salvaged`. It must not modify the original raw. It then
delegates the batch installation to `sweep ingest-batch`; the referee does not write parsed output or
status files itself.

Deepen the existing `sweep ingest-batch` checkpoint rather than adding a separate salvage registry:

- Parse `stances` and `new_findings` from the same supplied raw before admitting the batch.
- A batch is `complete` only when the retained raw, exact-ID stances, parsed new findings,
  `status.nf.* == 0`, and expected-ID checkpoint all belong to that successful ingest.
- Persist a small per-seat/batch source record identifying the supplied raw and whether it was the
  canonical `.salvaged` side file. The retained `.out` remains a byte snapshot; the source record is
  provenance, not an instruction to re-read the source.
- Publish the existing `.out` completion marker last. `sweep has` and `resume-plan` must treat the
  whole bundle as the checkpoint; `.out` alone is incomplete. Legacy in-progress review compatibility
  is not required because old `/tmp` review state will be removed rather than resumed across this
  change.
- On a failed or partial ingest, remove that batch's incomplete checkpoint artifacts and publish the
  parse statuses only. Do not leave a retained `.stances.json` beside a failed `status.nf.*`.
- If the complete bundle already exists, collection returns it without re-reading either the original
  or salvaged raw. This makes ordinary recollection and a repeated salvage command idempotent.

`round collect-debate` continues to own the normal coarse collection path. It passes the original raw
to `sweep ingest-batch` only for an incomplete batch and reports an existing complete bundle without
re-ingesting it. A successful `round salvage-debate` therefore makes the next `collect-debate` a read
of checkpoint state, not a fallback to the malformed original.

`round commit` must stop globbing `*.stances.json`. Build both the stance input and new-finding input
from the active plan's complete batches, and include a seat only when all of its planned batches are
complete. Missing artifacts in a supposedly complete bundle are a hard error. This keeps exceptional
multi-batch plans correct and prevents any checkpoint outside the engaged set from reaching
`decide_round` or `decide_degraded_round`.

Rejected alternatives:

- A standalone source-path marker beside the current writes is too shallow: it selects the repaired
  raw but leaves stance, new-finding, and engagement state able to diverge.
- Letting `round` write or delete `sweep` checkpoint files breaks existing ownership and duplicates
  batch validation.
- Automatically preferring any `.salvaged` file is ambiguous and can consume an abandoned partial
  rewrite; the explicit coarse command is the registration event.

Step 4's regressions now exercise this interface, unchanged second collection, invalid-salvage
cleanup, CLI-only/canonical-path validation, and plan-selected commit input.

### Gemini's rejected secondary claim

Gemini also called the Round-0 salvage example a stale Claude-specific instruction. That is incorrect:
the command uses the generic `round0.$seat.txt.salvaged` path, not `round0.claude.txt.salvaged`. Do not
change it on that basis.

Gemini violated the read-only prompt by creating `shipping-gate-review.md`; that unintended artifact
was deleted immediately. A subsequent status check showed no other Gemini-created repository change.

## Representative measurement completed

The user ran a representative two-round review with plugin version 1.0.8:

- Panel ID: `panel-20260714-170100-13096e7d`
- Claude session: `0a2b1330-4fe7-4993-befc-d74ca5a6924e`
- Workdir/scope: `/workspace/dt-pr`, `base=9afc58a34dfd79b`
- Diff: 72,928 bytes
- Outcome: 5 issues — 3 accepted, 1 rejected, 1 contested
- Coverage: Claude, Codex, and Gemini engaged in Round 0 and both debate rounds; every seat evaluated
  every issue; all issues were fully vetted; no timeout, malformed block, salvage, redispatch, or down
  pass occurred; the repository guard remained clean.
- Delivery: the durable verdict was written and the verdict reached the main conversation.

Usage was deduplicated by `message.id`. For output tokens, select the final/highest usage record for
each ID: JSONL records for one response can contain progressively increasing `output_tokens`, even
though their input/cache fields are repeated. This corrects the old report's 9,026 baseline output
tokens to 152,140; the old input/cache totals remain unchanged.

| Metric | `analysis-codex.md` baseline | Version 1.0.8 | Change |
|---|---:|---:|---:|
| API calls | 178 | 152 | -14.6% |
| Input-context tokens | 10,108,204 | 7,770,873 | -23.1% |
| Referee calls | 58 | 36 | -37.9% |
| Referee input-context | 5,482,074 | 2,373,376 | -56.7% |
| Claude-seat input-context | 4,045,975 | 4,734,164 | +17.0% |
| Peak context | 144,840 | 135,058 | -6.8% |
| Corrected output tokens | 152,140 | 149,156 | -2.0% |

The old Round-1 transaction-debugging detour was eliminated. Round-1 referee traffic fell from 28
calls / 2,775,612 input-context tokens to 9 calls / 666,796 tokens. The referee as a whole fell from
54.2% to 30.5% of Claude input-context traffic. Claude seats are now the largest cost center at 60.9%.

There was one smaller orchestration mistake: the referee initially called `regen_cards` without a
valid `--workdir`, then retried successfully. The extra model turn cost approximately 59,900
input-context tokens and did not damage state.

### Comparison limitations and same-branch evidence

The `analysis-codex.md` baseline is not a controlled replay: its diff was 225,483 bytes and its scope
differed. Treat the exact whole-run percentage as representative, not causal, and do not claim exact
issue-state parity.

`panel-20260711-124945-2c70d80f` is a better branch-family quality comparator. It reviewed an earlier
56,500-byte version of the same darktable work, but used five debate rounds and included CLI/Claude
retries, so it is also not a direct cost A/B. It produced 7 issues (6 accepted, 1 contested); one issue
lacked Codex coverage. Its findings covered the same OpenCL write-back/readback and pipe-shutdown
subsystems. The version-1.0.8 run investigated the evolved code, found adjacent/new failure modes, and
achieved complete three-seat coverage rather than merely reproducing the earlier issue list.

The older run's referee used 93 calls, 27,679,931 input-context tokens, and a 622,737-token peak. Its
five-round/retry workload explains part of the difference, but the version-1.0.8 referee peak of
105,288 is still strong evidence that coarse commands and phase-specific loading prevented the old
long-context growth.

### Decisions originally unlocked by the version-1.0.8 measurement

- Recommendation 8's soft guidance was added as an experiment, not a proven saving. The later
  version-1.0.9 same-diff measurement below supersedes this decision: explicit batching and
  multi-symbol preferences are now reverted, while redundant-read avoidance, sufficient-evidence
  stopping, and no hard call limit remain.
- Keep the Opus referee. Do not switch models without a separate quality A/B.
- Do not prioritize the CLI barrier: it remained a small cost center and its wake-up role is
  intentional.

### New final-delivery fidelity finding

The durable artifact and referee return correctly named `DT_DEV_PIXELPIPE_STOP_NODES`, but the main
conversation restated one heading as the nonexistent `DT_DEV_PIPELINE_STOP_NODES`. The verdict reached
the user, but the main-model restatement was not byte-faithful.

The live version-1.0.8 trace established the failure boundary: the referee completion notification and
`/tmp/panel-20260714-170100-13096e7d.md` both contained the correct identifier; after checking that the
artifact existed, the main model generated a separate 4,302-output-token restatement and introduced
the typo. The verdict writer and saved artifact are not the faulty seam.

The user does not care about minor screen inaccuracies and uses the verdict file exclusively. The
chosen fix is therefore **artifact-only final delivery**, not byte-faithful screen replacement:

- Do not add a `MessageDisplay` hook. Its display-only replacement semantics and transcript tradeoff
  solve a requirement the user does not have.
- Stop sending the complete verdict body through the main conversation for ordinary final delivery.
  The referee should persist the canonical verdict and return only the smallest fixed status/control
  result needed by `start`.
- Before claiming success, deterministically validate that the expected finished artifact exists and
  belongs to the current run. On success, the main conversation should return only
  `Done. Final report: /tmp/<ID>.md` (plus minimal low-gate or continuable status/decision text when
  required). If validation fails, do not claim completion; retain the interrupted-run recovery path.
- Add a focused regression at the seam exposed by the trace: a completed referee/artifact path must
  produce the fixed pointer response without copying any verdict body into the main-context return.
  Cover ordinary completion, continuable output, low-only gate handling, and missing/invalid artifact
  failure. Do not spend a new three-seat review merely to test delivery; use a fixture or existing
  validated artifact for a small Claude Code smoke test after implementation.

### Step 5 implementation: artifact-only final delivery

Step 5 is implemented in the working tree:

- `read_verdict_artifact --delivery` validates the artifact against the expected run without emitting
  its body. It returns only `Done. Final report: /tmp/<ID>.md`, adding minimal continuation counts when
  retained canonical state has leftovers. An incomplete artifact is deliverable only when its retained
  index proves a canonical low-only gate; that path returns only the snapshot filename and gate status.
- Artifacts stamp the exact canonical `index.json` hash. When run state is retained, `index
  delivery-status` owns gate/leftover classification and supplies the current hash; delivery rejects a
  stale snapshot even when the run ID, scope, diff hash, and continuation epoch still match. This closes
  the initial-gate → resumed-round → failed-final-response same-epoch stale-artifact window found in the
  final Spec review without duplicating issue-state math in the artifact reader.
- `start`, `resume`, and `continue` now run the same delivery validation after every referee Agent
  completion, including a failed final Agent response. They no longer copy or restate verdict prose.
- The referee persists the canonical artifact and returns only `PANEL_VERDICT_READY id=<id>`. Artifact
  persistence is now required because the file is the sole report surface: on write failure it returns
  `PANEL_VERDICT_WRITE_FAILED id=<id>`, skips cleanup, and leaves the run resumable.
- Low-gate finalization validates the finalized artifact before cleanup. Shared `ID`/`EPOCH` variables
  keep the same path correct for `start`, `resume`, and later `continue` epochs.
- Regressions cover ordinary completion, continuable output, an incomplete low-only gate, finalized
  gate delivery, missing artifacts, and non-gate incomplete artifacts. Static protocol assertions keep
  the referee stub and all three command skills on the artifact-only interface.
- No `MessageDisplay` hook was added, and no new three-seat review was used for this change.

## Verification already completed

Before the unresolved salvage blocker was found:

- `./tests/run_tests.sh` → `PASS: 197   FAIL: 0`.
- Focused suite → 24 tests passed:

  ```bash
  python3 -m unittest \
    tests.python.test_sweep \
    tests.python.test_round \
    tests.python.test_protocol_phases \
    tests.python.test_write_seat_raw -v
  ```

- `git diff --check` passed, including after the Gemini review artifact was removed.
- `python3 -m py_compile scripts/round scripts/read_protocol_phase` passed.
- `bash -n install.sh tests/run_tests.sh` and `jq empty` over both plugin manifests passed.
- An `install.sh` smoke test into a temporary `CLAUDE_DIR` confirmed `round`, `write_seat_raw`, and
  `read_protocol_phase` install executable.
- Independent Standards and Spec subreviews initially found no blockers after stale-raw, lazy-phase,
  and changed-panel recovery corrections. The later Gemini review found the salvage blocker above;
  those earlier reviews did not cover it.

After fixing salvage:

- Focused `test_sweep`, `test_round`, `test_protocol_phases`, and `test_write_seat_raw` suite → 29
  tests passed.
- Full `./tests/run_tests.sh` → `PASS: 199   FAIL: 0`.
- `python3 -m py_compile scripts/round scripts/sweep scripts/read_protocol_phase` passed.
- `bash -n install.sh tests/run_tests.sh`, `jq empty` over both plugin manifests, `git diff --check`,
  and trailing-whitespace checks passed.
- A temporary-`CLAUDE_DIR` install smoke test confirmed `round`, `sweep`, `read_protocol_phase`, and
  `write_seat_raw` install executable.

After implementing artifact-only final delivery:

- Focused `test_index` + `test_verdict_artifact` + `test_protocol_phases` suite → 35 tests passed.
- Full `./tests/run_tests.sh` → `PASS: 208   FAIL: 0`.
- `python3 -m py_compile scripts/index scripts/read_verdict_artifact` and `git diff --check` passed.
- A temporary-`CLAUDE_DIR` install smoke test confirmed the updated `index`, artifact reader/writer,
  `start` skill, and referee agent are installed together with executable script bits.
- Final two-axis review found the same-epoch stale low-gate snapshot path described above; the
  index-hash/`delivery-status` correction and regression now close it. The Standards follow-up found
  no hard violations after classification moved under `index`; its remaining local gate-classification
  duplication was extracted. The only remaining Spec comment requested legacy artifact-schema
  compatibility, which is intentionally out of scope under the user's existing decision to discard
  old review artifacts rather than support them across this change.

After adding recommendation 8's soft Claude-seat guidance:

- Focused `test_round` + `test_write_seat_raw` suite → 18 tests passed.
- Full `./tests/run_tests.sh` → `PASS: 216   FAIL: 0`.
- `bash -n tests/run_tests.sh` and `git diff --check` passed.
- A temporary-`CLAUDE_DIR` install smoke test confirmed the installed Claude-seat agent and delivery
  template contain the batching, no-hard-cap, and single validation/write guidance.
- No Claude seat, Gemini seat, panel review, or review subagent was invoked during the isolated
  guidance implementation. The broader adversarial review was deferred to sequence step 7 because
  the user asked to conserve Claude quota.

After the same-diff measurement showed no call reduction and 30.2% higher matched input-context:

- Removed the explicit batch-independent lookup and multi-symbol search preferences from the Claude
  seat while preserving redundant-read avoidance, sufficient-evidence stopping, and no hard cap.
- Updated README and test contracts to describe and enforce that narrower guidance.
- Left both plugin version fields unchanged for the user's separately owned 1.0.10 bump.

After the version was bumped to 1.0.9, step 7 was completed without spending Claude quota:

- Focused `test_sweep` + `test_round` + `test_protocol_phases` + `test_write_seat_raw` + `test_index`
  + `test_verdict_artifact` suite -> 61 tests passed.
- Full `./tests/run_tests.sh` -> `PASS: 216   FAIL: 0`.
- `git diff --check`, manifest parsing, and shell syntax checks passed.
- Codex traced the live checkpoint, resume, Claude delivery, phase-loading, artifact-delivery, and
  packaging paths and found no material blocker.
- Gemini reviewed the same live worktree through `scripts/run_agy` under an explicit read-only
  contract and returned `APPROVED` with no material finding. Its verbatim response is
  `q-2026-07-15-16-21-30-answer.md`; `analysis-2026-07-15-16-21-30.md` records Codex's agreement and
  narrows Gemini's overstatements about security, statelessness, and what installation path it proved.
- The local marketplace and installed plugin were updated from 1.0.8 to 1.0.9. Seventeen reviewed
  runtime/control files in the new versioned cache matched the source byte-for-byte; required script
  executable modes were correct and the removed `scripts/check_draft.jsonl` was absent. Reload plugins
  or start a fresh Claude session before the darktable comparison.

## Step 8 measurement: version-1.0.9 same-diff rerun

The user reran the review with version 1.0.9 as
`panel-20260715-170356-97b133b8`. The rerun used the same 72,928-byte diff, diff hash
`88ea0fdce1a1a0fcc602c2c2f8dddcd7f2db638c4ba255ea0ace5961a5058b2e`, and author
instructions as the version-1.0.8 run. The old manifest stored the abbreviated base SHA and the new
manifest stored the equivalent full SHA. Every configured seat returned parseable output in every
pass; all status files are `0`.

Usage was extracted with the same method as the previous measurement: deduplicate by
`message.id`, retain the record with the highest `output_tokens` for each response, and define
input-context as input + cache-creation + cache-read tokens. Re-extracting the old session reproduced
its recorded totals exactly, providing a check on the comparison method.

### Whole-run totals are not a direct A/B

The old run used two debate rounds; the rerun used four. The rerun's whole-run increase therefore
must not be attributed to the Claude-seat batching guidance.

| Metric | Version 1.0.8 | Version 1.0.9 rerun | Change |
|---|---:|---:|---:|
| API calls | 152 | 219 | +44.1% |
| Input-context tokens | 7,770,873 | 14,806,016 | +90.5% |
| Corrected output tokens | 149,156 | 234,022 | +56.9% |
| Peak context | 135,058 | 201,151 | +48.9% |
| Referee calls | 36 | 63 | +75.0% |
| Referee input-context | 2,373,376 | 6,899,475 | +190.7% |
| Claude-seat calls | 75 | 103 | +37.3% |
| Claude-seat input-context | 4,734,164 | 6,992,183 | +47.7% |

Rounds 3-4 themselves used 61 API calls, 3,810,452 input-context tokens, and 52,260 output tokens
across the referee, Claude seats, and CLI barriers. This is the directly separable cost of executing
the two extra rounds. It excludes their context carry-over into the later verdict calls, so it is a
lower bound on their total effect.

Artifact-only delivery did reduce main-conversation output from 6,637 to 2,271 tokens (-65.8%), as
intended. That saving is real but small beside the extra debate work.

### Best available matched comparison: Claude-seat Rounds 0-2

Matching only the first three Claude-seat passes removes the direct cost of Rounds 3-4. It still is
not a controlled quality A/B: model sampling produced different initial findings, Round 1 generated a
genuinely new low maintainability finding, and Round 2 handled two open issues rather than the old
run's one.

| Claude-seat metric, Rounds 0-2 | Version 1.0.8 | Version 1.0.9 rerun | Change |
|---|---:|---:|---:|
| API calls | 75 | 75 | 0.0% |
| Input-context tokens | 4,734,164 | 6,164,287 | +30.2% |
| Corrected output tokens | 110,355 | 135,925 | +23.2% |
| Peak context | 135,058 | 201,151 | +48.9% |
| Tool calls | 88 | 122 | +38.6% |
| Tool-bearing turns | 72 | 72 | 0.0% |
| Turns containing multiple tool calls | 14 | 37 | +164.3% |
| Tool-result characters | 352,435 | 480,465 | +36.3% |

The soft guidance changed behavior in the requested direction only at the batching level: many more
turns contained multiple tool calls. It did not reduce tool-bearing turns or API calls. Instead, the
seat issued more searches and reads in those turns, received 36.3% more tool-result text, and carried
that text through later cached contexts. The matched input-context total consequently increased by
30.2%.

Round 0 is the strongest individual comparison because it began from the same diff and instructions
before debate outcomes diverged. Both seats used 22 API calls, but the rerun used 34 tool calls versus
26, 2,588,808 input-context tokens versus 1,888,469 (+37.1%), and a 201,151-token peak versus 135,058
(+48.9%). The 351-byte increase in the Claude Round-0 prompt is too small to explain this difference.

This one rerun does **not** demonstrate a token saving from recommendation 8. It suggests that the
batching instruction worked mechanically while the "stop after sufficient evidence" part did not
constrain exploration. Because the outputs and later issue workloads differ, do not claim that the
guidance causally increases cost from this sample alone. The measured batching/multi-symbol
preferences were reverted while the narrower no-reread, sufficient-evidence, and no-hard-cap rules
were retained. Do not make another evidence-efficiency guidance change or run another whole-review
benchmark until the duplicate-finding round-extension bug below is investigated; otherwise the
benchmark will remain vulnerable to the same confounder.

### Later investigation: duplicate debate finding reopened a settled issue

In debate Round 2, Claude emitted `nf.2.claude.1.json` claiming that STOP_NODES is ignored because it
is enumerated below PROCESSING. This is the same defect already represented by initial issue `i1`;
Claude itself was one of the three Round-0 raisers recorded in `origins/round0.json`.

The referee correctly folded the new evidence into `i1`, but `addendum.2.json` also changed `i1` from
`accepted` back to `open`. That caused Round 3 to re-review it and Round 4 to resolve its revised
severity/claim, even though no new issue had been born. Investigate this as a protocol/referee
duplicate-new-finding state-transition bug. The expected behavior needs to distinguish new evidence or
detail refinement for an existing settled issue from a genuinely new issue that requires birth and
subsequent debate. Preserve the reported artifacts as the reproduction trace; no runtime fix has been
made yet.

### Step 10 fix: folded findings reopen only on conflict

**Completed 2026-07-16:** reproduced the transition with a fresh `/tmp` run through the public
`merge_payload` -> `index commit-sweep` path. Starting from an `accepted` issue, an addendum
containing reinforcing `add_evidence` plus `set_state {open}` commits successfully and leaves the
issue `open`. The control addendum containing the same evidence without `set_state` also commits
successfully and correctly preserves `accepted`.

The scripts are behaving according to their contracts. `merge_payload` deliberately gives an
addendum's `set_state` precedence, and `index commit-sweep` has no semantic information with which to
decide whether a finding is a duplicate or whether its evidence changes an issue's disposition. The
canonical protocol supplied the bad transition: debate step 11 told the referee that every finding
folded into an existing issue must include `set_state {open}`. The Round-2 referee followed that
instruction exactly.

That unconditional rule conflicted with two existing contracts:

- README says issue state follows stances, not the presence of evidence;
- the canonical Transitions table says a new finding belonging to an existing issue is `merged`, not
  automatically reopened.

Because the addendum is merged after `decide_round`, the same instruction can also override a terminal
state selected by the mechanical transition/forced-limit logic. A script-only fix is not appropriate:
clustering and the meaning of new evidence are explicitly referee-owned judgments.

Implemented policy: a fold that reinforces the current outcome or adds a non-material detail adds
deduplicated evidence and preserves the issue's state. It reopens only when its evidence materially
conflicts with the current outcome and both debate limits leave budget. Conflicting evidence found
after either limit produces the normal terminal human handoff rather than overriding the forced-limit
rule with `open`. A genuinely new issue continues through `add_issues` and the normal birth/debate
rules. The referee owns the semantic conflict decision; no runtime classifier was added.

The policy is pinned at the referee-facing `read_protocol_phase debate` interface and synchronized
across the canonical protocol, README, script-ownership rules, and test documentation. The new
regression failed against the unconditional rule and passes after the change. Focused
`test_protocol_phases` -> 4 tests passed; full `./tests/run_tests.sh` -> `PASS: 216   FAIL: 0`;
`git diff --check` passed for the changed files.

### Step 11 fix: returning dropped seats are reactivated

**Completed 2026-07-16:** added a public recovery regression that prepares one debate round with
Claude and Codex, completes only Claude, resumes without Codex so it is dropped, then resumes that
same uncommitted round after Codex returns. Before the fix, the second-resume CLI barrier contained
only Gemini even though `panel.json` configured Codex again. The regression failed at that missing
Codex dispatch.

The stale state was in the stored common plan. `sweep extend-plan` added a batch only for seats that
were not already planned, so an already-planned Codex was left in `dropped_seats`. `round
prepare-debate` then wrote Codex into the effective configured panel but filtered it out of dispatch,
collection reported it as dropped, and it could not engage.

`sweep extend-plan`, which owns plan membership and dropped-seat state, now removes every supplied
current-panel seat from `dropped_seats` before adding any genuinely unplanned batches and atomically
rewriting the plan. The existing `round` path then sees the restored batch as incomplete, dispatches
it, and includes its valid response in engagement. Seats still absent from the current panel remain
dropped, completed checkpoints remain preserved, and exceptional multi-batch plans remain on the
manual recovery path.

The recovery contract is synchronized across README, the canonical recovery protocol, script
ownership rules, and this handoff. The new regression failed before the production change and passes
after it; focused `test_round` + `test_sweep` -> 22 tests passed; full `./tests/run_tests.sh` ->
`PASS: 216   FAIL: 0`.

## Current worktree ownership

Tracked modified files belonging to the pending implementation:

- `.claude-plugin/marketplace.json`
- `.claude-plugin/plugin.json`
- `.claude/rules/scripts.md`
- `AGENTS.md`
- `README.md`
- `agents/panel-review-claude-seat.md`
- `agents/panel-review-referee.md`
- `scripts/read_verdict_artifact`
- `scripts/index`
- `scripts/sweep`
- `scripts/write_verdict_artifact`
- `skills/continue/SKILL.md`
- `skills/panel-review-for-agent/SKILL.md`
- `skills/panel-review-for-agent/references/protocol.md`
- `skills/resume/SKILL.md`
- `skills/start/SKILL.md`
- `tests/python/test_sweep.py`
- `tests/python/test_index.py`
- `tests/python/test_verdict_artifact.py`
- `tests/README.md`
- `tests/run_tests.sh`

New untracked files belonging to the pending implementation:

- `prompts/claude_delivery.tmpl`
- `scripts/read_protocol_phase`
- `scripts/round`
- `scripts/write_seat_raw`
- `tests/python/test_protocol_phases.py`
- `tests/python/test_round.py`
- `tests/python/test_write_seat_raw.py`
- `pending-issues/` (remaining-work index, detailed issues, and completed design history)
- `pending.md` (this handoff)

Step-7 review artifacts (preserve as review evidence, not plugin implementation):

- `q-2026-07-15-16-21-30.md`
- `q-2026-07-15-16-21-30-answer.md`
- `analysis-2026-07-15-16-21-30.md`

Pre-existing/unrelated untracked user artifacts: preserve them and do not delete or fold them into the
implementation without explicit reason:

- `analysis-2026-07-14-04-15-56.md`
- `analysis-codex.md`
- `design-notes/blind-pass-robustness.md` (and the `design-notes/` tree generally)
- `panel-20260712-185806-61199f6f-analysis.txt`

There are no staged changes. No commit or push was made.

## Suggested next-session sequence

1. Read `AGENTS.md`, this file, and the relevant salvage/coarse-round sections named above.
2. Reproduce the inconsistency in a new failing test before changing implementation.
3. **Completed 2026-07-14:** design the smallest deterministic salvage interface with `sweep`
   retaining checkpoint ownership and `round` retaining coarse normal-path ownership. The decision is
   recorded under "Step 3 design decision" above.
4. **Completed 2026-07-14:** implement the fix and update the canonical protocol, README, script
   rules, and tests together.
5. **Completed 2026-07-14:** implemented artifact-only final delivery. The referee now persists the
   canonical report and returns a fixed stub; the main command validates the current-run artifact and
   returns only its filename plus minimal gate/continuation status. Focused regressions cover every
   delivery state named above.
6. **Completed 2026-07-14, superseded after measurement:** added recommendation 8's soft
   Claude-seat batching/search guidance with no hard call cap. Step 9 records its measured rollback.
7. **Completed 2026-07-15:** focused/full verification passed, Codex plus Gemini completed the
   adversarial shipping review with no material blocker, and marketplace version 1.0.9 was installed
   and verified against the source tree. Reload plugins or start a fresh Claude session before the
   quota-bearing run.
8. **Completed 2026-07-15:** measured the version-1.0.9 same-diff rerun. The matched Claude-seat
   passes showed no API-call reduction and 30.2% higher input-context; the whole-run comparison is
   confounded by a duplicate Round-2 finding that reopened an accepted issue and added two rounds.
9. **Completed 2026-07-15:** reverted the explicit batching and multi-symbol lookup preferences after
   the experiment produced no call reduction and higher context use. Retained redundant-read
   avoidance, sufficient-evidence stopping, and no hard cap. The user owns the 1.0.10 version bump.
10. **Completed 2026-07-16:** reproduced the duplicate-new-finding transition and traced it to the
    canonical protocol's unconditional fold-reopen instruction. The protocol now preserves a folded
    issue's state unless new evidence materially conflicts with its outcome and debate budget remains;
    forced terminal handling still wins at the limits. The public phase-interface regression and full
    local suite pass.
11. **Completed 2026-07-16:** added a same-round multi-resume regression and fixed common-plan
    reconciliation. A returning already-planned seat is removed from `dropped_seats`, dispatched,
    retained in `panel.json`, and included in engagement after a valid response. Focused and full
    suites pass.
12. Work through [`pending-issues/README.md`](pending-issues/README.md) in numerical order. It is the
    authoritative priority order for all remaining work. **Item 1 completed 2026-07-16:** stance is
    now the two-value existence decision `support`/`reject`; optional revisions are orthogonal to
    support, exact no-ops are inert, reject revisions are discarded, and retained legacy stance
    names fail explicitly. Full verification passed (`PASS: 216   FAIL: 0`). **Item 2 completed
    2026-07-16:** the referee now writes only `/tmp/<ID>.md`; the obsolete worktree verdict write and
    its special cleanup path are gone, while failed durable writes retain resumable state. Full
    verification passed (`PASS: 218   FAIL: 0`). **Item 3 completed 2026-07-16:** both always-loaded
    referee contracts now scope seat agreement to consensus outcomes and qualifying detail revisions;
    canonical mechanical evidence, coverage, counter, audit, degradation, and terminal-limit updates
    do not imply agreement. Focused and full verification passed. **Item 4 completed 2026-07-16:**
    the Claude role summary now requires both debate blocks, with `new_findings` required-emptyable;
    regressions cover the role wording, assembled Claude debate/delivery prompt, successful `[]`, and
    fail-closed omission. Focused and full verification passed. Resume with item 5, the remaining
    executable-contract work, followed by documentation, maintainability cleanup, and model
    experimentation.

## Suggested skills

- Use `tdd` for behavior changes: first expose the current bad behavior, then fix it.
- Use `codebase-design` for the instruction-contract ownership work in issue 05.
- Use `karpathy-guidelines` to keep each issue independently reviewable.
- Use `code-review` or `adversarial-review` only after an implementation is requested and completed.
- Use `scripts/run_agy` again only if the user specifically requests Gemini or approves its quota
  cost.


## doc updates

The documentation workflow and its exact prompts moved to
[`pending-issues/07-architecture-evolution-and-adrs.md`](pending-issues/07-architecture-evolution-and-adrs.md).
