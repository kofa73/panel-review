# Forbid seat writes into the repository under review, not just tracked files

Priority: 57

Status: Pending

Source: post-hoc audit of run `panel-20260822-071254-fc74a565` (darktable commit review), 2026-08-22

Triage: ready-for-agent

## Problem

The seat prompts' hard rule protects tracked files and the card cache and says nothing about
untracked build output, so a seat can rebuild the repository under review while fully complying with
it.

The rule, identical in both templates (`prompts/blind_pass.tmpl:33`, `prompts/debate.tmpl:38`):

```text
Hard rule: never modify, create, or delete any version-controlled (git-tracked)
file, or anything under the repository's .panel-review/ directory (the panel's own
card cache — read-only for you; write only under your scratch subdir above).
```

`repo_guard` matches that scope deliberately — tracked content only
(`scripts/repo_guard:9-11`) — so a full rebuild of a gitignored `build/` tree is invisible to it and
correctly reported as clean.

The cost that makes this worth fixing is **wasted seat budget**, not corruption. A seat that starts
a build blocks on it, and in the observed case spent the majority of its review on a build it never
used.

## Verified evidence

Run `panel-20260822-071254-fc74a565`, workdir `/workspace/darktable`. Sources: the agy trajectory
store `~/.gemini/antigravity-cli/conversations/b045cde2-326b-4999-a72d-da8c6c84183e.db` (steps 90-119)
and the Codex rollout `~/.codex/sessions/2026/08/22/rollout-2026-08-22T07-13-50-*.jsonl`.

**The Gemini seat built the tree.** Step 90 `ninja -C build` (exit 1, wrong generator), then step 96
`make -C build -j4` with `WaitMsBeforeAsync: 10000`. agy converted it to a background task
(`task-97`); the seat emitted the prose *"I have started the build task in the background and will
continue once it completes"*, called agy's `schedule` tool, and got back *"Wait cancelled (agent
already has undelivered messages from …/task-97)"*. The task result was delivered at **07:16:08Z**,
exit code 0.

So the seat did wait, and the build did succeed. The problem is what it cost:

| | |
|---|---|
| Gemini seat wall time | 07:13:49 → 07:16:43 = **2m54s** |
| of which waiting on the build | **1m48s** (62%) |
| what it did with the result | nothing — never ran the binary |
| its two follow-up compile attempts | both failed (`No rule to make target …imageop.c.o`; `make -C build/src`: `No such file or directory`) |

Its `findings` block was empty. Compare Codex at 6m50s (one finding) and Claude at ~16m.

**The writes were real and invisible to the panel.** Files modified under
`/workspace/darktable/build`, bucketed by seat window:

```text
07:12-07:14 : 0
07:14-07:17 : 714      <- Gemini's make
07:17-07:21 : 0        <- Codex's window
07:21-07:31 : 0        <- Claude's window
```

Including `build/bin/version_gen.c` (a regenerated source), `build/bin/libdarktable.so`,
`build/bin/darktable`, and every plugin `.so`. The verdict's Process notes say *"Guard: … clean, no
tracked file was modified by any seat"* — accurate, and silent about all 714.

**Codex shows the behaviour to preserve.** It derived a write-free compile check unprompted: read
`build/compile_commands.json`, replace the `-o <obj> -c <src>` span with `-fsyntax-only`, replay each
line. Verified write-free two ways — zero files touched in its window, and this compile database
carries no output-producing flags beyond `-o`/`-c` (checked: 0 occurrences of `-MD`/`-MF` across
both the Makefile-generated `build/` and the ninja-generated `cmake-build-debug/` databases, 656
entries). **That check produced the run's only finding.** Any fix must not block it.

Note that a seat cannot self-verify this: `build*/` is gitignored, so the
`git status --short --untracked-files=all` Codex ran after its check could not have seen build-tree
writes either way.

## Fix

Prompt-only; extend the existing hard rule in both templates.

1. Change the criterion to **"writes nothing into the repository under review"**, covering untracked
   and gitignored paths, not just tracked files and `.panel-review/`.
2. **Name the forbidden shape explicitly** — `make`, `ninja`, `cargo build`, `npm run build`,
   anything writing into a build or output directory. A model reading "prefer read-only checks" does
   not on its own exclude `make -C build -j4`; that is precisely what happened here.
3. State that **read-only checks are allowed and encouraged**, with output going to the seat's
   existing `/tmp/<ID>/work/<token>/` scratch.

The criterion has to be the *property* (writes nothing), not a command allow-list: check modes
differ across ecosystems — `gcc -fsyntax-only` and `tsc --noEmit` write nothing, `cargo check`
populates `target/`, `mypy` writes `.mypy_cache`.

## Considered and rejected

- **Per-seat git worktrees.** Would isolate builds, but a fresh worktree has no build tree (build
  dirs are untracked and `CMakeCache.txt` hardcodes absolute paths), so each seat pays a cold
  configure. It also collides with `--uncommitted` scope, with per-workdir `repo_guard`, and with the
  `<workdir>/.panel-review/<ID>/` marker that *is* the per-workdir run lock (`scripts/init_run:22`),
  and it would end the single frozen Round-0 prompt by giving each seat its own review root. Its one
  unique benefit — cross-seat read isolation — was already delivered by issue 24.
- **A panel-run build up front, failing the review early if it fails.** Requires build knowledge the
  panel does not have and cannot autodetect across ecosystems; validates the *working tree*, which
  need not match the reviewed scope (a `--commit <old SHA>` review would build unrelated bytes);
  makes panel-review the workspace's largest mutator; and adds the build to every run's critical
  path. Building before invoking a review stays the human's job.
- **An untracked-drift probe** (`touch` a stamp before dispatch, then
  `find <workdir> -newer <stamp> -print -quit` after the pass; measured at ~25 ms over 17,740
  entries). Rejected as premature: it detects nothing that has ever been observed to go wrong, it
  yields one boolean for the whole pass with no seat attribution and no concurrency information, and
  it reports only after the damage. Attribution already exists post-hoc in the CLI transcripts cited
  above. Revisit only if a seat is observed reconfiguring a build tree, which is the one silent
  expensive failure this class has.

## Residual limitation

This is a **convenience, not a control** — a seat can still write, and nothing detects it. That is
consistent with the trust model in `AGENTS.md` ("Design principles / trust model"): the guard targets
honest accidents and model confusion, which is exactly what happened here, and a guard that only
works when the seat cooperates must be labelled as such.

No corruption has ever been observed. Only one seat built, its build exited 0, and the windows did
not overlap (Gemini's build finished 07:16:08; Codex's syntax checks ran 07:17:47). The concurrency
hazard — two seats writing one build tree, which `make` does not lock — remains hypothetical; this
fix removes the writer, which is what would prevent it.
