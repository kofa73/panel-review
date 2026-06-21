---
name: continue
description: Re-debate a finished panel review's leftover unresolved/contested issues. Takes an optional leftover category plus round-limit overrides — scope and instructions come from the saved session. Redirects to status/resume/discard if the saved session isn't finished-with-leftovers.
disable-model-invocation: true
argument-hint: "[unresolved|contested]  [--issue-rounds N] [--max-rounds N]"
---

# panel-review:continue

You are the **main-context entry point** for re-debating a finished review's leftovers. This command
takes **no scope, no instructions** — both come from the manifest. Run from the repo root.

```bash
# CLAUDE_PLUGIN_ROOT is substituted into this text at skill-load — it is NOT a
# shell env var (it's empty in the shell). Keep the literal verbatim; don't
# build it dynamically or read $CLAUDE_PLUGIN_ROOT at runtime.
SC="${CLAUDE_PLUGIN_ROOT}/scripts"
```

## Step 1 — parse `$ARGUMENTS` (category + limit overrides only)

- **Category.** If `$ARGUMENTS` contains the word `unresolved` or `contested`, set `CAT` to that;
  otherwise `CAT=both`.
- **Limit overrides.** Apply `--issue-rounds N` / `--max-rounds N` if present (track whether each was
  actually given).
- Anything else in `$ARGUMENTS` — a scope flag, free text, `--instructions` — is a hard error:
  > `panel-review:continue` takes the scope and instructions from the saved review; it doesn't accept
  > them. `panel-review:status` shows what's stored.

## Step 2 — find the session

Same as `resume`'s Step 2:

```bash
base="$PWD/.panel-review"
ids=(); [ -d "$base" ] && for d in "$base"/*/; do [ -f "$d/.panel-run" ] && ids+=("$(basename "$d")"); done
```

- **0** → "No saved review. Start one: `panel-review:start <scope>`." Stop.
- **>1** → the same ambiguous message as `resume`'s Step 2. Stop.
- **1** → `id="${ids[0]}"`. Continue to Step 3.

## Step 3 — adopt scope/limits/instructions, resolve the current diff

Identical to `resume`'s Step 3: read `scope`/`ISS`/`MAX`/`INSTR` from `/tmp/$id/manifest.json`, apply
any Step 1 limit overrides, resolve + hash the current diff for `scope` into `DH`. If the scope no
longer resolves, emit the same diverged-family message `resume` does and stop.

## Step 4 — the redirect: act only if the session is finished with leftovers

```bash
"$SC/resume_check" --workdir "$PWD" --scope "$scope" --diff-hash "$DH"
```

- **`continuable $id`** → this command's job. Go to Step 5.
- **`resume $id`** → not finished, it was interrupted mid-debate. Redirect:
  > Not finished — it was interrupted mid-debate. Did you mean `panel-review:resume`? `<details>`
  Build `<details>` the way `status` would (scope, instructions, progress via
  `"$SC/inspect_run" --id "$id" --workdir "$PWD"`), no ID. Stop.
- **`diverged $id`** → same diverged message as `resume`'s Step 4. Stop.
- **`stale $id`** → same as `resume`'s Step 4: clean it, report cleared, "No saved review." Stop.
- **`fresh`/`ambiguous`** → same fallback as `resume`'s Step 4. Stop.

## Step 5 — confirm the category has leftovers, reopen, write back limits, dispatch

```bash
have="$(jq --arg c "$CAT" '[.issues[] | select(($c=="both" and (.state=="unresolved" or .state=="contested")) or (.state==$c))] | length' "/tmp/$id/index.json")"
[ "$have" -gt 0 ] || { echo "Run $id has no $CAT issue to continue."; exit 1; }
"$SC/reopen" --id "$id" --category "$CAT" || { echo "Could not re-open run $id."; exit 1; }
```

If Step 3's overrides changed `ISS`/`MAX` from the manifest's stored values, write them back:

```bash
"$SC/set_limits" --id "$id" --issue-rounds "$ISS" --max-rounds "$MAX"
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

Present the verdict per `start`'s Step 5 (verbatim, strip/act on `<<<PANEL-GATE…>>>` /
`<<<PANEL-CONTINUABLE…>>>` control lines the same way).
