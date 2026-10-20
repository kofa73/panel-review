# Continue a finished review (`--continue`) — design

**Status:** approved (design dialogue 2026-06-20)
**Goal:** Let the user push a *finished* panel review further on the issues it handed back —
`unresolved` and/or `contested` — without re-reviewing everything, by giving those issues a fresh
debate budget.

## User-facing behavior

A finished review may end with leftover issues handed to the human: `contested` (split at the round
limit, but reviewed) and `unresolved` (never met the 2-seat quorum). Today those are reported and the
run is deleted. With this feature:

- A run that finishes **with any `unresolved`/`contested` issue is preserved** (not cleaned up),
  exactly like the existing Round-0 low-severity gate preserves its run.
- The verdict tells the user `--continue` is available.
- `/panel-review --continue` re-opens those issues and runs more debate rounds:
  - `--continue` → both `unresolved` and `contested`
  - `--continue unresolved` → only `unresolved`
  - `--continue contested` → only `contested`
- Only the **selected** category is re-opened and reset. The other leftover category (if any) stays
  as-is and is carried into the new verdict unchanged.

`--continue` takes its **scope and round limits from the finished run** (read from the run's
manifest); it must not be combined with a scope or limit flag.

## What "counters start fresh" means

The continuation reuses the run's **same round limits**, but resets counters so the re-opened issues
get a full budget again:

- Per re-opened issue: `state→open`, `rounds_debated→0`, and the vetting flags
  `peer_reviewed→false`, `fully_vetted→false`, `detail_contested→false` (they must re-earn them).
- Global: `round→0`, `committed_rounds→[]`.
- **Kept:** accumulated `evidence_pro`/`evidence_contra` and origins (so the seats see the prior
  arguments — the whole point of continuing a close call). Projected cards are rebuilt from the
  index when a run resumes.
- **Untouched:** already-`accepted`/`rejected` issues, and the non-selected leftover category.

## Architecture — all new logic in deterministic scripts; the agent is nearly unchanged

The re-opened issues become ordinary `open` issues with zeroed counters, which is byte-identical to
the shape a Round-0-gated run has when the user chooses to debate. So the referee's existing
`mode=resume` path drives the continuation with **no new agent code path**. The change set:

1. **`index reopen <ID> <category>`** (new subcommand of the `index` script — still the only writer
   of `index.json`): performs the issue/global reset above.
2. **`reopen` script** (new): calls `index reopen`, then **clears `/tmp/<ID>/sweeps/`**. This is
   mandatory — the referee's debate recovery scans `sweeps/` and uses `committed_rounds` to decide
   what to re-apply; with `committed_rounds` reset to `[]`, leftover sweep dirs would be re-applied
   and corrupt the continuation. After clearing, the state matches a gated run (issues present, no
   committed sweeps) and resume starts cleanly at round 1.
3. **`resume_check`**: new verdict line `continuable <ID>` — emitted when the single marker's
   scope/limits/diff match AND the index shows a *finished* run with leftovers: **no `open` issues
   and ≥1 `unresolved`/`contested`**. (An interrupted run still has `open` issues → `resume` as
   today. This needs no new sentinel — "finished with leftovers" is derivable from the index alone.)
4. **Referee** (`panel-review-for-agent/SKILL.md`, `agents/panel-review-referee.md`): at the end,
   if the final index has any `unresolved`/`contested` issue, **skip cleanup** and append a control
   line `<<<PANEL-CONTINUABLE id=<ID> unresolved=<n> contested=<m>>>>` — a direct parallel to the
   gate's `<<<PANEL-GATE …>>>`. No leftovers → cleanup as today.
5. **Dispatcher** (`panel-review/SKILL.md`):
   - Parse `--continue [unresolved|contested]`; forbid combining it with a scope/limit flag.
   - `--continue` flow: find the lone preserved run, source scope+limits from its manifest, resolve
     the **current** diff and confirm the stored hash still matches (the **scope/diff gate** — refuse
     if the code moved), confirm via `resume_check` that it is `continuable`, confirm the requested
     category has ≥1 issue, then `reopen` and dispatch `mode=resume` (`debate-low=true`).
   - No-flag flow: when `resume_check` returns `continuable <ID>`, **ask** (Continue both / Fresh
     discard / Stop) instead of silently resuming.
   - Step 5: handle the `<<<PANEL-CONTINUABLE …>>>` line like the gate line — strip it, present the
     verdict verbatim, append a one-line hint about `--continue`, and do **not** clean up.

## Scope / diff gate

`--continue` re-resolves the diff for the run's stored scope and compares it to the stored
`diff_hash`. If they differ, the code under review moved; continuing a debate over changed code is
unsound, so it refuses with a clear message ("run a fresh review instead"). This reuses the existing
`moved` detection in `resume_check`.

## Lifecycle of an un-continued finished run

A preserved finished run lingers in `.panel-review/<ID>/` + `/tmp/<ID>/` until the user continues it,
discards it, or starts a different review. Starting a review on a **different** scope while a
finished run lingers is handled by the existing `moved`/ask path (discard the old run, or stop) —
no new behavior needed beyond `resume_check` recognizing the finished run.

## Out of scope

- No partial-issue selection (only whole categories).
- No carrying issues across a changed diff (the scope/diff gate refuses).
- No new referee debate logic — continuation is plain `mode=resume` over re-opened issues.

## Testing

The repo has no test harness (bash skill suite). Each script task is verified with an ad-hoc
fixture: build a small `index.json` in a temp dir, run the script, assert the JSON/output with `jq`.
