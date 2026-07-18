# Evaluate a compact catalogue of previously catalogued claims

Priority: 11

Status: Optional

Source: observed review `panel-20260715-170356-97b133b8`

## Observation

Debate prompts contain only the currently open blind cards. A seat investigating those cards can
therefore encounter a claim that already settled earlier in the run and return it as a
`new_findings` item. The referee then spends judgment work folding the item into the existing issue.

This can duplicate investigation and output, but the observed example was not pure waste. Issue
`i1` was accepted at birth and omitted from the round-2 cards. Claude independently encountered it
while reviewing `i4` and `i5`, then supplied new evidence that limited the demonstrated impact to
wasted processing and latency rather than data corruption. The referee folded that evidence into
`i1`, reopened it, and the later debate reduced its severity from high to medium.

## Triage

Do not add the proposed block of accepted/rejected issues directly. This is an optional token-cost
experiment, not a known correctness defect or release blocker.

A block that identifies claims as accepted or rejected would reveal a consensus-derived outcome to
the seats and could anchor their independent review. Even without outcomes, repeating every settled
claim in every debate prompt adds input tokens and may discourage seats from reporting materially
conflicting evidence that should reopen an issue. The benefit is therefore unproven and may reverse
as the issue set grows.

## Candidate experiment

If duplicate rediscovery becomes a measured cost, compare the current prompt with a compact
deterministically rendered catalogue that:

- includes only the canonical issue ID, claim, and location for issues not represented by the
  current batch's cards;
- omits state, origins, stance history, tallies, and evidence, so it does not disclose whether a
  claim was accepted or rejected;
- labels the catalogue non-authoritative and asks seats to avoid returning merely cumulative
  duplicates;
- explicitly requires a `new_findings` item when newly verified evidence materially conflicts with
  the catalogued claim or its apparent impact; and
- is generated from `index.json` by the prompt-preparation path rather than assembled by referee
  prose.

Use representative runs with actual settled-claim rediscovery. Compare total prompt and output
tokens, tool calls, duplicate findings, referee addendum work, latency, useful conflicting evidence,
reopened issues, and final issue quality. Adopt the catalogue only if it produces a clear net saving
without suppressing corrections or weakening blindness.

## Constraints

- Do not expose which claims were accepted or rejected, origins, or numerical alignment.
- Do not tell seats to ignore a matching claim unconditionally; later conflicting evidence is part
  of the existing reopen contract.
- Keep the catalogue compact enough that its repeated input cost cannot dominate the duplication it
  is intended to prevent.
- Keep the existing referee fold/reopen behavior as the correctness backstop.

## Verification if implemented

- Add prompt-construction tests proving that the current batch's issues are absent from the
  catalogue and that state, origins, stance data, and evidence are not rendered.
- Add a protocol/contract test preserving the requirement to report materially conflicting
  evidence.
- Run `scripts/check_contracts --root .`, the focused prompt/round tests, the full suite, and
  `git diff --check`.
