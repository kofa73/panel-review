# Define and enforce stance semantics

Priority: 1

Status: Completed

Source: instruction-contract audit

## Problem

The debate prompt distinguishes `support`, `support_with_revision`, and `reject`, but the schema,
parser, and transition code do not enforce one consistent meaning. A syntactically accepted stance
can therefore carry a field revision whose meaning contradicts its declared stance, and that revision
can change canonical issue state.

This is the highest-priority remaining issue because it affects data interpreted as panel agreement,
not merely wording or diagnostics.

## Verified evidence

- `prompts/debate.tmpl` says plain `support` accepts the issue as stated, while
  `support_with_revision` supplies corrected fields.
- The then-current `prompts/schema/stances.txt` demonstrated a `support` stance with a populated
  `revision`; issue 05 later replaced that fragment with `scripts/seat_contract.py`.
- `scripts/parse_block` validates the stance name and normalizes a present revision, but does not
  enforce stance-dependent fields or require a rationale where the prompt assigns one semantic
  meaning.
- `scripts/decide_round` treats both support variants as supporting stances and reads revision values
  from either. Consequently, a plain `support` carrying `revision` can affect canonical severity,
  location, category, or claim.
- The current static prompt checks and full test suite pass despite this disagreement, so those tests
  do not establish semantic consistency.

## Design decision

Decision made 2026-07-16: remove `support_with_revision`. The old stance enum combined two separate
decisions: whether the issue exists and whether one of its canonical fields should change. The
executable contract now represents those decisions independently:

| Stance | Required | Optional | Normalization |
|---|---|---|---|
| `support` | issue ID and stance | `revision`, `rationale`, `new_evidence` | Invalid revision fields are discarded; fields equal to the canonical issue are no-ops. |
| `reject` | issue ID, stance, non-empty counter-evidence rationale | `new_evidence` | Any supplied `revision` is discarded because a rejected issue has no fields to revise. |

`support` affirms issue existence, not necessarily every current field. An omitted revision endorses
the current effective values. A populated revision proposes new severity, location, category, or
claim values; the existing convergence rules still decide whether any proposal is adopted. When all
revision fields are no-ops, the stance behaves exactly like support without a revision and does not
change the card. A support rationale is optional and is promoted only when the stance contains an
effective revision; `new_evidence` retains its existing independent meaning.

The raw-input parser owns tolerant structural normalization. Decision code owns comparisons with the
canonical issue because only that layer has the required context. Downstream code must see only the
two canonical stance names and must never infer a revision from prose.

No compatibility alias is retained for `support_with_revision`. Incompatible old review artifacts
may be discarded under the project's existing artifact-compatibility decision.

## Required outcome

Make the schema example, rendered prompt, parser, decision logic, glossary, authoritative README,
protocol, script-ownership rules, and tests agree with the design decision above. Validation and
normalization should occur at the earliest deterministic layer without losing an otherwise
unambiguous stance.

## Scope and non-goals

- Cover every revision field accepted by the current parser.
- Preserve blindness rules for rationale and evidence text.
- Do not redesign the issue lifecycle or replace unanimity with majority voting.
- Do not fold the broader instruction deduplication into this fix; issue 05 prevents recurrence after
  this immediate behavior is settled.

## Verification

- Add negative tests for the removed stance name and for reject without counter-evidence.
- Add positive tests for support with and without revision and for reject.
- Prove that support revisions participate in convergence, while no-op revisions cannot change
  canonical issue fields or card evidence.
- Prove that a revision attached to reject cannot change canonical issue fields.
- Reject removed stance names and missing reject rationale again at the decision seam so retained
  pre-change checkpoints fail explicitly rather than changing the outcome.
- Verify the generated/rendered seat instructions, not only isolated source fragments.
- Run focused parser/decision tests, then `./tests/run_tests.sh` and `git diff --check`.

## Implementation and verification

Completed 2026-07-16:

- `parse_block` accepts only `support` and `reject`, requires reject counter-evidence, normalizes
  optional support revisions, and discards revisions attached to reject.
- `decide_round` treats revisions as orthogonal support proposals, filters exact no-ops from enum
  mutation, claim advice, rationale promotion, and blindness checks, and fails explicitly on removed
  stance names or invalid reject checkpoints retained from an older run.
- The rendered debate prompt, then-current schema fragment, README, glossary, canonical protocol,
  script rules, repository instructions, examples, fixtures, and test documentation used the same
  contract. Issue 05 later made `scripts/seat_contract.py` its executable owner.
- Focused parser/check-draft/decision/round tests passed.
- Full `./tests/run_tests.sh` passed: `PASS: 216   FAIL: 0`.
- Python compilation and `git diff --check` passed.
