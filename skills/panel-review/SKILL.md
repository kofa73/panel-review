---
name: panel-review
description: Three-way symmetric BLIND debate across Claude + OpenAI Codex (GPT) + Google Gemini (agy CLI). Dispatches the review to the panel-review-referee agent. Resumable across crashes.
disable-model-invocation: true
argument-hint: "--base <branch> | --uncommitted | --commit <SHA> | <question>  [--issue-rounds N] [--max-rounds N] [--debate-low]  | --continue [unresolved|contested]"
---

# Panel Review — dispatcher

You are the **main-context entry point**. Your job: parse the scope + round limits, decide
resume-vs-fresh (you, not the agent — only the main context has `AskUserQuestion`), mint/validate
the run, dispatch the `panel-review-referee` agent, and present its verdict **verbatim**. You do
**not** run the review yourself. Run everything from the repo root.

```bash
SC="$HOME/.claude/skills/panel-review/scripts"
```

## Step 1 — parse `$ARGUMENTS` (round limits FIRST, then scope)

The harness does **not** parse flags; you get the raw `$ARGUMENTS` string. Parse it yourself:

0. **`--continue [unresolved|contested]` — handle this FIRST, before any other parsing.** If
   `$ARGUMENTS` contains `--continue`, set `CONT` to `both` (bare `--continue`), or to `unresolved`
   / `contested` if that word follows; remove `--continue` and its optional value from the string.
   Then require the remainder to be **empty**: if any other token remains — a scope flag, free text,
   `--issue-rounds`, `--max-rounds`, or `--debate-low` — stop with exactly
   `--continue takes the scope and limits from the finished run; don't combine it with another flag.`
   Then **skip the rest of Step 1** and follow **Step 1.5** instead (which runs Step 2's resolve+hash
   inline before Step 3, sourcing the scope and limits from the finished run). If `--continue` is
   absent, leave `CONT` unset and parse the rest of Step 1 (round limits, `--debate-low`, scope) normally.
1. **Round limits.** Defaults `issue-rounds=2`, `max-rounds=4`. Apply `--issue-rounds N` /
   `--max-rounds N` if present, then validate the **resolved** values: each a positive integer and
   `issue-rounds ≤ max-rounds`. Otherwise stop with a one-line error.
1b. **`--debate-low`** (boolean, default off). If present, set `DEBATE_LOW=true` and remove it from
   the string; else `DEBATE_LOW=false`. It tells the agent to debate even when Round 0 finds only
   low-severity items (skip the Round-0 severity gate).
2. **Scope** from what remains after removing the round/boolean flags, as a **canonical token**:

   | In `$ARGUMENTS` | Canonical `scope` token |
   |-----------------|-------------------------|
   | `--base X` | `base=X` |
   | `--uncommitted` | `uncommitted` |
   | `--commit SHA` | `commit=SHA` |
   | leftover non-empty free text | `question=<that text>` |

3. If **no scope flag was given AND** nothing remains after removing the flags → print exactly:
   ```
   Specify a scope: --base <branch> | --uncommitted | --commit <SHA> | <question>  [--issue-rounds N] [--max-rounds N]
   ```
   and stop. (`--uncommitted` legitimately leaves no positional text — that is a valid scope, not
   an error. Never guess a base branch.)

## Step 1.5 — `--continue` path (only when `CONT` is set)

Adopt the finished run's scope + limits instead of parsing them:

```bash
base="$PWD/.panel-review"
ids=(); for d in "$base"/*/; do [ -f "$d/.panel-run" ] && ids+=("$(basename "$d")"); done
[ "${#ids[@]}" -eq 1 ] || { echo "Need exactly one finished run to continue (found ${#ids[@]} in .panel-review/)."; exit 1; }
ID="${ids[0]}"; man="/tmp/$ID/manifest.json"
[ -s "$man" ] || { echo "The finished run's state was cleaned up; nothing to continue."; exit 1; }
scope="$(jq -r '.scope' "$man")"; ISS="$(jq -r '.limits.issue_rounds' "$man")"; MAX="$(jq -r '.limits.max_rounds' "$man")"
```

