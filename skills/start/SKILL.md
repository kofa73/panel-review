---
name: start
description: Start a fresh panel review (three-way blind debate across Claude + Codex + Gemini). Takes the scope, optional review profile, optional author instructions, and round limits. Refuses if a saved review already exists for this workdir.
disable-model-invocation: true
argument-hint: "--base <branch> | --uncommitted | --commit <SHA> | <question>  [--review-profile <path>] [--issue-rounds N] [--max-rounds N] [--debate-low]  [<focus text> | --instructions <text|auto>]"
---

# panel-review:start

You are the **main-context entry point** for starting a fresh review. Your job: parse the scope +
instructions + round limits, refuse if a session already exists, otherwise mint the run, dispatch
the `panel-review:panel-review-referee` agent, and validate the durable report it writes. The report
file is the only verdict-delivery surface; never copy its body into this conversation. You do **not**
run the review yourself. Run everything from the repo root.

```bash
# CLAUDE_PLUGIN_ROOT is substituted into this text at skill-load — it is NOT a
# shell env var (it's empty in the shell). Keep the literal verbatim; don't
# build it dynamically or read $CLAUDE_PLUGIN_ROOT at runtime.
ROOT="${CLAUDE_PLUGIN_ROOT}"; ROOT="${ROOT%/}"   # strip trailing slash so $SC has no //
SC="$ROOT/scripts"
```

## Step 1 — parse `$ARGUMENTS` (instructions, profile, round limits, then scope)

The harness does **not** parse flags; you get the raw `$ARGUMENTS` string. Parse it yourself:

0. **`--instructions` (explicit form) — extract this BEFORE round limits, `--debate-low`, and
   scope.** Before extracting it, reject a `--review-profile` token after `--instructions` with
   `--review-profile must appear before --instructions.` Otherwise it must be processed first
   because everything after it is literal: if the token
   `--instructions` appears, it must be **last** in `$ARGUMENTS`, and you take **everything after it** —
   verbatim, including newlines and any `--`-looking tokens — as the instruction text, then remove
   `--instructions` + that text from the string. This is the escape hatch: after `--instructions`,
   nothing is parsed as a flag, so the text may contain `--max-rounds`, file paths, etc. Set `INSTR` to
   that text. The special value `--instructions auto` sets `INSTR=auto` (referee generates context from
   branch / commit messages / `git status`). If `--instructions` is present but the text is empty, stop
   with `--instructions needs text (or 'auto').` If `--instructions` is absent, leave `INSTR` unset for now.
0b. **`--review-profile <path>`.** Accept at most one occurrence in the remaining arguments, set
   `PROFILE` to its path, and remove both tokens. Reject a missing path or duplicate flag clearly.
   The path may be relative to the current repository or begin with `~`; `init_run` resolves it and
   owns regular-file, non-empty UTF-8, and 64 KiB validation. If absent, leave `PROFILE` empty so
   `init_run` snapshots panel-review's built-in generic profile.
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
   Specify a scope: --base <branch> | --uncommitted | --commit <SHA> | <question>  [--review-profile <path>] [--issue-rounds N] [--max-rounds N]  [<focus text> | --instructions <text|auto>]
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
PROFILE_ARGS=()
[ -z "$PROFILE" ] || PROFILE_ARGS=(--review-profile "$PROFILE")
ID="$("$SC/init_run" --workdir "$PWD" --scope "$scope" --issue-rounds "$ISS" --max-rounds "$MAX" --diff-hash "$DH" --instructions "$INSTR" "${PROFILE_ARGS[@]}")"
EPOCH=0
```

Spawn the `panel-review:panel-review-referee` subagent (Agent tool) with the resolved values in its prompt:

```
subagent_type: panel-review:panel-review-referee
run_in_background: false
prompt: |
  Run the panel-review referee protocol.
  mode=fresh
  id=<ID>
  workdir=<repo root absolute path>
  scope=<base=X | uncommitted | commit=SHA | question=...>
  issue-rounds=<ISS>  max-rounds=<MAX>  debate-low=<DEBATE_LOW>
  Persist the canonical verdict artifact, then return only PANEL_VERDICT_READY id=<ID>.
