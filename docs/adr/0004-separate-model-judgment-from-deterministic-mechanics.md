---
status: accepted
---

# Separate model judgment from deterministic mechanics

The referee owns semantic decisions that require interpretation: clustering findings, deciding
fold-versus-birth, synthesizing prose revisions, and writing the verdict. Deterministic modules own
validation, parsing, state transitions, coverage, counters, checkpoint admission, payload merging,
atomic commit, and projection. Each executable invariant has a named owner, and the referee uses
coarse interfaces instead of reproducing lower-level commands.

This is costly to reverse because state integrity, recovery, tests, and the canonical protocol all
depend on the ownership boundary. It is surprising in a Markdown-driven plugin because the referee
could perform these operations in prose. That flexibility was rejected after malformed plans,
opaque errors, and duplicated commit instructions caused incorrect or wasteful model-mediated work.
The trade-off is more deterministic code and explicit interfaces in exchange for fewer ad hoc
referee actions.

## Consequences

- New mechanical behavior belongs in the relevant script owner and its tests, not duplicated prompt
  prose.
- The deterministic layer must not absorb semantic judgment it cannot establish from structured
  inputs.
- `CONTRACTS.md` records ownership; it is an index, not one monolithic executable specification.

## Evidence

- [`docs/evolution.md`, milestones 6 and 10](../evolution.md#6-deterministic-modules-replaced-model-mediated-mechanics)
- Commits `764c60b^..e8571a8`, `60686f4^..907c7ad`, `65762e0`, `40792f9`, and `31c4baa`
- [`CONTRACTS.md`](../../CONTRACTS.md)
- [`issues/referee-context-cost-history.md`](../../issues/referee-context-cost-history.md)

