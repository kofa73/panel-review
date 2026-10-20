# Detect the setting that blocks Claude's direct reads of `/tmp/<ID>/`

Priority: 62

Status: Completed

Source: Claude Code docs review, 2026-09-05 — `permissions.blockReadsOutsideWorkingDirectories`
and auto mode's first-outside-read prompt, both new in **2.1.257**. Installed Claude Code: 2.1.261;
`docs/agents/external-cli-baselines.md` baseline is 2.1.239.

Triage: ready-for-agent

## Problem

The panel's single source of truth lives **outside** the repository under review. `/tmp/<ID>/` holds
the manifest, index, sweeps, raw seat output, origins and audit; seat scratch is
`/tmp/<ID>/work/<seat-token>/`; the delivered verdict is `/tmp/<ID>.md`. That placement is
deliberate and load-bearing (`issues/24`: a seat's repo-wide search returning a rival seat's raw
output broke blindness). Claude Code 2.1.257 added two ways for those reads to stop working:

- **`permissions.blockReadsOutsideWorkingDirectories`** — "Stop Claude from reading paths outside
  the session's working directories with the Read, Grep, Glob, and LSP tools, **in every permission
  mode including `bypassPermissions`**. A Bash command that reads a matching path through a file
  command Claude Code recognizes, such as `cat`, prompts you even in auto mode and
  `bypassPermissions` mode."
- **auto mode's one-time prompt before the first read outside the working directories** — and
  choosing to block writes `true` into that setting, permanently, from inside an ordinary session.

Two properties make this worse than an ordinary misconfiguration:

- **Its scope is `Any file`, and it only ratchets on.** "If any settings source sets `true`, the
  block applies" — a checked-out repository's own `.claude/settings.json` can turn it on for a
  project, and a `false` elsewhere does not lift it. The repository *under review* can therefore
  disable the panel that is reviewing it.
- **`bypassPermissions` is not an escape.** Every other permission problem the panel has hit was
  fixable by permission mode; this one is not.

The failure can land before dispatch: `start` hashes the resolved diff through an input redirection
from `/tmp`, which Claude Code recognizes as an outside-workdir read. If that is approved or avoided,
the Claude seat's direct read of the canonical diff is blocked later. Opaque wrapper scripts can
still read `/tmp`, and the external Codex and Gemini processes are not themselves fenced by this
Claude Code setting.

## Expected behavior

1. `preflight` reports the state of `permissions.blockReadsOutsideWorkingDirectories` across the
   local settings files it can inspect and **hard-fails** when it is on without a `/tmp` working-
   directory grant. It names every detected enabling file and prints both supported remedies: add
   `permissions.additionalDirectories: ["/tmp"]` to repository or user settings, or launch with
   `--add-dir /tmp` plus the explicit preflight marker.
2. The auto-mode first-read prompt is documented as a hazard in README's requirements section: a
   user who answers "block" once has silently disabled every future review.
3. Whether the panel should instead **stop depending on outside-workdir reads** is explicitly
   answered, not left implicit. It should not: `issues/24` moved state to `/tmp` precisely so seats
   could not stumble over each other's output inside the repo, and moving back would undo that. Say
   so in the issue record so the question is not reopened.

## Verification

- With `{"permissions": {"blockReadsOutsideWorkingDirectories": true}}` in a scratch settings file,
  `scripts/preflight` exits 1 and names the setting and the file.
- With the setting absent, `preflight` is byte-identical to today's output.
- A run started under the block, if the check is bypassed, is confirmed to fail the way this issue
  predicts — so the diagnosis in the error message matches the real symptom.
- `scripts/check_contracts --root .` and `./tests/run_tests.sh` pass.

## Resolution

**Completed 2026-09-05.** Live probes against Claude Code 2.1.261 confirmed that native `Read`, a
recognized `cat`, and panel-review's exact `diff_hash < /tmp/file` command are denied with the block
enabled even in `bypassPermissions`. A repository `.claude/settings.json` can activate the block.
An opaque wrapper that reads the same file internally still runs, so this is a Claude tool boundary,
not a filesystem boundary and not a block on every seat.

Both `--add-dir /tmp` and `permissions.additionalDirectories: ["/tmp"]` restore access while the
block remains enabled. `preflight` now detects the user, shared-project, project-local, and file-based
managed settings it can inspect. Persistent grants are detected from those files. Claude Code does
not expose startup `--add-dir` values to subprocesses, so the documented session-only launch carries
`PANEL_REVIEW_TMP_ADDED=1` as an explicit attestation for `preflight`.

## Non-goals

- Do not add the setting to any file the plugin ships or installs. The plugin does not own the
  user's `~/.claude/settings.json`, and writing `false` there would not help anyway (a `true`
  anywhere else still blocks).
- Do not move panel state back inside the repository under review; that reverses `issues/24`.
- Do not extend the check to the sandbox read rules in the same setting's documentation
  (`sandbox.filesystem.allowRead`). The panel does not run under Claude Code's sandbox.
