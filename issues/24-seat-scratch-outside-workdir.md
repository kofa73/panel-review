# Move seat scratch out of the repository under review

Priority: 24

Status: Pending

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
