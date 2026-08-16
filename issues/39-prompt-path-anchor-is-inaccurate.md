# Correct the blind-pass prompt's "every path resolves under the root" claim

Priority: 39

Status: Pending

Source: Panel review `panel-20260816-080558-5ab680af` (Claude + Codex + Gemini), 2026-08-16 — accepted unanimously, severity `low`

Triage: ready-for-agent

## Problem

`prompts/blind_pass.tmpl:8`, immediately after the absolute workdir anchor, states:

```text
Every path below (the diff file, scratch dir, any file you read) resolves under it.
```

It is false for two of the three items it names. `scripts/round:366` points `DIFFINFO` at
`/tmp/<ID>/diff.txt` and `scripts/round:144` puts the review profile at
`/tmp/<ID>/review-profile.md`. Only the scratch dir is actually under the workdir — and issue 24
argues it should not be.

`prompts/debate.tmpl:13` repeats the sentence verbatim and then supplies `{{PROFILEINFO}}`
(`prompts/debate.tmpl:49`), which also resolves to `/tmp/<ID>/`, so a correction has to touch both
templates.

This matters more than a wording slip because of what the anchor is for. `AGENTS.md:141` records
that agy runs its tools inside its own managed sandbox and guesses the repo root each run — it was
observed anchoring at `/home/developer` instead of the workdir under a large prompt. This sentence is
the documented correction for exactly the seat least able to tolerate an inaccurate one: a seat that
reads it literally and then receives a `/tmp/...` path has been given contradictory instructions
about where it is.

## Expected behavior

1. Both templates state the anchor accurately: the **code under review** resolves under the workdir;
   the diff file and review profile are absolute paths outside it and are given in full. Keep the
   existing "pass `cwd` explicitly" directive — that is the part that does the work.
2. The two templates stay in sync. If `check_contracts` can assert the shared anchor wording, add it
   there; otherwise note the pairing in the templates.

## Verification

- `grep -n "resolves under" prompts/*.tmpl` shows the corrected wording in both files.
- `scripts/check_contracts --root .` passes.
- `./tests/run_tests.sh` passes.

## Non-goals

- Do not move the diff or profile into the workdir to make the sentence true. `/tmp/<ID>/` is the
  single source of truth by design, and putting review inputs inside the reviewed tree is the defect
  issue 24 exists to fix.
- Do not drop the anchor. It is the workaround for agy's root guessing; issue 27 covers re-measuring
  whether that workaround is still needed on agy 1.1.13.
