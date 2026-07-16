# Panel Review

Panel Review is a blind, multi-model review protocol that turns independent findings into canonical
issues, debates those issues to unanimity where possible, and hands the rest to a human. This
glossary names the concepts shared by its user-facing workflow, referee protocol, and issue model.

## Review boundary

**Review scope**:
The code change or technical question that every seat reviews. A scope is the subject of the review,
not a statement of what conclusions the seats should reach.
_Avoid_: Target, review instructions

**Review instructions**:
Optional emphasis shared with every seat without narrowing the review scope or suppressing relevant
findings outside that emphasis.
_Avoid_: Scope, filter

**Review run**:
One durable review identity for a fixed scope and its accumulated issues, evidence, and outcomes. A
run may survive interruptions and contain more than one continuation cycle.
_Avoid_: Session

**Continuation cycle**:
A new debate cycle within the same review run, created by reopening selected leftovers with a fresh
debate budget while retaining prior evidence and settled issues.
_Avoid_: Epoch, resumed run

**Resume**:
Continue an interrupted review run from its current cycle without reopening terminal issues or
resetting their debate budget.
_Avoid_: Continue

**Continue**:
Start a continuation cycle for selected leftovers from a finished review run.
_Avoid_: Resume, restart

**Diverged review**:
A saved review run whose current review scope no longer matches the scope snapshot on which the run
was based.
_Avoid_: Moved review, stale review

## Participants and blindness

**Panel**:
The configured seats against which participation and review coverage are measured for the current
phase or debate round.
_Avoid_: Engaged seats

**Seat**:
An independent model reviewer occupying one place on the panel. Claude, Codex, and Gemini are seats;
the referee is not.
_Avoid_: Agent, participant, reviewer model

**Peer seat**:
Either optional external seat, Codex or Gemini, that reviews alongside the Claude seat. At least one
peer seat is needed for a panel rather than a solo review.
_Avoid_: Required Codex seat, Gemini add-on

**Referee**:
The non-reviewing participant that preserves blindness, clusters findings, administers debate, and
synthesizes the verdict without independently deciding whether the reviewed code is correct.
_Avoid_: Reviewer, Claude seat

**Configured seat**:
A seat included in the panel for the current phase or round and therefore included in full-coverage
measurement, whether or not it successfully responds.
_Avoid_: Engaged seat, available seat

**Engaged seat**:
A configured seat that supplied a complete, valid response required for the current seat pass. Seat
engagement is per pass and does not persist automatically into later rounds.
_Avoid_: Configured seat, available seat, active seat

**Down seat**:
A configured seat that did not engage in the current pass because it was unavailable, failed, timed
out, or returned an unusable response. A down seat may engage again in a later round.
_Avoid_: Removed seat, excluded seat

**Blind review**:
A review in which seats do not know which seat originated a point or how seats are numerically
aligned. Round 0 is also independent: each seat reviews before seeing any other seat's findings.
_Avoid_: Anonymous majority vote

**Origin**:
The seat attribution of a finding, evidence point, or stance. Origins are known to the referee and
hidden from seats.
_Avoid_: Author, vote

## Review material

**Finding**:
A seat-authored concern that has not yet been clustered into the canonical issue set. Findings may
arise during Round 0 or later debate rounds.
_Avoid_: Issue, verdict item

**Issue**:
A canonical concern tracked through debate and assigned one lifecycle state. One issue may combine
matching findings from several seats while retaining their distinct evidence and origins.
_Avoid_: Finding, card

**Issue birth**:
The point at which one or more clustered findings become a canonical issue with an initial state and
review-coverage record.
_Avoid_: First debate round

**Claim**:
The issue's concise statement of the suspected defect or design problem. It may be revised without
changing the identity of the issue when the underlying location and failure mechanism remain the same.

**Evidence point**:
A concrete technical fact for or against an issue, tied to a location or analysis context. Distinct
points remain distinct unless they describe the same location and failure mechanism.
_Avoid_: Vote, finding

**Blind card**:
The seat-facing projection of an issue, containing its current claim and technical evidence but no
origins or stance tally.
_Avoid_: Issue record, transcript

