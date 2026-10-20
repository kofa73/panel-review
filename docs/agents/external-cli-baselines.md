# External CLI review baselines

The commit each external reference repository was last reviewed at, so "check the changelogs for
what's new" has a defined starting point instead of a guess at a date.

Panel-review depends on three external runtimes it does not control — Claude Code (the host), the
`codex` CLI (Codex seat), and the `agy` CLI (Gemini seat). Their behavior changes under it. This file
records where the last such review stopped; everything after these commits is unreviewed.

## Current baselines

| Reference | Local path | Release record | Baseline commit | Baseline date | Version reviewed |
|---|---|---|---|---|---|
| Claude Code docs | `~/github-repos-for-agents/claude-code-docs/` | `docs/changelog.md` | `c063e238e16aac8d17fba2984431b13236e7d9da` | 2026-10-19 | Claude Code 2.1.303 |
| Codex | `~/github-repos-for-agents/codex/` | GitHub releases (`CHANGELOG.md` is only a pointer); use `git log` | `e4568a3538c9cab6627d64ff8cdfc7d98b79b7db` | 2026-10-19 | codex-cli 0.163.0 |
| Antigravity (agy) | `~/github-repos-for-agents/antigravity/` | `CHANGELOG.md` (repo root) | `86a5bdda81a063d707ac4ab87fb72f7dfe30ab67` | 2026-10-19 | agy 1.4.2 |
| Agent Skills standard | `~/github-repos-for-agents/agentskills/` | commits only | `69ef37e9424c0a7ea9dd2293b559e43ec8176379` | 2026-10-19 | — |

The **version reviewed** column is the CLI actually installed at review time, which is not always
what the checkout is at: the Codex checkout tracks `main` and runs ahead of the released binary
(0.150.0-alpha at the 2026-08-22 baseline), so a commit found in it may not be in the installed CLI
yet. Check with `codex --version` / `agy --version` / `claude --version` before acting on one.

The 2026-10-19 review read the whole agy changelog delta and every Claude Code "Changed" entry. It
filtered the Claude Code additions and fixes, and the Codex commit subjects, for the surfaces the
plugin touches. Agent Skills had only client-showcase commits. It filed issues 63-66 and added
comments to 21, 22, 23, 28, 43, 59, 60 and 61.

## Reviewing a delta

Pull each repository first, then list what is new since its baseline:

```sh
git -C ~/github-repos-for-agents/claude-code-docs diff <baseline>..HEAD -- docs/changelog.md
git -C ~/github-repos-for-agents/antigravity  diff <baseline>..HEAD -- CHANGELOG.md
git -C ~/github-repos-for-agents/codex        log --oneline <baseline>..HEAD
```

Codex has no usable changelog in the tree, so its delta is read from commit subjects — filter for the
surfaces the plugin touches (`codex exec` flags, config layering, sandbox, MCP, bundled models)
rather than reading all of them.

**Advance a baseline only after its delta has been triaged** — turned into issues under `issues/`, or
consciously dismissed. Advancing first loses the delta: nothing else records where the review stopped.
Note the CLI versions in the issues you file, the way `issues/20`, `issues/23`, `issues/27`,
`issues/28` and `issues/29` do, so a later reader can tell which measurement applies to which version.

## Previous baselines

- **2026-09-05** — Claude Code 2.1.261 (docs `a3eb21304ae88c30e94613db01016e5fa09fbeb9`), codex-cli
  0.153.4 (release tag `rust-v0.153.4`, `3d2ee51ca2d5db578f328aa75e20aa22c0197c9a`; the checkout
  commit used then was not recorded), agy 1.1.27 (`1ae9cb7b51667192c051b73a91099c71e816ca5f`).
  Reconstructed on 2026-10-19 from issues 59-62 and the comments that review added to 21, 22, 23,
  26, 27, 28, 40 and 43; that review did not advance this file.
- **2026-08-22** — Claude Code 2.1.239 (docs `4243e7a4778e44ad0e82d496afba336c51308ff8`), codex-cli
  0.149.0 (`343074d4207d572809bd8cea15f4be1d09d98e0b`), agy 1.1.18
  (`f09d6b583d0f902d3f0f63736af23d34f0a5ddbe`), Agent Skills
  `217be548739f21d6008915c29aefe320ea1a90af` (2026-08-04).
- **2026-08-16** — Claude Code 2.1.233 (docs `0d19eec42d4d10074506cae4bccccff8ec53290e`), codex-cli
  0.147.0 (`73abda8bfef6bd42eb11351be53980a027fd1feb`), agy 1.1.13
  (`fbf22703a9c4bda0758b5bace0ab3142746780a9`). Reconstructed on 2026-08-22 from issue sources, not
  recorded at the time. Produced issues 20-23, 25, 27-29, 41, 47.
