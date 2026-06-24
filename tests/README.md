# tests/

Regression suite for the debate-pipeline scripts. Plain bash + `jq` (the repo has
no test framework); run it after touching any of: `parse_block`, `decide_round`,
`merge_payload`, `index` (the `commit-sweep` validator), or the SKILL debate loop.

## Run

```bash
./tests/run_tests.sh            # all tests; exits nonzero if any fail
VERBOSE=1 ./tests/run_tests.sh  # also prints each PASS
```

Requires `jq` and the scripts under `../scripts`. The suite mints throwaway run
ids under `/tmp/pr-test-$$-*` (because `decide_round`/`index` hardcode
`/tmp/<id>/` paths) and cleans them up on exit. It does not touch any real run.

## What it covers

- **parse_block**: normal-mode exit codes on real messy output (empty→0,
  flat-shape→5, timeout→4); stances parse **byte-identical** to stored output;
  `--diagnose` pinpoints each failure reason; all-valid → exit 0.
- **decide_round / decide_degraded_round**: round-1 + round-2 end-to-end through the real `index
  commit-sweep` (and idempotent re-commit); finding-1 effective-value enum
  convergence (i4 stays open, ceiling→detail_contested, true-unanimity→adopt);
  split support/reject cannot adopt a unilateral revision; finding-2 integrity
  gate (duplicate/missing/unknown `_source` → exit 3);
  dropped empty seat → decides on remainder, withholds `fully_vetted`; degraded zero/one-seat
  outcomes and atomically persisted coverage.
- **merge_payload**: finding-3 set_state-replace + revise field-merge; merged
  payload commits; contrast that hand-appending is genuinely rejected.
- **Blindness**: rationale, assertion, precondition, impact, and array-valued
  location markers reject the round with exit 5.
- **Other scripts**: `sweep` owns batch ingestion/checkpoint/recovery classification; `index
  gate-status` covers low-only predicates; `resolve_diff` combines staged + unstaged changes and has a
  no-`HEAD` fallback; `preflight` recognizes authenticated `codex login status`.
- **Protocol/template contracts**: the suite pins the documented batch-completeness,
  dropped-seat cleanup, low-only gate, coverage, and prompt/schema requirements.

## Fixtures

`fixtures/` holds captured **real** run output so tests are self-contained
(don't depend on `/tmp` oracle dirs that get cleaned):

- `parse_block/round0.claude.flat.txt` — the real flat-shape failure
  (valid JSON, wrong schema) that motivated `--diagnose`.
- `parse_block/round0.{codex.empty,gemini.timeout}.txt` — clean-empty vs no-block.
- `parse_block/round1.<seat>.stances.txt` + `expected.<seat>.stances.json` —
  raw → parsed regression oracle.
- `decide_round/index.round0.json`, `manifest.json`, `stances.round1.json`,
  `evaluated.round0.json` — a full round-0 result + round-1 stances + the
  cumulative `evaluated_by` map.

Synthetic per-reason / edge cases are built inline in `run_tests.sh`.

Source runs (for regenerating fixtures, if still present):
`/tmp/panel-20260624-074239-aeb340eb` (full debate) and
`/tmp/panel-20260621-161717-42270ee2` (round-0 with the flat-shape failure).
