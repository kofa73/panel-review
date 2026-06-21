# Curated issues — re-evaluated for the real usage scenario

The panel self-review (`example_self_review.md`) accepted 12 issues. Many were
scored against a multi-user / concurrent / adversarial threat model that does
**not** match how `/panel-review` is actually run:

- **One developer at a time**, from their own Claude Code console.
- **No concurrency**: a developer does not launch two runs against the same
  working tree at once.
- **Seats don't write process files.** The review seats (Claude/Codex/Gemini)
  are read-only reviewers. The *only* writer of `index.json` / sweeps is the
  referee, via the `index` and `sweep` scripts. There is a single writer, and it
  controls the IDs, states, flags, and payload shapes it emits.
- **Disposable container** trust model; the "attacker" is not a third party but,
  at worst, the model's own mistakes or prompt-injection from the reviewed code.

Re-scored below. Each issue is marked **KEEP** (real and worth fixing),
**DOWNGRADE** (real but lower severity / defensive-only), or **DROP**
(hypothetical under the real scenario). Severities are the corrected values.

---

## KEEP — worth fixing

### 1. commit-sweep silently drops a wrong-shape `set_flag` and still commits the round
`skills/panel-review/scripts/index:94-123` · **severity: high (kept)**

Strongest finding, and the only one **observed in a real run** (`issues.md:4`:
the referee emitted `{"id",…,"peer_reviewed":true}` instead of
`{"id","flag","value"}`; the flags were silently dropped, and because the round
was already recorded in `committed_rounds`, the corrected same-round commit was a
no-op). This does not depend on any multi-user or concurrency assumption — the
single trusted writer hit it by itself. Up-front validation (index:94-97) checks
only `add_issues` id shape; `set_flag`/`set_state`/`add_evidence`/`revise`
sub-entries are applied unvalidated, and the unknown-shape `set_flag` falls
through to the `else .` branch (index:106-109) and vanishes.

Fix: validate `set_flag` (and the other sub-entry shapes) up front and **fail
the commit** on a malformed payload, so the round is not recorded and can be
re-committed correctly. Drop the "unrecoverable" wording — the state is
hand-repairable via `index flag` — but the silent-drop + locked-out re-commit is
the real defect.

### 2. Gemini seat is not sandboxed read-only (asymmetry with Codex)
`skills/panel-review/scripts/run_agy:20-26` · **severity: medium (was "security/high")**

Not a multi-user security breach under the real model, so the original framing
overstates it. But it is still a genuine defect: the Gemini seat runs as a full
agentic tool user that can **write the working tree and run shell**, while the
Codex seat is pinned `--sandbox read-only` (run_codex:51). A reviewer is not
supposed to mutate anything. The realistic harm is a model mistake or
prompt-injection from the reviewed code corrupting the developer's *uncommitted*
working tree — exactly the thing under review. The asymmetry with Codex makes the
intent clear and the fix obvious: constrain the Gemini seat to read-only if `agy`
supports it, or document explicitly that it cannot be constrained and rely on the
disposable container. The code comment already admits the gap; close it or
declare it intentional.

---

## DOWNGRADE — real but minor / defensive-only

### 3. cleanup strips a pre-existing user `.panel-review/` git-exclude line
`skills/panel-review/scripts/_panel_common.sh:46-52` (with `cleanup`) · **severity: low**

Real and user-relevant: this matches the developer's own note (`issues.md:7`:
"no need to actively edit `.git/info/exclude`: just add `.panel-review` once, if
not there"). `panel_git_exclude_add` is idempotent but records no ownership;
`panel_git_exclude_del` removes the line unconditionally on cleanup, so a line the
user added themselves before any run gets stripped, changing later `git status`.
Fix aligns with the user's intent: add once if absent, and on cleanup only remove
a line this tool added (track ownership, or simply never remove it).

### 4. crash during `--continue` can replay a stale sweep
`skills/panel-review/scripts/reopen:30-35` · **severity: low (was Important)**

Real crash-consistency gap but a narrow window: `index reopen` clears
`committed_rounds` and reopens issues, *then* a separate `rm -rf sweeps`. A crash
(Ctrl-C, closed terminal) precisely between them leaves stale sweep dirs with
`committed_rounds=[]`, and resume re-applies the cached seat outputs onto the new
cycle. Single-dev crashes do happen, so it is worth hardening, but the
probability is low and the blast radius is one continuation that can be restarted
fresh. Fix: clear sweeps *before* resetting `committed_rounds`, or treat the
reset+clear as one recoverable step.

