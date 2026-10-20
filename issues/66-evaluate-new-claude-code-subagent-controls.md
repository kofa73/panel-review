# Evaluate the new Claude Code subagent controls

Priority: 66

Status: Optional

Source: Claude Code changelog review (2.1.262 → 2.1.303), 2026-10-19. Installed Claude Code:
2.1.303.

Triage: ready-for-human

## Problem

Claude Code added four subagent-level controls that touch the Claude seat or the referee. None of them
is needed to keep the panel working; each one needs a decision, recorded here so the next review does
not re-analyse it. This is the Claude Code counterpart of `issues/23` (agy) and `issues/28` (Codex).

| Control | Version | Why it might matter here |
|---|---|---|
| `omitClaudeMd` in agent frontmatter | 2.1.271 | Runs a subagent without the user, project and local `CLAUDE.md` files (managed policy still loads). Today the Claude seat reads the reviewer's personal `~/.claude/CLAUDE.md` and the reviewed repository's `CLAUDE.md`. The CLI seats read their own equivalents (`AGENTS.md`, `~/.codex/AGENTS.md`, `GEMINI.md`). So this is a parity question, not a blindness defect. For the **referee**, which never reviews code, omitting the reviewed repository's `CLAUDE.md` would cut context with no loss. That matters for `issues/09` and `referee-context-cost-history.md`. |
| `autoCompactWindow` in agent frontmatter | 2.1.296 | Lets one subagent compact earlier than the main conversation. The referee is long-lived; an earlier compaction trades retained context for cost. Measure before changing (same caution as the 2.1.242 cache-TTL note in `issues/22`). |
| Agent tool `effort` parameter | 2.1.292 | A per-spawn effort. The seat and referee already pin `effort:` in frontmatter (`xhigh` and `high`). A per-spawn value would only matter if the referee ever chose effort per pass, which it should not. Expected decision: decline. |
| Opus 5.5 became the `opus` alias | 2.1.280 | Both `model: opus` agents moved to Opus 5.5 with no change in this repository. Nothing in a verdict records which Claude model reviewed; `seat_models` holds only Codex (`issues/47`). Candidate: record the Claude seat's resolved model the way `issues/63` item 4 proposes for Gemini, if Claude Code exposes it to the seat or a hook. |

## Expected behavior

One recorded decision per row: adopt, decline, or measure first. For each one adopted, the change
lands with its rationale in the agent file and README, and passes `scripts/check_contracts --root .`
and `./tests/run_tests.sh`.

## Non-goals

- Do not change the seat's `model:` or `effort:` pins here (`issues/10` owns referee model choice).
- Do not adopt `omitClaudeMd` for the Claude seat without deciding the parity question explicitly.
