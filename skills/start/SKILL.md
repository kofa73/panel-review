---
name: start
description: Start a fresh panel review (three-way blind debate across Claude + Codex + Gemini). Takes the scope, optional author instructions, and round limits. Refuses if a saved review already exists for this workdir.
disable-model-invocation: true
argument-hint: "--base <branch> | --uncommitted | --commit <SHA> | <question>  [--issue-rounds N] [--max-rounds N] [--debate-low]  [<focus text> | --instructions <text|auto>]"
---

# panel-review:start

You are the **main-context entry point** for starting a fresh review. Your job: parse the scope +
instructions + round limits, refuse if a session already exists, otherwise mint the run and dispatch
the `panel-review:panel-review-referee` agent, then present its verdict **verbatim**. You do **not** run the review
yourself. Run everything from the repo root.

```bash
# CLAUDE_PLUGIN_ROOT is substituted into this text at skill-load — it is NOT a
# shell env var (it's empty in the shell). Keep the literal verbatim; don't
# build it dynamically or read $CLAUDE_PLUGIN_ROOT at runtime.
SC="${CLAUDE_PLUGIN_ROOT}/scripts"
```

## Step 1 — parse `$ARGUMENTS` (instructions, then round limits, then scope)

The harness does **not** parse flags; you get the raw `$ARGUMENTS` string. Parse it yourself:

0. **`--instructions` (explicit form) — extract this BEFORE round limits, `--debate-low`, and
   scope.** It must be processed first because everything after it is literal: if the token
   `--instructions` appears, it must be **last** in `$ARGUMENTS`, and you take **everything after it** —
   verbatim, including newlines and any `--`-looking tokens — as the instruction text, then remove
   `--instructions` + that text from the string. This is the escape hatch: after `--instructions`,
   nothing is parsed as a flag, so the text may contain `--max-rounds`, file paths, etc. Set `INSTR` to
   that text. The special value `--instructions auto` sets `INSTR=auto` (referee generates context from
   branch / commit messages / `git status`). If `--instructions` is present but the text is empty, stop
   with `--instructions needs text (or 'auto').` If `--instructions` is absent, leave `INSTR` unset for now.
1. **Round limits.** Defaults `issue-rounds=2`, `max-rounds=4`. Apply `--issue-rounds N` /
   `--max-rounds N` if present, then validate the **resolved** values: each a positive integer and
   `issue-rounds ≤ max-rounds`. Otherwise stop with a one-line error.
1b. **`--debate-low`** (boolean, default off). If present, set `DEBATE_LOW=true` and remove it from
   the string; else `DEBATE_LOW=false`. It tells the agent to debate even when Round 0 finds only
   low-severity items (skip the Round-0 severity gate).
