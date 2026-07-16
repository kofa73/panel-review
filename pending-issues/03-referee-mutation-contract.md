# Correct the referee mutation contract

Priority: 3

Status: Pending

Source: agent/protocol consistency audit

## Problem

The referee agent says it mutates issue records only on seat agreement. That is too broad and
contradicts the canonical protocol: agreement is required for acceptance or rejection, but the
system also performs valid mechanical mutations without unanimous agreement.

Because the statement is in the referee's short, always-loaded role contract, it can override or
confuse the more precise phase instructions.

## Verified evidence

- `agents/panel-review-referee.md` says the referee will "mutate issue records only on seat
  agreement."
- The protocol and transition scripts update evidence, coverage, counters, flags, revisions, and
  audit data as rounds are committed.
- Degraded and round-limit handling can force `contested` or `unresolved` terminal states without
  unanimous acceptance or rejection.
- The documented lifecycle requires unanimity for settling an issue as accepted or rejected, not for
  every record mutation.

## Required outcome

Replace the broad mutation prohibition with the precise invariant:

> Only acceptance or rejection requires unanimity among at least two engaged seats. Mechanical
> evidence, coverage, counter, audit, degradation, and terminal-limit updates follow the canonical
> transition rules and do not imply agreement.

The agent overview should remain short and defer transition details to the canonical phase protocol.
It must not independently restate a simplified state machine.

## Verification

- Add a contract test that checks the precise unanimity invariant without freezing incidental prose.
- Retain behavioral tests for contested/unresolved limit transitions and committed evidence/coverage
  updates.
- Confirm the agent definition and canonical protocol cannot reasonably instruct opposite actions.
- Run the relevant index, sweep, and round tests, then the full suite and `git diff --check`.
