# Design note — blind-pass robustness (diff externalization, seat orientation, repair, schema single-sourcing)

Status: proposal (not yet implemented) — revised after a Codex design review (see §6)
Date: 2026-07-07
Trigger run: `/tmp/panel-20260705-160154-c0aff340` (gemini emitted prose, was ejected)

## 1. Motivation

In the trigger run the Gemini (agy) seat produced a full prose review — including a
genuine bug — but **no `findings` fenced block**, so `parse_block` returned exit 4
("no block") and the seat was dropped from Round 0 and every later round. The review
lost a whole participant, and the one real defect Gemini found was nearly lost with it.

Investigation (run artifacts + the three CLIs' own logs under `~/.claude`, `~/.codex`,
`~/.gemini`) identified **four independent contributing faults**, plus one maintenance
weakness. Evidence, briefly:

- **Prompt size correlates with Gemini failure (empirical, not code-proven).** Across
  recorded runs, every `round0.prompt` larger than ~99 KB (240 KB, 105 KB, 100 KB)
  yielded prose-not-fence from Gemini; every prompt ≤ 87 KB yielded a valid fence. The
  trigger prompt was 240 KB / 3952 lines, ~3850 of them the inline diff, with the
  output-format contract buried at the very end (lines 3909–3952). This is a strong
  correlation and a plausible mechanism (attention dilution + buried contract), **not**
  a proof that size alone caused the prose response.
- **The inline diff is not the *only* thing making seats share scope.** In the same
  240 KB run the Codex seat was unaffected: it re-derived the diff itself via
  `tilth_diff {"source":"e852fb85d6d58..HEAD"}`, read ~40 sections of the live tree,
  validated with `check_draft`, and emitted a valid block. So Codex tolerates (and
  partly bypasses) the inline copy. **Caveat (from the review):** today the protocol and
  README explicitly make the **resolved diff bytes the authoritative shared review
  material** — so "inline diff is dead weight" is too strong. Externalizing it keeps
  those bytes canonical; it just stops *inlining* them into the prompt.
- **Seat orientation is guesswork — for one seat.** Two of the three seats already run
  from the repo root: the Claude seat is a referee subagent that inherits cwd = workdir
  (`SKILL.md:97,273`), and the Codex seat inherits the shell cwd through `run_codex`
  (trigger-run logs show it oriented to `/workspace/ansel`). **agy is the outlier:** it
  does not execute tools in the process cwd at all — it runs them in its own managed
  sandbox (`~/.gemini/antigravity-cli/scratch`) and *guesses* the repo root each run, so
  `cd`-ing the wrapper cannot move it. Sampled successful runs guessed `/workspace/...`;
  the trigger run anchored to `/home/developer` and never reached `/workspace/ansel`,
  because the prompt gives **no absolute anchor** to the repo (scratch `{{SCRATCH}}` is
  relative `.panel-review/<ID>/work`, and debate `CARDS` paths are relative too).
  Certainty: the Claude/Codex cwd is structural; agy's scratch-cwd behavior is empirical
  (from the run logs), not proven from agy source.
- **The repair retry doesn't cover the no-fence case.** `run_seat` fires its one-shot,
  shape-only repair **only on parse exit 5** (malformed fence, `scripts/run_seat:82`).
  A no-fence prose answer is exit 4 (`scripts/parse_block:149`) and is treated as a
  down/refusing seat — even when it contains a complete, salvageable review.
- **(Maintenance) the emit schema is duplicated** across `blind_pass.tmpl`,
  `debate.tmpl`, and the SKILL, is enforced separately in `parse_block`, and is
  *restated in prose but not given exactly* in `repair.tmpl`. These can drift.

## 2. Scope of change / non-goals

In scope: reduce the prompt to a size Gemini handles reliably, make seat orientation
deterministic across all rounds, move the output contract to a salient position,
salvage review-complete-but-misformatted **Round-0** output cheaply, and single-source
the emit schema.

Non-goals:

- **Do not remove the provided diff** ("just run git yourself"). It stays the canonical
  scope; we change delivery (file reference) not authority. In particular the
  `--uncommitted` diff from `resolve_diff` includes untracked-file contents and excludes
  `.panel-review/`, so a plain `git diff` / `tilth_diff` does **not** reproduce it — the
  external file must be named the canonical bytes, and any "run tilth_diff" wording is
  *optional navigation only*, never an equivalent source.
