# Support external review profiles

Priority: 16

Status: Completed

Source: design discussion, 2026-07-20

Triage: ready-for-agent

## Decision

Add a generic `--review-profile <path>` extension seam to panel-review. A review profile supplies
project-specific review methods, invariants, high-risk cases, execution variants, false-positive
filters, and severity guidance without changing the panel's orchestration or consensus protocol.

The panel must not contain a built-in darktable mode or registry entry. Darktable's profile remains
owned by the external `darktable-review` skill, under `references/review-profile.md`; that skill's
`SKILL.md` also reads the same reference for standalone reviews. Panel-review accepts the file
through the generic interface and distributes one persisted snapshot to every seat.

This is executable prompt and persistence work, so it belongs after the current release-blocking
orchestration defect and before optional cost/model experiments.

## Problem

Panel-review currently provides one generic critic/defender method plus non-authoritative author
instructions. The author-instructions seam is suitable for intent and temporary focus, but not for
a reusable domain review method:

- author guidance cannot replace irrelevant portions of the generic high-risk checklist;
- asking each seat to activate a locally installed skill depends on three different skill runtimes;
- the complete standalone skill may redefine scope discovery, tools, output, or verdict format that
  the panel already owns; and
- separately installed Claude, Codex, and Gemini skill copies can drift, breaking the requirement
  that all seats receive the same blind review material.

Embedding darktable knowledge in panel-review would solve the immediate discovery problem by making
the general-purpose plugin a darktable specialist. The desired seam is instead an opaque,
project-neutral profile supplied explicitly by the caller.

## Interface

`panel-review:start` accepts an optional profile file with a diff or question scope:

```text
panel-review:start --base main \
  --review-profile ~/.agents/skills/darktable-review/references/review-profile.md
```

`--review-profile` and `--instructions` are independent:

- the profile describes how to review this class of code;
- instructions describe the author's intent or desired emphasis; and
- because `--instructions` consumes all remaining arguments, it must remain last when both are used.

The initial interface accepts a file path, not a registered profile name. Named project profiles or
repository auto-detection would couple the plugin to external projects and are out of scope.

## Ownership and precedence

Panel-review continues to own:

- seat identity, blindness, and role separation;
- review scope and canonical diff/card material;
- read-only and scratch-write rules;
- required output blocks and validation;
- issue identity, stance values, debate transitions, and unanimity-or-human; and
- durable state and verdict delivery.

The selected profile may own only:

- domain documentation and invariants;
- investigation priorities and execution matrices;
- project-specific high-risk cases;
- false-positive elimination; and
- domain-specific impact and severity guidance consistent with the panel's finding schema.

The profile cannot redefine the panel's output, roles, scope, mutation rules, finding lifecycle, or
consensus semantics. Author guidance remains non-authoritative focus and cannot override either the
panel contract or the selected review method.

## Persistence and prompt assembly

At run creation:

1. Resolve and validate the profile path before creating the per-workdir marker.
2. Copy the exact bytes into `/tmp/<ID>/review-profile.md` using the repository's atomic-write path.
3. Record stable profile metadata in the manifest, including a display name and content hash. Do not
   make the source path necessary for resume or continuation.
4. Use the saved snapshot for Round 0 and every debate round so installed-profile edits cannot alter
   an active run.
5. Record the applied profile name and hash in status/result metadata and the verdict artifact. Do
   not embed the full profile in the verdict.

The resolved absolute source path is the profile's display name and provenance. The source must be
a readable regular, non-empty UTF-8 file no larger than 64 KiB. Its SHA-256 is computed over the
exact bytes copied into the run.

Every configured seat must receive the same profile bytes. Prefer a salient absolute reference to
the saved file, with its size and hash, over repeatedly inlining a large profile into every prompt.
The hash is an audit and accidental-drift convenience under the existing trust model, not a control
against a malicious seat.

## Prompt structure

Separate the current generic high-cost bug catalogue from the invariant panel instructions:

- retain the common critic lens, defender lens, grounding, finding bar, and calibration in the panel
  prompt;
- make the current generic priority catalogue the built-in default review profile; and
- replace that catalogue with a supplied external profile rather than merely appending both.

An external profile therefore changes investigation priorities without duplicating or weakening the
panel protocol. Debate prompts must retain the selected profile so seats adjudicate cards against
the same domain invariants used in the blind pass.

## Darktable adapter outside this repository

The `darktable-review` skill should extract its reusable review method and high-risk cases into:

```text
darktable-review/references/review-profile.md
```

Its `SKILL.md` remains the standalone adapter: it owns scope discovery, tool use, read-only behavior,
and standalone output, and explicitly reads the shared reference. Panel-review is the second adapter:
it consumes only the reference through `--review-profile` and retains its own output/debate contract.

The profile belongs under `references/`, rather than `assets/`, because it is domain-specific
instructional documentation that an agent reads and applies. Synchronizing the externally installed
skill copies remains the darktable skill's packaging concern; a panel run relies only on its saved
profile snapshot.

Only the copy explicitly selected by `--review-profile` participates in a panel run. Claude resolves
that path while launching the review; Codex and Gemini read the shared `/tmp/<ID>/review-profile.md`
snapshot and do not need their own installed profile copies.

## Verification

- A run without `--review-profile` preserves the current generic review behavior.
- Start parsing accepts a readable profile alongside every supported scope and with optional
  `--instructions`; malformed ordering and duplicate profile flags fail clearly.
- Missing, unreadable, non-regular, or unacceptably large profile input fails before the workdir
  marker is created.
- The manifest and `/tmp/<ID>/review-profile.md` contain the expected metadata and exact bytes.
- Round-0 and debate prompts for Claude, Codex, and Gemini identify the same saved profile.
- Editing or deleting the source profile after start does not change resume or continue behavior.
- A profile that contains conflicting output instructions cannot change phase block cardinality,
  accepted fields, or stance values; the executable seat contract remains authoritative.
- Status and result surfaces identify the profile without dumping its contents.
- Update `README.md`, the start/resume/continue/status/result skill documentation, the canonical
  protocol, `CONTRACTS.md`, and relevant script ownership documentation.
- Run `scripts/check_contracts --root .`, `./tests/run_tests.sh`, and `git diff --check`.

## Non-goals

- Do not add darktable-specific text, detection, defaults, or profile names to panel-review.
- Do not ask the three seat runtimes to discover or activate their locally installed skill copies.
- Do not let profiles replace panel output contracts or consensus rules.
- Do not reload a profile from its original path during resume or continuation.
- Do not treat the profile hash as protection against a malicious, unconstrained seat.

## Implementation

- `profiles/default.md` owns the generic priority catalogue previously embedded in the blind prompt.
- `stage_review_profile` validates and atomically snapshots built-in or external profile bytes;
  `init_run` stores the resolved source path, size, and SHA-256 before publishing the workdir marker.
- `round` verifies the saved snapshot and gives the same absolute reference to Round 0 and every
  debate prompt. Resume and continuation never read the original source path.
- Status exposes the saved metadata. Verdict frontmatter records it, and `panel-review:result` prints
  the source path and SHA-256 before the verdict body. Legacy verdict artifacts remain readable.
- The canonical `~/.agents/skills/darktable-review` copy now keeps its reusable method in
  `references/review-profile.md`; its `SKILL.md` reads that reference for standalone reviews.

Verification, 2026-07-20:

- `scripts/check_contracts --root .` — passed.
- `./tests/run_tests.sh` — `PASS: 246`, `FAIL: 0`.
- `git diff --check` — passed.
