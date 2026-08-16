# Ship a launcher that starts the review session correctly

Priority: 31

Status: Pending

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

## Open questions

- **Name.** `panel-review-session`, `claude-review`, `panel-review-shell`. `claude-review` matches
  the README's existing alias example; a `panel-review-` prefix keeps the plugin's namespace.
- **Install location.** `~/.local/bin` symlink by default vs. print-the-instruction only. A symlink
  is a write outside the plugin tree, which `install.sh` does not currently do.
- **Non-repo directories.** `preflight` requires a git work tree and a writable cwd, so the launcher
  would refuse to start a session anywhere else. That is correct for a review session and wrong for a
  general-purpose shell alias — which argues for the `panel-review-` prefixed name over
  `claude-review`.
- **Failure policy.** Refuse on any preflight hard failure (recommended, since `start` would refuse
  anyway) vs. warn and launch.

## Verification

- Launcher started from a clean repo: preflight passes, session starts, `panel-review:status` inside
  it reports fork mode acceptable.
- Launcher started from a directory with no git work tree, or with neither `codex` nor `agy`
  installed: refuses, prints preflight's output, does not start a session.
- Launcher started in a workdir with a saved review: says so before launching.
- `CLAUDE_CODE_FORK_SUBAGENT` remains unset in the parent shell afterward.
- `preflight`'s fork-mode check and its tests are unchanged.
- `install.sh` reports what it linked and is idempotent across reruns; `./tests/run_tests.sh` passes.

## Non-goals

- Do not remove or weaken `preflight`'s fork-mode check (see above).
- Do not make the launcher run a review; it only starts a correctly configured session.
- Do not duplicate any preflight check inside the launcher — call `preflight`.
- Do not write to shell rc files or export the variable beyond the launched process.
