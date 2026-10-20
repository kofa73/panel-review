# Replace the Gemini seat pins that agy 1.4.2 no longer offers

Priority: 63

Status: Pending

Source: External CLI review, 2026-10-19 — installed agy **1.4.2**; previous review stopped at 1.1.27
(2026-09-05). Measured with `agy models` (quota-free) on 2026-10-19.

Triage: ready-for-human

## Problem

Neither model `run_agy` pins is offered any more. `scripts/run_agy:74-75` pins
`PRIMARY_MODEL="Gemini 3.1 Pro (High)"` and `FALLBACK_MODEL="Gemini 3.7 Flash (High)"`. `agy models`
on 1.4.2 lists:

```
gemini-4-argon-{medium,high,low}      Gemini 4 Argon (Medium|High|Low)
gemini-3.8-flash-{high,medium,low}    Gemini 3.8 Flash (High|Medium|Low)
claude-opus-5-5-{low,medium,high}     Claude Opus 5.5 (…)
claude-sonnet-5-5-{low,medium,high}   Claude Sonnet 5.5 (…)
gpt-oss-120b-medium                   GPT-OSS 120B (Medium)
```

The whole Gemini 3.1 Pro, 3.7 Flash and 3.6 Flash lines are gone. What agy 1.4.2 does when asked for
an unlisted label is **not measured**. Both behaviors seen so far are bad:

- **Hard error** (agy 1.1.13): both attempts fail at startup, so the Gemini seat is down on every
  pass. The panel quietly becomes a two-seat panel. Process notes record each down pass, but nothing
  says why.
- **Silent substitution** (agy 1.1.10): agy runs some other model, and nothing in the run records
  which one.

No panel run has used agy since it was upgraded (the newest run directories are from 2026-09-05), so
there is no field observation yet. The agy log line that `tests/live/agy_model_binding.sh` relies on,
`Propagating selected model override to backend: label="…"`, still exists on 1.4.x (seen in the
2026-10-18 logs), so that test can still answer the question. Its listing check will fail on both
pins as things stand.

This is the third time the pins have gone stale (`issues/21` on 2026-08-05 and 2026-09-05). Each time
the first signal was a human reading `agy models`.

### Related changes in agy 1.1.28 → 1.4.2

- **1.2.11** added `--effort` (`low|medium|high|xhigh|max`).
- **1.3.4** changed `--model` to accept a base model name without `--effort` and pick that model's
  default thinking level. The pins put the effort in the label (`issues/20`), so this does not break
  the label form, but it is a second way to say the same thing, and its binding is unmeasured.
- **1.1.28** "the CLI log now records whenever a model name you specify resolves to a different
  model, such as alias resolution, `--effort` variant selection, or replacement of a deprecated saved
  model".
- `agy --help` on 1.4.2 lists `--log-file` ("Override CLI log file path"). A per-attempt log file
  makes the binding line attributable to one attempt, instead of grepping a shared log directory.

## Expected behavior

1. **Measure first, on 1.4.2.** Run `tests/live/agy_model_binding.sh` (with `--negative-control`)
   and record here what an unlisted label does now: hard error, substitution, or something new.
2. **The owner picks the new pins.** Candidates from the listing: `Gemini 4 Argon (High)` and
   `Gemini 3.8 Flash (High)`. Confirm each binds with `tests/live/agy_model_binding.sh --model
   "<label>"` under the authentication the panel actually uses. Then update the pins, the
   "Verified to bind" comment above them, and the stale model-order bullet in the `run_agy` header
   (the bullet is already wrong today; see `issues/59` item 2). This supersedes the Gemini half of
   `issues/21`.
3. **Catch the next disappearance before a run.** `preflight` reads `agy models` (no quota) and
   reports a pin that is not listed, the way it reports `CODEX_MODEL_LAYER` for `issues/47`. It must
   not block the run: a missing pin is a fact for the human, and `start` can ask. This targets an
   honest accident (a vendor retiring a model), so it fits the trust model.
4. **Optional: record what bound.** Do what `issues/47` did for Codex: run each attempt with
   `--log-file /tmp/<ID>/…`, extract the propagated label, and write it where `round verdict-input`
   reads `seat_models`. The verdict can then say which Gemini model reviewed the code. Nothing should
   depend on this record, so an unrecognized log line costs only the record.

## Verification

- The measurement in item 1 is recorded here with the agy version.
- `tests/live/agy_model_binding.sh` passes for both new pins, including the wrapper-dispatch check.
- `preflight` names a missing pin when a pin is edited to a label that is not listed, and its output
  is unchanged when both pins are listed.
- `scripts/check_contracts --root .` (including `agy-model-pin-form`) and `./tests/run_tests.sh`
  pass.
- One real review completes with the Gemini seat engaged.

## Non-goals

- Do not switch to slugs or to `--effort`. The label form stays the contract until a measurement
  shows otherwise (`issues/20`).
- Never pin agy's Claude or GPT-OSS entries. The Gemini seat must run a Gemini model.
- Do not touch the print-timeout handling (`issues/59`) or add `/boost` (`issues/60`) here.
