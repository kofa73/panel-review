# Evaluate offloading referee judgment

Priority: 9

Status: Optional

Source: former `fix_plan.md` Track B

## Decision

Do not add another helper agent without a controlled measurement showing that the remaining referee
judgment context is again a material cost center. The coarse `round` commands and phase-specific
protocol loading have already removed most model-mediated mechanics, so the expected benefit is lower
than when this proposal was written.

This is a cost experiment, not a known correctness problem or release blocker.

## Remaining opportunity

The referee still performs the judgment that deterministic scripts cannot own:

- clustering Round-0 findings into canonical issues and recording their origins;
- deciding whether later findings fold into an existing issue or create a new one;
- resolving prose-claim revisions and writing the small judgment addendum;
- synthesizing the final verdict.

The original B1 proposal was to move Round-0 clustering into a fresh, disposable, non-reviewing
helper Agent. It would consume the seat-labeled findings and persist only:

- the clustered `issues.map.json`; and
- a finding-to-seat origin index from which canonical origins can be installed.

The long-lived referee would then consume only those compact artifacts rather than retaining all raw
Round-0 findings. The helper is internal orchestration, not a fourth review seat, and must produce no
seat-facing output.

## Conditional follow-up

Only if B1 produces a clear net saving, evaluate the former B2 proposal: use the same disposable
helper pattern for the remaining debate judgment glue. Mechanical stance processing, state
transitions, coverage, counters, evidence promotion, payload merging, and commit remain owned by
`round`, `decide_round`, `decide_degraded_round`, `merge_payload`, `sweep`, and `index`.

The helper may decide only the existing LLM-owned seams: prose-claim synthesis and new-finding
fold/birth decisions. It must return or persist a compact addendum accepted by the existing
deterministic transaction path.

## Constraints

- Preserve blindness: no seat sees origins, seat labels, stance tallies, or helper output.
- Preserve role separation: the helper does not review the target code or independently decide issue
  validity.
- Keep the Claude review seat fresh and never forked; this helper is a different non-reviewing role.
- Do not move deterministic state transitions back into model prose.
- Keep artifact ownership explicit and fail closed on missing, malformed, or ambiguous helper output.
- Account for cold-start overhead. A helper must load enough contract context to make the judgment,
  so it can cost more on short or simple reviews.
- Do not combine this experiment with a referee-model change; that would confound attribution.

## Minimum experiment design

1. Stabilize the correctness and instruction-contract work in issues 01-06 first.
2. Profile a representative current run and confirm that Round-0 clustering materially increases the
   referee's retained context and later cache-read cost.
3. Replay the same repository state, scope, instructions, panel, and round limits with and without
   B1 where practical.
4. Compare total and referee API calls, input-context/cache-read tokens, peak context, output tokens,
   latency, clustering quality, origin accuracy, protocol errors, and recovery behavior.
5. Retain the raw evidence and state unavoidable run-to-run differences.
6. Adopt B1 only if the saving is clear and issue quality and protocol reliability are not worse.
7. Consider B2 only after B1 meets that threshold.

The original baseline and the decisions that led to this experiment are retained in
[`referee-context-cost-history.md`](referee-context-cost-history.md).
