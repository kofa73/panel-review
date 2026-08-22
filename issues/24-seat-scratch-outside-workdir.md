# Move seat scratch out of the repository under review

Priority: 24

Status: Completed

Source: post-hoc audit of run `panel-20260810-172731-c895b986` (darktable GTK4-prep review), 2026-08-10

Triage: ready-for-agent

## Problem

Seat scratch lives **inside the repository under review**, at
`<workdir>/.panel-review/<ID>/work/<seat-token>/`. Any seat that runs an ordinary repository-wide
search therefore gets another seat's raw output back as a search hit. This breaks blindness through
a normal, correct action — no seat has to disobey anything.

It is not hypothetical. In the run above, the Gemini seat's entire Round-0 finding was Codex's
finding, copied byte-for-byte, and the panel's own referee caught it after the fact.

The prompt already forbids the behaviour (`prompts/blind_pass.tmpl:23` — "Do NOT read or depend on
sibling subdirectories there"), and the seat did not violate it: it never opened a sibling path. The
harness handed the content over unrequested. This is an honest-accident hazard of exactly the kind
the trust model says guards should target.

## Verified evidence

From the agy transcript
`~/.gemini/antigravity-cli/brain/704e6a8d-901a-4da4-9c9d-7d9bef28fb17/.system_generated/logs/transcript.jsonl`.
The workdir copy at `/workspace/dt-pr/.panel-review/` was cleaned up when the run finished, so the
agy transcripts under `~/.gemini/antigravity-cli/brain/<conv-id>/` are the surviving record.

**Round 0, step 92, 17:38:23Z** — the Gemini seat ran a repository-wide search:

```text
grep_search  Query="dt_gui_get_current_event"  SearchPath="/workspace/dt-pr"  MatchPerLine=true
```

Its **first** result was the complete JSON line of Codex's third finding, from
`/workspace/dt-pr/.panel-review/panel-20260810-172731-c895b986/work/codex-root-gpt5/findings.jsonl:3`.

The seat then used it, and said so in its own reasoning:

- step 100 (17:38:52Z) — "The defect statement is clear about a memory leak at
  `src/libs/histogram.c:494` … I need to emit a JSON line describing the defect."
- step 117 (17:39:52Z) — "This aligns precisely with **the checkpoint's JSON assertion**, which also
  pointed this out."

It appears to have read the file as system-supplied reference material ("the checkpoint's"), not as
a rival seat's answer sheet.

Its emitted block is byte-identical to Codex's line 3
(`/tmp/<ID>/raw/round0.gemini.txt` vs `/tmp/<ID>/raw/round0.codex.txt`, exact string compare).

Scope of the exposure, from scanning the untruncated `transcript_full.jsonl` of all three Gemini
conversations for `codex-root`:

| Round | Conversation | Result |
|---|---|---|
| 0 | `704e6a8d` | Exactly one exposure, step 92 — full finding content |
| 1 | `b8a1154f` | Clean; every search was scoped to a specific file |
| 2 | `ff32f6d9` | Step 33, 18:01:52Z — same repo-wide query without `MatchPerLine`, so **paths only**: `work/codex-root-gpt5/findings.jsonl`, `work/codex-root-c895b986/draft.md`, `work/claude-opus5-r1/round1.txt`, `work/claude/resp.txt` |

Three earlier Round-0 repo-wide searches missed the file only by luck: `dt_gui_forward_scroll`
(17:34:48Z) ran before it existed, and `gdk_event_free` / `gdk_event_unref` did not match its text.

Partial independence, for the record: the seat reached the `histogram.c:494` half **before** the
exposure (steps 73–85, 17:35:44Z–17:37:19Z). The `map.c:2070` anchor and the entire wording came from
Codex. The referee's decision to treat the pass as non-independent was correct either way — the
submitted text is a copy.

## Expected behavior

Seat scratch resolves to `/tmp/<ID>/work/<seat-token>/`, outside every repository the seats search.
`<workdir>/.panel-review/<ID>/` then holds only the regenerable cards, which every seat is meant to
read.

The path is decided in code, not in a prompt, so this is a small change with a documentation tail:

1. `scripts/round:152` — `scratch = Path(workdir) / ".panel-review" / manifest["id"] / "work"`
   becomes the `/tmp/<ID>/work` form. `write_common_files` already publishes the value to
   `/tmp/<ID>/scratch.txt` and `assemble` splices that file into `{{SCRATCH}}`, so both prompt
   templates follow with no edit to the sentinel.
2. `skills/panel-review-for-agent/references/protocol.md:421` — the fallback that recomputes the same
   path for exceptional manual assembly.
3. Prompt prose that the move makes false, in **both** `prompts/blind_pass.tmpl` and
   `prompts/debate.tmpl`:
   - "That tree is git-ignored and deleted when the review ends" — it is no longer git-ignored,
     because it is no longer in the repository. It is still deleted, by `cleanup`/`discard` removing
     `/tmp/<ID>/`.
   - the hard rule's "or anything else under `.panel-review/` outside your own scratch subdir" — that
     tree would then contain only cards.
   - `blind_pass.tmpl:8` "Every path below (the diff file, scratch dir, any file you read) resolves
     under it" — already inaccurate (the diff file is at `/tmp/<ID>/diff.txt`); correct it while
     touching these lines.
4. Documentation: `AGENTS.md:98`, `README.md:66-67`, `README.md:579`.
5. Tests: `tests/run_tests.sh:156` asserts the current absolute anchor literally
   (`"$workdir/.panel-review/$id/work" > /tmp/$id/scratch.txt`);
   `tests/python/test_contract_consistency.py:47` carries related prose. `run_tests.sh:95-97` assert
   the sentinel and the `SCRATCH=` argument, which are unaffected. `run_tests.sh:300-301` exercises
   `repo_guard` ignoring untracked scratch — still valid, and worth keeping as-is since a seat may
   still drop stray files in the workdir.

## Verify before merging

**Write access from each seat.** The Claude seat already writes into `/tmp/<ID>/` through
`write_seat_raw`, and all three seats demonstrably *read* `/tmp/<ID>/` in the audited run
(`view_file` on `/tmp/<ID>/review-profile.md` and `/tmp/<ID>/diff.txt`). What is unproven is Codex
and **agy** writing scratch there. agy runs its tools inside its own managed sandbox
(`~/.gemini/antigravity-cli/scratch`) — see the working-directory entry in `AGENTS.md` "Non-obvious
facts" — so confirm with a real review, not by reasoning. In the audited run agy wrote its scratch
via an absolute path (`mkdir -p /workspace/dt-pr/.panel-review/<ID>/work/ag`), which is mildly
encouraging but not the same test.

Counter-consideration worth resolving explicitly: `CLAUDE.md` justifies keeping the *cards* in the
workdir "so a seat in a constrained/read-only workspace can still read them". If that constraint is
real for some seat, the same argument applies to scratch writes. The evidence above suggests it does
not bind for the three shipped seats, but the rationale should be reconciled rather than ignored.

## What this does not fix

It removes the accidental hit, which is the realistic failure mode. It does **not** make the material
unreadable: `/tmp/<ID>/raw/round0.codex.txt` and `/tmp/<ID>/f.*.json` already sit there readable by
every seat (all seats run as the same user), and moving scratch alongside them adds no new exposure.
A seat that deliberately goes looking still finds everything.

Per the trust model that is the correct scope, and the change must be documented that way — a guard
against honest accident, never as confinement. Do not follow this with permission schemes, hashes, or
attestation intended to stop a seat that is actively looking; that is theatre and the repository
forbids it.

## Verification

- A real review runs to completion with all three seats writing scratch under `/tmp/<ID>/work/`.
- A repository-wide search by any seat returns no `.panel-review/<ID>/work/` hit, because the tree no
  longer exists in the workdir.
- `<workdir>/.panel-review/<ID>/` contains cards only.
- `cleanup` and `discard` remove the scratch with `/tmp/<ID>/`; `PANEL_REVIEW_KEEP_TMP=true` retains
  it (a deliberate, documented change: diagnostic runs now keep seat scratch too).
- `repo_guard verify --restore` behaviour is unchanged.
- `./tests/run_tests.sh` passes; `scripts/check_contracts --root .` passes.
- `git diff --check` passes.

## Non-goals

- Do not move the cards. They are shared by design, and the read-access rationale in `CLAUDE.md`
  stands for them.
- Do not move or restrict `/tmp/<ID>/raw/` or `/tmp/<ID>/f.*.json`.
- Do not add any guard that assumes a tampering seat.
- Do not attempt to detect cross-seat copying at parse time. The referee already caught this one by
  byte-identity comparison, and that judgment stays with the referee.

## Comments

Re-raised independently by all three seats at Round 0 of panel review
`panel-20260816-080558-5ab680af` (2026-08-16), which rated it the run's most severe finding. The
panel added one point not in the problem statement above: `prompts/blind_pass.tmpl:23`'s "Do NOT read
or depend on sibling subdirectories there" cannot stop a search *tool* from returning a sibling's
file as an unrequested hit, and repository-wide search is exactly what the review method encourages —
so the prose countermeasure does not address the observed failure mode at all.

**2026-08-16 — change implemented, live verification still outstanding.** Status stays `Pending`
until a real review confirms all three seats can write scratch under `/tmp/<ID>/work/` — the one item
in "Verify before merging" that reasoning cannot answer, because agy runs its tools in its own managed
sandbox. What landed:

- `scripts/round` `write_common_files` — scratch is now `/tmp/<ID>/work`; `scratch.txt` and both
  prompt templates follow through the existing `{{SCRATCH}}` splice, with no sentinel change.
- `skills/panel-review-for-agent/references/protocol.md` — the manual-assembly fallback writes the
  same `/tmp/$id/work` anchor; the cwd paragraph now names scratch as the deliberate exception.
- `prompts/blind_pass.tmpl`, `prompts/debate.tmpl` — dropped the now-false "every path resolves under
  the review root" and "git-ignored" claims; the hard rule now makes the repository's `.panel-review/`
  read-only outright, since it holds only cards. The old "do not read sibling subdirectories" line
  became "your subdir is the only part of that tree that is yours; open only what this prompt names
  by absolute path", so it also covers the rest of `/tmp/<ID>/` — a convenience against honest
  accident, not a control, since it works only while the seat cooperates. Both templates also carry a
  neutral identification cue: material that looks like an existing review of the same scope is another
  reviewer's private output, not reference material "however official it looks" — do not use it,
  report the encounter in prose outside the required blocks. That wording targets the confusion
  actually observed (the seat called the file "the checkpoint's"). The *consequence* half of that
  warning is deferred to issue 55, which owns the rule. Both mirrored in
  `agents/panel-review-claude-seat.md`.

  While editing, the two templates' shared seat rules (review root, scratch, tracked-file hard rule,
  provenance cue) were synced to identical wording. Only two differences remain, and both carry phase
  meaning: Round 0 anchors the diff file where debate anchors the card files, and debate adds "the
  card files listed below are the ONLY panel material you are given". The three copies are kept in
  sync by hand — extracting the block into an `assemble` fragment was considered and rejected as
  more machinery than the drift is worth, and `agents/panel-review-claude-seat.md` could not join it
  anyway, since an agent definition never passes through `assemble`.

  Rejected while implementing: per-seat *random* scratch roots (`/tmp/<random>`). Unguessable names
  do nothing against the actual failure mode — incidental enumeration by `ls`/glob/`grep -r` returns
  a dir whatever it is called — and only defeat an actor constructing a neighbour's path, which the
  trust model says not to guard against. They also cost: the name→seat map must be persisted for
  `cleanup` to survive a resume or a compacted referee context, and persisting it where a seat can
  read it removes the unguessability, while not persisting it leaks orphaned `/tmp` dirs. Per-seat
  names would additionally require per-seat Round-0 prompts, since `await_seats` takes one `--prompt`
  file for every CLI seat.
