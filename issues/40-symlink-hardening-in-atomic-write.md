# Decide whether the symlink hardening in `panel_atomic_write` stays

Priority: 40

Status: Optional

Source: Panel review `panel-20260816-080558-5ab680af` (Claude + Codex + Gemini), 2026-08-16 — **contested**: two seats supported removal, one rejected. Severity `low`, category `maintainability`

Triage: ready-for-human

## Problem

Both `panel_atomic_write` implementations carry symlink-specific hardening against a pre-planted
path in shared temporary storage, a threat the documented model excludes:

- `scripts/_panel_common.sh:32` — the backup-rotation comment names the threat explicitly
  ("a local attacker can pre-plant `/tmp/<ID>.md.bak` as a symlink") and replaces a one-line `cp -p`
  with a mktemp-plus-rename sequence.
- `scripts/panel_common.py:53` — `_rotate_backup` re-implements the same defence independently with
  `os.O_NOFOLLOW` plus a `stat.S_ISREG` check.

`AGENTS.md:129` states "No security theatre … safety rests on the disposable container" and
`README.md:491` states "Panel-review assumes one user running one Claude Code session". A second
local user is outside that model. The guarded surface is also narrow: only
`scripts/write_verdict_artifact:8` writes a destination directly into `/tmp`; every other caller
writes inside the run-owned `/tmp/<ID>/` directory. And the run id embeds four bytes from
`openssl rand -hex 4` (`scripts/init_run:70`), so `/tmp/<ID>.md` is not a name anyone can pre-plant
before the run exists.

The panel could not settle it, so this is a maintainer decision, not a defect to fix blind.

**For removal:** the rule is maintained in two languages that `AGENTS.md` already flags as "parallel
shared-helper libs kept in sync", to defend a threat the stated model excludes, on one path, whose
name is unpredictable.

**Against removal:** symlink-defensive rotation and atomic writes are standard safe POSIX handling of
shared temp directories, cost nothing at runtime, and cause no defect. The temp-plus-rename shape is
also not purely defensive — it makes `.bak` replacement all-or-nothing, which `cp -p` writing
straight into the destination is not.

Both sides agree the **atomic temp-file-and-rename rotation itself must stay**. Only the
symlink-specific checks (`[ ! -L ]`, `O_NOFOLLOW`, `S_ISREG`) are in question.

## The part that needs no decision

The two copies are **not equivalent**, and this is verifiable directly:

- `scripts/_panel_common.sh:47` tests the destination with `[ ! -L "$dest" ]` and then opens it in a
  separate `cat` — check-then-open, a TOCTOU gap.
- `scripts/panel_common.py:56` opens the same path with `O_NOFOLLOW` in a single call.

The duplicated rule has already drifted in strength: the bash copy does not deliver the protection
its own comment describes. Whichever way the removal question is settled, one of these two files is
currently wrong — either both should be removed, or the bash copy should be brought up to the
Python copy's guarantee.

## Expected behavior

Pick one and record it:

- **Remove** the symlink-specific checks from both implementations, keep the temp-file-and-rename
  rotation, and note in the header comments that atomicity — not symlink defence — is why the
  rotation exists. Consistent with `AGENTS.md`'s no-security-theatre rule.
- **Keep** them, and fix the bash copy's check-then-open so the two implementations actually match,
  plus a comment in each pointing at the other.

Either way the outcome belongs in the headers of both files so the next reader does not re-litigate
it. If the decision is "keep", it is worth a line in `AGENTS.md`'s trust-model section explaining why
this one guard survives a rule that rejects guards against a tampering local actor.

## Verification

- `./tests/run_tests.sh` passes.
- `scripts/check_contracts --root .` passes.
- The bash and Python `panel_atomic_write` headers describe the same rule.

## Non-goals

- Do not remove the temp-file-and-rename rotation. Both sides of the panel agreed it stays.
- Do not extend either implementation with further hardening; that is the direction `AGENTS.md`
  rules out.

## Comments

### 2026-09-05 — the host now does its own symlink refusal, for a different target

Claude Code (in the 2.1.240–2.1.261 range) added: "Fixed plugins being able to read files outside
their own directory through a declared command, agent, skill, hooks or other component path that is
a symlink; such paths are now refused with an error."

This does **not** decide this issue. The host's refusal covers the *plugin tree's* declared component
paths; `panel_atomic_write` guards *run state* under `/tmp/<ID>/`, which the host never inspects. The
two protect different things.

What it does supply is one data point for the argument the panel could not settle: a runtime whose
own trust model is far stricter than this plugin's still judged symlink refusal worth implementing on
the paths it owns. That is evidence about the general question, not about whether the duplicated
bash/Python checks here earn their keep — and it says nothing at all about the drift between the two
copies, which is this issue's one undisputed defect.
