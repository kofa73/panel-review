# Put the lifecycle state mechanics behind one controller

Priority: 51

Status: Deferred

Source: Simplification panel (Sol, "Boundary 1"), 2026-08-16

Triage: ready-for-human

## Problem

`skills/start/SKILL.md`, `skills/resume/SKILL.md`, and `skills/continue/SKILL.md` are 239, 146, and
107 lines of Markdown that a model executes as a procedure. They repeat marker enumeration, manifest
adoption, diff resolution and hashing, limit validation and write-back, Agent-failure handling,
artifact validation, and cleanup. `resume` and `continue` refer back to "start Step 5", so
correctness depends on a prose cross-file jump that no test can check.

`scripts/inspect_run:41-90` and `scripts/resume_check:46-88` independently read the same manifest and
index and resolve the same diff, and already disagree about a corrupt index (issue 48, item 2).

This is the largest remaining body of state-machine behavior encoded in model instructions rather
than in tested code. ADR-0004 puts deterministic mechanics in scripts; the command skills are the
place that rule was never applied.

## Expected behavior

Add one deterministic lifecycle module (`runctl`) whose subcommands emit small JSON action plans:

- `inspect --workdir` — pure classification: no run, interrupted, continuable, diverged, stale,
  invalid. `inspect_run` and `resume_check` both become callers of this one classifier.
- `create` — validate resolved inputs, snapshot the profile, write canonical `/tmp` state, publish
  the marker last.
- `resume-plan` / `continue-plan` — adopt the saved identity, apply explicit overrides, return the
  exact referee prompt parameters.
- `reopen` — archive and reopen through the existing `index` owner.
- `delivery` — validate the artifact, return the fixed user-facing pointer and gate state, and run
  eligible cleanup only after validation succeeds.
- `discard` — enumerate and remove this workdir's state through one implementation.

Each command skill then owns only what needs the main Claude context: interpreting the invocation,
asking the human the low-severity/continue question, making the foreground referee Agent call, and
printing the controller's fixed result.

`scripts/set_limits` (33 lines, used only by resume/continue) folds into the controller.

Move one verb at a time — status, resume, continue, then start and discard — with characterization
tests for the existing classification and delivery behavior written **first**. Keep the six public
verbs and their differing mutation permissions exactly as ADR-0003 defines them.

## Verification

- Characterization tests for the current behavior pass unchanged against the controller.
- Interruption, divergence, stale-state, and continuation paths each have a test.
- One real review per migrated verb before the corresponding prose is deleted.

## Non-goals

- **Do not interpolate `$ARGUMENTS` into a shell command.** Claude Code substitutes the full string
  exactly as typed (`claude-code-docs/docs/skills.md:386-423`), and the current grammar deliberately
  treats everything after `--instructions` as literal text. Either retain model-side argument parsing
  or define a tested stdin/JSON transport that preserves arbitrary bytes. Moving state mechanics is
  the value here; a shell-injection-prone argument parser is not.
- Do not collapse the six verbs into one intent-guessing command. ADR-0003 is the reason they are
  explicit, and issue 32 already tracks the natural-language front-end question separately.
- Do not let the controller silently repair corrupt state; see issue 48.

## Comments

`Deferred` because it should follow the correctness work (issues 24, 33-38, 41-43) and the inert-state
removal (issue 45) — a controller built on the current text would freeze known-bad behavior into a
new interface.
