# Re-verify the Gemini seat against agy's changed print-mode semantics (1.1.19 → 1.1.27)

Priority: 61

Status: Pending

Source: External CLI changelog review, 2026-09-05 — agy baseline in
`docs/agents/external-cli-baselines.md` is **1.1.18**; installed agy is **1.1.27**. Nine releases
of print-mode (`-p`) changes are unreviewed.

Triage: ready-for-agent

## Problem

`run_agy` decides whether the Gemini seat succeeded almost entirely from **agy's exit code**: a
non-zero exit from either attempt drives the fallback and then the seat-down path. Three changes in
the unreviewed range move exactly that signal, and a fourth changes what a prompt means.

### 1. `-p` exit codes were deliberately narrowed (1.1.20)

> Fixed print mode (`-p`/`--print`, including `--output-format json` and `stream-json`) treating
> benign tool execution errors and permission denials as fatal run failures with non-zero exit
> codes, ensuring headless exit codes reflect only cascade-level failures and match interactive
> session behavior.

This is the dangerous direction for this wrapper. Conditions that used to exit non-zero — and so
were caught as a failed attempt — now exit **0**. A seat run that lost most of its tool calls to
denials can now return a clean exit with a thin or block-less answer, and `attempt()` will relay it
as a success. The only remaining catch is `parse_block`, which rejects a missing or malformed block
but happily accepts a *well-formed* block built on almost no evidence.

### 2. Denied actions are now reported, giving a usable detector (1.1.27)

> Fixed headless runs with `-p` silently skipping tool actions they were not permitted to take,
> which now end with a notice naming the refused actions and report them as `denied_actions` in the
> JSON output.

The seat runs with `--dangerously-skip-permissions`, so denials should be rare — but "should be" is
the assumption item 1 removed the guard for. Whether the notice appears on stdout (and would land
inside the relayed output) or stderr is unmeasured, and matters: anything printed on stdout that is
not the response is contamination the fence scan has to survive.

### 3. Piped-stream handling changed (1.1.24)

> Fixed headless CLI invocations with piped standard output or standard error hanging on exit by
> setting `FD_CLOEXEC` on the preserved streams so child processes do not keep the caller's pipes
> open.

`run_agy` redirects stdout to a file and lets stderr pass through, and `await_seats` captures both.
This fix is in the panel's favour, but `issues/59` proposes *also* capturing stderr to a file, and
that proposal should be written against the 1.1.27 stream behavior rather than the 1.1.18 one.

### 4. Slash commands expand in print mode

`agy --help` on 1.1.27 documents `--disable-slash-commands  Disable slash command and skill
expansion in print mode`. A prompt whose **first** token is a slash command is executed as that
command, and the changelog records that a command followed by a newline parses, and that multiple
leading commands stack. Today the panel is unaffected — both prompt templates start with
`{{SEAT_CONTRACT}}`, whose rendered text begins `You are performing…` / `You are continuing…` — but
nothing enforces that, and free-text scope (`panel-review:start "<question>"`) puts user-supplied
text into the run. The decision to make is which side of this the panel wants: `issues/60` wants
expansion **on** so `/boost` works, which rules out adopting `--disable-slash-commands` and makes
"no seat prompt may begin with `/`" an invariant somebody has to own.

## Expected behavior

1. Each of the four items above is measured on the installed agy and the result recorded here with
   the version, the way `issues/20` records its model-pin measurements.
2. `run_agy`'s failure detection covers the exit-0-with-a-degraded-answer case that item 1 created,
   or this issue records why it is judged acceptable and what would catch it instead. A cheap
   candidate: treat the presence of a denied-actions notice, or an implausibly short response, as a
   failed attempt — but only after item 2 establishes which stream carries it.
3. The panel states, in one place, whether agy slash-command expansion is on by design. If it is
   (the `issues/60` direction), the "a seat prompt must not begin with `/`" invariant is written
   down and structurally checked in `assemble` or `check_contracts`, not left to chance.
4. `docs/agents/external-cli-baselines.md` advances its agy row to 1.1.27 once this issue and
   `issues/23`, `issues/27` and `issues/59` have taken their share of the delta.

## Verification

- A `run_agy` invocation whose tools are all denied is shown to exit 0 (item 1 confirmed) or
  non-zero (item 1 does not apply on this version) — either result is a valid answer, but it must be
  measured, not assumed.
- The stream carrying the denied-actions notice is identified from a real run.
- A prompt beginning with `/boost` is shown to be executed as a command, and a prompt beginning with
  prose is shown to be sent verbatim.
- `scripts/check_contracts --root .` and `./tests/run_tests.sh` pass.

## Non-goals

- Do not fold in `issues/59` (the print-timeout shape). Same wrapper, adjacent symptom, separate
  measurement; land whichever comes first without rewriting the other.
- Do not adopt any new agy flag here. `issues/23` is the register that records a decision per flag.
- Do not change model pins (`issues/21`) or add `/boost` (`issues/60`) as part of this issue.
