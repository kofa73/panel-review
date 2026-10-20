# Make the Codex model pin authoritative and stop writing to the user's home config

Priority: 47

Status: Completed

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

## Comments

### 2026-09-05 — measured: the override is live on this machine, against darktable

The layering claim is no longer source-review only. Measured on installed **codex-cli 0.153.4**
(checkout `ddf04ad267`, whose `codex-rs/config/src/loader/mod.rs:108-121` still documents
`profile → cwd → tree → repo → runtime`), by running `scripts/run_codex` unmodified with a trivial
prompt and reading `model`/`effort` out of the `turn_context` record of the resulting rollout under
`~/.codex/sessions/`:

| cwd | Repo-local `.codex/config.toml` | Profile pins | **Bound** |
|---|---|---|---|
| `/workspace/darktable` | `model = "gpt-5.6-luna"`, `model_reasoning_effort = "max"` | `gpt-5.6-sol` / `high` | **`gpt-5.6-luna` / `max`** |
| `/workspace/panel-review` | none | `gpt-5.6-sol` / `high` | `gpt-5.6-sol` / `high` |

So the panel's Codex seat has been reviewing darktable under a model and effort the manifest does not
record, and the control case confirms the profile is otherwise honoured — the repo layer is the sole
cause. `/workspace/dt-pr` and `/workspace/dev-doc-update` carry the same file; `/workspace/darktable`
and `/workspace` are both `trust_level = "trusted"` in `~/.codex/config.toml`, so the layer is
enabled rather than merely present.

**This makes the issue live rather than theoretical, on the panel's principal review target.** What
is lost is not only verdict provenance: the pin is what makes two runs comparable, and it is not in
force wherever the reviewed repository configures Codex itself — which is exactly the class of
repository this user reviews.

**Item 5 of "Expected behavior" is wrong and should be dropped.** Waiting for issue 21's model choice
is not a prerequisite: the fix is to pass *whatever the profile file already says* as highest-
precedence `-c` overrides, so it is orthogonal to which model that is. Reading the two keys out of
`$PROFILE_FILE` and re-emitting them as `-c model=… -c model_reasoning_effort=…` keeps the profile as
the single source of the values and needs no decision from issue 21.

### 2026-09-05 — the remedy is detect-and-report, not a forced override

Owner's call, and it supersedes item 1 of "Expected behavior" above. Forcing the profile over the
reviewed repository's `.codex/config.toml` with runtime `-c` flags would silently defeat a setting
the user wrote deliberately — `/workspace/darktable/.codex/config.toml` is the user's own file — so
it is the same defect pointed the other way. **The defect is the silence, not the precedence.**

It also fits the repo's trust model better: there is nothing hostile to enforce against here, so a
report is the honest guard and a forced override would be a control bought against a non-threat.
And it is less code — a file check instead of a new precedence layer.

Revised expected behavior, replacing items 1 and 5:

1. **`preflight` detects the condition and reports it.** Check for a Codex config layer above the
   profile that is anchored at or under the workdir — `$(git rev-parse --show-toplevel)/.codex/config.toml`
   (repo layer), `$PWD/config.toml` (cwd layer), and `.codex/config.toml` in parent directories up to
   root (tree layer). If one exists and sets `model` or `model_reasoning_effort`, print the file, the
   values it sets, and the values `~/.codex/<profile>.config.toml` pins, so the difference is visible
   before a run exists. `preflight` is the right home: it is read-only, it is already the single
   source for both the skill and the prereq report, and it already does exactly this shape of
   environment detection for the `/tmp` read block (issue 62).
2. **`start` asks before proceeding**, the way it does for other preflight conditions — proceed under
   the repository's model, or stop and let the user move the file. Not a hard failure: reviewing a
   repository under its own configured model is a legitimate choice, it just must not be an
   invisible one.
3. **Item 2 above stays and becomes the more important half.** Asking alone still leaves the manifest
   recording a model that did not review the code. Record what actually bound, so the verdict's
   provenance is true whichever way the user answers.

