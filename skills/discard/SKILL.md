---
name: discard
description: Delete all saved panel-review sessions for this workdir (the reset). Normally there's exactly one. Act-and-report, no confirmation prompt.
disable-model-invocation: true
argument-hint: ""
---

# panel-review:discard

You are the **automatic cleanup / reset**. This command removes **every** saved session for this
workdir, then drops `.panel-review/` entirely. It is **act-and-report** — typing the command is itself
the intent, so there is no confirmation prompt. Run from the repo root.

```bash
# CLAUDE_PLUGIN_ROOT is substituted into this text at skill-load — it is NOT a
# shell env var (it's empty in the shell). Keep the literal verbatim; don't
# build it dynamically or read $CLAUDE_PLUGIN_ROOT at runtime.
ROOT="${CLAUDE_PLUGIN_ROOT}"; ROOT="${ROOT%/}"   # strip trailing slash so $SC has no //
SC="$ROOT/scripts"
"$SC/discard" --workdir "$PWD"
```

Present the script's output **verbatim**. It prints one summary line for the workdir, or a no-op
message when `.panel-review/` does not exist. Do not add further explanation; the script's output is
the complete report.

In the normal one-session case this removes one run. If it removes more than one, that only happens
after out-of-band interference (`.panel-review:status` would have flagged it as "ambiguous"). The
summary does not itemize the removed runs.

## Notes

- This is the escape hatch `panel-review:start`'s strict precondition needs: a user blocked by an
  unwanted saved session runs `panel-review:discard`, then `panel-review:start`.
- Only `/tmp/<id>/` state and the in-tree `.panel-review/` go. The durable verdict copy at the
  sibling path `/tmp/<id>.md` (if one was ever written) is deliberately left untouched — discard
  abandons the *session*, not a verdict the human may already have seen and want to keep.
- `discard` reads `cleanup.keep_tmp` from the current user config. An invalid config stops the
  command before it deletes any marker or `/tmp` state.
- Manual alternative, if you'd rather not clear everything: remove a specific `.panel-review/<ID>/`
  marker dir **and** its matching `/tmp/<ID>/` state dir yourself — `panel-review:status` lists the
  paths.
