# Rename the free-text scope placeholder away from "question"

Priority: 30

Status: Pending

Source: usability review, 2026-08-16

Triage: ready-for-human

## Problem

The scope alternatives are advertised as:

```text
--base <branch> | --uncommitted | --commit <SHA> | <question>
```

Three of the four are named by *what they select*; the fourth is named by the *grammatical form of
the text you type*. That is the wrong axis. `CONTEXT.md:10` defines the scope as "the code change or
technical question that every seat reviews", and everything downstream — the manifest field, the
skill's parse table, the referee's handoff line — calls the whole thing `scope`. Only the
user-facing placeholder switches vocabulary.

The result is two concrete confusions:

- **`<question>` reads as a channel for asking something**, not as a declaration of what is under
  review. In the same argument hint it sits next to `[<focus text> | --instructions <text|auto>]`,
  which *is* the "say what you want looked at" channel — so the hint appears to offer two ways to
  phrase a request, when in fact one names the subject and the other steers the reviewers.
- The two are **mutually exclusive by construction** and the naming hides it: a bare free-text scope
  has no separate instructions channel at all (`README.md:214` — "the question text *is* the
  scope"). A user who reads `<question>` as "the thing I want to ask about this diff" gets a
  diffless review of their sentence.

The wording is not wrong about the supported use — validating an answer to a broad technical
question is a real scope — it is wrong about the *category*, and the category is what the user has
to get right at the prompt.

## Expected behavior

Rename in two separable layers. Layer 1 is cheap and self-contained; layer 2 is optional and has a
compatibility cost, so it should be decided on its own merits rather than dragged along.

**Layer 1 — user-facing placeholder (do this).** One name, used in every surface a user reads:

- `skills/start/SKILL.md:5` (`argument-hint`) and its usage error at `skills/start/SKILL.md:74`
- `README.md:160` (usage block) and `README.md:214` (the instructions note)
- `skills/panel-review-for-agent/SKILL.md:41` (the referee's scope line, user-visible in prose)

Candidates, with the trade-off:

| Candidate | For | Against |
|---|---|---|
| `<topic>` (recommended) | Short; names a subject, not a sentence form; reads as an alternative to the three diff scopes | Slightly undersells that a question is fine |
| `<topic or question>` | Loses nothing | Long in a hint line that is already long |
| `<free-text scope>` | Maximally explicit about the category | Jargon-ish; "scope" is repo vocabulary, not user vocabulary |

Recommendation: `<topic>` in the hint, with the README line spelling out the range once —
`panel-review:start "<topic>"   # review a free-text topic or question (no diff)`.

**Layer 2 — internal `question=` scope token (decide separately).** The literal prefix appears in
`scripts/resolve_diff:12,53`, `scripts/diff_hash:4,9` (comments), `skills/start/SKILL.md:59,68,136,157`,
`agents/panel-review-referee.md:28`, and `tests/fixtures/decide_round/manifest.json`. Renaming it to
match (e.g. `topic=`) removes the last vocabulary split, but the token is written into the manifest,
so a run created before the change and resumed after it would carry the old prefix. If layer 2 is
taken, `resolve_diff` must accept both prefixes for one release, or the change must be declared as
breaking in-flight runs.

## Verification

- `grep -rn "<question>" README.md skills/` returns nothing after layer 1.
- `scripts/check_contracts --root .` passes (confirm first whether any invariant pins the old
  placeholder; the current grep shows none, but the check must be rerun after edits).
- `./tests/run_tests.sh` passes.
- A `start` invocation with a bare free-text argument still produces the same `question=`/`topic=`
  manifest scope and the same diffless behavior — this is a naming change, not a behavior change.

## Non-goals

- Do not add a flag for the free-text scope (e.g. `--topic <text>`); the bare-argument form is the
  short path and adding a flag alongside it creates a second way to say the same thing.
- Do not give the free-text scope its own instructions channel here — that is a behavior change and
  belongs in its own issue if it is ever wanted.
- Do not rename the `scope` concept itself.
