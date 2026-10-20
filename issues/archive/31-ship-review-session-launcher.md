# Ship a launcher that starts the review session correctly

Priority: 31

Status: Completed

Source: usability review, 2026-08-16

Triage: ready-for-human

## Problem

Every prerequisite panel-review can determine *before* a session exists is currently checked *inside*
the session, where the cheapest failure costs a restart and the user has already typed a command:

- **Fork mode.** `CLAUDE_CODE_FORK_SUBAGENT=0` is read at session start, so `preflight`'s block
  (`scripts/preflight:37`) is discovered at the worst possible moment: the user has started a
  session, invoked `panel-review:start`, and the only remedy is "start a new session".
- **Everything else `preflight` already checks** — `jq`, `git`, a git work tree, a writable cwd, at
  least one peer seat CLI — is equally knowable from a shell prompt.

The README's answer is to hand-write an alias or a wrapper (`README.md:35-50`). That works, but it
puts the one hard requirement of the tool into a snippet the user copies, owns, and can get wrong,
and it does nothing about the rest of the checks.

## Proposal

Ship the wrapper instead of describing it. A small executable (`bin/panel-review-session`, name open)
that:

1. exports `CLAUDE_CODE_FORK_SUBAGENT=0` for the session it launches — and only for that session,
   which is exactly the scoping the README currently argues for in prose;
2. runs `scripts/preflight` and refuses to launch on a hard failure, printing preflight's own output
   (no second copy of the check logic);
3. reports whether this workdir already has a saved review (`.panel-review/<ID>/` marker), so the
   user knows before starting whether they are heading for `start` or `resume`; and
4. `exec`s `claude "$@"`, passing through any arguments.

Installation: `install.sh` can symlink it into a user PATH directory (`~/.local/bin` by default,
opt-out or overridable), and must say what it did. The marketplace install path cannot do this — the
plugin lands in a versioned `~/.claude/plugins/cache` directory — so the script must also work when
run directly from the repo or the installed skills tree, and the README keeps the alias as the
zero-install fallback.

## Keep the preflight fork-mode check

The suggestion that shipping the launcher would let `preflight` drop its `CLAUDE_CODE_FORK_SUBAGENT`
check should be rejected, for one reason: the launcher is *one* entrypoint, and nothing forces its
use. A session started with plain `claude`, from an IDE extension, resumed from history, or by a user
who installed via the marketplace and never got the PATH symlink, would silently run with fork mode
on — and the failure it produces is not a clean error but a variance in referee behavior (measured in
issue 25: 1 of 4 trials improvised a polling wait). The check is a single string comparison, is
covered by `tests/run_tests.sh:84-91`, and is what makes the requirement enforced rather than
advisory.

The launcher's value is removing the *friction* and moving the discovery earlier, not removing the
guard. Under the repo's own trust model this is the honest-accident case the guards exist for.

If the panel owner still wants the check removed after that, it is their call — but it should be a
recorded decision, not a side effect of adding the launcher.

## Resolved choices

- **Name.** `panel-review-session` keeps the command specific to this plugin; it requires a review
  worktree and is not a general Claude launcher.
- **Install location.** `install.sh` links into `~/.local/bin` by default. `PANEL_REVIEW_BIN_DIR`
  overrides the link directory, and `PANEL_REVIEW_INSTALL_LAUNCHER=0` skips the link.
- **Non-repo directories.** The launcher preserves `preflight`'s refusal outside a writable git
  worktree.
- **Failure policy.** The launcher refuses on a preflight failure and prints the check's output.

## Verification

- Shell tests exercise startup from a git worktree and refusal outside one, with mock `claude` and
  Codex commands. They verify forwarded arguments, scoped fork mode, and saved-marker messages.
- Installer tests verify the executable copy, PATH symlink, rerun behavior, and opt-out.
- `preflight`'s fork-mode check and its existing tests remain unchanged.
- `./tests/run_tests.sh` passes.

## Non-goals

- Do not remove or weaken `preflight`'s fork-mode check (see above).
- Do not make the launcher run a review; it only starts a correctly configured session.
- Do not duplicate any preflight check inside the launcher — call `preflight`.
- Do not write to shell rc files or export the variable beyond the launched process.

## Resolution (2026-10-20)

Added `bin/panel-review-session`. It resolves its plugin root when called through a PATH symlink,
sets fork mode off for preflight and Claude, refuses on a preflight failure, reports saved markers,
and execs `claude` with the supplied arguments. `install.sh` copies the launcher and links it into a
configurable PATH directory by default. The README documents direct use, installer options, and the
marketplace alias fallback. The `preflight` fork-mode check remains in place.
