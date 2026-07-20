# Add user configuration and stable run defaults

Priority: 18

Status: Pending

Source: design discussion, 2026-07-20

Triage: ready-for-agent

## Decision

Add one versioned user configuration file for named review profiles and panel-review defaults while
keeping the distributed plugin project-neutral. Resolve review defaults only when creating a run;
after that, the manifest owns the run's effective profile and execution settings. `resume` and
`continue` may change supported execution settings only through explicit command options. Cleanup
retention remains action-time policy and is read when cleanup or discard executes.

Use the XDG user-config location:

```text
${XDG_CONFIG_HOME:-$HOME/.config}/panel-review/config.json
```

The initial schema is:

```json
{
  "version": 1,
  "profiles": {
    "darktable": "/home/developer/.agents/skills/darktable-review/references/review-profile.md"
  },
  "defaults": {
    "review_profile": "darktable",
    "issue_rounds": 2,
    "max_rounds": 4,
    "seat_timeout_seconds": 2400
  },
  "cleanup": {
    "keep_tmp": true
  }
}
```

The example `darktable` entry is user configuration, not plugin-shipped configuration. Panel-review
must not install, generate, or hard-code a darktable profile name or path.

## Problem

Issue 16 added an explicit profile-path seam, but a user who repeatedly reviews one project class
must provide the same path on every run. Other user preferences remain split between command-skill
defaults and ambient environment variables:

- round limits default in the `start` command;
- `PANEL_REVIEW_SEAT_TIMEOUT` changes CLI-seat timing without becoming durable run state; and
- `PANEL_REVIEW_KEEP_TMP` changes destructive cleanup behavior through inherited process state.

This makes defaults difficult to inspect, reproduce, and apply consistently. It also lets inherited
environment state change behavior unexpectedly. The plugin needs one user-owned configuration
source without moving project-specific knowledge into the shared plugin.

## Configuration contract

- A missing config file is valid and preserves the built-in behavior: generic profile,
  `issue_rounds=2`, `max_rounds=4`, `seat_timeout_seconds=2400`, and normal removal of `/tmp/<ID>/`.
- The file must be regular, UTF-8 JSON with `version: 1`. Reject malformed JSON, unsupported
  versions, unknown keys, wrong types, and invalid values rather than silently ignoring mistakes.
- Profile registry values are full absolute source paths. They remain outside panel-review and are
  validated through the existing review-profile size, regular-file, non-empty, and UTF-8 contract
  when selected.
- `issue_rounds` and `max_rounds` must be positive integers satisfying
  `issue_rounds <= max_rounds` after defaults and command options are merged.
- `seat_timeout_seconds` must be a positive integer. The CLI barrier's wait budget must be derived
  from the same effective value so the outer wait cannot expire before the configured seat timeout.
- `cleanup.keep_tmp` must be boolean. It controls whether cleanup and discard preserve the
  diagnostic `/tmp/<ID>/` directory; the durable `/tmp/<ID>.md` verdict remains unaffected.
- Configuration loading and schema validation belong in one deterministic script/module rather
  than being reimplemented in command-skill prose or individual scripts.

## Profile selection

`panel-review:start --review-profile <selector>` accepts either a direct path or a configured name.
Classify the selector by syntax, not by whether a same-named file happens to exist:

- values beginning with `/`, `./`, `../`, or `~/`, or otherwise containing `/`, are paths and must
  succeed as paths;
- bare values such as `darktable` are names resolved through `profiles`; and
- the reserved selector `builtin:generic` selects panel-review's built-in generic profile even when
  the user configured another default.

An unknown name or invalid selected path is a hard error; do not fall back to the generic profile.
Do not discover profiles from headings, skill names, repository contents, or installed copies in
the three seat runtimes.

Profile precedence at `start` is:

```text
explicit --review-profile > defaults.review_profile > builtin:generic
```

The resolved source is validated and snapshotted exactly as in issue 16. The manifest should retain
the requested name or selector as provenance in addition to the resolved source path, size, and
SHA-256. Resume and continuation use only `/tmp/<ID>/review-profile.md` and never reload either the
registry or source file.

## Execution-setting precedence and persistence

Add the user-facing option `--seat-timeout <seconds>` to `start`, `resume`, and `continue`, alongside
the existing `--issue-rounds` and `--max-rounds` options.

At `start`, resolve each execution setting as:

```text
command option > user configuration > built-in default
```

Save the effective round limits and seat timeout in the manifest before publishing the workdir
marker. For `resume` and `continue`, do not reread configuration defaults. Resolve settings as:

```text
command option > saved manifest
```

Write any explicit override back to the manifest before dispatch so later interruption recovery
uses the same values. In particular:

- a `start` round or timeout override belongs to that review and survives `resume`;
- a `resume` or `continue` override becomes the new saved value for that review;
- changing `config.json` affects newly started reviews, not an existing run; and
- `scope`, author instructions, and the profile snapshot remain non-overridable on `resume` and
  `continue`.

The internal `await_seats --seat-timeout` interface may remain. `round` must populate it from the
manifest rather than relying on inherited environment state.

## Cleanup policy

Cleanup retention is action-time policy rather than immutable review state. `cleanup` and `discard`
must read the current `cleanup.keep_tmp` value when invoked. A missing config uses `false`. An invalid
config must fail before either command deletes workspace or `/tmp` state.

Remove `PANEL_REVIEW_KEEP_TMP` and `PANEL_REVIEW_SEAT_TIMEOUT` as behavioral configuration sources.
Do not retain environment-variable precedence. If a compatibility transition is required, reject a
set legacy variable with a clear migration message rather than silently using or ignoring it.

Standard environment conventions remain outside this change: `XDG_CONFIG_HOME`/`HOME` locate user
configuration, `TMPDIR` selects temporary storage, and `CLAUDE_DIR` controls installation rather
than review behavior.

## Verification

- Config absent: existing generic profile, round limits, timeout, and cleanup behavior remain
  unchanged.
- Configured named/default profiles resolve to the expected source and exact run snapshot; direct
  paths and `builtin:generic` override the configured default.
- Invalid JSON, schema versions, keys, values, aliases, and profile paths fail clearly before a run
  marker is published.
- `start` applies command/config/built-in precedence and records effective settings in the manifest.
- `resume` and `continue` ignore changed config defaults, preserve manifest values, and persist
  explicit round/timeout overrides.
- Round 0, debate, interrupted-round recovery, and continuation pass the saved timeout to every new
  CLI-seat barrier; the barrier wait budget remains consistent with it.
- Cleanup and discard read current config, preserve `/tmp/<ID>/` only when configured, and perform no
  deletion on config-validation failure.
- The legacy panel-review environment variables no longer influence behavior; tests cannot inherit
  them and accidentally change cleanup or timeout behavior.
- Status and result surfaces show the effective profile and execution settings needed to explain a
  saved run without dumping configuration contents.
- Update `README.md`, command-skill argument hints and parsing contracts, the canonical protocol,
  `.claude/rules/scripts.md`, `CONTRACTS.md`, and test documentation.
- Run focused config/profile/lifecycle tests, `scripts/check_contracts --root .`,
  `./tests/run_tests.sh`, and `git diff --check`.

## Non-goals

- Do not ship project-specific profile registrations or defaults with panel-review.
- Do not auto-detect a repository's profile.
- Do not reload or replace the saved profile on resume or continuation.
- Do not make every script parse user configuration; resolve run settings at creation and propagate
  them through the manifest.
- Do not move installer or standard operating-system environment conventions into runtime config.
