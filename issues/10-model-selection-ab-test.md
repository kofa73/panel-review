# Evaluate a referee model change

Priority: 10

Status: Optional

Source: former `pending.md` item 16

## Decision

Keep the referee on Opus unless a later, explicit Sonnet A/B test demonstrates comparable protocol
execution and verdict quality.

## Why this is last

This is a cost/performance experiment, not a known correctness problem. Changing the model while
behavioral contracts and instructions are still moving would confound the comparison and could hide
instruction defects behind model-specific compliance differences.

Run the judgment-offload experiment first if current profiling justifies it. Changing both the
context architecture and controller model together would make the result uninterpretable.

## Minimum experiment design

- Use the same repository state, scope, instructions, panel configuration, and round limits.
- Include cases that exercise resume, degradation, low-only gating, debate checkpoints, and artifact
  persistence rather than comparing only a straightforward review.
- Compare protocol compliance, issue quality, false positives/negatives, verdict completeness,
  latency, and token/cost use.
- Keep raw evidence and identify unavoidable run-to-run variance.
- Require comparable quality and reliability before considering cost savings.

No model change is warranted without that evidence.

## Existing benchmark model

The context-cost run dated 2026-07-12 used the `model: opus` alias before Claude Code 2.1.219 made
Opus 5 the default on 2026-07-24. Release chronology attributes it to Opus 4.8, not Opus 5 or 5.5.
The run manifest does not record the resolved Claude model, so this attribution follows the alias
timeline and is not runtime telemetry.