- **Do not change what a stance/finding *means* or how consensus counts them.** Concern F
  does change the debate block *contract* (`new_findings` becomes required-emptyable) to
  remove an ambiguity, but stances, folding, and lifecycle math are untouched. Until F
  lands, the no-fence repair stays Round-0 `findings`-only (Concern D hazard 1).
- **Do not change** consensus/lifecycle logic, blindness rules, `repo_guard`, or the
  `assemble` whole-line-literal substitution contract.

**Trust model (governs every "guard" below).** Seats run **unconstrained** by design
(`run_codex` bypasses the sandbox, `run_agy` uses `--dangerously-skip-permissions`); the
system's safety rests on a **disposable container**, and `repo_guard` reverts only
*honest* tracked-file drift. A seat could, in principle, read or rewrite the prompts,
scripts, another seat's raw output, the diff, or any hash meant to check them. We therefore
**do not build guards against a tampering seat** — any such guard is defeatable by the same
actor and is pure theater. Guards in this note target **honest accidents and model
confusion** (dilution, disorientation, misformatting, a truncated read, the harness
clobbering its own files), nothing else. When a proposed guard only "works" if the seat
cooperates, it must be labelled a convenience, not a control.

## 3. Planned implementation, per concern

### Concern A — prompt-size dilution: externalize the diff

**Change.** Stop splicing the diff body into the prompt. Reference it by **absolute
path** and let the seat page through it (or re-derive via `tilth_diff` as navigation).

- Storage. `resolve_diff` already writes `/tmp/$id/diff.txt` (SKILL Round 0 step 2). Keep
  that `/tmp` copy as the canonical source and reference its absolute path in the prompt.
  Prefer it over a workdir mirror (`.panel-review/<ID>/` is untracked, and one file shared
  by three seats is needless coupling); only add a workdir mirror if a constrained seat
  genuinely cannot read `/tmp`. **No integrity machinery** — see the trust-model note in
  §2: we do not defend the diff file against a tampering seat, because such a seat could
  defeat any guard we add. `chmod 0444` is acceptable only as trivial accident-hygiene (a
  stray scratch write fails loudly), never as a security control.
- `blind_pass.tmpl`: replace the `{{DIFF}}` body-splice with a `## Files / Diff`
  section that states the scope, the **absolute diff path**, its **size + sha256** (so
  the seat can confirm it read the whole thing and doesn't wander the filesystem), the
  note that these are the **canonical** bytes, and an instruction to read that file
  (`tilth_diff` optional for the structural view). The `{{DIFF}}` sentinel is removed.
- Delivery through `assemble` (revised). Do **not** invent `DIFFPATH=`/`DIFFMETA=` as
  separate inline variables. `assemble` maps a whole-line `{{KEY}}` sentinel to one
  file's bytes. So generate one small `/tmp/$id/diff_info.txt` (path + size + hash +
  canonicality wording) and splice it via a single sentinel, e.g. `{{DIFFINFO}}`. The
  SKILL `assemble` call (~line 280) drops `DIFF=` and gains `DIFFINFO=/tmp/$id/diff_info.txt`.
- Scope-mode conditionality: include a `base..HEAD` **range** in the prompt only for
  `--base` / `--commit` (for `--uncommitted` there is no range; for a free-form question
  there is no diff at all, and `assemble` already accepts `/dev/null`). The diff *file*
  is the universal artifact whenever a diff exists.

**Effect.** Round-0 prompt drops from ~240 KB to a few KB while the diff bytes stay
canonical. Also apply the same externalization to the **debate** prompt if its card bulk
is large (see Concern B / §4).

**One honest tradeoff (not a guard).** Inlining puts the diff bytes in context
unconditionally; a *reference* asks the model to open the file. A cooperative-but-lazy
model might answer without reading it. This is a quality question, not a security one, and
the answer is behavioral, not mechanical: instruct clearly ("read this file"), and lean on
the fact that seats already read the tree for context anyway (Codex read ~40 sections in
the trigger run; the whole premise of externalization is that they re-derive/read rather
than consume inline bytes). The size+hash in the prompt is a **convenience** so a
cooperative seat can notice a *truncated* read — not proof it read. No attestation scheme;
if a seat won't read a clearly-referenced file, that is a model-quality issue to observe in
a real run, not something to police with harness plumbing.

### Concern B — seat orientation: absolute anchors (all rounds)

