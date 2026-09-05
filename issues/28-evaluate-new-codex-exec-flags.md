# Evaluate new codex exec capabilities for the Codex seat

Priority: 28

Status: Optional

Source: codex-cli review (0.146.1 → 0.147.0), 2026-08-15

Triage: ready-for-human

## Problem

`codex exec` has gained flags since `run_codex`'s contract was written. None is required — every
flag `run_codex` passes still exists and still means what the header says (verified against
`codex exec --help` on **0.147.0**: `--profile`, `--dangerously-bypass-approvals-and-sandbox`,
`-c`, `-o`, `--json`). This is the Codex counterpart of issue 23: record the decision per candidate
so the analysis is not redone at the next CLI update.

## Candidates

### Hooks and `--dangerously-bypass-hook-trust`

Codex now runs lifecycle hooks from the user, project, and session config layers, gated by a
persisted per-hook trust record; the flag runs enabled hooks without that record. A hook configured
by the operator would execute inside a review seat, which can change what the seat does without any
sign of it in the panel's output.

Untrusted hooks are reported as untrusted rather than executed, so the likely failure is a hook that
does *not* run, not a hang. Decide: leave hooks alone (a seat inherits the operator's Codex setup,
same as it inherits the base config), or document that panel-review does not manage them.
**Do not** adopt `--dangerously-bypass-hook-trust`: it would run hooks panel-review never vetted.

### `--ignore-rules` and `--ignore-user-config`

`--ignore-rules` skips user and project execpolicy `.rules` files; `--ignore-user-config` skips
`$CODEX_HOME/config.toml` entirely. Both would make the seat more reproducible across machines and
less dependent on operator configuration — and both would also discard the very base config the
`panel-review` profile is designed to layer over, including MCP server definitions such as tilth.
`--ignore-user-config` is therefore almost certainly wrong; `--ignore-rules` needs a test on a
machine that actually has `.rules` before it is considered.

### `--ephemeral`

Runs without persisting session files to disk. Attractive on tidiness grounds (a seat's transcript
is review content living outside `/tmp/<ID>/`), but it also removes the artifact that makes a failed
seat pass diagnosable after the fact. Decide on that trade; the persistence model in `CLAUDE.md`
says `/tmp/<ID>/` is the single source of truth, not that no other copy may exist.

### `--output-schema`

Same reasoning as agy's `--output-format json` in issue 23, and the same recommendation: decline.
All three seats deliver one fenced-block contract to `parse_block`; giving one seat a different
transport adds a second parse path and a second place for `seat_contract.py`'s schema to drift.

### `--enable` / `--disable <FEATURE>`, `--approve-for-me`

`--approve-for-me` routes approvals through automatic review in the workspace-write sandbox — the
sandbox `run_codex`'s header explains the seat cannot work under (MCP tool calls are auto-cancelled).
Decline, and say why in one line so it is not adopted later as an apparent safety improvement.
`--enable`/`--disable` are equivalent to `-c features.<name>=…`; no feature is currently needed.

### Removed upstream: legacy `--full-auto`

`codex exec` dropped its legacy `--full-auto` handling. `run_codex` never used it; recorded so the
absence is not read as an omission.

## Expected outcome

A decision recorded per candidate, and for each adopted flag a `run_codex` header entry explaining
why it is there — matching that wrapper's existing convention.

## Verification

- Any adopted flag is exercised by one real review with the Codex seat engaged.
- `scripts/check_contracts --root .` and `./tests/run_tests.sh` pass.

## Non-goals

- Do not change the Codex seat's output contract or `parse_block`'s interface.
- Do not create, edit, or delete any file under `~/.codex/` other than the profile `run_codex`
  already owns.
- Do not adopt a flag whose effect has not been observed on this machine.

## Comments

### 2026-09-05 — flag and behavior surface to triage on codex-cli 0.153.4

The recorded baseline is 0.149.0; installed is **0.153.4**. Every flag `run_codex` passes still
exists on 0.153.4 (`--profile`, `--dangerously-bypass-approvals-and-sandbox`, `-c`, `-o`, `--json`),
so this remains a decision register, not a defect. New or newly-relevant surface:

| Flag / behavior | Why it might matter here |
|---|---|
| `--enable <FEATURE>` / `--disable <FEATURE>` | Sugar for `-c features.<name>=true\|false`. Cheap way to turn a specific behavior off per run without touching the profile. |
| `--strict-config` | Still ruled out by this issue's non-goals and `issues/21`'s — it errors on user config keys the plugin does not own. |
| `--approve-for-me` | "Route approval requests through automatic review using the workspace-write sandbox." A milder alternative to `--dangerously-bypass-approvals-and-sandbox`, but it introduces a *second model* deciding what the seat may run, which is a blindness and determinism question, not just a permissions one. |
| `--thread-source <SOURCE>` | Classification only; no effect on the seat. Record as declined. |
| `--add-dir <DIR>` | Additional writable directories. Convenience, not a control — same trust-model caveat as agy's. |
| `--ignore-user-config` | Skips `$CODEX_HOME/config.toml`. Does **not** solve `issues/47`: that issue is about the cwd/tree/repo config layers sitting *above* the profile, which this flag does not touch. Say so there rather than letting the flag look like a fix. |
| `codex exec` managed worktrees (commit `eb5a00b068`) | New in this range. Same class of question as `issues/60`'s worktree measurement: if the Codex seat can be made to work in a worktree, it changes what `repo_guard` is guarding. |
| "Warn when saved model defaults are overridden" (`68e9c4a31a`) | Direct evidence for `issues/47` — the CLI now surfaces the override this panel cannot currently detect. Worth reading before that issue's fix is designed. |

**Guardian.** A substantial share of the 0.149→0.153 commits add a "Guardian" review layer with
model-provided review policies, per-model requirements, and compaction checkpoints. It is not a flag
and its interaction with `codex exec --dangerously-bypass-approvals-and-sandbox` is unmeasured. Read
before the next Codex-seat change; do not assume the bypass flag still bypasses everything it used to.

**Delta not fully triaged.** 608 commits separate the baseline from HEAD, filtered here for the
surfaces the plugin touches (`codex exec` flags, config layering, sandbox, MCP, bundled models). The
Codex baseline in `docs/agents/external-cli-baselines.md` should therefore **not** be advanced on the
strength of this comment alone.
