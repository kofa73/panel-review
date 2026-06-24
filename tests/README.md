# tests/

Regression suite for the panel-review scripts. It has two layers:

- **`run_tests.sh`** — plain bash + `jq`, covering the scripts that are still bash
  (`resolve_diff`, `preflight`, `birth_index`, `run_seat`, `resolve_instructions`,
  `cleanup`/`discard`) plus the protocol/template contracts. As its **final step**
  it runs the Python suite below, so this one command exercises the whole pipeline.
- **`python/`** — `unittest` tests for the stateful scripts that were ported to
  Python 3 (`index`, `parse_block`, `decide_round`, `decide_degraded_round`,
  `merge_payload`, `sweep`). These drive each script through its CLI (and import
  `panel_common` directly where useful).

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
  validation + `card_rev` bump; `commit-sweep` happy path, idempotent re-commit
  (no double bump), atomic `evaluated_by` coverage; and the rejection branches —
  format errors → exit 2, transaction/semantic errors (duplicate target, stale
  epoch, out-of-order, nonexistent id, invariant violation) → exit 1; `put`
  invariant; `reopen`.
- **parse_block** (`test_parse_block.py`): normal-mode exit codes (empty→0,
  flat-shape→5, no-block→4); stances parse **byte-identical** to the stored
  fixtures; `--diagnose` pinpoints each failure reason (and exit 5/0); `revision`
  sub-field stripping; empty-vs-real stances block idiom.
- **decide_round** (`test_decide_round.py`): round-1/round-2 transitions;
  effective-value enum convergence (stays-open, ceiling→detail_contested,
  true-unanimity→adopt); split support/reject cannot adopt a unilateral revision;
  integrity gate (duplicate/missing/unknown `_source` → exit 3); dropped seat
  decides on the remainder and withholds `fully_vetted`; the blindness gate
  (rationale/assertion/precondition/impact/array-location markers → exit 5);
  sorted-unique `evaluated_by`.
- **decide_degraded_round** (`test_decide_degraded_round.py`): zero/one-seat
  terminal outcomes (`unresolved`/`contested`), `fully_vetted` only on full
  coverage, two-seat → exit 2, integrity → exit 3.
- **merge_payload** (`test_merge_payload.py`): set_state-replace + revise
  field-merge; merged payload commits; hand-appending is genuinely rejected.
- **sweep** (`test_sweep.py`): batch ingestion classification
  (missing/empty/malformed/partial/wrong_ids/complete); `has`/`resume-plan`;
  `drop-seat` exclusion; `done`/`commit` (incl. stale-epoch rejection); plan
  validation.

## What the bash suite covers (`run_tests.sh`)

- **resolve_diff**: combined staged + unstaged tracked diff; no-`HEAD` fallback.
- **preflight**: recognizes authenticated `codex login status`.
- **birth_index**: birth-unanimity state/flags/coverage (unanimous→accepted/peer,
  full-panel→fully_vetted, divergence→detail_contested, partial/single→open),
  `evaluated_by` from raisers, and validation rejects (style severity, unknown
  raiser, duplicate id, empty evidence → exit 3); output installs via `index put`.
- **run_seat**: dispatch + parse status (mock CLI on `PATH`); one-shot repair
  salvages a malformed block; repair at most once then exit 5; `--no-repair`;
  no-block seat is down (4); repair extends to `new_findings`; gemini routes
  through `run_agy`; unknown seat → usage exit 2.
- **resolve_instructions**: verbatim/none resolved (0), `auto` → sentinel (3),
  missing manifest → exit 1.
- **cleanup / discard**: `PANEL_REVIEW_KEEP_TMP=true` preserves `/tmp/<id>` while
  removing the marker / `.panel-review`; the default still removes `/tmp/<id>`.
- **Protocol/template contracts**: pins the documented batch-completeness,
  dropped-seat cleanup, low-only gate, coverage, prompt/schema requirements, and
  the protocol's use of `birth_index` / `run_seat` / `resolve_instructions`.

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