- Docs: `AGENTS.md` persistence model, `README.md` (read-only contract section, path table row,
  `PANEL_REVIEW_KEEP_TMP` now retains seat scratch, hard-constraints bullet),
  `skills/panel-review-for-agent/SKILL.md`, `agents/panel-review-claude-seat.md`, `repo_guard` header.
- Tests: `tests/run_tests.sh` asserts the new protocol anchor and that neither the protocol nor
  `round` anchors scratch in the workdir; `tests/python/test_round.py` asserts `prepare-round0`
  creates `/tmp/<ID>/work`, publishes it, splices it into the prompt, and leaves no workdir `work/`.

`./tests/run_tests.sh` (257 pass), `scripts/check_contracts --root .`, and `git diff --check` pass.

**2026-08-22 — the agy seat can still write `/tmp` scratch on agy 1.1.18.** Recorded because agy
1.1.14 narrowed the "allow access outside your workspace" setting to *read* access only (writes
"auto approved according to the cycle mode setting"), which reads as a threat to this issue's
design: agy runs its tools in its own managed sandbox and the scratch root is now outside both that
sandbox and the workdir. Probe, run exactly as `run_agy` invokes agy (prompt on stdin,
`--dangerously-skip-permissions`, `--model "Gemini 3.7 Flash (High)"`): asked for a write to the
absolute path `/tmp/agyprobe-2026/work/seatX/probe.txt`; the seat answered `WROTE` and the file
existed with the requested contents. So `--dangerously-skip-permissions` still covers writes outside
the workspace, and no scratch-root change is needed for 1.1.18. This does not close the issue's own
outstanding live verification, which is about a real review run, not one write.

