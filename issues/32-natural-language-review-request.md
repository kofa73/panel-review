# Evaluate a natural-language front-end for starting a review

Priority: 32

Status: Optional

Source: usability review, 2026-08-16

Triage: needs-triage

## Problem

A fully specified `start` line is long and order-sensitive, and the argument hint that documents the
order disappears from the terminal as soon as the user starts typing:

```text
panel-review:start --commit 123abc --review-profile /home/developer/.claude/skills/darktable-review/references/review-profile.md --instructions watch out for any deadlocks the new foolock may cause
```

The user must remember rules that are invisible at that moment: `--review-profile` before
`--instructions`, `--instructions` last with everything after it taken literally, trailing free text
last and free of `--`-looking tokens, and the fact that trailing text after *no* scope flag means
something entirely different (it becomes the scope).

The same request as a sentence carries all of it with no syntax to recall:

```text
check commit 123abc using <path to profile>; watch out for any deadlocks the newly introduced foolock may cause
```

## Why this is not simply "parse the sentence"

Two constraints make the obvious implementation wrong:

1. **A bare free-text argument already has a meaning.** With no scope flag, leftover text *is* the
   scope — a diffless review of that text (`skills/start/SKILL.md:59,68`). So "interpret the argument
   as natural language when there are no flags" silently changes the meaning of currently valid
   input. Natural-language mode cannot be inferred; it has to be requested.
2. **A mis-parse is expensive and silent.** Parsing today is deterministic and done by the skill's
   own rules; a natural-language parse is a model judgement. Getting the scope wrong does not error —
   it runs a full three-seat review of the wrong thing. (It does not destroy an existing run:
   `start` refuses when a saved review exists.)

## Options

- **A — separate human-only skill.** e.g. `panel-review:review "<sentence>"`: translates the sentence
  into the exact canonical `panel-review:start …` line, **prints it, waits for the human's
  go-ahead**, then runs it. `start`'s grammar stays the single deterministic contract, the free-text
  scope keeps its meaning, and the mis-parse risk is eliminated by the echo rather than by better
  parsing. Costs one confirmation round trip. Must be `disable-model-invocation: true` for the same
  reason `start` is.
- **B — prefix inside `start`.** e.g. `panel-review:start nl: check commit 123abc …`. One less skill,
  but it puts two grammars behind one verb and still needs the confirmation echo.
- **C — natural language when no flags are present.** Rejected: collides with the free-text scope
  (constraint 1).

Recommendation: **A**, and only after measuring whether the pain survives issue 18 (see below).

## Sequencing note

Part of the length is already being addressed elsewhere, and this issue should be re-evaluated after
those land rather than duplicating them:

- Issue 18 adds named profiles (`--review-profile darktable`) and durable defaults, which removes the
  longest token in the example line and, with `defaults.review_profile`, often the flag entirely.
- Trailing free text already covers the "watch out for …" half without a flag.

After both, the example above is close to `panel-review:start --commit 123abc watch out for any
deadlocks the new foolock may cause` — which may be short enough that a second grammar is not worth
its cost. Measure before building.

## Verification (if adopted)

- A sentence naming a commit, a profile, and a focus produces the exact equivalent `start` line, is
  shown to the user, and runs only after explicit confirmation.
- A sentence the front-end cannot resolve to one scope stops and asks, rather than guessing.
- `panel-review:start` behavior is byte-identical to today, including bare free-text scope handling.
- The new skill is not model-invocable.

## Non-goals

- Do not make `start` model-invocable, and do not let a natural-language path skip the "saved review
  already exists" refusal.
- Do not change the flag grammar to accommodate the sentence form.
- Do not infer the scope from repository state (branch, last commit) when the sentence is ambiguous.