**Change.** Give every seat an absolute anchor in **every** round so no seat guesses the
repo root.

- Round 0: write the scratch sentinel as **`<workdir>/.panel-review/<ID>/work`**
  (absolute), not the relative `.panel-review/<ID>/work` — this is the exact source of
  the trigger run's `/home/developer/.panel-review/...` misplacement.
- Debate: the debate prompt currently passes `CARDS` as relative
  `.panel-review/<id>/issue-*.md`, so the same agy cwd drift can recur outside Round 0.
  Resolve card paths (and the debate scratch path) to **absolute** as well.
- State the absolute workdir once near the top of each template as the review root, **and
  add an explicit tool-invocation directive for agy**: *"when running any repository
  command/tool, set its `cwd` (working-directory) parameter to `<workdir>`."* An absolute
  path in prose only guarantees agy *reads/writes* the right files; it does not guarantee
  agy passes that path as the `cwd` argument when it invokes a tool (e.g. `tilth_diff`),
  which it may otherwise run from its own scratch. This is **agy-specific hardening**: the
  Claude and Codex seats already run from the repo root (see §1), and agy's own tool cwd
  cannot be moved by the wrapper, so the prompt is the only lever we have. Zero cost to
  the other two.

**Effect.** Orientation is deterministic regardless of prompt size, in Round 0 and
debate alike.

### Concern C — instruction ordering: hoist the output contract

**Change.** In `blind_pass.tmpl`, move `## Output format (STRICT JSON …)` and
`## Validate before you emit` (`check_draft`) **above** `## Files / Diff`. Cheap once
the diff is no longer 3800 lines in the middle; keeps the contract salient at the point
it matters. (Do the same in `debate.tmpl` relative to the cards.)

### Concern D — repair the no-fence case (exit 4), Round-0 `findings` only, reformat-only

