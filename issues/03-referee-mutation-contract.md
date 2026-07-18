# Correct the referee mutation contract

Priority: 3

Status: Completed

Source: agent/protocol consistency audit

## Problem

The referee's always-loaded contracts say it mutates issue records only on seat agreement. That is
too broad and contradicts the canonical protocol: agreement controls consensus outcomes and detail
revisions where the transition rules require it, but the system also performs valid mechanical
mutations without unanimous agreement.

Because the statement appears in both short, always-loaded referee contracts, it can override or
confuse the more precise phase instructions.

## Verified evidence

- `agents/panel-review-referee.md` and `skills/panel-review-for-agent/SKILL.md` say the referee will
  mutate issue records only when seats agree.
- The protocol and transition scripts update evidence, coverage, counters, flags, revisions, and
  audit data as rounds are committed.
- Degraded and round-limit handling can force `contested` or `unresolved` terminal states without
  unanimous acceptance or rejection.
- The documented lifecycle applies agreement to consensus outcomes and qualifying detail revisions,
  not to every record mutation.

## Required outcome

Replace the broad mutation prohibition with the precise invariant:

> Seat agreement controls consensus outcomes and detail revisions where required by the canonical
> transition rules. Mechanical evidence, coverage, counter, audit, degradation, and terminal-limit
> updates follow those rules and do not imply agreement.

The agent overview should remain short and defer transition details to the canonical phase protocol.
It must not independently restate a simplified state machine.

## Verification

- Add a contract test that checks the precise unanimity invariant without freezing incidental prose.
- Retain behavioral tests for contested/unresolved limit transitions and committed evidence/coverage
  updates.
- Confirm the agent definition and canonical protocol cannot reasonably instruct opposite actions.
- Run the relevant index, sweep, and round tests, then the full suite and `git diff --check`.

## Implementation and verification

Completed 2026-07-16:

- Replaced the broad mutation prohibition in both always-loaded referee contracts with the agreed
  distinction between agreement-gated decisions and canonical mechanical updates.
- Added contract checks for both invariant clauses and removal of the obsolete prohibition. The
  checks normalize whitespace so Markdown wrapping is not part of the contract.
- Retained the existing behavioral coverage for agreement-based detail revisions, forced terminal
  states, evidence, coverage, counters, and audit updates.
- The focused index, sweep, round, normal-decision, and degraded-decision suites passed: 58 tests.
- Full `./tests/run_tests.sh` and `git diff --check` passed.
