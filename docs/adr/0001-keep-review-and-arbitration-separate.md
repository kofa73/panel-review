---
status: accepted
---

# Keep review and arbitration separate

Panel Review uses independent seats to review the target and a separate referee to cluster findings,
administer debate, and synthesize the report. The referee does not review or fact-check the target;
the Claude seat is created cold for every pass and never forked from referee context. Seats do not
see origins or stance tallies. An issue settles only through unanimous support or rejection among a
quorum; anything else reaches the human rather than a majority vote or referee override.

This is costly to reverse because role isolation, blind cards, seat spawning, issue transitions, and
the report contract all depend on it. It is surprising because an orchestration model could
plausibly act as another reviewer or break ties. That alternative was rejected: remembered findings
would compromise blindness, and model voting is an issue-finding aid rather than autonomous
authority.

## Consequences

- The referee may perform semantic organization and synthesis but cannot independently decide issue
  validity.
- Seat agreement controls consensus; terminal disagreement is preserved for human judgment.
- Evidence remains visible, but its seat origin and numerical alignment remain hidden from seats.

## Evidence

- [`docs/evolution.md`, milestone 1](../evolution.md#1-founding-architecture-blind-seats-a-non-reviewing-referee-and-unanimity)
- Commit `3869ec4`, especially the initial README and the referee/Claude-seat definitions
- Current [`README.md`](../../README.md#what-makes-the-review-blind) and
  [`agents/panel-review-referee.md`](../../agents/panel-review-referee.md)