**Change.** Extend `run_seat`'s repair so an exit-4 (no fence) output that is a **required
block** and is a completed review is routed through the **existing** `repair.tmpl` —
which is already strictly shape-only ("do NOT re-review, do NOT add or remove items, do
NOT change any conclusion or severity"). The seat **does not re-run analysis**; it is
handed back its own prose and asked only to wrap it in the schema.

The set of "required blocks" widens once **Concern F** makes `new_findings`
required-emptyable, but F alone is **not** sufficient to repair debate safely — the
shared-raw overwrite (hazard 1) must be solved first. **If neither F nor the overwrite
fix is in place, the repair must be gated to `findings` only** (see hazard 1). Sequencing:
Round-0 `findings`-only repair is safe today; extending it to debate needs F **and** the
overwrite fix.

Four hazards the review surfaced, each addressed:

1. **Debate repair destroys the shared raw (confirmed, `run_seat:92-93`).** In debate,
   `stances` and `new_findings` are emitted by **one** model call into **one** raw file;
   `sweep ingest-batch` re-reads that same raw for stances (`SKILL.md:478-481`,
   `scripts/sweep:222`). But `run_seat`'s repair re-dispatches the model and does
   `"$cli" < "$prompt" > "$raw"` — it **overwrites the raw**. So repairing a missing/
   malformed `new_findings` clobbers the already-valid `stances` block before `sweep`
   reads it. **Concern F does NOT fix this** — F only makes "block absent" unambiguous
   (removing the *is it down or just silent?* guess); the *destructiveness* remains. A
   safe debate repair requires one of: (a) `repair.tmpl` demands the model re-emit **all**
   required blocks (`stances` **and** `new_findings`) so the overwrite is loss-free — but
   this re-touches a stances block that was already valid, a shape-only risk; (b) preserve
   the valid blocks out of the raw **before** the repair dispatch and splice the repaired
   block back (or write repair output to a side file and merge), so the canonical raw is
   never overwritten wholesale; or (c) keep the no-fence repair **Round-0 `findings`-only**
   and never repair a debate block. Until (a)/(b) is designed and implemented, **gate the
   no-fence repair to the required `findings` tag** (option c), never
   `new_findings`/`stances`.
2. **The diagnostic must reach the repair prompt.** `run_seat` builds `{{VIOLATIONS}}`
   from `parse_block --diagnose` **stdout**, but the exit-4 "no block" message currently
   goes to **stderr** (discarded) — verified: exit 4 → zero stdout bytes. So either add
   an exit-4 reason to `--diagnose` **stdout**, or have `run_seat` synthesize the
   repair reason itself: *"you produced a prose review with no `findings` fence; wrap
   your findings in the block below."*
3. **Don't ask an errored/timed-out seat to produce findings.** `run_agy` can relay
   non-empty timeout/error text after both attempts fail, and `run_seat` currently ignores
   the CLI rc before parsing. Simple gate: repair only when (a) the wrapper exited **0**
   (`run_seat` must capture and honor the seat rc — `run_agy`/`run_codex` already signal
   failure non-zero) **and** (b) the output does not end with a known wrapper-failure tail
   (reuse `run_agy`'s anchored `agy_ended_with_timeout` match). That's enough to separate
   "a real prose review" from "a timeout/refusal stub"; no elaborate substance-scoring.
   One negative test per known failure tail (agy timeout line, empty output) asserting
   no-repair. Scope: skipping repair only marks the seat down **for this pass** (exactly
   as an unrepaired failure does today); engagement is recomputed every round, so the seat
   is re-dispatched fresh next round regardless (`SKILL.md:537`) — this is not exclusion,
   it just avoids spending a repair call to turn an error stub into fake findings.
4. **Repair must not induce hallucination — nor over-suppress.** Even past hazard 3's
   gate, handing a seat "you must emit the schema" while its prose contains no findings is
   precisely the pressure that makes a model **confabulate** items to fill the block. But
   the naive fix ("emit `[]` if you found no issues") over-corrects: a lazy model handed
   unstructured prose may take the easy path and emit `[]` rather than extracting the
   findings its prose actually contains. So the wording must **prioritize extraction**,
   with empty as the strict fallback: *"Extract into the JSON block the issues you already
   stated in your prose. Emit an empty array if and only if your prose contained zero
   issues. Do not invent new findings."* Defenses combined: (a) hazard 3 keeps error/
   timeout non-reviews out of repair entirely; (b) this extract-first-else-empty wording
   replaces `repair.tmpl`'s current bare "do NOT add items," removing both the fabricate
   pressure and the lazy-empty escape. Compounds with Concern F, which normalizes `[]` as
   the correct answer for a genuine "nothing."

**Effect.** A review-complete-but-misformatted seat is salvaged with one cheap reformat
instead of silent ejection — the exact loss seen in the trigger run — without corrupting
the debate raw file and without pressuring a down seat to fabricate.

### Concern E (bonus) — single-source the emit schema, inlined

**Decision.** Author each tag's schema **once** and **inline** it into every prompt via
`assemble`; do **not** make agents read a schema file (it is ~1–2 lines, so inlining
costs almost nothing and keeps it high-salience at emission; a file-read reintroduces
the read-the-file/orientation failure class we are removing elsewhere).

- Add canonical fragments, e.g. `prompts/schema/findings.txt`, `prompts/schema/stances.txt`.
- Inject via new `assemble` sentinels `{{SCHEMA_FINDINGS}}` / `{{SCHEMA_STANCES}}` into
  `blind_pass.tmpl`, `debate.tmpl`, **and** `repair.tmpl` (the last gains the exact
  schema it currently only paraphrases, improving reformat reliability).
- Keep `parse_block` as the enforcement authority. Drift guard (revised): `parse_block`
  accepts `findings` and `new_findings` through one validator, tolerates whole-block
  JSON arrays/streams, normalizes `points`, strips invalid optional stance fields, and
  does **not** require every prompt-shown field. So the test must assert **parser
  behavior** — feed the canonical fragment's example line(s) through `parse_block` and
  assert they validate, and feed a deliberately field-shuffled variant to assert the
  documented normalization — **not** literal field-set string equality.

### Concern F — make debate `new_findings` required-emptyable

**Change.** Today the debate seat emits a required `stances` block and an **optional**
`new_findings` block; a legitimately-absent `new_findings` is exit 4 with non-empty raw.
That ambiguity ("no fence" = maybe malformed, maybe just nothing to add) is the sole
reason Concern D hazard 1 needs a carve-out. Make `new_findings` **required but
emptyable** — the seat always emits the block, `[]` when it has nothing new.

- `debate.tmpl` + `check_draft` (as `{{CHECK}}`): instruct "always emit a `new_findings`
  block; use `[]` if you are proposing no new issues."
- `parse_block` / `sweep`: accept an empty `new_findings` as valid (infrastructure
  already supports it — `extract_block --present` distinguishes empty from missing, per
  `.claude/rules/scripts.md`). An empty array yields zero new findings, same as today's
  absent block.
- Raw-file flow unchanged: the `new_findings` parse and the `sweep ingest-batch` stances
  re-read still share one raw file (`SKILL.md:478-481`) — this splits the output into two
  required *blocks*, **not** two files (two files would break the shared-raw flow for no
  gain).

**Effect.** "Block absent" becomes unambiguously malformed, and normalizing `[]` as the
correct "nothing" answer reinforces the anti-hallucination defense (Concern D hazard 4).
**Scope limit (agy review):** F removes only the *ambiguity* — it does **not** by itself
make debate repair safe, because `run_seat` still overwrites the shared raw and would
destroy the valid `stances` block (Concern D hazard 1). Generalizing D's no-fence repair
to debate needs F **and** the hazard-1 overwrite fix (re-emit-all-blocks, or
preserve-and-splice). Without both, keep D `findings`-only.

## 4. Files touched (summary)

- `prompts/blind_pass.tmpl` — drop `{{DIFF}}`; add `{{DIFFINFO}}` reference; hoist
  output-format + `check_draft` above the diff; inject `{{SCHEMA_FINDINGS}}`; absolute
  scratch/workdir.
- `prompts/debate.tmpl` — absolute `CARDS`/scratch; hoist output contract; inject
  `{{SCHEMA_STANCES}}` (+ `new_findings` if distinct); make `new_findings` required with
  "`[]` if none" wording (Concern F); externalize card bulk if large.
- `prompts/repair.tmpl` — inject the exact schema sentinel; exit-4 wording; extract-first-
  else-empty wording (Concern D hazard 4); for debate, demand re-emission of **all**
  required blocks if option (a) is taken (Concern D hazard 1).
- `scripts/check_draft` — "always emit `new_findings`, `[]` if none" (Concern F).
- `scripts/run_seat` — (debate generalization only) preserve valid blocks before the
  repair overwrite, or re-emit all required blocks — the hazard-1 overwrite fix. Not
  needed for Round-0 `findings`-only repair.
- `prompts/schema/{findings,stances}.txt` — new canonical fragments.
- `scripts/run_seat` — no-fence repair gated to required `findings` + the concrete
  completed-review predicate (seat rc==0 **and** no known wrapper-failure tail **and**
  minimum-substance, Concern D hazard 3); capture/honor the CLI seat rc; synthesize/relay
  the exit-4 repair reason into `{{VIOLATIONS}}`.
- `scripts/parse_block` — exit-4 `--diagnose` reason on **stdout** (if chosen over
  run_seat-side synthesis); accept an empty `new_findings` block as valid (Concern F).
- `scripts/sweep` — accept an empty `new_findings` batch (Concern F).
- `skills/panel-review-for-agent/SKILL.md` — keep `/tmp/$id/diff.txt` canonical; build
  `/tmp/$id/diff_info.txt` (path + size + hash for the seat's convenience self-check);
  resolve absolute workdir/scratch/card paths (Round 0 **and** debate); update `assemble`
  args (drop `DIFF=`, add `DIFFINFO=`, `SCHEMA_*=`); emit the range only when the scope
  carries one.
- `tests/run_tests.sh` (+ Python suite) — parser-behavior schema drift check; new
  template-sentinel assertions; a `run_seat` exit-4 Round-0 repair case **and** negative
  cases proving a known wrapper-failure tail (agy timeout line, empty output) is **not**
  repaired; assertion the diff body is no longer inlined.
- `README.md` — keep authoritative spec in sync (prompt carries a diff *reference*, not
  the body; diff bytes stay canonical; seats read an absolute diff path).

## 5. Risks / open questions

- **Does a cooperative seat reliably open a referenced file?** The one honest cost of
  externalization (see Concern A) — a quality/behavior question, not a guard to build.
  Observe it in a real run; the size+hash is a convenience self-check, not a control.
- **Constrained-seat `/tmp` access.** Confirm whether any seat genuinely cannot read
  `/tmp`; only then add per-seat read-only copies. Otherwise the single `/tmp` file stands.
- **tilth_diff vs the snapshot.** A seat navigating via `tilth_diff` on a dirty/stale
  tree could see something other than the pinned snapshot; `repo_guard` (snapshot +
  auto-revert + drift flag) governs this, unchanged — and the diff file, not tilth_diff,
  is canonical.
- **Root-cause certainty.** The size→failure link is empirical; keep the Concern-D
  repair net regardless, since it salvages the failure mode whatever its cause.
- **Ordering.** A removes the **240 KB root cause**; D only salvages the *no-fence
  symptom* — if the large prompt makes the seat time out or truncate, D cannot help. So A
  ships **with or before** relying on D as the main mitigation. Counter-weight: B, C are
  genuinely cheap and independently valuable; the Round-0 `findings`-only repair is safe
  today and worth landing early as a cheap net. Sequence: **B + C** (orientation/ordering),
  then **A** (kill the size root cause), then **D `findings`-only** (salvage net on the
  smaller prompt), then **F + hazard-1 overwrite fix + generalize D to debate** as one unit
  (never split — the overwrite is a real harness bug), then **E** (schema single-sourcing).
  Verify each with `tests/run_tests.sh` and a real review.

## 6. Review history

Codex design review (via `scripts/run_codex`, 2026-07-07) — verdict *needs-attention*.
Folded in: D re-scoped to required-`findings` only with the stderr/rc plumbing fixed
(its most serious finding — the naive version corrupted debate stances); B extended to
debate card paths; A storage decision changed to canonical read-only `/tmp` (no shared
mutable workdir file) with the `assemble` delivery via a single `{{DIFFINFO}}` file;
`--uncommitted` non-reproducibility called out; E drift test changed to parser-behavior;
and the "inline diff is dead weight / same-bytes illusion" framing tempered (resolved
diff bytes remain the authoritative shared material today).

Follow-up review (user, 2026-07-08) — three points folded in: (1) B reworded to state
that only agy lacks repo-root cwd (Claude/Codex already inherit it; agy's tool sandbox
cwd cannot be moved by the wrapper), with the certainty caveat; (2) Concern D hazard 4
added — repair must name empty-as-valid so a down/empty seat is not pressured to
hallucinate findings; (3) new **Concern F** — make debate `new_findings`
required-emptyable.

agy (Gemini) design review (via `scripts/run_agy`, 2026-07-08) — verdict *needs-attention*.
Corrections folded in: (1) **the important one** — F does **not** make debate repair safe;
`run_seat:92-93` overwrites the shared raw, so repairing `new_findings` destroys the valid
`stances` block (confirmed against the code). D hazard 1 rewritten from "F dissolves this"
to "F disambiguates but the overwrite remains; needs re-emit-all or preserve-and-splice";
ordering updated so F + the overwrite fix + debate generalization ship as one unit.
(2) hazard 4 wording changed to extract-first-else-empty (a bare "emit `[]`" invites a lazy
model to drop real findings). (3) B gains an explicit tool-`cwd` directive for agy (an
absolute path in prose does not guarantee agy sets the tool's `cwd` argument). Confirmed
sound with no change: Concern A storage model, Concern C, Concern E parser-behavior test.

Codex `review` design review (via `codex review`, gpt-5.5, 2026-07-08) — verdict
*needs-attention*; independently **confirmed** the debate-repair overwrite hazard
(`run_seat:91-94` + shared raw). Two of its points survived; two were rejected on the
trust-model grounds below. **Kept:** (1) Concern D's repair gate made concrete (rc==0 + no
wrapper-failure tail) with a negative test — accident-domain, real. (2) Ordering revised —
A (kill the 240 KB root cause) moves ahead of relying on D, since D only salvages the
no-fence symptom, not timeout/truncation.

Trust-model correction (user, 2026-07-08) — **reverted an over-defensive drift** in the
two prior reviews. Codex proposed enforcing diff read-integrity (`chmod 0444` + per-pass
hash-verify) and a read-attestation against "silent non-reading." Both assume a
*tampering* seat, which the system explicitly does not defend against: seats run
unsandboxed, and any seat that would corrupt the diff could equally rewrite the recorded
hash, `parse_block`, or another seat's raw output. Those guards are theater. Removed them;
added the **Trust model** note in §2 (guards target honest accidents/confusion only); the
diff stays a plain `/tmp` file (optional `chmod 0444` as accident-hygiene, not a control);
the size+hash in the prompt is relabelled a cooperative self-check, not integrity. The
"silent non-reading" concern is kept only as a one-line behavioral risk, not plumbing.
Two independent reviewers (agy, Codex) flagged the same shared-raw debate-corruption
hazard — that (a real harness bug, not a trust issue) needs the most care in implementation.