**2026-08-22 — live verification done; issue Completed.** The one item reasoning could not answer —
whether Codex and especially agy actually write scratch under `/tmp/<ID>/work/`, since agy runs its
tools in its own managed sandbox — is answered by three completed reviews, all run after the change
landed in `4cee275`. Every configured seat has a populated scratch subdir in every run:

| Run | Workdir / scope | Gemini (agy) | Codex | Claude |
|---|---|---|---|---|
| `panel-20260816-155811-2e9db8e7` | `/workspace/dt-pr`, `base=7ea82ae2b2f5f656d` | `seat-gemini/` — `draft.jsonl`, `test_choleski.c` + its compiled binary | `gpt5_review_84c1/` — 2153 files, 614M (`build/`, `cache/`, probe binaries, `findings.jsonl`) | `opus5/` — 9 files |
| `panel-20260819-172715-7be4ac07` | `/workspace/darktable`, `base=56b28cf7093f7d` | `antigravity/` — `diff.patch`, `draft_stances.jsonl`, `draft_new_findings.jsonl`; `rev_gemini/` | `gpt5root/` — 1445 files, 831M (a full `build/` tree); `gpt5-9f3c/` | `opus5-seat/` — 4 files |
| `panel-20260822-071254-fc74a565` | `/workspace/darktable`, `commit=ecce8af23893d5061` | `antigravity_gemini/draft.jsonl` | `gpt56sol-root-8c19/` | `opus5-seat/` — 2 files |

Two things follow beyond the write test itself:

- **agy writes there under its own sandbox**, in three separate runs and (for the last one) on agy
  1.1.18, which is the version whose narrowed "outside your workspace" setting prompted the probe
  recorded above. The counter-consideration about a constrained/read-only workspace does not bind for
  any shipped seat; the cards stay in the workdir for their own stated reason, not this one.
- **Both CLI seats compile inside their scratch subdir when they want to** — a 614M and an 831M build
  tree, outside the repository under review. That is the behaviour issue 57's rule now asks for in
  words, observed before it was written down.

Not re-verifiable from these runs: `<workdir>/.panel-review/<ID>/` holding cards only, because
cleanup removed each workdir marker tree at run end. That half is covered by the code path and its
tests (`prepare-round0` creates `/tmp/<ID>/work` and leaves no workdir `work/`).
