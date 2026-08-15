# Evaluate agy's API-key auth and print-mode probes

Priority: 29

Status: Optional

Source: agy CHANGELOG review (1.1.11 → 1.1.13), 2026-08-15

Triage: ready-for-human

## Problem

Two agy additions could simplify how panel-review reaches and checks the Gemini seat. Neither is
needed; both are worth a decision so they are not rediscovered at the next update.

### `GEMINI_API_KEY` direct-API mode (1.1.13)

agy can now run against the Gemini API without an interactive sign-in: set
`modelProvider: "gemini"` in `settings.json`, export `GEMINI_API_KEY`, optionally point
`GOOGLE_GEMINI_BASE_URL` at a custom endpoint.

For panel-review this is an authentication path that survives a fresh container without an OAuth
dance, which matters because the Gemini seat is the one that silently degrades when credentials
expire. Against it: it is a per-user `settings.json` change the plugin must not make (the same rule
that keeps `run_codex` out of `~/.codex/config.toml`), the model pins are display labels whose
availability under the direct API is unverified, and billing moves from the operator's Antigravity
quota to an API key.

Decide whether this is documented as a supported way to run the Gemini seat (README prerequisites,
one paragraph) or explicitly out of scope. **Do not** have any script write `settings.json`.

### Print-mode answers for read-only slash commands (1.1.11, 1.1.12)

`agy -p "/model"`, `/effort`, `/skills`, `/permissions`, `/help`, `/changelog` and others now answer
non-interactively — one tab-separated record per line, without starting an agent turn or spending
quota.

`scripts/preflight` currently reports Gemini availability by whether the CLI exists. A quota-free
`-p "/model"` probe could report what agy would actually run, which is the failure the label-pin
contract (issue 20) is designed against. Before adopting: confirm the probe is genuinely
quota-free and cannot hang, and confirm what it reports on a signed-out CLI. Keep any probe
advisory — preflight must not fail a run on it.

## Expected outcome

A decision recorded per item; if the preflight probe is adopted, it reports and never blocks.

## Verification

- Any adopted probe runs in under a couple of seconds on a signed-in and a signed-out CLI, and its
  failure path is exercised.
- `scripts/check_contracts --root .` and `./tests/run_tests.sh` pass.

## Non-goals

- No script writes or edits `~/.gemini/antigravity-cli/settings.json`.
- Do not turn the model probe into a hard gate on a run.
- Do not change the model pins here (issue 21) or the label-pin contract (issue 20).
