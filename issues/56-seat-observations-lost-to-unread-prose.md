# File deliberately-not-raised observations as findings, not prose

Priority: 56

Status: Pending

Source: post-hoc audit of run `panel-20260822-071254-fc74a565` (darktable commit review), 2026-08-22

Triage: ready-for-agent

## Problem

A seat's prose is read by nobody, and the prompt sends real observations into it.

Two independent facts combine into a loss:

1. **The contract asks for prose.** `scripts/seat_contract.py:250` — *"After the block, write 2-3
   sentences on overall quality and your confidence."*
2. **Nothing consumes it.** `parse_block` extracts only the fenced block (`scripts/parse_block:63-72`,
   via `extract_block`). The index, cards, verdict, and debate never touch anything outside the
   fence. The only `prose_*` consumer in the tree is `round`'s `prose_revisions`, which is the debate
   `claim`-field merge and unrelated. Post-fence text survives only in
   `/tmp/<id>/raw/round0.<seat>.txt`.

Worse, one prompt line **actively routes content there**: `prompts/blind_pass.tmpl:87-88`
(Grounding) — *"Express uncertainty in the prose summary, not in fields."* A seat that is uncertain
about a minor defect is told to write it where it will be discarded.

Three further lines push the same way:

- `prompts/blind_pass.tmpl:90-94` (Calibration) — *"Prefer one strong finding over several weak
  ones; do not dilute serious issues with filler"* and *"drop it unless it is … plausible under a
  real failure scenario"*.
- `prompts/blind_pass.tmpl:78-84` ("What a finding is (and is NOT)") — a paragraph whose whole
  thrust is *don't file*; the one clause blessing `low`/`style` for genuine minor defects is
  subordinate to it.
- `prompts/blind_pass.tmpl:74-76` (DEFENDER LENS) — *"before raising an issue, check whether … If
  so, do not raise it."*

There is also no worked example of a minor finding: the only example in the contract is
`severity: high, category: correctness` (`FINDING_EXAMPLE` in `scripts/seat_contract.py`).

## Verified evidence

Run `panel-20260822-071254-fc74a565`, scope `commit=ecce8af23893d5061`, workdir
`/workspace/darktable`. The Claude seat emitted an empty `findings` block and then wrote, in the
discarded prose (`/tmp/panel-20260822-071254-fc74a565/raw/round0.claude.txt`):

> Two residual observations I deliberately did not raise as findings.

Both were genuine minor defects, not confirmations:

1. **A behavioural regression introduced by the reviewed diff.** The new early return in
   `_gui_off_callback` also skips the callback tail, so the enable button's on/off tooltip is no
   longer refreshed for modules whose `hide_enable_button` is image-dependent
   (`highlights.c:1194`, `hotpixels.c:365`, `rawdenoise.c:510`, `cacorrect.c:1290`,
   `temperature.c:1167`). Textbook `low` / `correctness`.
2. **A latent trap the new doc comment does not warn about.** `darkroom.c:3254/3277/3345` rely on
   post-construction `set_active()` firing `.clicked_cb`; migrating them to the diff's new `.active`
   field — which the PR text invites — would silently leave the button lit with the feature off.
   `style` / `maintainability`.

The seat's own stated reason for withholding (1) matches the prompt exactly: *"I could not establish
that an insensitive button's tooltip is observable, so this stays below the bar."*

Observation (1) shares a root cause with the run's only recorded finding — Codex's
`src/develop/imageop.c:1219`, same early return, different consequence. Filed, it would have put two
independent seats on the same line of the diff in Round 0.

The verdict for that run (`/tmp/panel-20260822-071254-fc74a565.md`) records `Finding counts in
Round 0: Claude 0, Codex 1, Gemini 0` and an empty **Style notes** section. Neither observation
appears anywhere in it.

## Fix

Prompt-only; no code, no contract-cardinality change.

1. In `prompts/blind_pass.tmpl`, add a positive rule: anything the seat considered and **decided not
   to raise** is filed at `low`/`style` with the reason in the finding, never written in prose.
   Keep the existing anti-filler language — it is what stops a seat restating correct behaviour as a
   finding — and make the new rule the explicit exception to it.
2. Remove or requalify the Grounding line *"Express uncertainty in the prose summary, not in
   fields"*, which is the sentence that caused this. Uncertainty about *whether a defect matters*
   belongs in a `low`/`style` finding; only uncertainty about the **overall pass** belongs in prose.

## Considered and rejected

- **A third fenced `notes` block**, parsed into the verdict's (currently always-empty) **Style
  notes** section. Structurally the cleanest, but it is a contract change: block cardinality in
  `seat_contract.py`, `check_draft`, `parse_block`, `round`, the `SubagentStop` stub, and tests.
  Not justified by one observed instance; revisit if the prompt rule proves insufficient.
- **Carrying raw seat prose into the verdict verbatim.** Breaks blindness — prose is per-seat and
  self-referential ("I could not execute darktable") — and puts unvalidated free text into a durable
  artifact.
- **Softening the Calibration text.** Reintroduces exactly the filler that text exists to prevent.

## Residual limitation

Filing these as `low` would not have got them debated in this run: the Round-0 severity gate stops
the loop when only low-severity findings exist, so they would have appeared under **Minor — not
peer-reviewed**. Visible and durable, but not vetted. That is the gate working as designed
(`--debate-low` overrides it), not a further defect.
