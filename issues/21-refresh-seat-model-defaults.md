# Refresh the shipped seat model defaults

Priority: 21

Status: Pending — agy pins done 2026-08-15; the Codex asset decision remains

Source: external CLI update review (agy 1.1.10, codex-cli 0.146.1), 2026-08-05

Triage: ready-for-human

## Problem

Two shipped defaults name models from an earlier generation of their CLI. Neither is broken today,
but both are the value a *new* installation gets, and neither reflects what is now available.

| Where | Pinned | Status on the current CLI |
|---|---|---|
| ~~`scripts/run_agy` `PRIMARY_MODEL` / `FALLBACK_MODEL`~~ | ~~`Gemini 3.1 Pro (High)` / `Gemini 3.5 Flash (High)`~~ | **Resolved 2026-08-15** — now `Gemini 3.7 Flash (High)` primary, `Gemini 3.1 Pro (High)` fallback |
| `assets/default-panel-review.config.toml` | `model = "gpt-5.5"`, `model_reasoning_effort = "xhigh"` | 5.6-family models are current here; the effort enum now also has `max` and `ultra` above `xhigh` |

Model selection is a quality and cost decision for the panel owner, so this issue records the facts
and leaves the values to the user.

## Current facts

**agy 1.1.10** offers `gemini-3.6-flash-{high,medium,low}`, `gemini-3.5-flash-{high,medium,low}`,
`gemini-3.1-pro-{high,low}`, plus Claude and GPT-OSS entries the Gemini seat must never use. The
primary pin `Gemini 3.1 Pro (High)` still exists and binds correctly (verified 2026-08-05). The Pro
line has not moved past 3.1; the Flash line has moved twice.

**codex-cli 0.146.1** keeps the profile-v2 scheme this plugin already uses
(`-p/--profile <name>` layers `$CODEX_HOME/<name>.config.toml` over the base config), and every flag
`run_codex` passes still exists. Its reasoning-effort enum is
`none, minimal, low, medium, high, xhigh, max, ultra`. This machine's base config runs
`gpt-5.6-terra`; its already-installed `~/.codex/panel-review.config.toml` runs `gpt-5.6-sol` at
`max`, i.e. the shipped template has already been hand-corrected locally and only new installs see
`gpt-5.5`/`xhigh`.

`run_codex` copies the template only when `~/.codex/panel-review.config.toml` is absent, so changing
the asset affects new installations exclusively and cannot disturb a tuned profile.

## Decisions required

1. ~~**agy fallback.**~~ **Decided 2026-08-15** — see "agy decision" below.
2. ~~**agy primary.**~~ **Decided 2026-08-15** — see "agy decision" below.
3. **Codex model and effort in the shipped asset.** Which 5.6-family id and which effort ship as the
   default for a fresh install? Recommended: match what is already proven on this machine
   (`gpt-5.6-sol`, `max`), since that is the configuration the panel has actually been running.

## Expected behavior

- `scripts/run_agy` and `assets/default-panel-review.config.toml` carry the values chosen above.
- Any new agy pin uses the exact display-label form required by issue 20.
- The asset keeps its comment that the copy in `~/.codex/` is the user's to tune.
- No file under `~/.codex/` is created, edited, or deleted by this change.

## Verification

- `agy --model "<new fallback label>"` binds that exact label (check agy's CLI log
  `Propagating selected model override to backend: label="…"`).
- A fresh-install simulation (`CODEX_PROFILE` pointing at an unused name, or a temporary `$HOME`)
  produces the intended profile file; an existing profile file is left byte-identical.
- `scripts/check_contracts --root .` and `./tests/run_tests.sh` pass.
- One real review runs end to end with both seats engaged.

## agy decision (2026-08-15, agy 1.1.13)

Owner's call: `Gemini 3.7 Flash (High)` is now the best Gemini seat model, so it becomes the primary
pin, and the previous primary `Gemini 3.1 Pro (High)` becomes the fallback. Implemented in
`scripts/run_agy`; the 3.5/3.6 Flash question is moot.

Verified on this machine before shipping the change, using `run_agy`'s own invocation form (prompt on
stdin, no `--print`) and agy's CLI log line
`Propagating selected model override to backend: label="…"`:

| Requested `--model` | Bound |
|---|---|
| `Gemini 3.7 Flash (High)` | Gemini 3.7 Flash (High) |
| `Gemini 3.1 Pro (High)` | Gemini 3.1 Pro (High) |

`agy models` on 1.1.13 lists `gemini-3.7-flash-{high,medium,low}` above the 3.6/3.5 Flash and 3.1 Pro
entries; the Pro line still has not moved past 3.1. Effort rides in the label, so no `--effort` flag
is involved. A run of `scripts/run_agy` itself (post-change) logged
`label="Gemini 3.7 Flash (High)"`.

**Consequence to accept:** the fallback is no longer the *faster* model. Under the old Pro→Flash
order a primary `--print-timeout` expiry was followed by a quicker attempt; now a primary expiry is
followed by a second full 15-minute budget on Pro, so a doubly-unlucky Gemini seat can occupy up to
2×`WALL_TIMEOUT` before it is declared down. That is deliberate: quality over worst-case latency,
and the two models fail independently enough that the retry is worth the wait.

## Non-goals

- Do not rewrite the historical model values in `docs/superpowers/plans/*` or
  `design-notes/blind-pass-robustness.md`; those are dated records of what was run at the time.
- Do not add automatic model discovery or "latest model" resolution to either wrapper. Pins are
  deliberate: a silently changing seat model makes review results incomparable between runs.
- Do not adopt `--strict-config` for Codex; it fails on user config keys the plugin does not own.
