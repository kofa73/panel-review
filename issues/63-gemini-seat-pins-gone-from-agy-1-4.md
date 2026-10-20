# Replace the Gemini seat pins that agy 1.4.2 no longer offers

Priority: 63

Status: Pending — items 1, 3 and 4 done 2026-10-20; the new pins (item 2) are the owner's call

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

## Progress (2026-10-20)

### Item 1: what agy 1.4.2 does with an unlisted label

Measured on agy **1.4.2** with one direct print-mode call, using `run_agy`'s invocation form plus a
per-call `--log-file`, asking for the current primary pin `Gemini 3.1 Pro (High)`:

- **Hard error, exit 1, no output on stdout.** stderr: `error: invalid model selection (--model
  "Gemini 3.1 Pro (High)" --effort ""): model Gemini 3.1 Pro (High) is not recognized as a known
  model or custom model in settings`, followed by the list of available labels. This is the same
  behavior as 1.1.13. With both pins unlisted, `run_agy` fails both attempts, so the Gemini seat is
  down on every pass.
- **The log names a model that never ran.** Before the error, the log has `Failed to resolve model
  flag Gemini 3.1 Pro (High)` followed by `Propagating selected model override to backend:
  label="Gemini 3.8 Flash (High)"`, which is the `settings.json` default on this machine. A
  propagation line is therefore proof of binding only for a call that succeeded.
  `tests/live/agy_model_binding.sh` already checks the exit code before it reads the label. Its
  header and negative-control wording now describe both behaviors, depending on the version.
- **`--log-file` works on 1.4.2.** When it is given, agy writes the CLI log only to that file and
  nothing to `~/.gemini/antigravity-cli/log/`. `agy --help` prints to stderr.

The full live script (`--negative-control`, wrapper dispatch) was not run. Its listing check fails on
both current pins, and the wrapper check would spend two failing attempts, so it gives no further
information until new pins are chosen.

### Item 2: candidate binding, partly measured

- `Gemini 4 Argon (High)` **binds**. One direct call with `--model "Gemini 4 Argon (High)"`
  exited 0, printed `OK`, and every propagation line in its log read `label="Gemini 4 Argon (High)"`.
- `Gemini 3.8 Flash (High)` was **not** checked through `--model`. It appears in the log above only
  as the `settings.json` default, which does not prove that the label binds.

### Item 3: done

`preflight` reads `agy models` (bounded by a 30 s `timeout`; no quota) and compares each `run_agy`
pin with the label column, using an exact whole-line match. It prints a new tail line,
`GEMINI_PIN_UNLISTED: yes|no|unknown`, ahead of `CODEX_MODEL_LAYER`. When a pin is unlisted, it
also prints a WARNING block that names the pin and lists the Gemini labels on offer. `unknown`
means the listing could not be read, or it had no label column (the slug-only listing of 1.1.10).
The check never blocks. `start` asks *Run anyway, or stop?* when the line says `yes`, the same way it
asks for `CODEX_MODEL_LAYER`. The protocol's preflight comment, the README, `.claude/rules/scripts.md`
and `AGENTS.md` describe the new line.

One deviation from the Verification wording: preflight's output is not byte-identical when both pins
are listed. It gains the always-present `GEMINI_PIN_UNLISTED: no` line, the same way
`CODEX_MODEL_LAYER: no` is always present. A fixed tail keeps scripted parsing simple. No WARNING or
NOTE is printed in that case.

### Item 4: done (optional item)

`await_seats` exports `AGY_SEAT_MODEL_FILE=/tmp/<ID>/agy-model.txt` for the Gemini seat. With that
variable set, `run_agy` checks `agy --help` for `--log-file`. If agy offers the flag, each attempt
logs to its own file under `/tmp/<ID>/agy-logs/`. Those logs are kept, because agy then writes nothing
to its default log directory. After a **successful** attempt only, `run_agy` writes `model=<logged
label(s)>` and `requested=<pin>`. A successful attempt with no recognized line removes an older
record, so the file always describes the last successful pass. `round verdict-input` returns this record as `seat_models.gemini`,
and Process notes state it, including a substitution when `model` differs from `requested`. If agy
lacks the flag or no line is recognized, only the record is lost.

### Still to measure

- `tests/live/agy_model_binding.sh` with the chosen pins, including the wrapper-dispatch check and
  `--negative-control`.
- How an exhausted Argon quota shows up in print mode (exit code, stderr). A quota error that exits
  non-zero triggers the fallback. An exit 0 with an error message would not.
- One real review with the Gemini seat engaged. Its `agy-model.txt` confirms the record in the field.

## Open questions for the owner

1. **Primary pin.** Options:
   - **(a) `Gemini 4 Argon (High)`** (recommended). This is the strongest Gemini on offer, and it binds
     on 1.4.2 (measured). Cost: it is quota-limited on your plan, and its price doubles after the
     promotion. A failed attempt (quota or timeout) falls through to the fallback.
   - (b) `Gemini 4 Argon (Medium)`. Same family, presumably cheaper per pass. Its quality is not
     measured, and it is unclear whether it draws on the same quota.
   - (c) `Gemini 3.8 Flash (High)`. Not recommended: you rated the Flash line unreliable (wrong
     document references).
2. **Fallback pin.** Options:
   - **(a) `Gemini 3.8 Flash (High)`** (recommended, with reservations). It is the only other Gemini
     family on offer, so an Argon quota exhaustion is unlikely to take it down too. It is a weak
     reviewer by your assessment, but the debate rounds can reject its wrong claims. Its binding still
     needs one check.
   - (b) `Gemini 4 Argon (Medium)`. Higher expected quality, but it is the same family and probably
     the same quota pool, so it is likely to fail when the primary fails for quota reasons.
   - (c) No usable fallback: you prefer a down Gemini seat to a Flash review. This needs a code change,
     because `run_agy` and `check_contracts` (`agy-model-pin-form`) require two distinct pins. Choose
     this only if a Flash review does more harm than a two-seat panel.

