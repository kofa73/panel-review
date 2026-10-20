# Remove duplicate addendum and commit instructions

Priority: 14

Status: Completed

Source: review `panel-20260716-202101-013e59c4`

## Problem

The canonical debate protocol assigns addendum merging and atomic round commit to
`round commit --addendum`, then later instructs the referee to perform the same operations through
lower-level helpers. This contradicts the coarse-command ownership introduced after the earlier
referee-cost analysis and retained by the instruction-contract single-source work.

The duplicate instructions make the normal path ambiguous: a referee can call only the coarse
interface, only the lower-level sequence, or both. They also keep obsolete clobber-avoidance and
transaction details in the referee context even though `round` now owns those details.

## Verified evidence

In `skills/panel-review-for-agent/references/protocol.md`:

- debate step 10 says `round commit` owns the mechanical transaction and directs an exit-3 caller to
  write an addendum and call `round commit "$id" --addendum <file>`;
- step 11 separately instructs the referee to run `merge_payload`, guard a temporary file, and
  replace `payload.<round>.json` manually; and
- step 12 shows direct `sweep commit` and `regen_cards` commands even though it also says
  `round commit` performs the step.

`scripts/round`, `cmd_commit`, already:

1. regenerates the deterministic decision payload;
2. invokes `merge_payload` when `--addendum` is supplied;
3. atomically installs the merged payload;
4. invokes `sweep commit`; and
5. regenerates the cards.

The live run followed both instruction paths in Round 2. The referee manually merged
`addendum.2.json` into `payload.2.json`, then called `round commit --addendum addendum.2.json`.
`round` regenerated the base payload and merged the same addendum again before committing, so the
result was correct, but the manual work was redundant.

`scripts/check_contracts --root .` currently reports `instruction contracts: OK` while this
contradiction is present. The existing ownership checks therefore do not cover the normal debate
addendum boundary.

## Required outcome

Give the normal debate path one executable owner:

- the referee creates only the judgment addendum after exit 3;
- `round commit --addendum <file>` exclusively owns validation, merge, atomic payload installation,
  sweep commit, and card regeneration; and
- the debate protocol describes the addendum's semantic contents without reproducing lower-level
  merge or commit commands.

If direct `merge_payload`, `sweep commit`, or `regen_cards` calls remain necessary for an exceptional
recovery path, put them only in the relevant recovery phase and state why the coarse interface is
not applicable. They must not remain as alternative normal-path instructions.

## Scope and non-goals

- Preserve referee ownership of prose-claim synthesis and new-finding fold/birth judgment.
- Preserve `merge_payload` as the implementation helper used by `round`; removing it from referee
  instructions does not imply deleting the script.
- Do not change transition semantics, addendum shape, atomicity, or idempotence.
- Do not collapse exceptional salvage or recovery mechanics into the normal debate path.

## Verification

- Add a semantic contract check that rejects direct normal-debate instructions to run
  `merge_payload`, `sweep commit`, or post-commit `regen_cards` outside the owning `round` interface.
- Check the rendered `read_protocol_phase debate` output, not only the source file.
- Retain end-to-end round tests proving that `round commit --addendum` merges judgment, commits once,
  and regenerates cards.
- Add or retain a failed-addendum test proving that the canonical payload and index remain intact.
- Run `scripts/check_contracts --root .`, focused round/protocol tests, the full suite, and
  `git diff --check`.

## Implementation

Completed 2026-07-18.

- The rendered normal debate phase now gives the referee one path: create the semantic judgment
  addendum, then pass it to `round commit --addendum`. It no longer contains direct merge, sweep
  commit, or post-commit card-regeneration commands.
- `CONTRACTS.md` records `scripts/round commit` as the owner of the normal debate transaction.
- `check_contracts` renders the debate phase and rejects direct lower-level transaction commands.
- End-to-end round tests verify successful judgment merge, one committed round, regenerated cards,
  and preservation of the canonical payload and index after an invalid addendum.

Verification completed successfully with `scripts/check_contracts --root .`, the focused contract,
protocol-phase, and round unit tests, `./tests/run_tests.sh`, and `git diff --check`.