Now run **Step 2** (resolve + hash the CURRENT diff for that `scope`) and the **Step 3
`resume_check`** call, then require its verdict to be `continuable <ID>`:

- `moved <ID>` → the code moved since the finished run. Stop: "The code under review changed since finished run `<ID>`; run a fresh review instead." (this is the scope/diff gate)
- `resume <ID>` → the run still has open issues (interrupted, not finished). Stop: "Run `<ID>` isn't finished — resume it without `--continue`."
- `stale <ID>` → the run's `/tmp` state is gone; stop with "Run `<ID>`'s state was cleaned up; nothing to continue." (`fresh`/`ambiguous` cannot occur here — Step 1.5 already required exactly one run dir.)

On `continuable <ID>`, confirm the requested category exists, re-open, and dispatch:

```bash
have="$(jq --arg c "$CONT" '[.issues[] | select(($c=="both" and (.state=="unresolved" or .state=="contested")) or (.state==$c))] | length' "/tmp/$ID/index.json")"
[ "$have" -gt 0 ] || { echo "Run $ID has no $CONT issue to continue."; exit 1; }
"$SC/reopen" --id "$ID" --workdir "$PWD" --category "$CONT" || { echo "Could not re-open run $ID."; exit 1; }
```

Dispatch the `panel-review-referee` agent (Step 4 form) with `mode=resume`, `id=$ID`, the adopted
`scope`/`issue-rounds`/`max-rounds`, and `debate-low=true`. Present its verdict per Step 5. (Then
skip the normal Step 2/3 below — they were just run here.)

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
DH="$("$SC/diff_hash" < "$DIFF_FILE")"      # hash the exact diff; resume compares this
rm -f "$DIFF_FILE"
```
If `preflight` hard-fails, stop and surface its message. A `CODEX: no` or `GEMINI: no` is fine (the
review runs with the remaining seats) — pass it through. For a diff scope whose resolved diff is
empty, you may stop early with
"no changes in scope" rather than dispatching.

## Step 3 — resume / fresh decision

```bash
"$SC/resume_check" --workdir "$PWD" --scope "$scope" \
   --issue-rounds "$ISS" --max-rounds "$MAX" --diff-hash "$DH"