2. **Scope** from what remains after removing the instructions/round/boolean flags, as a **canonical
   token**, then **any leftover free text alongside a diff scope becomes the instructions** (the
   keyword-less form):

   | In `$ARGUMENTS` | Canonical `scope` token | Leftover free text |
   |-----------------|-------------------------|--------------------|
   | `--base X` | `base=X` | → `INSTR` (if `INSTR` not already set) |
   | `--uncommitted` | `uncommitted` | → `INSTR` (if `INSTR` not already set) |
   | `--commit SHA` | `commit=SHA` | → `INSTR` (if `INSTR` not already set) |
   | leftover non-empty free text, **no** scope flag | `question=<that text>` | (the text *is* the scope) |

   Positionality / precedence:
   - A **diff scope** (`--base`/`--uncommitted`/`--commit`) + trailing free text → that text is the
     instructions. Put it **after** the scope and any `--issue-rounds`/`--max-rounds` flags. It must
     **not** contain `--`-looking tokens (they'd be parsed as flags) — if it needs to, use the
     explicit `--instructions … ` form instead.
   - If `INSTR` was already set by `--instructions` (step 0) **and** non-flag free text also remains,
     stop with `Give instructions either as trailing text or via --instructions, not both.`
   - With **no** scope flag, leftover text is the `question=` scope itself (a diffless review); there
     is no separate instructions channel in that mode.
   - Default `INSTR` to empty if nothing set it.

3. If **no scope flag was given AND** nothing remains after removing the flags → print exactly:
   ```
   Specify a scope: --base <branch> | --uncommitted | --commit <SHA> | <question>  [--issue-rounds N] [--max-rounds N]  [<focus text> | --instructions <text|auto>]
   ```
   and stop. (`--uncommitted` legitimately leaves no positional text — that is a valid scope, not
   an error. Never guess a base branch.)

## Step 2 — prereqs + scope hash

```bash
"$SC/preflight" || { echo "Core prerequisites missing (see above)."; exit 1; }   # also prints CODEX: yes|no / GEMINI: yes|no
# Resolve to a FILE and check the exit code separately — do NOT pipe resolve_diff
# into diff_hash: a bad ref makes resolve_diff fail but diff_hash succeeds on the
# empty input, so the pipeline would silently hash an empty diff and proceed.
DIFF_FILE="$(mktemp /tmp/panel_scope_diff.XXXXXX)"
if ! "$SC/resolve_diff" "$scope" > "$DIFF_FILE"; then
  rm -f "$DIFF_FILE"
  echo "Could not resolve scope '$scope' (bad branch/commit, or not a git ref). Fix it and retry."; exit 1
fi
DH="$("$SC/diff_hash" < "$DIFF_FILE")"
rm -f "$DIFF_FILE"
```
If `preflight` hard-fails, stop and surface its message. A `CODEX: no` or `GEMINI: no` is fine (the
review runs with the remaining seats) — pass it through. For a diff scope whose resolved diff is
empty, you may stop early with "no changes in scope" rather than dispatching.

## Step 3 — refuse if a session already exists

This check is about the **existing** session's own state, not about whether it matches the scope you
just parsed — a saved `--uncommitted` review is still a saved review even if you just asked for
`--base main`. So classify it self-referentially, not by comparing it to `$scope`/`$DH`:

```bash
base="$PWD/.panel-review"
ids=(); [ -d "$base" ] && for d in "$base"/*/; do [ -f "$d/.panel-run" ] && ids+=("$(basename "$d")"); done
```

- **`${#ids[@]}` is 0** → no saved session. Proceed to Step 4.
- **`${#ids[@]}` is more than 1**, or the one id fails `panel_valid_id` (not your call to check
  directly — `inspect_run`/`resume_check` apply it; here just notice you have an unexpected marker
  count) → **ambiguous**. Stop:
  > More than one review marker under `.panel-review/` (only possible if it was edited out of band).
  > `panel-review:discard` clears them all (then `panel-review:start` for a new review), or remove the
  > `.panel-review/<ID>/` + `/tmp/<ID>/` pairs by hand — `panel-review:status` lists them with creation
  > times.
- **Exactly 1 id** → inspect it on its own terms:
  ```bash
  RESULT="$("$SC/inspect_run" --id "$id" --workdir "$PWD")"
  state="$(jq -r '.state' <<<"$RESULT")"
  ```
  - **`stale`** → the marker's `/tmp/<ID>` state is gone (volume cleaned). Drop the dead marker and
    proceed to Step 4 — no need to ask:
    ```bash
    "$SC/cleanup" --id "$id" --workdir "$PWD"
    ```
  - **`interrupted`** or **`continuable`** (resumable / finished-with-leftovers) → stop:
    > A saved review exists (`<scope>`; instructions: «`<instructions>`»). `panel-review:resume` /
    > `panel-review:continue` to keep working it, or `panel-review:discard` to remove it.
    (`<scope>`/`<instructions>` from `$RESULT`.)
  - **`diverged`** → the reviewed code changed since the snapshot. Stop:
    > The working tree diverged from the reviewed snapshot — the code under review was modified since
    > this review started (`<scope>`; created `<created>`). It can't be resumed or continued; run
    > `panel-review:discard` before `panel-review:start`.
    Adapt "working tree" to "branch"/"commit" to match the scope's flavor (`--uncommitted` /
    `--base` / `--commit`); a `question=` scope never reaches this branch (no diff, never diverges).

## Step 4 — mint the run and dispatch

```bash
ID="$("$SC/init_run" --workdir "$PWD" --scope "$scope" --issue-rounds "$ISS" --max-rounds "$MAX" --diff-hash "$DH" --instructions "$INSTR")"
```

Spawn the `panel-review:panel-review-referee` subagent (Agent tool) with the resolved values in its prompt:

