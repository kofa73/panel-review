---
name: result
description: Retrieve a finished panel review's validated durable verdict by its exact artifact ID. Read-only; does not resume or re-run seats.
argument-hint: "<ID>"
---

# panel-review:result

Retrieve a finished verdict after its review session has already ended, including after a quota
reset. This command is read-only and artifact-ID based because normal cleanup removes the workspace
marker and canonical run directory.

`$ARGUMENTS` must contain exactly one non-empty run ID and no flags or additional text. Otherwise
print `Usage: panel-review:result <ID>` and stop.

```bash
# CLAUDE_PLUGIN_ROOT is substituted into this text at skill-load — it is NOT a
# shell env var (it's empty in the shell). Keep the literal verbatim.
ROOT="${CLAUDE_PLUGIN_ROOT}"; ROOT="${ROOT%/}"
SC="$ROOT/scripts"
id="$ARGUMENTS"
"$SC/read_verdict_artifact" --id "$id"
```

The reader validates the artifact ID, completion status, metadata shape, and diff-hash shape, then
prints the saved review-profile path/hash followed by the verdict body. Legacy artifacts without
profile metadata still print only their verdict body. Present stdout verbatim. Do not parse the frontmatter, summarize
the verdict, resume the run, or dispatch any seat. If validation fails, surface the script's error.
