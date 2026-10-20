# Correct the documentation contradictions found by the simplification panel

Priority: 42

Status: Completed

Source: Simplification panel (Opus §5, Sol §"Correct smaller contradictions"), 2026-08-16 — each item
re-verified in the working tree

Triage: ready-for-agent

## Problem

Six independent statements in the tree are wrong. Each is small; together they make the authoritative
documents unsafe to trust without re-reading the code.

| # | Where | Problem |
|---|---|---|
| 1 | `skills/panel-review-for-agent/references/protocol.md:150-151` | Says `fully_vetted` stays false **permanently** if an issue settles while a seat was down. Lines 653-655 of the same file say it flips to true the round the last configured seat evaluates the issue, and never reverts. The latter matches `AGENTS.md` and the implementation; line 150-151 is the wrong copy. |
| 2 | `scripts/await_seats:27-29` | Calls the CLI barrier and Claude seat "Two background Agents per pass". They are **foreground** Agents dispatched in one response; that is the whole point of issue 15's fix. |
| 3 | `README.md:461` (the `run_agy` row) and `scripts/run_agy:68-69` | Both say an unrecognized `--model` "is not an error, agy silently runs the user's `settings.json` default". That was measured on agy 1.1.10. On 1.1.13 — the installed and verified version — an unknown label hard-errors (`issues/archive/20-agy-model-pin-contract.md:129-149`). The label-pin rule stays; only the stated failure mode is stale. |
| 4 | `README.md:630-631` | The file ends with literal `</content>` and `</invoke>` lines — a tool-call fragment written into the authoritative spec. |
| 5 | `README.md:131` | The `install.sh` file list omits `profiles/`, which `install.sh:56` does copy. Without it the built-in review profile would be missing, so the list is wrong, not the installer. |
| 6 | `AGENTS.md:32-35` | The "The Python scripts are …" list omits `stage_review_profile`, which is Python. |

## Expected behavior

Fix all six in one change. For item 3, version the statement (`observed on agy 1.1.10; 1.1.13 fails
the run`) rather than replacing one undated absolute with another.

## Verification

- `scripts/check_contracts --root .` and `./tests/run_tests.sh` pass.
- `tail -3 README.md` shows prose.
- The two `fully_vetted` paragraphs in `protocol.md` state the same rule.

## Non-goals

- Do not weaken the agy display-label pin while correcting item 3. The pin is cheap compatibility
  insurance across agy versions; only its rationale sentence is out of date.

## Resolution

Corrected all six statements. The protocol now says `fully_vetted` can become true when a previously
down seat re-engages, the barrier comment describes paired foreground Agents, and the agy fallback
history is versioned. The README now lists `profiles/` in the installer copy list and ends with prose;
`AGENTS.md` lists `stage_review_profile`. Updated the `check_contracts` comment and bumped the plugin
version to 1.0.34 because the canonical protocol is loaded at runtime.
