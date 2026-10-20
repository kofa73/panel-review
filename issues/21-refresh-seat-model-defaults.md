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
| ~~`scripts/run_agy` `PRIMARY_MODEL` / `FALLBACK_MODEL`~~ | ~~`Gemini 3.1 Pro (High)` / `Gemini 3.5 Flash (High)`~~ | **Resolved 2026-08-15**, **revised 2026-08-22** — see "agy decision" below for the order in force |
| `assets/default-panel-review.config.toml` | `model = "gpt-5.5"`, `model_reasoning_effort = "xhigh"` | On codex-cli 0.163.0, a short profile probe bound `gpt-6-luna` / `medium` from the installed profile, which is marked as a temporary test setting. The fresh-install default still needs an owner choice. |

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
3. **Codex model and effort in the shipped asset.** Which model and effort ship as the default for a
   fresh install? Recommended: use the last recorded non-test panel choice (`gpt-5.6-sol`, `high`).
   Adopt a GPT-6 pair only after a real review on that exact model and effort.

## Open questions for the owner

Which model and effort should a fresh install use?

- Keep the current asset values, `gpt-5.5` / `xhigh`.
- Use `gpt-5.6-sol` / `high` (recommended), the last recorded non-test panel choice.
- Choose a GPT-6 model and effort after a real review on that exact pair.

The installed `~/.codex/panel-review.config.toml` currently says `gpt-6-luna` / `medium` and marks
that pair as a temporary test setting. A short `codex exec --profile panel-review` on codex-cli
0.163.0 bound those values. That confirms the pair binds from the current profile, not that it reviews
well or should be the fresh-install default. `run_codex` copies the asset only when the profile file
does not exist, so changing the asset leaves existing profiles alone.

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

### Reversed 2026-08-22 (agy 1.1.18)

Owner's call after live experiments: the order goes back to `Gemini 3.1 Pro (High)` primary,
`Gemini 3.7 Flash (High)` fallback. Both labels were re-verified to bind by
`tests/live/agy_model_binding.sh` on 1.1.18. The "consequence to accept" above is therefore undone —
the fallback is again the faster model, and a primary expiry is once more followed by a quicker
second attempt.

Neither suite needed an edit: both read the pins out of `scripts/run_agy` and assert only their form
(display label, fallback ≠ primary), which is the property `check_contracts`' `agy-model-pin-form`
invariant owns.

Nothing here decides which model reviews *better*; that judgement is the owner's, from runs not
recorded in this repository. What the pin order costs and buys mechanically is stated above.

## Non-goals

- Do not rewrite the historical model values in `docs/superpowers/plans/*` or
  `design-notes/blind-pass-robustness.md`; those are dated records of what was run at the time.
- Do not add automatic model discovery or "latest model" resolution to either wrapper. Pins are
  deliberate: a silently changing seat model makes review results incomparable between runs.
- Do not adopt `--strict-config` for Codex; it fails on user config keys the plugin does not own.

## Comments

### 2026-09-05 — both pins are behind again (agy 1.1.27, codex-cli 0.153.4)

Two new candidates, both raised by the panel owner or found in the same CLI-delta review. Neither is
adopted here: the choice of review model is still the owner's call, and this section only records
what exists.

**Gemini seat — `Gemini 3.8 Flash (High)` is now available and is the owner's preferred candidate.**
`agy models` on 1.1.27 lists, in catalogue order:

```
gemini-3.8-flash-{high,medium,low}    Gemini 3.8 Flash (High|Medium|Low)
gemini-3.7-flash-{high,medium,low}
gemini-3.6-flash-{high,medium,low}
gemini-3.1-pro-{high,low}
```

The Pro line still has not moved past 3.1, and 3.1 Pro is still the primary pin (reversed 2026-08-22,
above). The owner's assessment is that 3.8 Flash may now beat 3.1 Pro outright, which — if adopted —
would reverse the order a *second* time and restore the 2026-08-15 consequence: the fallback would no
longer be the faster model. Note that agy 1.1.25's changelog announces 3.8 Flash only "when
connecting with a `GEMINI_API_KEY`", yet it is listed under this machine's current auth; if the pin
is adopted, verify it binds under the auth the panel actually runs on, not just that it is listed
(`tests/live/agy_model_binding.sh`).

**Codex seat — the shipped asset is now two generations behind.** `assets/default-panel-review.config.toml`
still ships `model = "gpt-5.5"`, `model_reasoning_effort = "xhigh"`. The bundled catalogue in the
installed codex-cli 0.153.4 carries `gpt-6-astra`, `gpt-5.6-sol`, `gpt-5.6-terra`, `gpt-5.6-luna`,
`gpt-5.5` and `gpt-5.2` as listed entries (`gpt-6-astra` was added hidden in the 0.153 line and
un-hidden shortly after, per codex commits `ed391d4dd2` and `a97cf1b72e`). This machine's already
hand-corrected `~/.codex/panel-review.config.toml` runs `gpt-5.6-sol` at `high` — note the effort
has drifted from `max` as recorded in the body above, so whatever ships should be re-read from that
file rather than from this issue.

The recommendation in "Decisions required" item 3 stands but its value is stale: match what is
actually proven on this machine (`gpt-5.6-sol`), or take `gpt-6-astra` only after a real review run
on it. Do not adopt a model on catalogue position alone.

### 2026-10-19 — the Gemini half moved to issue 63; Codex has GPT-6 candidates

**Gemini.** On agy 1.4.2 both current pins are gone from `agy models` (only Gemini 4 Argon and
Gemini 3.8 Flash remain). That is a defect, not a refresh, so it is filed as `issues/63`, which
supersedes this issue's Gemini half.

**Codex.** The bundled catalogue at codex `main` (2026-10-19; installed codex-cli **0.163.0**) lists
`gpt-6-astra`, `gpt-6.1-sol`, `gpt-6-sol`, `gpt-6-luna`, `gpt-5.6-sol`, `gpt-5.6-terra`,
`gpt-5.6-luna` and `gpt-5.5`. GPT-6 Sol and Luna were added on 2026-09-22 (`49e95cc73f`).
`gpt-5.6-sol`, which this machine's `~/.codex/panel-review.config.toml` runs at `high`, is still
listed, so nothing is broken. The shipped asset still says `gpt-5.5`/`xhigh`. The 2026-09-05 advice
still applies: adopt a newer model only after a real review run on it.

### 2026-10-20 — the installed Codex profile is a temporary test setting

`codex --version` reports codex-cli 0.163.0. A short `codex exec --profile panel-review` reported
`gpt-6-luna` / `medium`, matching the installed profile's explicit temporary-test comment. This
confirms that this CLI can bind that pair from the profile. It provides no model-quality evidence.
The last recorded non-test panel profile remains `gpt-5.6-sol` / `high` from the 2026-10-19 note
above. No shipped or installed profile was changed. The owner still needs to choose the fresh-install
values, and any GPT-6 choice needs a real review on that exact pair.
