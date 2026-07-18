# tests/

Regression suite for the panel-review scripts. It has two layers:

- **`run_tests.sh`** — plain bash + `jq`, covering the scripts that are still bash
  (`resolve_diff`, `preflight`, `birth_index`, `run_seat`, `resolve_instructions`,
  `cleanup`/`discard`) plus the protocol/template contracts. As its **final step**
  it runs the Python suite below, so this one command exercises the whole pipeline.
- **`python/`** — `unittest` tests for the Python script interfaces, including `index`,
  `parse_block`, `seat_contract.py` through rendered `round` prompts, `check_contracts`,
  `decide_round`, `decide_degraded_round`, `merge_payload`, `sweep`, `round`,
  `write_seat_raw`, `read_protocol_phase`, `read_verdict_artifact`, and the
  `enforce_agent_status_stub` hook. These drive public interfaces rather than private helpers
  (except `panel_common`'s shared primitives).

Run it after touching any of those scripts, the `commit-sweep` validator, the debate
decision logic, or the SKILL debate loop.

## Run

```bash
./tests/run_tests.sh                          # bash suite + python suite; nonzero if any fail
VERBOSE=1 ./tests/run_tests.sh                # also prints each PASS
python3 -m unittest discover -s tests/python  # just the python suite
python3 -m unittest discover -s tests/python -v   # verbose
```

Requires `jq`, `git`, **`python3`**, and the scripts under `../scripts`. Tests mint
throwaway run ids under `/tmp` (the scripts hardcode `/tmp/<id>/` paths) and clean
them up. No real run is touched.

## What the python suite covers (`tests/python/`)

- **index** (`test_index.py`): `gate-status` low-only predicate; `state` enum
  validation + `card_rev` bump; read-only `delivery-status` classification and index identity;
  `commit-sweep` happy path, idempotent re-commit (no double bump), audit output, new-issue birth,
  and atomic `evaluated_by` coverage; and the rejection branches — format errors → exit 2,
  transaction/semantic errors (duplicate target, stale epoch, out-of-order, nonexistent id,
  invariant violation) → exit 1; `put` invariant; `reopen`.
- **parse_block** (`test_parse_block.py`): normal-mode exit codes (empty→0,
  flat-shape→5, no-block→4); stances parse **byte-identical** to the stored
  fixtures; `--diagnose` pinpoints each failure reason (and exit 5/0); `revision`
  sub-field stripping; empty-vs-real stances block idiom; `--response` phase block
  cardinality (missing and duplicate blocks).
- **check_draft** (`test_check_draft.py`): valid bare JSONL and already-fenced input; empty drafts;
  findings, stances, and new-findings validation; mixed valid/invalid item detection; file input;
  invalid tags and missing arguments.
- **instruction contracts** (`test_contract_consistency.py`): the live tree passes the ownership
  checker; known barrier/path/return/panel/health/delivery/stance drift is reintroduced one case at a
  time and must fail with the invariant name; direct normal-debate transaction helpers are rejected.
- **decide_round** (`test_decide_round.py`): round-1/round-2 transitions;
  effective-value enum convergence (stays-open, ceiling→detail_contested,
  true-unanimity→adopt); split support/reject cannot adopt a unilateral revision;
  support claim revisions reach referee advice while exact no-op revisions and
  unused support rationale remain inert;
  integrity gate (duplicate/missing/unknown `_source` → exit 3); dropped seat
  decides on the remainder and withholds `fully_vetted`; the blindness gate
  (rationale/assertion/precondition/impact/array-location markers → exit 5);
  sorted-unique `evaluated_by`.
- **decide_degraded_round** (`test_decide_degraded_round.py`): zero/one-seat
  terminal outcomes (`unresolved`/`contested`), `fully_vetted` only on full
  coverage, two-seat → exit 2, integrity → exit 3.
- **merge_payload** (`test_merge_payload.py`): set_state-replace + revise
  field-merge; bump/coverage combination; malformed addendum errors remain clean exit-2 failures;
  merged payload commits; hand-appending is genuinely rejected.
- **sweep** (`test_sweep.py`): batch ingestion classification
  (missing/empty/malformed/partial/wrong_ids/complete); `has`/`resume-plan`;
  `drop-seat` exclusion; `done`/`commit` (incl. stale-epoch rejection); plan
  validation with field-specific diagnostics; `plan-scaffold` validation and scaffold-to-plan round
  trip; extending a live plan when a configured seat appears or returns.
- **round** (`test_round.py`): every Round-0/debate rendering for two- and three-seat panels uses the
  shared contract and runtime-valid examples; coarse prepare/collect behavior; strict Claude debate
  delivery; canonical CLI salvage; checkpoint and changed-panel resume handling; verdict-input
  filtering; and successful/failed `round commit --addendum` transaction boundaries.
- **write_seat_raw** (`test_write_seat_raw.py`): derived Round-0/debate destinations; strict round and
  batch shapes; complete phase-required block validation; atomic installation without replacing a
  valid raw on invalid input.
- **protocol phases** (`test_protocol_phases.py`): every marked canonical phase
  is independently readable with no marker leakage; the debate interface keeps
  settled folds terminal unless evidence conflicts and debate budget remains; the normal debate path
  uses only the coarse commit interface; the bootstrap alone owns the split
  success/persistence-failure/review-failure return literals.
- **verdict artifacts** (`test_verdict_artifact.py`): durable write/read validation, artifact-only
  delivery, cleanup/discard retention, continuable reports, low-gate snapshots and explicit
  finalization, same-epoch freshness, metadata/hash rejection, and write-failure recovery.
- **Agent status hook** (`test_agent_status_hook.py`): exact Claude/referee status admission,
  prose/wrong-ID/malformed result rejection, retry behavior, unrelated-agent pass-through, plugin
  hook registration, and executable installation through `install.sh`.

## What the bash suite covers (`run_tests.sh`)

- **resolve_diff**: combined staged + unstaged tracked diff; no-`HEAD` fallback.
- **preflight**: recognizes authenticated `codex login status`.
- **birth_index**: birth-unanimity state/flags/coverage (unanimous→accepted/peer,
  full-panel→fully_vetted, divergence→detail_contested, partial/single→open),
  `evaluated_by` from raisers, and validation rejects (style severity, unknown
  raiser, duplicate id, empty evidence → exit 3); output installs via `index put`.
- **run_seat**: dispatch + parse status (mock CLI on `PATH`), a single dispatch —
  it no longer repairs (salvage is the referee's job); a malformed block is
  reported (5) not repaired, `findings` or `new_findings`; a no-block seat is
  down (4); gemini routes through `run_agy`; unknown seat and the retired
  `--no-repair` flag → usage exit 2.
- **resolve_instructions**: verbatim/none resolved (0), `auto` → sentinel (3),
  missing manifest → exit 1.
- **cleanup / discard**: `PANEL_REVIEW_KEEP_TMP=true` preserves `/tmp/<id>` while
  removing the marker / `.panel-review`; the default still removes `/tmp/<id>`.
- **Protocol/template contracts**: runs `seat_contract.py render` through runtime parsing and pins
  the documented batch-completeness,
  dropped-seat cleanup, low-only gate, coverage, prompt/schema requirements,
  the referee's agreement-gated-decision versus mechanical-update invariant,
  Claude-seat redundant-read and sufficient-evidence guidance without lookup
  batching or a hard call cap, its single final validation/write step, and the
  protocol's use of `birth_index` / `run_seat` / `resolve_instructions` and the coarse normal-debate
  transaction owner.

## Fixtures

`fixtures/` holds captured **real** run output so tests are self-contained. They are
now consumed by the Python suite:

- `parse_block/round0.claude.flat.txt` — real flat-shape failure (valid JSON, wrong
  schema) that motivated `--diagnose`.
- `parse_block/round0.{codex.empty,gemini.timeout}.txt` — clean-empty vs no-block.
- `parse_block/round1.<seat>.stances.txt` + `expected.<seat>.stances.json` —
  raw → parsed regression oracle (byte-identical check).
- `decide_round/index.round0.json`, `manifest.json`, `stances.round1.json`,
  `evaluated.round0.json` — a full round-0 result + round-1 stances + the cumulative
  `evaluated_by` map.

Synthetic per-reason / edge cases are built inline (in `run_tests.sh` for bash, and
within each `test_*.py`).
