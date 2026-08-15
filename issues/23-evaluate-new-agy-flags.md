# Evaluate new agy CLI capabilities for the Gemini seat

Priority: 23

Status: Optional

Source: external CLI update review (agy 1.1.6 → 1.1.10), 2026-08-05

Triage: ready-for-human

## Problem

agy gained four flags since `run_agy`'s contract was written. None is required, two are plausible
robustness wins against failure modes this repository has already hit, and one should be explicitly
declined so it is not adopted later "for safety". Recording the evaluation prevents the same
analysis being redone at the next CLI update.

## Candidates

### `--disable-slash-commands` — cheap hardening, probably adopt

agy 1.1.9 made print mode expand slash commands *and skills* found in the prompt, with this flag to
opt out. 1.1.9 also widened recognition to commands separated from their arguments by a newline or
tab.

Panel-review feeds its prompt on stdin and every template starts with plain prose, so today's
exposure is low. It is not zero: the prompt carries a diff and card text the plugin does not control,
and the failure would be silent — an expanded command changes what the seat reviews without changing
what the referee thinks it sent.

Open question before adopting: confirm that stdin-fed prompts (no `--print`) go through the same
expansion path as `-p`. If they do not, the flag is a no-op and can still be passed as insurance
against that changing.

### `--add-dir <dir>` — test before adopting

`AGENTS.md` records that agy runs tools inside its own managed sandbox and *guesses* the repository
root each run, which `cd` cannot influence; the mitigation is an absolute path anchor plus an
explicit "set the tool `cwd`" directive in the prompt. `--add-dir` adds a directory to the workspace
and is a mechanical anchor rather than a prompt instruction.

Verified 2026-08-05 (agy 1.1.10, small prompt, existing prompt anchor only): the seat reported `pwd`
= the workdir and ran `git status --short` and `git diff --stat HEAD~1` successfully, so the current
mitigation works at that prompt size. The known drift case was a very large prompt.

Test to run before adopting: a deliberately large prompt with and without `--add-dir`, checking
whether the flag changes the sandbox's root guess. Adopt only if it does — an inert flag in a
wrapper that documents every flag's reason is worse than none.

### `--output-format json` + `--json-schema` — recommend against

Structured output would attack the known prose-not-JSONL failure directly. It is still the wrong
trade here: all three seats deliver the same fenced-block contract to `parse_block`, and making one
seat's transport different adds an envelope-unwrapping step, a second parse path, and a second place
for `seat_contract.py`'s schema to drift. The existing mitigations (lean prompts, salient contract,
`check_draft`, referee salvage) address the same failure without splitting the contract.

Reconsider only if prose-without-fence recurs after prompt-size control.

### `--sandbox` — decline, and say why

agy now exposes an opt-in sandbox with terminal restrictions. Panel-review deliberately runs the
seat unconstrained (`--dangerously-skip-permissions`) because safety rests on the disposable
container plus `repo_guard`, and because a sandboxed seat cannot run the tools the review asks for —
the same lesson `run_codex` already records. Worth one line in the `run_agy` header so it is not
added later as an apparent improvement.

Related, no action: agy 1.1.10 made `.git` read-only inside its terminal sandbox. Verified above
that read-only git commands still work; only a write-touching command (`stash`, `worktree`, `gc`)
would fail, and no prompt asks a seat for one.

## Expected outcome

A decision recorded per candidate, and for each adopted flag a `run_agy` header entry explaining why
it is there — matching the existing convention that every flag in that wrapper carries its rationale.

## Verification

- Any adopted flag is exercised by one real review with the Gemini seat engaged.
- `--add-dir` is adopted only with the large-prompt comparison recorded in this file.
- `scripts/check_contracts --root .` and `./tests/run_tests.sh` pass.

## Non-goals

- Do not change the Gemini seat's output contract or `parse_block`'s interface.
- Do not adopt `--effort` (see issue 20).
- Do not add flags whose effect has not been observed on this machine.
