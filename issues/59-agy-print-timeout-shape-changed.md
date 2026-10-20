# Correct the agy print-timeout contract and revive its dead detector

Priority: 59

Status: Pending

Source: External use of the agy CLI outside panel-review, 2026-08-26 — measured on installed
agy **1.1.20** against `scripts/run_agy` itself

Triage: ready-for-agent

## Problem

`run_agy` documents, detects, and tests one specific shape for a fired `--print-timeout`. On agy
1.1.20 that shape no longer occurs. Two independent statements in the wrapper are now wrong.

### 1. The print-timeout no longer exits 0 with the message on stdout

`scripts/run_agy:62-67` states that when `--print-timeout` fires, agy prints
`Error: timed out waiting for response` and **exits 0** — a clean exit with truncated, block-less
stdout — and that `agy_ended_with_timeout` (`scripts/run_agy:86-89`) therefore exists to convert that
false success into a failure. `README.md:482` repeats the wording. Measured on 1.1.20, all three
parts changed:

| | Documented (measured on ≤1.1.18) | agy 1.1.20 |
|---|---|---|
| Wording | `Error: timed out waiting for response` | `Error: timeout waiting for response` |
| Stream | stdout, as the last line | **stderr** |
| Exit code | 0 | **1** |
| stdout | truncated partial answer | **empty** |

Probe, a byte-identical copy of `scripts/run_agy` with only `PRINT_TIMEOUT="10s"` and
`WALL_TIMEOUT=60` substituted, given a prompt too long to answer in 10s:

```
rc=1, 26s
stdout: 0 bytes
stderr: Error: timeout waiting for response
        run_agy: primary model ('Gemini 3.1 Pro (High)') failed (timeout/error); retrying with fallback ('Gemini 3.7 Flash (High)')
        Error: timeout waiting for response
        run_agy: both primary ('Gemini 3.1 Pro (High)') and fallback ('Gemini 3.7 Flash (High)') models failed
```

**The seat still degrades correctly**, so this is not a live defect: the non-zero exit alone drives
`attempt()`'s fallback and then the seat-down path, exactly as intended. What is broken is the
explanation and the guard:

- `agy_ended_with_timeout` is **dead code** on this version — it cannot match a message that never
  reaches stdout, in wording it no longer has. The wrapper's most-explained safety net is now inert,
  and nothing says so.
- The residual risk it was written for is unguarded. Its purpose was the *clean-exit* case, where a
  truncated answer would otherwise pass for a complete review. If a future agy returns to exit 0
  with a reworded line, the detector still will not match, and a truncated pass reaches `parse_block`
  as if it were real output.
- `tests/run_tests.sh:567-568` and `tests/fixtures/parse_block/round0.gemini.timeout.txt` encode the
  old shape, so the suite proves the fallback fires for a stimulus the installed CLI cannot produce.

### 2. The wrapper's model-order bullet contradicts its own pins

