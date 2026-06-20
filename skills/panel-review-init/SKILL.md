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
"$SC/preflight"   # hard: jq/git/work-tree/writable-cwd + ≥1 peer (codex or agy); soft: codex login; tail lines CODEX: yes|no / GEMINI: yes|no
# init-only extras preflight doesn't print:
command -v codex >/dev/null && echo "codex: $(codex --version 2>/dev/null)"
if command -v agy >/dev/null; then
  echo "agy: $(agy --version 2>/dev/null | head -1) — invoked only via $SC/run_agy (never raw)"
  agy models 2>/dev/null | grep -i gemini || echo "  (run 'agy models' to confirm available Gemini models)"
fi
```

- Panel Review owns its Codex profile `~/.codex/panel-review.config.toml`; `run_codex` auto-creates
  it from `skills/panel-review/assets/default-panel-review.config.toml` on first use — nothing to set
  up by hand. (Upstream `/codex-peer-review init` owns the separate `peer-review` profile; the two no
  longer share config.)
- There is no profile file for agy; its model and flags are pinned in
  `panel-review/scripts/run_agy`.
- A missing `agy` or `codex` is reported as `GEMINI: no` / `CODEX: no`, not a failure as long as one
  peer remains — the review runs with the seats present. Only zero peers is a hard failure.

**Stop after reporting.** Do not dispatch a review.