**Stance**:
A seat's position on one issue during a debate round: support or reject. A stance concerns issue
existence; a supporting stance may independently propose changes to issue details.
_Avoid_: Vote

**Support**:
A stance affirming the issue's existence. It may include a revision proposing a change to severity,
claim, category, or location; without a revision, it endorses the current values.

**Reject**:
A stance denying that the issue is valid.

**Style note**:
A non-substantive observation classified as style rather than a defect. It is reported separately
and does not enter the issue debate lifecycle.
_Avoid_: Low-severity issue

## Review flow and coverage

**Round 0**:
The initial blind pass in which every engaged seat reviews the same scope independently and produces
findings from which issues are born.
_Avoid_: Debate round, round 1

**Debate round**:
One complete evaluation of every currently open issue by the seats that engage for that round.
_Avoid_: Sweep, pass

**Seat pass**:
One seat's complete contribution to Round 0 or a debate round. In a batched debate round, the
contribution is complete only when all of that seat's debate batches are complete.
_Avoid_: Debate round, review run, pass

**Debate batch**:
A subset of one debate round's open issues assigned to one seat when the full set is too large for a
single response. The union of a seat's batches is its contribution to that round.
_Avoid_: Debate round, seat pass

**Quorum**:
At least two engaged seats evaluating the same issue in a qualifying pass. Quorum permits an issue
to be peer reviewed and settled; one seat alone cannot settle it.
_Avoid_: Majority

**Consensus**:
Unanimous agreement among engaged seats on an issue's existence, or on the same proposed value for a
revised issue detail. A numerical majority is not consensus.
_Avoid_: Majority decision, winning value

**Peer reviewed**:
A coverage status meaning that an issue has received qualifying evaluation from at least two engaged
seats. It records review coverage, not acceptance or full-panel coverage.
_Avoid_: Accepted, fully vetted

**Fully vetted**:
A coverage status meaning that every configured seat has evaluated the issue at least once. It is
stronger than peer reviewed but still does not express whether the issue was accepted or rejected.
_Avoid_: Accepted, unanimous

**Low-severity gate**:
The decision point reached when every open issue after Round 0 is low severity, allowing the user to
finish with the current report or spend the debate budget on those issues.
_Avoid_: Low-severity outcome

**Salvage**:
Referee-owned recovery of a seat's already-completed review from an unusable response shape, without
changing its conclusions or asking the seat to review the scope again.
_Avoid_: Retry, re-review, reinterpretation

## Issue outcomes

**Open**:
An active issue whose existence or material details have not reached a terminal outcome and that
remains eligible for another debate round.
_Avoid_: Unresolved

**Accepted**:
A terminal outcome affirming an issue's existence through consensus or qualifying independent birth.
Its details may still be marked detail contested.
_Avoid_: Fully vetted, fixed

**Rejected**:
A terminal outcome recording consensus that an issue is not valid.
_Avoid_: Resolved, ignored

**Contested**:
A terminal human-handoff outcome for an issue that received quorum review but did not settle before
its debate ended.
_Avoid_: Unresolved, rejected

**Unresolved**:
A terminal human-handoff outcome for an issue that never received quorum review before its debate
ended.
_Avoid_: Contested, open

**Detail contested**:
A status on an accepted issue whose existence reached consensus but whose severity, claim, category,
or location did not converge on one value.
_Avoid_: Contested issue

**Merged**:
A disposition for a proposed issue whose finding and evidence were folded into an existing issue
because they describe the same location or code path and the same failure mechanism.
_Avoid_: Duplicate, accepted

**Leftover**:
A contested or unresolved issue handed to the human at the end of a review cycle and eligible for a
later continuation cycle.
_Avoid_: Open issue, unfinished issue

**Finished review**:
A review run with no open issues. It may still contain leftovers available for continuation.
_Avoid_: Fully accepted review, cleaned-up review

## Delivery

**Verdict**:
The referee's synthesized human-facing account of the issue set, its outcomes, supporting evidence,
and material process limitations.
_Avoid_: Report file, raw review

**Report**:
The durable document that contains a verdict together with identifying review metadata. It is the
user-facing delivery form of a verdict.
_Avoid_: Artifact, final response, verdict body
