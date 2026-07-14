---
name: resume
description: Resume an interrupted panel review (mid-debate, crashed, or stopped). Takes only optional round-limit overrides — scope and instructions come from the saved session. Redirects to status/continue/discard if the saved session isn't interrupted.
disable-model-invocation: true
argument-hint: "[--issue-rounds N] [--max-rounds N]"
---

# panel-review:resume

You are the **main-context entry point** for resuming an interrupted review. This command takes
**no scope, no instructions** — both come from the manifest. Run from the repo root.

```bash
# CLAUDE_PLUGIN_ROOT is substituted into this text at skill-load — it is NOT a
# shell env var (it's empty in the shell). Keep the literal verbatim; don't
# build it dynamically or read $CLAUDE_PLUGIN_ROOT at runtime.
ROOT="${CLAUDE_PLUGIN_ROOT}"; ROOT="${ROOT%/}"   # strip trailing slash so $SC has no //
SC="$ROOT/scripts"
```

## Step 1 — parse `$ARGUMENTS` (limit overrides only)

Apply `--issue-rounds N` / `--max-rounds N` if present (track whether each was actually given — you
need that later to decide whether to write back an override). Anything else in `$ARGUMENTS` — a scope
flag, free text, `--instructions` — is a hard error:

> `panel-review:resume` takes the scope and instructions from the saved review; it doesn't accept
> them. `panel-review:status` shows what's stored.

## Step 2 — find the session

```bash
base="$PWD/.panel-review"
ids=(); [ -d "$base" ] && for d in "$base"/*/; do [ -f "$d/.panel-run" ] && ids+=("$(basename "$d")"); done
```

- **0** → "No saved review. Start one: `panel-review:start <scope>`." Stop.
- **>1** → ambiguous:
  > More than one review marker under `.panel-review/` (only possible if it was edited out of band).
  > `panel-review:discard` clears them all (then `panel-review:start` for a new review), or remove the
  > `.panel-review/<ID>/` + `/tmp/<ID>/` pairs by hand — `panel-review:status` lists them with creation
  > times.
  Stop.
- **1** → `id="${ids[0]}"`. Continue to Step 3.

## Step 3 — adopt scope/limits/instructions, resolve the current diff

```bash
man="/tmp/$id/manifest.json"
[ -s "$man" ] || { "$SC/cleanup" --id "$id" --workdir "$PWD"; echo "No saved review. Start one: panel-review:start <scope>."; exit 0; }
scope="$(jq -r '.scope' "$man")"
ISS="$(jq -r '.limits.issue_rounds' "$man")"
MAX="$(jq -r '.limits.max_rounds' "$man")"
INSTR="$(jq -r '.instructions // ""' "$man")"
```

Apply any `--issue-rounds`/`--max-rounds` override from Step 1 on top of the adopted `ISS`/`MAX` now
(validate as `start` does: positive integers, `issue-rounds ≤ max-rounds`).

Resolve + hash the **current** diff for the adopted `scope` (same as `start`'s Step 2):

```bash
DIFF_FILE="$(mktemp /tmp/panel_scope_diff.XXXXXX)"
if ! "$SC/resolve_diff" "$scope" > "$DIFF_FILE"; then
  rm -f "$DIFF_FILE"
  # The scope no longer resolves (e.g. base branch deleted) — same family as diverged.
  echo "The working tree diverged from the reviewed snapshot — the code under review was modified since this review started ($scope). It can't be resumed or continued; run panel-review:discard before panel-review:start."
  exit 1
fi
DH="$("$SC/diff_hash" < "$DIFF_FILE")"
rm -f "$DIFF_FILE"
```

## Step 4 — the redirect: act only if the session is interrupted

```bash
"$SC/resume_check" --workdir "$PWD" --scope "$scope" --diff-hash "$DH"
```

- **`resume $id`** → this command's job. Go to Step 5.
- **`continuable $id`** → not interrupted, it's finished with leftovers. Redirect:
  > Nothing to resume. There's a finished review you can continue —
  > `panel-review:continue [unresolved|contested]`? `<details>`
  Build `<details>` the way `status` would (scope, instructions, leftover counts via
  `"$SC/inspect_run" --id "$id" --workdir "$PWD"`), no ID. Stop.
- **`diverged $id`** →
  > The working tree diverged from the reviewed snapshot (code modified since this review started);
  > it can't be resumed or continued — `panel-review:discard` before `panel-review:start`.
  Stop.
- **`stale $id`** → the marker's `/tmp/<ID>` state is gone. Clean it (you mutate anyway, unlike
  `status`), then report it was cleared:
  ```bash
  "$SC/cleanup" --id "$id" --workdir "$PWD"
  ```
  > The saved review's state had already been cleaned up (`.panel-review/<ID>/` removed). No saved
  > review. Start one: `panel-review:start <scope>`.
  Stop.
- **`fresh`/`ambiguous`** → shouldn't occur here (Step 2 already confirmed exactly one valid marker);
  if it somehow does, treat `fresh` as "no saved review" and `ambiguous` as the Step 2 ambiguous
  message. Stop.

## Step 5 — write back limit overrides, dispatch

If Step 3's overrides changed `ISS`/`MAX` from the manifest's stored values, write them back so the
referee picks them up:

```bash
"$SC/set_limits" --id "$id" --issue-rounds "$ISS" --max-rounds "$MAX"
```

In all cases, capture the current continuation epoch for failed-response artifact validation:

```bash
EPOCH="$(jq -r '.run_epoch // 0' "/tmp/$id/index.json")"
```

Spawn the `panel-review:panel-review-referee` subagent (Agent tool):

```
subagent_type: panel-review:panel-review-referee
prompt: |
  Run the panel-review referee protocol.
  mode=resume
  id=<id>
  workdir=<repo root absolute path>
  scope=<scope>
  issue-rounds=<ISS>  max-rounds=<MAX>  debate-low=true
  Return only the synthesized verdict in the documented Output format.
```

Re-runs only missing seats/rounds; reopens nothing. **Await its single return — do not poke it** (it
waits for its own slow seats via background helper Agents — the `panel-review-cli-barrier` plus the
Claude seat — and may run many minutes with no output; `SendMessage`-poking it only forces a wasteful
full-context re-read — see `start`'s Step 4). Present
the verdict per `start`'s Step 5 (verbatim, strip/act on `<<<PANEL-GATE…>>>` /
`<<<PANEL-CONTINUABLE…>>>` control lines the same way). If the Agent ends unsuccessfully, apply
`start`'s validated finished-artifact recovery using `--id "$id" --scope "$scope" --diff-hash
"$DH" --run-epoch "$EPOCH"`; otherwise retain the interrupted-run behavior. Never parse the
artifact frontmatter in the main model.
