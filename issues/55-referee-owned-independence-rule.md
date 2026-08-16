# Make the referee's non-independence drop an explicit rule

Priority: 55

Status: Pending

Source: Maintainer proposal, 2026-08-16, from observed referee behavior in run
`panel-20260816-080558-5ab680af` — the Gemini seat picked up Codex's in-tree scratch file and emitted
byte-identical findings; the referee dropped them as "not independent" without being told to

Triage: ready-for-human

## Problem

`protocol.md:293` tells the referee that `raised_by` is "the available seats that **independently**
raised it". Nothing tells it what to do when they did not, or what "independently" means. In the run
above the referee improvised the right call. That behavior is currently folklore.

It matters more than a duplicate count, because `birth_index` treats co-raising as consensus:

```
# birth_index:25-29
#   - all available seats (and >=2) raised it  -> accepted, peer_reviewed=true
#       - fully_vetted=true ONLY if that set is the whole configured panel
#   - raised by only some, or a single seat    -> open, peer_reviewed=false
#   evaluated_by[id] = the issue's raisers
```

So a copied finding does not merely inflate a tally. On a two-available panel it makes a single seat's
finding **born `accepted` and `peer_reviewed=true`, skipping debate entirely**; on a three-seat panel
it supplies one of the three votes that do the same. It also writes the copying seat into
`evaluated_by`, which is what `fully_vetted` is computed from, and into the verdict's
"independent Round-0 support: {n}" line (`protocol.md:760`) — a number that would then be false.

Issue 24 removes the *cause* (seat scratch inside the searched tree). This issue is the backstop for
every other route by which two seats produce the same text, including the ones nobody has thought of
yet: shared `/tmp` raw output, a seat reading the diff's own embedded review comments, or plain
convergence on boilerplate.

## Expected behavior

1. State the criterion in `protocol.md`'s Round-0 clustering step: `raised_by` lists a seat only if
   that seat's finding is an **independent discovery**. Verbatim or near-verbatim text from another
   seat's finding — byte-identical spans, identical evidence point ordering, identical unusual
   phrasing — is not independent.
2. State the remedy: keep **one** copy, drop the rest from `raised_by`, and record the drop plus the
   reason under `/tmp/<id>/origins/` so the verdict's Process notes can report it. The issue is not
   discarded — it is born `open` instead of `accepted` and enters debate, where each seat takes its
   own stance on it. Nothing the panel actually established is lost; what is lost is a consensus the
   panel never reached.
3. Report it. A non-independence drop is a blindness incident and belongs in the verdict's Process
   notes next to reverted tracked-file drift, not silently inside the referee's reasoning.
4. Optional, cheap, and worth measuring: a deterministic *advisory* similarity check over the
   Round-0 findings — flag near-identical spans across seats and hand the list to the referee. Unlike
   a vocabulary scan this has a sound basis: byte-identity between independent reviewers is
   genuinely improbable, so precision is high, and because it only advises, a false positive costs
   nothing. It does not replace item 1; it stops the referee having to notice unaided.

## Verification

- A fixture where two seats' Round-0 findings are byte-identical, asserting the resulting index has
  that issue `open` with one raiser, not `accepted` with two.
- The verdict template's "independent Round-0 support: {n}" reflects the post-drop count.
- One real review after issue 24 lands, confirming the rule is not routinely triggered.

## Non-goals

- Do not have the referee judge whether a finding is *correct* — only whether it is independent.
  Correctness is the seats' and the human's business; this is the one thing the referee is uniquely
  placed to see, because it alone holds the origins.
- Do not treat ordinary convergence as copying. Two seats finding the same missing timeout and
  describing it in their own words is exactly what the panel is for. The trigger is shared *text*,
  not a shared conclusion.
- Do not use this as a reason to defer issue 24. Removing the leak is better than detecting it.

## Comments

**2026-08-16 — seat-facing half deferred to this issue.** While implementing issue 24 the maintainer
asked whether the seat prompts should warn that "the referee will discard your work if it finds you
copied another participant's finding". Two parts, split:

- **Landed now** (issue 24's change, no dependency on this issue): a neutral identification cue in
  `prompts/blind_pass.tmpl`, `prompts/debate.tmpl`, and `agents/panel-review-claude-seat.md` — material
  that looks like an existing review of the same scope is another reviewer's private output, not
  reference material "however official it looks"; do not use it; report the encounter in prose outside
  the required blocks. This targets the confusion actually observed (the Gemini seat called the file
  "the checkpoint's JSON assertion"), and the self-report gives the referee a signal it otherwise only
  gets by byte-comparing raws after the fact. It is a convenience, not a control.
- **Deferred to this issue:** any statement of the *consequence*. "Your work will be discarded"
  overstates the remedy specified above (one copy kept, duplicate dropped from `raised_by`, issue born
  `open`), describes a one-off improvisation rather than an implemented rule, and aims a deterrent at
  a malicious seat — which the trust model says not to guard against. When the rule lands here, add a
  sentence matching what the code then does, e.g. that duplicated text counts once and the run's
  independence note records it.