```
Act on the single verdict line:

- **`fresh`** → mint a run and go fresh:
  ```bash
  ID="$("$SC/init_run" --workdir "$PWD" --scope "$scope" --issue-rounds "$ISS" --max-rounds "$MAX" --diff-hash "$DH")"
  ```
  Dispatch with `mode=fresh`, `id=$ID`.

- **`resume <ID>`** → a prior run matches this invocation. **Ask the user** (`AskUserQuestion`):
  *Resume the interrupted review `<ID>`, or stop?*
  - Resume → dispatch with `mode=resume`, `id=<ID>`.
  - Stop → tell the user to remove `.panel-review/<ID>/` themselves (not your job to delete
    their state) and halt.

- **`continuable <ID>`** → a prior run on this exact scope **finished** with leftover
  `unresolved`/`contested` issues and was preserved (not cleaned up). **Ask the user**
  (`AskUserQuestion`): *Run `<ID>` finished with leftovers — continue debating them, start fresh, or
  stop?*
  - Continue → `"$SC/reopen" --id "<ID>" --workdir "$PWD" --category both`; dispatch `mode=resume`,
    `id=<ID>`, `debate-low=true`.
  - Fresh → `"$SC/cleanup" --id "<ID>" --workdir "$PWD"` then `init_run` a new ID; dispatch `mode=fresh`.
  - Stop → halt; leave the run for the user.

- **`stale <ID>`** → the marker's `/tmp/<ID>` state is gone (volume cleaned). Drop the dead marker
  and start fresh — no need to ask:
  ```bash
  "$SC/cleanup" --id "<ID>" --workdir "$PWD"      # removes the orphan marker (tmp already gone)
  ID="$("$SC/init_run" --workdir "$PWD" --scope "$scope" --issue-rounds "$ISS" --max-rounds "$MAX" --diff-hash "$DH")"
  ```
  Dispatch `mode=fresh`, `id=$ID`.

- **`moved <ID>`** → state exists but the scope/limits or **diff hash changed** (the code under
  review moved). Do **not** silently continue on stale cards. **Ask the user** (`AskUserQuestion`):
  *The code/scope changed since interrupted run `<ID>`. Start a fresh review (discard the old run),
  or stop?*
  - Fresh → `"$SC/cleanup" --id "<ID>" --workdir "$PWD"` then `init_run` a new ID; dispatch `mode=fresh`.
  - Stop → halt; leave the old run for the user.

- **`ambiguous`** → more than one marker dir (or an unexpected marker name). Stop and tell the user
  to clean up `.panel-review/` (keep at most one run) and retry. Do not delete it yourself.

## Step 4 — dispatch the agent

Spawn the `panel-review-referee` subagent (Agent tool) with the resolved values in its prompt:

```
subagent_type: panel-review-referee
prompt: |
  Run the panel-review referee protocol.
  mode=<fresh|resume>
  id=<RUN_ID>
  workdir=<repo root absolute path>
  scope=<base=X | uncommitted | commit=SHA | question=...>
  issue-rounds=<N>  max-rounds=<N>  debate-low=<true|false>
  Return only the synthesized verdict in the documented Output format.
```

Pass `debate-low=$DEBATE_LOW`. On a **resume-to-debate** re-dispatch (see Step 5) always send
`mode=resume` and `debate-low=true`.

The agent reconstructs all state from `/tmp/<id>/`, runs the loop, and cleans up after producing
the verdict. Run from cwd = repo root.

## Step 5 — present the verdict (and the low-severity gate)

First check whether the agent's return ends with a control line of the form:

```
<<<PANEL-GATE id=<ID> reason=low-only open=<n>>>>
```

- **No control line** (the normal case) → present the verdict **verbatim** — do not re-summarize,
  re-classify, or add commentary. If it reports a degrade (any peer seat — Codex or Gemini — down), pass that note
  through as-is. Done.

- **Gate line present** → Round 0 found only low-severity items and the agent skipped the debate to
  save tokens (the run is preserved, not cleaned up). Then:
  1. Present the verdict verbatim **with the `<<<PANEL-GATE …>>>` line removed** (it's a control
     signal, not for the human).
  2. **Ask the user** (`AskUserQuestion`): *Round 0 surfaced only low-severity findings. Debate them
     anyway (another pass across all three seats), or finish here?*
     - **Debate them** → re-dispatch the **same** `panel-review-referee` agent (Step 4 form) with
       `mode=resume`, `id=<ID>`, the same `workdir`/`scope`/limits, and `debate-low=true`. It reuses
       Round 0 (no seat re-run) and runs the debate loop. Present its returned verdict verbatim.
     - **Finish here** → the verdict is already shown; tear the run down:
       `"$SC/cleanup" --id "<ID>" --workdir "$PWD"`. Done.

- **`<<<PANEL-CONTINUABLE id=<ID> unresolved=<n> contested=<m>>>>` present** → the run finished with
  leftovers and was preserved (not cleaned up). Present the verdict verbatim **with that line
  removed**, then append one line: *"`<n>` unresolved, `<m>` contested remain — run `/panel-review
  --continue [unresolved|contested]` to debate them further, or remove `.panel-review/<ID>/` to
  discard."* Do **not** clean up.

## Notes

- Prerequisite-only status report: `/panel-review-init` (never dispatches a review).
- The cards/state live in `.panel-review/<ID>/` (git-excluded) and `/tmp/<ID>/`. A clean
  finish removes both; an interruption leaves them for resume.
