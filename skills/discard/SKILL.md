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
SC="${CLAUDE_PLUGIN_ROOT}/scripts"
"$SC/discard" --workdir "$PWD"
```

Present its output **verbatim** — each removed `.panel-review/<ID>/` + `/tmp/<ID>/` pair, and any
removed invalid-name marker whose `/tmp` state could not be mapped (left untouched), or the no-op
message if there was nothing to discard. Do not add commentary.

In the normal one-session case this removes exactly one pair. If it removed more than one, that's
fine — it only happens after out-of-band interference (`.panel-review:status` would have flagged it as
"ambiguous"); the report names every pair so the action is auditable.

## Notes

- This is the escape hatch `panel-review:start`'s strict precondition needs: a user blocked by an
  unwanted saved session runs `panel-review:discard`, then `panel-review:start`.
- Only `/tmp/<id>/` state and the in-tree `.panel-review/` go. The durable verdict copy at the
  sibling path `/tmp/<id>.md` (if one was ever written) is deliberately left untouched — discard
  abandons the *session*, not a verdict the human may already have seen and want to keep.
- Manual alternative, if you'd rather not clear everything: remove a specific `.panel-review/<ID>/`
  marker dir **and** its matching `/tmp/<ID>/` state dir yourself — `panel-review:status` lists the
  paths.