```

The agent reconstructs all state from `/tmp/<id>/`, runs the loop, persists the verdict artifact, and
cleans up only after successful persistence. Run from cwd = repo root.

If this Agent call fails with the exact Claude Code error `Subagent spawn limit reached`, fail closed:
do not perform the referee's work in the main context and do not retry the Agent call in this
conversation. Leave the run intact, tell the user to start a fresh conversation (normally `/clear`),
then invoke `panel-review:resume`. Apply the same handling to the low-severity gate's Step 4-form
re-dispatch below, then stop here without applying the artifact-delivery flow.

**Await its single return — do not poke it.** Internally, each pass issues the foreground CLI-barrier
and Claude-seat Agent calls together, and the referee resumes only after both return. The paired calls
can legitimately run for many minutes with no intermediate output. Do **not** `SendMessage`-resume the
referee, re-dispatch it, or otherwise nudge it: every such poke makes it re-read its whole
(long-context-tier) context for nothing — exactly the waste these scripts exist to avoid. Let it run;
act only on its final return. (A genuine interruption — the human cancels — is recovered later via
`panel-review:resume`, not by poking the live agent.)

## Step 5 — validate artifact-only delivery (and handle the low-severity gate)

Apply this after every referee Agent call in this command, whether it returns or fails, including the
gate-time `mode=resume` call below, except the exact outer spawn-limit failure stopped in Step 4 and
the fixed review-failure early stop defined next. An Agent's return is only a small status stub; it is
never a report transport. Do not parse artifact YAML or copy the verdict body into the main
conversation.

- **The Agent returned `PANEL_REVIEW_FAILED id=<ID>`** → report that the review failed before a
  validated report was produced and the run was kept. The fixed status does not disclose whether a
  nested Agent call hit the session spawn limit, so use the safe resumable recovery: tell the user to
  start a fresh conversation (normally `/clear`) and invoke `panel-review:resume`. Stop without
  cleanup or artifact delivery.

For every other returned status or Agent-tool failure, ask the deterministic reader to validate and
classify the artifact against the run minted above:

```bash
if DELIVERY="$("$SC/read_verdict_artifact" --delivery --id "$ID" --scope "$scope" --diff-hash "$DH" --run-epoch "$EPOCH")"; then
  # DELIVERY contains only a fixed file pointer plus minimal gate/continuation status.
  true
else
  # No validated finished or low-gate artifact: retain interrupted-run behavior.
  false
fi
```

- **Reader failure** → if the Agent also failed, surface its failure normally. If the Agent returned
  its ready stub but validation failed, report that no validated final report was produced. In either
  case leave the run for `panel-review:resume`; never claim completion or advertise the artifact.
- **`DELIVERY` is exactly `Done. Final report: /tmp/<ID>.md`** → run
  `"$SC/cleanup" --id "$ID" --workdir "$PWD"` idempotently, then present `DELIVERY` exactly and stop.
  This closes the crash window where artifact persistence succeeded but the referee's cleanup or final
  response did not.
- **`DELIVERY` starts with `Done. Final report:` and has a second line** → this is a continuable run.
  Present `DELIVERY` exactly, do not clean up, and do not add report prose.
- **`DELIVERY` starts with `Review paused because only low-severity findings remain.`** → present
  `DELIVERY` exactly, then ask the user (`AskUserQuestion`): *Only low-severity findings remain. Debate
  them anyway (another pass across all three seats), or finish here?*
  - **Debate them** → re-dispatch the **same** `panel-review:panel-review-referee` agent (Step 4 form)
    with `mode=resume`, `id=<ID>`, the same `workdir`/`scope`/limits, and `debate-low=true`. It reuses
    the completed passes and runs the debate loop. Await its return, then repeat Step 5; the refreshed
    artifact overwrites the gate snapshot.
  - **Finish here** → finalize the gate artifact from the referee's canonical verdict body. Only clean
    up after both finalization and delivery validation succeed:
    ```bash
    if "$SC/write_verdict_artifact" --id "$ID" --final < "/tmp/$ID/verdict.new.md" >/dev/null \
      && FINAL_DELIVERY="$("$SC/read_verdict_artifact" --delivery --id "$ID" --scope "$scope" --diff-hash "$DH" --run-epoch "$EPOCH")"; then
      "$SC/cleanup" --id "$ID" --workdir "$PWD"
      printf '%s\n' "$FINAL_DELIVERY"
    else
      echo "Could not finalize a validated report; the review was kept for panel-review:resume."
      exit 1
    fi
    ```

## Notes

- Read-only status (no scope to type): `panel-review:status`.
- The cards/state live in `.panel-review/<ID>/` (git-excluded) and `/tmp/<ID>/`. A clean finish removes
  both; an interruption leaves them for `panel-review:resume`/`panel-review:continue`.
