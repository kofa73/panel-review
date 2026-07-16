# Define and enforce stance semantics

Priority: 1

Status: Pending

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
- `prompts/schema/stances.txt` demonstrates a `support` stance that contains a populated `revision`.
- `scripts/parse_block` validates the stance name and normalizes a present revision, but does not
  enforce stance-dependent fields or require a rationale where the prompt assigns one semantic
  meaning.
- `scripts/decide_round` treats both support variants as supporting stances and reads revision values
  from either. Consequently, a plain `support` carrying `revision` can affect canonical severity,
  location, category, or claim.
- The current static prompt checks and full test suite pass despite this disagreement, so those tests
  do not establish semantic consistency.

## Required outcome

Choose and document one executable contract. The recommended contract is:

| Stance | Required | Forbidden |
|---|---|---|
| `support` | issue ID and stance | `revision`; rejection/revision rationale |
| `support_with_revision` | non-empty supported revision and rationale | empty or irrelevant revision |
| `reject` | rationale containing counter-evidence | `revision` |

Then make the schema example, rendered prompt, parser, decision logic, and tests agree. Validation
should fail at the earliest deterministic boundary rather than silently assigning meaning to an
internally contradictory object.

If a different contract is chosen, it must explicitly define whether plain support may revise fields
and how that differs from `support_with_revision`; retaining both names with identical effects is not
a coherent outcome.

## Scope and non-goals

- Cover every revision field accepted by the current parser.
- Preserve blindness rules for rationale and evidence text.
- Do not redesign the issue lifecycle or replace unanimity with majority voting.
- Do not fold the broader instruction deduplication into this fix; issue 05 prevents recurrence after
  this immediate behavior is settled.

## Verification

- Add negative tests for every forbidden stance/field combination.
- Add positive tests for all three valid stance shapes.
- Prove that a plain support cannot silently revise canonical issue fields.
- Verify the generated/rendered seat instructions, not only isolated source fragments.
- Run focused parser/decision tests, then `./tests/run_tests.sh` and `git diff --check`.
