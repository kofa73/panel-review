# Delete the dead script surface

Priority: 44

Status: Pending

Source: Simplification panel (Opus §2, Sol "Small removals"), 2026-08-16 — every call site re-checked
by grep over `scripts/ skills/ agents/ hooks/ prompts/ tests/ docs/`

Triage: ready-for-agent

## Problem

Four executable surfaces have no caller. One of them is worse than merely dead: it is an unlocked
side door around the atomic round transaction the protocol exists to enforce.

| Item | Evidence | Note |
|---|---|---|
| `sweep record` (`scripts/sweep:199-222`, plus its `KNOWN_CMDS` entry and usage string) | Zero call sites. Superseded by `ingest-batch`, which writes the `.out` completion marker itself. | Delete. |
| `index bump` / `index state` / `index flag` (`scripts/index:455-526`) | Zero call sites; all state mutation goes through `commit-sweep`. Only `tests/python/test_index.py:114-120` exercises `state`. | Delete the verbs, their tests, and the usage strings. They let any caller mutate issue state and flags outside the round transaction ADR-0004 is about. |
| `scripts/write_card` | Zero call sites; referenced only by `README.md:474`, `.claude/rules/scripts.md`, and `protocol.md:171`. `project_card`/`regen_cards` own every live card write. | Delete it with its three references, **or** keep it and state plainly that it exists so the referee can write `origins/` atomically — which is what `protocol.md:171` actually means. Decide, don't leave it ambiguous. |
| `install.sh:33-52` (pre-plugin migration) | Removes `panel-review-for-agent`/`panel-review-init` loose skills and top-level `panel-review-referee.md`/`panel-review-claude-seat.md` agents — a layout this repository has not produced for many versions. | Delete the migration block. **Keep** the shadow warning (`install.sh:68-83`): a stale `~/.claude/agents/panel-review-*.md` still silently outranks the plugin's, which is current Claude Code behavior. |

Two explicitly-defensive unreachable branches (`scripts/index:433-438`, guarding `KNOWN_CMDS` and
`mutations` from drifting apart, and `scripts/repo_guard:612-616`, a second default case) disappear
for free once the dispatch tables shrink.

## Expected behavior

Each item removed together with its tests, usage strings, and documentation rows in the same commit,
so no document describes a verb that no longer exists.

## Verification

- `grep -rn "sweep record\|index bump\|index state\|index flag\|write_card" scripts skills agents
  hooks prompts tests docs README.md CONTRACTS.md` returns only intentional prose, if any.
- `scripts/check_contracts --root .` and `./tests/run_tests.sh` pass.
- A fresh `./install.sh` into a scratch `CLAUDE_DIR` still produces a working plugin tree, and the
  shadow warning still fires when a stale agent file is planted.

## Non-goals

- Do not remove the second install path. Whether `install.sh` or the marketplace entry is the
  supported one is a separate maintainer decision; `AGENTS.md` currently requires both to work.
