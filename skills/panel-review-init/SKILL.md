---
name: panel-review-init
description: Check/setup prerequisites for the three panel-review seats (Claude + Codex + Gemini/agy). Read-only status report, no review.
disable-model-invocation: true
---

# Panel Review — Prerequisites Check

Runs **inline** (not forked): this only inspects the environment and reports. It never
dispatches a review and never writes config files.

```bash
SC="$HOME/.claude/skills/panel-review/scripts"
"$SC/preflight"   # core (codex/jq/profile) hard checks + summarizer/login/agy status; last line GEMINI: yes|no
# init-only extras preflight doesn't print:
command -v codex >/dev/null && echo "codex: $(codex --version 2>/dev/null)"
if command -v agy >/dev/null; then
  echo "agy: $(agy --version 2>/dev/null | head -1) — invoked only via $SC/run_agy (never raw)"
  agy models 2>/dev/null | grep -i gemini || echo "  (run 'agy models' to confirm available Gemini models)"
fi
```

- The Codex profile files are owned by `/codex-peer-review init` — do **not** write them
  here; if `~/.codex/peer-review.config.toml` is missing, point the user there.
- There is no profile file for agy; its model and flags are pinned in
  `panel-review/scripts/run_agy`.
- A missing `agy` is reported as `GEMINI: no`, not a failure — the review still runs 2-way.

**Stop after reporting.** Do not dispatch a review.