```
subagent_type: panel-review:panel-review-referee
prompt: |
  Run the panel-review referee protocol.
  mode=fresh
  id=<ID>
  workdir=<repo root absolute path>
  scope=<base=X | uncommitted | commit=SHA | question=...>
  issue-rounds=<ISS>  max-rounds=<MAX>  debate-low=<DEBATE_LOW>
  Return only the synthesized verdict in the documented Output format.
```

The agent reconstructs all state from `/tmp/<id>/`, runs the loop, and cleans up after producing the
verdict. Run from cwd = repo root.

**Await its single return — do not poke it.** The referee waits for its own slow seats internally
(one background `await_seats` barrier per pass), so it can legitimately run for many minutes with no
intermediate output. Do **not** `SendMessage`-resume it, re-dispatch it, or otherwise nudge it on
seat-completion notifications: every such poke makes the referee re-read its whole (long-context-tier)
context for nothing — exactly the waste these scripts exist to avoid. Let it run; act only on the
verdict it returns. (A genuine interruption — the human cancels — is recovered later via
`panel-review:resume`, not by poking the live agent.)

## Step 5 — present the verdict (and the low-severity gate)

**The pointer line is conditional.** The referee writes `/tmp/<ID>.md` best-effort and returns *only*
the verdict — it reports no write success/failure. So before appending any *"Saved to `/tmp/<ID>.md`
…"* pointer line below, confirm the artifact actually exists: `test -f "/tmp/<ID>.md"`. If it is
absent (the write failed, e.g. `/tmp` full), present the verdict **without** the pointer line — never
advertise a file that is not there. This applies to every branch that mentions the pointer line.

First check whether the agent's return ends with a control line of the form:

```
<<<PANEL-GATE id=<ID> reason=low-only open=<n>>>>
```

- **No control line** (the normal case) → present the verdict **verbatim** — do not re-summarize,
  re-classify, or add commentary. If it reports a degrade (any peer seat — Codex or Gemini — down), pass
  that note through as-is. Then, **if the artifact exists** (see above), append one line: *"Saved to
  `/tmp/<ID>.md` — move it somewhere permanent to keep it (`/tmp` is cleared on reboot)."* Done.

- **Gate line present** → Round 0 found only low-severity items and the agent skipped the debate to
  save tokens (the run is preserved, not cleaned up). Then:
  1. Present the verdict verbatim **with the `<<<PANEL-GATE …>>>` line removed** (it's a control
     signal, not for the human).
  2. **Append the `/tmp/<ID>.md` pointer line now** (only if the file exists) — at gate time, *before*
     the decision prompt — because choosing "Debate them" below overwrites this same path, so the user
     must be told the gate-time snapshot exists while it still does.
  3. **Ask the user** (`AskUserQuestion`): *Round 0 surfaced only low-severity findings. Debate them
     anyway (another pass across all three seats), or finish here?*
     - **Debate them** → re-dispatch the **same** `panel-review:panel-review-referee` agent (Step 4
       form) with `mode=resume`, `id=<ID>`, the same `workdir`/`scope`/limits, and `debate-low=true`.
       It reuses Round 0 (no seat re-run) and runs the debate loop. Present its returned verdict
       verbatim, then the `/tmp/<ID>.md` pointer line **again** (only if the file exists) — it has been
       refreshed with the debated result, overwriting the gate-time snapshot.
     - **Finish here** → the verdict and its pointer are already shown and the file is unchanged, so
       don't repeat the pointer; just tear the run down: `"$SC/cleanup" --id "<ID>" --workdir "$PWD"`.
       Done.

- **`<<<PANEL-CONTINUABLE id=<ID> unresolved=<n> contested=<m>>>>` present** → the run finished with
  leftovers and was preserved (not cleaned up). Present the verdict verbatim **with that line
  removed**, then append the `/tmp/<ID>.md` pointer line (only if the file exists) and one more: *"`<n>` unresolved, `<m>`
  contested remain — run `panel-review:continue [unresolved|contested]` to debate them further, or
  `panel-review:discard` to remove the saved review."* Do **not** clean up.

## Notes

- Read-only status (no scope to type): `panel-review:status`.
- The cards/state live in `.panel-review/<ID>/` (git-excluded) and `/tmp/<ID>/`. A clean finish removes
  both; an interruption leaves them for `panel-review:resume`/`panel-review:continue`.
