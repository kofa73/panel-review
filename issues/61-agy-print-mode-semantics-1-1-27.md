# Re-verify the Gemini seat against agy's changed print-mode semantics

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

## Open questions for the owner

1. Once the denied-actions notice is measured, should any denied action make `run_agy` fail the
   attempt and try the fallback, even when agy exits 0 and returns a valid block?
   - **Recommended:** yes. A response may contain a valid block even when the seat could not check
     all relevant evidence. Retrying with the other model preserves the existing failure path.
   - Accept the block when it parses. This keeps the current behavior but accepts the risk that the
     seat missed evidence after a denied action.

## Comments

### 2026-10-19 — exit codes moved again between 1.1.28 and 1.4.2

Installed agy is now **1.4.2**. Measure there, not on 1.1.27. Changes since this issue was filed:

- **Item 1 is narrower but not closed.** 1.2.10: headless runs "that streamed part of a response and
  then ended on a model or agent error" now exit `3` instead of `0`. 1.2.6: agent or model API
  failures exit `3` (was `1`) and print a structured `AGY_ERROR: {…}` line on stderr. Both help
  `run_agy`, which treats any non-zero exit as a failed attempt. Tool errors and permission denials
  still exit 0 (the 1.1.20 change stands), so the degraded-answer case this issue is about remains.
- **New stderr signals.** 1.1.28 added a stable `error:` marker for fatal errors and "a note … when
  the response may be truncated". Together with `AGY_ERROR` and the 1.1.27 denied-actions notice,
  these are the candidates for item 2's detector. `issues/59` needs the same stderr capture, so
  design it once.
- **1.2.15** "Improved how the agent handles a permission request that is not approved … it now
  respects the denial and no longer tries to work around it". With `--dangerously-skip-permissions`
  this should not arise, but it changes what a denied pass looks like.
- **1.3.6** headless `-p` runs skip questions that subagents ask, so a subagent cannot hang waiting
  for an answer. This matters only if `issues/60` adopts `/boost`.
- **Item 4:** `--disable-slash-commands` is unchanged on 1.4.2.

The timeout half moved to `issues/59` (agy 1.1.28 made a timed-out pass exit 0 with partial output).

### 2026-10-20 — stdin slash expansion confirmed on agy 1.4.3

`agy --version` reports **1.4.3**. `agy models` lists `Gemini 3.8 Flash (High)`, which was used for
the one permitted short print-mode probe. The probe fed `/help` on stdin using the wrapper's
non-interactive invocation form:

```
printf '/help' | timeout 30 agy --print-timeout=25s --model 'Gemini 3.8 Flash (High)' --dangerously-skip-permissions
```

It exited 0, printed agy's command list, and wrote nothing to stderr. This confirms that agy expands
a leading slash command on the stdin prompt path. The probe used `/help`, not `/boost`. The policy
remains to leave expansion enabled for `/boost` (issue 60). Both prompt templates require the prose
`SEAT_CONTRACT` sentinel on the first line. `scripts/check_contracts` checks the template prefix and
the rendered contract.

This probe did not attempt a denied tool action, so it does not measure whether all-denied runs exit
0 or where the denied-actions notice appears. It also does not measure a prose-first prompt's output
stream. The current `run_agy` pins are absent from the 1.4.3 model list, as issue 63 tracks. No
denied-action detector was added. Resolve the failure policy above after the notice and exit behavior
are measured. The external CLI baseline remains at 1.4.2 because this probe did not review the full
1.4.2-to-1.4.3 change set.

`scripts/check_contracts --root .` passed. `./tests/run_tests.sh` passed with 366 checks and no
failures. No panel review was run because this change does not alter the seat invocation.
