# Make the Codex model pin authoritative and stop writing to the user's home config

Priority: 47

Status: Pending

Source: Simplification panel (Sol, "Runtime-specific simplifications — Codex"), 2026-08-16 — layering
claim verified against the local Codex checkout `73abda8bfef6`

Triage: ready-for-human

## Problem

`run_codex` pins the Codex seat's model through `--profile panel-review`, and its header says the
profile owns the model (`scripts/run_codex:12-15`). That is not how Codex resolves configuration.

`codex-rs/config/src/loader/mod.rs:103-119` documents the layer order, lowest to highest:

```
package → admin → system → cloud → user (~/.codex/config.toml)
        → profile (${CODEX_HOME}/<name>.config.toml)
        → cwd (${PWD}/config.toml)
        → tree (../.codex/config.toml up to root)
        → repo ($(git rev-parse --show-toplevel)/.codex/config.toml)
        → runtime (-c flags)
```

The **cwd, tree, and repo layers sit above the profile**. `codex exec` runs with cwd = the repository
under review, so a reviewed repository that ships its own `.codex/config.toml` — and is trusted —
overrides the panel's model and effort. The seat then reviews under a model the manifest does not
record, silently, and the verdict's provenance is wrong. Reviewing any repository that uses Codex
itself is exactly the case this hits.

Two smaller points in the same wrapper:

- `run_codex:37` states "`--json` is required because `-o` writes only the final message". Current
  Codex source sends the last-message file to both the human and JSON event processors, and default
  stdout already contains only the final message (`codex-rs/exec/src/lib.rs:656-683`). If that holds
  on the installed 0.147.0, `--json` and the `CODEX_JSONL` plumbing can become opt-in diagnostics
  rather than a mandatory second output stream.
- Auto-creating `~/.codex/panel-review.config.toml` on first use mutates the user's home directory
  for a value the wrapper could pass directly.

## Expected behavior

1. Pass the model and effort as highest-precedence runtime `-c` overrides so the advertised pin is
   real regardless of what the reviewed repository ships.
2. Record the effective model in the manifest or run metadata, so the verdict can state what actually
   reviewed the code.
3. Decide whether the auto-created profile file survives. If the runtime overrides carry the pin, the
   profile's remaining job is inheriting the user's base MCP definitions, which the base user layer
   already provides. Removing it ends the home-directory mutation.
4. Make `--json` / `-o` conditional on `CODEX_JSONL` being set, after confirming the stdout claim
   against installed Codex 0.147.0. If the diagnostic toggle has never been used, remove it entirely.
5. Settle issue 21's Codex model choice first — this change touches the same line.

## Verification

- A probe: plant a `.codex/config.toml` naming a different model in a scratch repository, run
  `run_codex`, and confirm the pinned model is used.
- A probe on installed 0.147.0 confirming `-o` alone yields the final message before `--json` is made
  conditional.
- `./tests/run_tests.sh` passes; one real review completes with the Codex seat engaged.

## Non-goals

- **Do not remove `--dangerously-bypass-approvals-and-sandbox` on the strength of documentation
  review.** The wrapper's claim that every MCP call is cancelled under any Codex sandbox is not an
  upstream invariant — current source has a stdio MCP integration test passing under a read-only
  permission profile (`codex-rs/core/tests/suite/rmcp_client.rs:1350-1433`). That does not establish
  that 0.147.0 plus tilth plus `/tmp` scratch works under `workspace-write`. Run one real disposable
  probe before touching it; until then keep the behavior and rewrite the blanket claim as a
  version- and server-specific observation.
- Do not add a general profile-customization seam. Two wrapper-level values are enough.