Note on trust: the cwd, tree and repo layers are "loaded but disabled when the directory is
untrusted" (`loader/mod.rs:117-119`), so a detected file does not always apply. Determining trust
means parsing `~/.codex/config.toml`'s `[projects."…"]` table, which `preflight` must not write to
and should not need to reason about. Report the file and say it applies if the directory is trusted;
do not try to predict the resolution exactly. Over-reporting here costs one line of output.

Items 3 (whether the auto-created profile file survives) and 4 (`--json`/`-o` conditionality) are
unaffected by this change — but note item 3's premise is now gone: without runtime overrides the
profile is still what carries the pin, so it stays.

### 2026-09-05 — implemented as detect / ask / record

Verified live on **codex-cli 0.153.4** before writing anything, in the two repositories the earlier
comment used (`/workspace/darktable`'s file has since been removed; `/workspace/dt-pr` still carries
the same one):

| cwd | Repo-local `.codex/config.toml` | **Bound (Codex's own config summary)** |
|---|---|---|
| `/workspace/panel-review` | none | `gpt-5.6-sol` / `high` — the profile pin |
| `/workspace/dt-pr` | `gpt-5.6-luna` / `max` | **`gpt-5.6-luna` / `max`** |

**1. `preflight` detects and reports** (`scripts/preflight`). It collects the config layers above the
profile that are anchored at or under the workdir — the cwd layer `$PWD/config.toml` and the tree
layer `.codex/config.toml` in `$PWD` and every ancestor, which subsumes the repo layer since the git
toplevel is always one of those directories — skipping a `.codex` that *is* Codex's own home, as the
loader does. A candidate counts only if it sets `model` or `model_reasoning_effort` **at the TOML
root**; a `model` under some `[table]` is a different key and is not read. The report names the file,
its values, and the profile's pins, and says the layer applies only if the directory is trusted rather
than trying to predict Codex's trust resolution. New machine-readable line `CODEX_MODEL_LAYER: yes|no`
sits ahead of the existing `CODEX:`/`GEMINI:` tail. It is a warning: exit stays 0.

**2. `start` asks** (`skills/start/SKILL.md` Step 2). It now keeps `preflight`'s output, counts that
line, and on a hit asks (`AskUserQuestion`) whether to review under the repository's own Codex model or
stop and move the file. Nothing is minted before the answer.

**3. The binding is recorded** (`scripts/run_codex`, `scripts/await_seats`, `scripts/round`). Two facts
made this observable rather than predicted: `-o` writes the final assistant message in **both** of
`codex exec`'s output modes, and human mode prints the resolved config summary — including
`model:` and `reasoning effort:` — to **stderr**, where `--json` replaces it with a `thread.started`
event carrying only a thread id. So `run_codex` dropped `--json`, captures stderr, and reads the two
values from between the summary's first two `--------` rules (bounded, so a `model:` line inside the
echoed prompt cannot win). `await_seats` — the only dispatcher that knows the run id — points it at
`/tmp/<ID>/codex-model.txt`, and `round verdict-input` surfaces it as `seat_models`, which the protocol
tells the referee to state in Process notes.

**Item 4 resolved by removal.** `CODEX_JSONL` had no caller anywhere in the repository, and its stated
rationale ("`--json` is required because `-o` writes only the final message") is false on 0.153.4, so
the toggle is gone rather than made conditional. Item 3 stands as the last comment left it: without
runtime overrides the profile still carries the pin, so the auto-created profile file stays.

**Not done, deliberately:** the `--dangerously-bypass-approvals-and-sandbox` non-goal was left
untouched — it requires its own disposable probe, not this change.

Tests: `tests/run_tests.sh` covers preflight's detection (including the `[table]`-scoped false
positive and the tail order), `run_codex`'s recording (including the decoy prompt line and the
no-destination path), and `await_seats`' wiring. 291 pass, 0 fail; `check_contracts` clean.