`scripts/run_agy:35-42` says "PRIMARY Gemini 3.7 Flash (High), FALLBACK Gemini 3.1 Pro (High)" and
draws a consequence from it ("unlike the old Pro->Flash order, the fallback is NOT the faster
model"). The code two dozen lines below sets the opposite: `PRIMARY_MODEL="Gemini 3.1 Pro (High)"`,
`FALLBACK_MODEL="Gemini 3.7 Flash (High)"` (`scripts/run_agy:74-75`). The code is correct — the
reversal is the owner's 2026-08-22 decision recorded in `issues/21-refresh-seat-model-defaults.md`
("Reversed 2026-08-22"), which explicitly undoes that consequence. The header was left at the
superseded 2026-08-15 decision, so the file states both orders at once.

## Expected behavior

1. `run_agy`'s print-timeout bullet and `README.md:482` describe both observed shapes, dated and
   versioned the way `issues/42` item 3 asks for: exit 0 with the message on stdout on ≤1.1.18,
   exit 1 with `Error: timeout waiting for response` on stderr on 1.1.20. Neither is presented as
   the rule.
2. The detector covers both. Cheapest form that keeps the guard alive: capture agy's stderr to a file
   instead of letting it pass straight through, match a wording-tolerant pattern
   (`Error: timed? ?out waiting for response`) against stderr **and** the tail of stdout, and treat
   either hit as a failed attempt. Stderr must still reach the caller verbatim — `run_seat` and the
   referee rely on it for diagnosis.
3. `run_agy`'s header bullet names the pins actually in force (Pro primary, Flash fallback) and
   states the consequence that follows from that order. Better still, stop restating the values in
   prose and point at `PRIMARY_MODEL`/`FALLBACK_MODEL`, the way `AGENTS.md:156-158` already tells
   readers to.
4. The test double and the parse fixture cover the 1.1.20 shape as well as the old one.

## Verification

- The probe above, repeated against the patched wrapper: the fallback fires, the run exits non-zero,
  and the failure is reported as a print-timeout rather than a generic error.
- A simulated ≤1.1.18 response (exit 0, message as the last stdout line) is still classed as a
  failure.
- `scripts/check_contracts --root .` and `./tests/run_tests.sh` pass.
- One real review with the Gemini seat engaged still completes.

## Non-goals

- Do not raise or lower `PRINT_TIMEOUT`, and do not change the model pins — that is `issues/21`.
- Do not remove `agy_ended_with_timeout` on the grounds that it is currently dead. The clean-exit
  failure mode is the dangerous one precisely because it is silent, and agy's behavior here has now
  changed twice.
- Do not fold in `issues/42` item 3 (the unrecognized-`--model` sentence in the same header). Same
  file, different statement; land whichever comes first without rewriting the other.
- The installed agy is 1.1.20 while `docs/agents/external-cli-baselines.md` records a 1.1.18
  baseline. Advancing that baseline needs the full changelog delta triaged, which this issue does
  not do.

## Comments

### 2026-09-05 — re-measure on 1.1.27, not 1.1.20

The measurements in this issue were taken on agy **1.1.20**; installed is now **1.1.27**. agy's
print-mode exit-code semantics changed again inside that range — 1.1.20 itself narrowed `-p` exit
codes so that "benign tool execution errors and permission denials" no longer produce a non-zero
exit. Since this issue's whole conclusion rests on "the seat still degrades correctly via the exit
code", repeat the probe on 1.1.27 before writing the fix. `issues/61` owns the wider exit-code
question; this issue owns the print-timeout shape and the dead detector.

The expected behavior above stands: the fix must cover **both** shapes and must not delete
`agy_ended_with_timeout` on the grounds that it is currently dead. If 1.1.27 produces a third shape,
add it rather than replacing either.

### 2026-10-19 — agy 1.1.28 brought back the clean-exit case: partial output, exit 0

Installed agy is now **1.4.2**. The changelog records a third print-timeout shape, and it is the
dangerous one this issue's non-goals warned about:

> **1.1.28** — Changed what happens when `--print-timeout` expires mid-turn: the CLI now returns the
> partial output it has and exits successfully with a warning on stderr, instead of failing with a
> timeout error; interrupts such as Ctrl+C still exit non-zero.

What this means for `run_agy`, read from the code and not yet measured:

- `agy_ended_with_timeout` (`scripts/run_agy:86-89`) cannot match. It looks at the stdout tail for
  the ≤1.1.18 wording, and the new signal is a warning on stderr with unknown wording.
- `attempt()` returns 0, so a primary timeout **no longer triggers the fallback model**. The truncated
  answer goes to `parse_block`. It usually has no fenced block yet (status 4), so the pass is either
  lost without trying the fallback, or the referee salvages a truncated review as if it were complete.
  Salvage is defined for "a genuine completed CLI review", and the stderr warning is the only sign
  that this one is not.
- "The seat still degrades correctly" in the body above held on 1.1.20 only. It is false on 1.1.28+.

Related changes in the same range: fatal headless errors now print a stable `error:` marker on stderr,
and "a note is printed when the response may be truncated" (1.1.28). Agent or model failures exit `3`
with an `AGY_ERROR: {…}` JSON line on stderr (1.2.6). A response that streamed partly and then hit a
model or agent error exits `3` instead of `0` (1.2.10). The default print timeout became unlimited
(1.2.6); `run_agy` passes `15m` explicitly, so that change does not affect it. A stalled model
connection is now cancelled and retried after 5 minutes of silence (1.3.6), which uses up part of the
15-minute budget.

Consequences for the plan above:

- Expected behavior item 2 (capture stderr, match a wording-tolerant pattern) is now the fix for a
  **live** defect, not a dormant one. The pattern must also cover the 1.1.28 timeout warning and the
  truncation note. Their exact wording must be measured on 1.4.2 (repeat this issue's probe with
  `PRINT_TIMEOUT="10s"`).
- Expected behavior item 4 gains a third fixture: exit 0, partial stdout, warning on stderr.
- This issue now outranks `issues/61`. Re-ordered in `issues/README.md`.