### 5. `panel_atomic_write` calls bare `sync`
`skills/panel-review/scripts/_panel_common.sh:31` · **severity: low (was Important, contested)**

Bare `sync` flushes every filesystem visible to the process, not just the temp
file, on every atomic write. On a single developer's machine with a tiny,
infrequent write workload this is a minor inefficiency, not a correctness problem.
Optional fix: `dd conv=fsync` (or `fdatasync`) on the temp file only. Low
priority.

### 6. uncommitted scope emits two concatenated patches
`skills/panel-review/scripts/resolve_diff:34-35` · **severity: low (was Important, contested)**

The output is only **read by reviewers and hashed for resume** — never
`git apply`-ed — so a file that is both staged and unstaged showing up twice is
reviewer confusion, not an apply failure. Cheap, worthwhile fix: a single
`git diff HEAD -- . ':(exclude).panel-review/**'` yields one coherent
HEAD→worktree patch (still append untracked file contents as today).

### 7. commit-sweep `add_issues` does not enforce ID uniqueness
`skills/panel-review/scripts/index:101` · **severity: low (defensive)**

Real but the referee is the single writer that assigns issue IDs; a collision
requires a referee bug, not a hostile input. A duplicate id would make every
later `select(.id==$x)` mutate multiple records. Worth a cheap uniqueness guard
in the same up-front validation, but not high value.

### 8. no allowlist for `state` values
`skills/panel-review/scripts/index:75` and commit-sweep set_state (index:104-105) · **severity: low (defensive)**

`.state=$s` accepts any string (unlike `flag`, which validates). A typo'd state
silently breaks `select(.state=="open")`. Single trusted writer, controlled
vocabulary, so low value — but a cheap allowlist (`open|accepted|rejected|
contested|unresolved|merged`) is a reasonable guardrail given the referee already
tripped a different payload-shape bug (#1).

### 9. commit-sweep maps an unrecognized evidence `side` to `contra`
`skills/panel-review/scripts/index:112-114` · **severity: low (defensive)**

`if $e.side=="pro" … else (contra)` routes any non-`pro` value to `evidence_contra`.
Same reasoning as #8: single trusted writer, so low value; a cheap validation
prevents a silently misclassified audit trail.

### 10. debate revision schema omits `category`
`skills/panel-review/prompts/debate.tmpl:18` · **severity: low**

Real schema/doc inconsistency: the seat-facing `revision` object is
`{severity, location, claim}`, yet `commit-sweep revise` applies `.category`
(index:121) and the protocol lists category as revisable. Seats have no
documented channel to propose a category change. Fix: add `category` to the
schema in debate.tmpl, or drop category from the revisable set if intentionally
not seat-proposable.

---

## DROP — hypothetical under the real scenario

### 11. concurrent fresh invocations can start two referees
`skills/panel-review/scripts/init_run:62-68`

The entire premise is two simultaneous fresh invocations against the same
workdir. A single developer running one review at a time from their console does
not do this. The marker `flock` already serializes the race it can realistically
see. Not worth complicating the contract for a scenario that does not occur. (If
multi-user/CI use is ever added, revisit — the caller-can't-distinguish-existing-
run behavior would then matter.)

---

## Cleanup / docs (from the panel's style note + the developer's own list)

- **Dead code:** `index commit-round` is no longer on the live path
  (`sweep commit` → `index commit-sweep`). The `sweep` header comment
  (sweep:17-19) and the `index` subcommand docs still advertise `commit-round`
  and omit the live `reopen`. Remove the dead subcommand or mark it, and sync the
  comments. Low risk, real maintenance debt.
- **Codex `login` warning** (`issues.md:3`): the recurring
  `WARNING: run 'codex login'` at preflight is harmless but noisy and wastes
  tokens — suppress or downgrade it once the seat is confirmed working.
- **Document the `/tmp/<ID>` rationale** (`issues.md:6`): reword "so Codex's
  read-only sandbox can read them" to a future-proof "so workspace-locked seats
  can read them" — visibility, not read-only-ness, is the point, and more seats
  may come.
