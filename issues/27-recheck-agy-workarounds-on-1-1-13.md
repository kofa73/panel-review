# Re-verify the two agy workarounds on the current CLI

Priority: 27

Status: Pending

Source: agy CHANGELOG review (1.1.11 → 1.1.13), 2026-08-15

Triage: ready-for-human

## Problem

Two facts in `AGENTS.md` describe agy behavior that may have changed. Each fact carries a
workaround the plugin pays for on every run. A short probe touched the repo-root question, but the
realistic-size root comparison and >99 KB prompt replay remain incomplete on the current CLI.
Nothing is known to be broken. The risk is carrying complexity and prompt budget for defects that may
be fixed.

### 1. The repo-root guess (agy runs tools in its own sandbox)

`AGENTS.md` records that agy guesses the repository root each run, that `cd`-ing the wrapper cannot
move it, and that a prompt therefore needs an absolute path anchor plus an explicit "set the tool
`cwd`" directive — with an observed drift to `/home/developer` under a very large prompt.

agy **1.1.12**: "Improved repository detection so a Git repository nested inside a larger
multi-repository checkout resolves to the intended root, with submodules and worktrees covered."

That is the same subsystem. If the guess is now reliable, the prompt anchor is cheap insurance and
can stay, but issue 23's `--add-dir` candidate becomes moot and the fact needs a dated update rather
than deletion.

### 2. Prompt size correlated with prose-not-JSONL output

`AGENTS.md` records that a `round0.prompt` over ~99 KB produced prose without a fence from the
Gemini seat, while ≤~87 KB produced valid blocks — the reason the plugin keeps prompts lean and the
output contract salient.

agy **1.1.13**: "Fixed trajectory truncation destroying nearly all of a long conversation's history,
by charging the size budget only against steps whose bytes can actually be reclaimed instead of
against protected checkpoints and the unreclaimable residue of already-cleared steps."

A truncation bug that eats a long input is a plausible mechanism for exactly the observed failure
(a contract at the end of a huge prompt disappearing before the model sees it). This is a
hypothesis, not a finding — the original observation was correlational too.

## Expected outcome

A dated re-measurement of both facts on the installed agy, and `AGENTS.md` updated to say what is true
now while keeping the historical observations and their versions. Specifically:

- Fact 1: run a seat pass with the current prompt anchor and one without it, at a realistic prompt
  size, and record where agy's tools actually resolved. Update the fact; decide `--add-dir`
  (issue 23) on that evidence.
- Fact 2: re-run the >99 KB prompt shape that failed and record whether the fenced block comes back.
  If it does, say so with the version; **do not** relax the lean-prompt rule on the strength of a
  changelog entry alone, and do not raise any prompt budget as part of this issue.

## Already corrected (no work left)

`agy models` piped output on 1.1.13 prints `<slug>\t<label>`, not the slug column alone that issue
20 recorded for 1.1.10; and `agy models --output-format json`, announced in the 1.1.12 changelog,
does not exist in 1.1.13 (usage error, exit 1). `scripts/run_agy`'s header already states this.

## Verification

- Both measurements are recorded in this file with the agy version and date before `AGENTS.md`
  changes.
- `scripts/check_contracts --root .` and `./tests/run_tests.sh` pass.
- One real review runs end to end with the Gemini seat engaged.

## Non-goals

- Do not delete a hard-won fact on changelog evidence alone; measure first.
- Do not change `run_agy`'s invocation form or model pins here (issues 20 and 21).
- Do not raise the prompt-size budget as part of this issue.

## Open questions for the owner

1. Can the remaining large-prompt measurements run in a later live-test slot, after issue 63 selects
   the seat pins?
   - (a) **Recommended:** compare the prompt with and without the absolute path at realistic size,
     then replay the historical >99 KB prompt. Coordinate with issues 23 and 60 so one setup also
     measures `--add-dir` and the worktree location.
   - (b) Defer those calls and keep the issue Pending. This leaves the current safeguards in place
     but does not answer either behavioral question.
2. How should the required real-review check proceed under the no-`git checkout` rule?
   - (a) **Recommended:** provide a smoke script that creates its test branch without `git checkout`,
     then run it with a Gemini seat engaged. The current `/tmp/panel-issue-run/smoke.sh` runs
     `git checkout -q -b bug`; a compliant script would meet the issue's verification requirement.
   - (b) Waive the real-review check for this documentation-only update and leave this issue Pending.

## Comments

### 2026-09-05 — the version this issue names is four releases stale

Installed agy is now **1.1.27**; this issue is written against 1.1.13, and the recorded baseline in
`docs/agents/external-cli-baselines.md` is 1.1.18. Two things follow.

**The measurements are still the right ones, but must be taken on 1.1.27.** Both workarounds this
issue re-checks — the absolute path anchor (agy guesses its repo root) and the prompt-size limit
(prose-not-JSONL above ~99 KB) — are behavioral, not versioned, so re-running them on 1.1.13 would
prove nothing about what the panel runs today.

**The repo-root question has new evidence in it.** `issues/60` may put the Gemini seat under
`/boost`, which runs subagents in "ephemeral isolated worktrees". Where those land is the same
question this issue asks about the anchor, one level down. Take the two measurements together if
both are live; they share a setup.

Nothing here changes this issue's scope or its non-goals — only the version to measure on.

### 2026-10-20 — small root probe on agy 1.4.3

`agy --version` reported **1.4.3**. `agy models` listed `Gemini 3.8 Flash (Low)`, used for one
short print-mode probe. The prompt contained no repository path:

```sh
printf '%s' 'Use a terminal tool to report the current working directory and the output of git rev-parse --show-toplevel from that same directory. Do not open or change files. Return only those two values.' | timeout 30 agy --print-timeout=20s --model 'Gemini 3.8 Flash (Low)' --dangerously-skip-permissions
```

The command exited 0 and returned `/workspace/panel-review` for both values. This is a small probe,
not a seat pass or a realistic-size comparison. The current CLI's anchored-versus-unanchored root
behavior at realistic prompt size remains unmeasured. No >99 KB prompt was sent, so the truncation
change and fenced-block behavior also remain unmeasured. Keep both safeguards in place.

The real-review verification remains open. The provided smoke script invokes `git checkout -q -b bug`,
which the worker brief prohibits. This update changes documentation only; no panel review was run.
