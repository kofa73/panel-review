# Architectural evolution

Status: historical record, reconstructed from the repository through commit `5082f6e` (2026-07-18)

This document explains how Panel Review reached its current architecture. It is not a second runtime
specification. Current public behavior belongs in [`README.md`](../README.md), current vocabulary in
[`CONTEXT.md`](../CONTEXT.md), executable ownership in [`CONTRACTS.md`](../CONTRACTS.md), and the
live referee procedure in
[`skills/panel-review-for-agent/references/protocol.md`](../skills/panel-review-for-agent/references/protocol.md).

Commit ranges are inclusive. A range written as `A^..B` starts with commit `A`. Status applies to the
decision described, not necessarily to every implementation detail introduced in the same range.

## Decision records extracted from this history

Seven decisions satisfy all three repository ADR criteria: they are costly to reverse, surprising
without their rationale, and the result of a real trade-off.

- [`ADR 0001`](adr/0001-keep-review-and-arbitration-separate.md): keep review and arbitration
  separate, and require unanimity or human judgment.
- [`ADR 0002`](adr/0002-treat-external-seats-as-symmetric-optional-peers.md): treat Codex and Gemini
  as symmetric optional peers.
- [`ADR 0003`](adr/0003-use-explicit-review-lifecycle-verbs.md): expose review-run intent through
  explicit lifecycle verbs, including continuation cycles.
- [`ADR 0004`](adr/0004-separate-model-judgment-from-deterministic-mechanics.md): keep semantic
  judgment in the referee and mechanical transitions in deterministic owners.
- [`ADR 0005`](adr/0005-use-tool-capable-seats-with-honest-drift-restoration.md): run tool-capable
  seats under a disposable-environment and honest-drift-restoration trust model.
- [`ADR 0006`](adr/0006-keep-bulk-review-content-out-of-long-lived-contexts.md): keep bulk review
  content out of long-lived orchestration contexts.
- [`ADR 0007`](adr/0007-deliver-reports-through-a-durable-validated-artifact.md): deliver reports
  through one durable, validated artifact.

No ADR was created for the CLI wake barrier, prompt schema/repair iterations, or marketplace path:
those are replaceable implementation mechanisms or lack evidence for a durable trade-off. The
referee-helper, referee-model, and settled-claim-catalogue ideas remain unmeasured proposals, so
recording them as accepted decisions would be premature.

## Milestone summary

| Date | Decision milestone | Evidence | Status |
|---|---|---|---|
| 2026-06-20 | Separate the non-reviewing referee from three blind review seats; require unanimity or human judgment | `3869ec4` | Implemented and retained |
| 2026-06-20 | Treat Codex and Gemini as symmetric optional peer seats | `9aa417c^..8cb49aa` | Implemented and retained |
| 2026-06-20–21 | Preserve finished leftovers and reopen them as a new continuation cycle | `a34eca6^..6be3f56`, later `c6a3020` | Implemented and retained |
| 2026-06-21 | Replace implicit fresh/resume inference with explicit plugin verbs | `b201ad8^..6a33aa7` | Implemented; command set later extended |
| 2026-06-21–07-18 | Make a durable, validated report artifact the delivery boundary | `8d4c8ed`, `c32936e`, `65762e0`, `b845d9f`, `177f48f` | Implemented; exact stub enforcement is bounded |
| 2026-06-24 onward | Move state transitions and normal-path mechanics from referee prose into deterministic modules | `764c60b^..e8571a8`, `60686f4^..907c7ad`, `65762e0`, `40792f9`, `31c4baa` | Implemented and retained |
| 2026-06-28–07-09 | Permit tool-capable seats under an explicit trust model; harden prompt delivery and make salvage referee-owned | `ef7c9a7`, `b32b20c^..1e45ec1` | Partly retained; two mechanisms were superseded |
| 2026-06-30–07-04 | Use a background Agent as the CLI completion barrier | `a15413c^..5747dc3` | Implemented and retained |
| 2026-07-14–16 | Reduce long-lived referee context with coarse commands, phased protocol loading, and seat-owned Claude raw writes | `c32936e`, `65762e0` | Implemented; further helper offload remains proposed |
| 2026-07-16–18 | Give executable contracts named owners and remove duplicated instruction paths | `306d9c6^..40792f9`, `31c4baa` | Implemented and retained |

## 1. Founding architecture: blind seats, a non-reviewing referee, and unanimity

**Evidence.** Commit `3869ec4` (2026-06-20), including the initial README, referee and Claude-seat
definitions, protocol skill, and wrapper scripts.

The initial import already contained the architecture that still defines the product:

- Claude, Codex, and Gemini review the same scope independently in Round 0;
- a separate referee clusters their findings and administers debate but does not review the target;
- the Claude seat is a fresh, never-forked subagent on every pass;
- seat-facing cards omit origins and stance tallies;
- an issue settles only by unanimous support or unanimous rejection among a quorum, otherwise it is
  handed to the human; and
- canonical state lives under `/tmp/<ID>/`, while worktree cards are a derived cache.

**Rationale.** Explicit: the imported design says the earlier upstream arrangement let the
orchestrator act as the Claude reviewer and remember its own findings. Separating the referee and
spawning a cold Claude seat made the Claude contribution blind. It also says that hiding technical
points would cripple verification, while hiding origins and the numerical alignment removes the
conformity signal that matters. Majority rule was rejected because the panel is an issue-finding aid,
not an autonomous authority. Sources: `3869ec4:ORIGINAL_README.md`,
`3869ec4:agents/panel-review-referee.md`, and
`3869ec4:agents/panel-review-claude-seat.md`.

**Inference.** The initial import already preferred wrapper-owned writes, parsing, and state math,
but those boundaries were still substantially enforced by referee instructions. Later milestones
turned more of that discipline into deterministic interfaces and tests. This is inferred from the
initial protocol and script layout compared with the current [`README.md`](../README.md) wrapper map;
the initial sources do not state a staged plan to do so.

**Status:** implemented and retained. The current role split and consensus boundary are exercised by
[`tests/python/test_decide_round.py`](../tests/python/test_decide_round.py),
[`tests/python/test_round.py`](../tests/python/test_round.py), and the protocol contract checks in
[`tests/run_tests.sh`](../tests/run_tests.sh).

## 2. Symmetric, optional peer seats

**Evidence.** Commits `9aa417c^..8cb49aa` (2026-06-20), the optional-peer design and plan, and the
corresponding preflight, Codex-wrapper, referee, and documentation changes.

The first post-import redesign removed the inherited assumption that Codex was mandatory while
Gemini was merely an optional add-on. Preflight began requiring Claude plus either external peer,
reporting Codex and Gemini availability symmetrically. `run_codex` also received a Panel Review-owned
profile copied from a shipped template.

**Rationale.** Explicit: the approved design identifies the asymmetry as residue from the two-seat
upstream project. Once Panel Review had three independent seats, Codex and Gemini served the same peer
role; requiring one named peer unnecessarily prevented a valid two-seat panel. A separate Codex
profile avoided silently coupling Panel Review tuning to the upstream tool, and point-of-use profile
creation kept preflight read-only. Sources:
[`docs/superpowers/specs/2026-06-20-optional-peer-seats-design.md`](superpowers/specs/2026-06-20-optional-peer-seats-design.md),
[`docs/superpowers/plans/2026-06-20-optional-peer-seats.md`](superpowers/plans/2026-06-20-optional-peer-seats.md),
and the changes to the then-current `preflight`, `run_codex`, referee protocol, and README in the
commit range.

**Inference.** This was the point where “configured panel” and “engaged seats in this pass” began to
need distinct meanings, although that vocabulary and the degraded terminal path became more explicit
later. The symmetric preflight change alone did not establish all of today's per-pass engagement
semantics.

**Status:** implemented and retained. Current sources are [`scripts/preflight`](../scripts/preflight),
[`scripts/run_codex`](../scripts/run_codex), and the “Graceful degradation” section of
[`README.md`](../README.md).

## 3. Finished reviews became continuable review runs

**Evidence.** Commits `a34eca6^..6be3f56` (2026-06-20–21), with transcript preservation added by
`c6a3020` (2026-07-11); the continuation design/plan and current reopen implementation.

The original resume mechanism continued an interrupted debate. This milestone added a different
operation: reopen selected `contested` or `unresolved` leftovers after a finished cycle, reset their
debate budget, preserve their evidence and settled siblings, and run another cycle against the same
scope snapshot. `run_epoch` prevented stale sweeps from an earlier cycle from being replayed. The
later epoch archive moved previous-cycle files before their round-numbered names could be reused.

**Rationale.** Explicit: the approved design says close calls should be debatable further without
re-reviewing settled issues or discarding the arguments already accumulated. Reopened issues are
made ordinary open issues so the existing resume path can process them; deterministic scripts own
the reset rather than adding a second referee state machine. Scope/diff equality is required because
continuing old arguments over changed code is unsound. The follow-up simplification explicitly
rejected staging and lock machinery as redundant under the epoch invariant and the single sequential
referee assumption. Sources:
[`docs/superpowers/specs/2026-06-20-continue-leftovers-design.md`](superpowers/specs/2026-06-20-continue-leftovers-design.md),
[`docs/superpowers/plans/2026-06-20-continue-leftovers.md`](superpowers/plans/2026-06-20-continue-leftovers.md),
commit messages for `da2c352` and `6be3f56`, and current
[`scripts/reopen`](../scripts/reopen).

**Inference.** Archiving prior cycle files in `c6a3020` makes the distinction between a durable review
run and one continuation cycle concrete. The commit message describes overwrite prevention, not a
formal domain-model decision; the domain interpretation is therefore inferred.

**Status:** implemented and retained. The historical specs use the retired `--continue` flag, but the
behavior now belongs to `panel-review:continue`; that interface change does not supersede the
continuation model. Current verification is in [`tests/python/test_index.py`](../tests/python/test_index.py),
[`tests/python/test_sweep.py`](../tests/python/test_sweep.py), and continuation cases in
[`tests/run_tests.sh`](../tests/run_tests.sh).

## 4. Explicit command verbs and plugin packaging

**Evidence.** Author instructions in `7ebbf1d`; command/plugin redesign in `b201ad8^..6a33aa7`
(2026-06-21); local marketplace added in `5023150` (2026-07-05); read-only result retrieval added in
`c32936e` (2026-07-14).

The single overloaded command originally inferred fresh, resume, continue, or discard intent from
stored state and repeated arguments. It was replaced by namespaced skills with explicit
preconditions: `start`, `status`, `resume`, `continue`, and `discard`. `result` later became a sixth
read-only verb. Only `start` accepts scope and author instructions; resume and continue adopt them
from the manifest.

**Rationale.** Explicit: the command design records three coupled problems: intent was inferred from
disk state, resume required retyping the original scope, and the newly added author instructions had
to match byte-for-byte even though a mismatch was reported with the same `moved` state as changed
code. Explicit verbs made intent user-supplied and made each command's accepted arguments and
mutation behavior deterministic. Read-only `status` remains model-invocable; the four mutating verbs
are user-only, especially `discard`. Sources:
[`docs/superpowers/specs/2026-06-21-subcommands-design.md`](superpowers/specs/2026-06-21-subcommands-design.md),
[`skills/start/SKILL.md`](../skills/start/SKILL.md),
[`skills/status/SKILL.md`](../skills/status/SKILL.md), and the other command skills.

`7ebbf1d` explicitly framed author instructions as neutral emphasis shared by all seats, never as a
filter that can suppress defects. Its original decision to include instructions in resume identity
was superseded by the explicit-verb design: stored instructions are now adopted rather than retyped.

**Inference.** Namespacing also made the repository a coherent distributable component instead of a
set of globally named skills and agents. The design explicitly discusses collision avoidance and
component qualification, but the broader “coherent component” characterization is an inference.

**Status:** implemented, with two extensions. The original design's five-command set was extended by
`result`. Its explicit “skills-dir only, not a marketplace” distribution choice was superseded in
practice by `5023150`: the current [`README.md`](../README.md) supports both `install.sh` and the
repository's local marketplace. The commit adding the marketplace is titled only “cleanup” and does
not record why the earlier distribution decision was reopened.

## 5. Verdict delivery moved from conversation text to a durable report boundary

**Evidence.** Initial artifact `8d4c8ed` (2026-06-21); validated retrieval and phased protocol split
`c32936e` (2026-07-14); artifact-only returns and delivery validation `65762e0` (2026-07-16); removal
of the worktree verdict dependency `b845d9f` (2026-07-16); bounded status-stub hook `177f48f`
(2026-07-18).

The first artifact change wrote each verdict to `/tmp/<ID>.md`, a sibling of the canonical run
directory so normal cleanup and discard would not delete it. At that stage the referee still returned
the verdict body. Later changes bound the report to the continuation epoch and index hash, introduced
validated `result` and `--delivery` reads, made the command return only a validated filename and
minimal control status, and removed the temporary worktree verdict copy. A failed durable write now
keeps the run resumable and blocks cleanup.

**Rationale.** Explicit: the artifact design says a clean finish destroys run state, so a conversation
transcript was an insufficient sole copy. The sibling path survives cleanup without polluting the
reviewed tree. Later failure evidence showed that a referee could finish and persist a correct report
but exhaust or misformat its final Agent response; delivery therefore had to be recoverable and
validated independently of that model return. The worktree copy was then removed because it was not
a delivery surface yet could prevent the durable write. Sources:
[`docs/superpowers/specs/2026-06-21-verdict-artifact.md`](superpowers/specs/2026-06-21-verdict-artifact.md),
[`issues/02-artifact-only-verdict-persistence.md`](../issues/02-artifact-only-verdict-persistence.md),
[`scripts/write_verdict_artifact`](../scripts/write_verdict_artifact),
[`scripts/read_verdict_artifact`](../scripts/read_verdict_artifact), and
[`tests/python/test_verdict_artifact.py`](../tests/python/test_verdict_artifact.py).

The status hook's explicit rationale is narrower: real version-1.0.11 Agent notifications prefixed
the required status with prose, causing completed raw review or verdict summaries to enter the caller
context even though the final command still delivered only the validated filename. The hook keeps the
same subagent running and asks it to correct the response, avoiding repeated review or persistence
work. Source:
[`issues/13-enforce-agent-status-stub-boundaries.md`](../issues/13-enforce-agent-status-stub-boundaries.md).

**Inference.** Artifact-only delivery is also a context-budget decision because it keeps verdict and
raw-seat bodies out of parent model contexts. The repository records both correctness/recovery and
context-cost evidence, so an ADR should not reduce the choice to only one of those motives.

**Status:** implemented and retained. The hook is intentionally bounded conformance enforcement, not
an absolute isolation or security boundary: Claude Code stops a subagent after eight consecutive
hook blocks. Deterministic user-visible delivery remains owned by `read_verdict_artifact`.

## 6. Deterministic modules replaced model-mediated mechanics

**Evidence.** First large extraction `764c60b^..e8571a8` (2026-06-24); debate-plan diagnostics
`60686f4^..907c7ad` (2026-07-12); coarse `round` operations `65762e0` (2026-07-16); executable seat
contract `40792f9` (2026-07-16); duplicate normal commit path removed in `31c4baa` (2026-07-18).

The initial referee protocol described many state transformations for the model to perform. The June
24 extraction introduced deterministic decision, degraded-decision, payload-merge, birth-index,
seat-dispatch, and sweep modules, then migrated the stateful Python-sized scripts with unit tests.
Later work made the debate plan shape scaffoldable and diagnostic, introduced coarse `round`
preparation/collection/commit interfaces, and made `round commit --addendum` the sole normal-path
owner of validation, merge, atomic sweep commit, and card regeneration.

**Rationale.** Explicit: `764c60b` names the objective directly: move mechanical debate logic out of
the referee. The initial README had already required scripts for byte-exact flags, writes, index math,
and parsing. The plan-scaffold history records a concrete failure where an opaque schema rejection
made the referee inspect `sweep` and reconstruct JSON, enlarging context and risking another invalid
plan. The addendum issue records a later live run in which duplicate high- and low-level instructions
caused the referee to merge the same addendum manually and then ask `round` to do it again. Sources:
[`issues/referee-context-cost-history.md`](../issues/referee-context-cost-history.md),
[`issues/14-remove-duplicate-addendum-commit-instructions.md`](../issues/14-remove-duplicate-addendum-commit-instructions.md),
[`scripts/round`](../scripts/round), and [`scripts/sweep`](../scripts/sweep).

**Inference.** The architecture is a deliberate judgment/mechanics split, not an attempt to remove
the referee. Clustering findings, deciding whether later findings fold or become issues, synthesizing
prose revisions, and writing the verdict remain model judgments because the current deterministic
interfaces cannot decide semantic identity or write the human explanation. This boundary is explicit
in the current protocol; interpreting the sequence of extractions as the gradual realization of that
boundary is an inference.

**Status:** implemented and retained. The shell and Python suites under [`tests/`](../tests) now test
the mechanical interfaces directly. Replacing these mechanics with another model helper was
explicitly rejected in the retained context-cost history.

## 7. Tool-capable seats, tracked-tree restoration, and prompt robustness

**Evidence.** Tool access and repository guard `ef7c9a7` (2026-06-28); blind-pass robustness
`b32b20c`; repair ownership correction `1e45ec1` (2026-07-09).

Seats were allowed to use tilth and throwaway scratch scripts, and Codex began running with its
sandbox bypassed. `repo_guard` snapshots tracked content and restores honest tracked-file drift after
each pass. The later robustness work stopped inlining large diffs, supplied absolute review-root and
card anchors, moved the output contract to a salient prompt position, made debate `new_findings`
required-emptyable, and addressed usable but misformatted seat output.

**Rationale.** Explicit: the current trust model says safety rests on an isolated disposable
environment plus restoration of tracked repository content, not on a seat sandbox. Since the seats
are unconstrained and could defeat cooperative checks, hashes, permissions, and attestations must not
be presented as protection from a malicious seat. Guards target honest accidents and model
confusion. Sources: [`AGENTS.md`](../AGENTS.md), the “Read-only review contract” section of
[`README.md`](../README.md), [`scripts/repo_guard`](../scripts/repo_guard), and
[`design-notes/blind-pass-robustness.md`](../design-notes/blind-pass-robustness.md).

The robustness note separately records observed evidence: very large inlined prompts correlated with
Gemini returning prose without a required fence, and agy's managed tool sandbox could guess the wrong
repository root. Externalizing the canonical diff reduced prompt size, while absolute anchors tell
agy what `cwd` to set. The note labels the prompt-size causal mechanism empirical rather than proven.

**Inference.** These changes trade preventive confinement for reviewer capability and post-pass
restoration. That trade follows from the explicit trust model and wrapper flags, but no single commit
message states it in those exact terms.

**Status:** mixed at the mechanism level.

- Implemented and retained: diff-file reference, absolute anchors, required-emptyable debate output,
  broad seat capability, tracked-tree restoration, and the honest-accident trust model.
- Superseded: `b32b20c`'s script-level repair/re-dispatch path. `1e45ec1` made salvage referee-owned
  because deciding whether prose is a real completed review or a down-seat error is judgment, and a
  new CLI model invocation is not the original seat merely reformatting its own response.
- Superseded: the small prompt schema fragments added in `b32b20c`. `40792f9` replaced them with the
  executable [`scripts/seat_contract.py`](../scripts/seat_contract.py) owner.

## 8. Reliable asynchronous seat completion without referee polling

**Evidence.** Commits `a15413c^..5747dc3` (2026-06-30–07-04), current `await_seats` and CLI-barrier
agent sources, and their tests.

CLI seats can run much longer than a foreground Bash call. `await_seats` first consolidated their
parallel execution and timeout accounting. Direct background Bash still did not reliably wake the
referee, so a small background `panel-review-cli-barrier` Agent was introduced to run the barrier and
return when its completion sentinel appears.

**Rationale.** Explicit: repeated referee polling wasted turns and replayed the referee's accumulated
context. More importantly, a background Bash completion is routed to the root session rather than
re-invoking the referee subagent, while a background Agent reliably wakes its spawner. The completion
sentinel carries `await_seats`' exit status even when the normal done-summary is absent, preventing a
setup failure or wedged job from being mistaken for a settled pass. Sources:
[`agents/panel-review-cli-barrier.md`](../agents/panel-review-cli-barrier.md),
[`scripts/await_seats`](../scripts/await_seats), and the current wrapper description in
[`README.md`](../README.md).

**Inference.** The barrier is an event-delivery adapter for Claude Code, not a review participant or a
general-purpose worker. Its deliberately small context and lack of review authority support that
interpretation.

**Status:** implemented and retained. Later measurements found the barriers to be a small cost center
with a material reliability role, so the project explicitly chose not to optimize them first. See
[`issues/referee-context-cost-history.md`](../issues/referee-context-cost-history.md).

## 9. Referee context-cost reduction without changing review semantics

**Evidence.** Artifact recovery and initial protocol reference split `c32936e` (2026-07-14); coarse
round operations, phase loading, and Claude seat-owned raw persistence `65762e0` (2026-07-16).

Measured review runs showed that the long-lived Opus referee repeatedly replayed a large accumulated
context. The response was architectural rather than a smaller prompt alone:

- `round` owns normal preparation, compact collection, and deterministic commit work;
- `read_protocol_phase` loads common, active-mode, exceptional, and final-synthesis instructions only
  when needed;
- the Claude seat validates and atomically writes its complete raw response through
  `write_seat_raw`, then returns a short status; and
- the long-lived referee keeps only the semantic judgment seams that have not been made
  deterministic.

**Rationale.** Explicit: the retained history records a run in which the referee was the largest
consumer, with avoidable script-reading after a plan rejection and duplicate Claude raw content in a
completion notification and a referee write. A later working-tree report, `analysis-codex.md`,
measured 10,108,204 input-context tokens in another run, 54.2% in the referee, while the CLI barriers
used 4.3%; it recommended coarse operations, phase-specific protocol loading, validated artifact
recovery, and seat-owned raw writes before model substitution. The checked-in synthesis is
[`issues/referee-context-cost-history.md`](../issues/referee-context-cost-history.md).

The untracked working analyses `analysis-2026-07-14-04-15-56.md` and
`analysis-2026-07-15-16-21-30.md` corroborate the same conclusions and explicitly caution that the
protocol split avoids duplicate initial injection but cannot remove already-read text from later
context replay. They are local evidence, not durable repository authority.

**Inference.** The chosen changes optimize the multiplier—long context times many referee turns—while
preserving the three-seat review semantics. This description follows the measured analysis, but the
exact saving attributable to each change cannot be isolated from the available multi-change runs.

**Status:** implemented for coarse operations, phased loading, and Claude raw delivery. Most of the
former “judgment offload” idea was superseded because transitions and payload mechanics are now
deterministic. A fresh helper for Round-0 clustering remains **proposed and conditional**, not
accepted architecture: [`issues/09-referee-judgment-offload-experiment.md`](../issues/09-referee-judgment-offload-experiment.md)
requires a controlled measurement showing a material net saving without worse clustering, origins,
quality, or reliability. Debate-judgment offload is conditional on that first experiment succeeding.

## 10. Executable contract ownership and semantic cleanup

**Evidence.** Stance semantics `306d9c6`; artifact persistence `b845d9f`; referee mutation wording
`5837859`; Claude debate contract `be3cfe8`; shared executable contract `40792f9` (all 2026-07-16);
duplicate normal commit instructions removed in `31c4baa` (2026-07-18).

An instruction audit found that agent definitions, prompts, protocol prose, schema fragments,
parsers, state-transition code, tests, and user documentation repeated the same invariants and had
drifted. The repository responded by assigning one owner per invariant rather than creating one
monolithic specification.

The most visible semantic correction removed `support_with_revision`. A seat now chooses only
`support` or `reject`; a support stance may independently propose a detail revision. Reject requires
counter-evidence and cannot mutate issue details. This separates issue existence from proposed field
values while retaining consensus rules for adopting revisions.

**Rationale.** Explicit: the seat-contract issue says “one source of truth” means one owner per
invariant. `seat_contract.py` owns seat fields, block cardinality, stance values, normalization, and
rendered instructions; the phase protocol plus transition scripts own orchestration and lifecycle;
the barrier owns waiting; verdict scripts own report persistence and delivery; agent definitions own
identity and role limits; README owns public explanation. `check_contracts` tests assembled variants
and runtime payloads instead of relying only on phrase scans. Sources:
[`issues/05-instruction-contract-single-source.md`](../issues/05-instruction-contract-single-source.md),
[`CONTRACTS.md`](../CONTRACTS.md), [`scripts/seat_contract.py`](../scripts/seat_contract.py), and
[`scripts/check_contracts`](../scripts/check_contracts).

The stance rationale and implementation evidence are in
[`issues/01-stance-contract-semantics.md`](../issues/01-stance-contract-semantics.md).
The narrower referee mutation and Claude two-block corrections are documented in
[`issues/03-referee-mutation-contract.md`](../issues/03-referee-mutation-contract.md)
and
[`issues/04-claude-debate-output-contract.md`](../issues/04-claude-debate-output-contract.md).

**Inference.** This milestone makes the repository easier for both models and deterministic tests to
navigate because a reader can follow ownership rather than reconcile copies. That maintainability
benefit is implicit in the drift diagnosis; runtime consistency is the explicitly tested objective.

**Status:** implemented and retained. The old `support_with_revision` vocabulary and prompt schema
fragments are superseded. Current verification is concentrated in
[`tests/python/test_contract_consistency.py`](../tests/python/test_contract_consistency.py), parser and
decision tests, and `tests/run_tests.sh`.

## Decisions that remain proposed or superseded

### Still proposed

- **Referee judgment offload:** only a controlled Round-0 clustering experiment is open, and only if
  new profiling shows the referee judgment context is again material. Debate judgment offload is a
  conditional follow-up. No helper is part of current architecture.
- **Referee model selection:** a cheaper controller with short-lived higher-capability judgment
  helpers was recommended for A/B testing in the working analyses, but no quality comparison has
  established it as an accepted decision. It is tracked separately in
  [`issues/10-model-selection-ab-test.md`](../issues/10-model-selection-ab-test.md).

### Superseded

- The single overloaded `/panel-review` interface and instructions-as-resume-identity were replaced
  by explicit verbs that adopt stored scope and instructions.
- The original five-command plugin was extended with the read-only `result` command.
- The subcommand design's “skills-dir only” distribution was extended to support a repository-local
  marketplace as an independent install path.
- Script-driven model re-dispatch for malformed/no-fence output was replaced by referee-owned salvage
  of already-completed CLI review output; Claude output instead fails closed at `write_seat_raw`.
- Static prompt schema fragments were replaced by `seat_contract.py` and rendered contracts.
- The worktree verdict snapshot was removed; `/tmp/<ID>.md` is the sole report delivery artifact.
- `support_with_revision` was removed; support and optional detail revision are orthogonal fields.
- Model-mediated low-level transition and commit sequences were replaced by deterministic modules and
  the coarse `round` interface.

## Unresolved evidence questions for ADR work

The research found no uncertainty that blocks ADR classification for the founding role separation,
unanimity-or-human rule, deterministic state ownership, explicit verbs, continuation cycles,
artifact-only report delivery, honest-accident trust model, or phased/coarse referee interfaces.

Two narrower claims should not be promoted into accepted ADR rationale without additional evidence:

1. **Why the marketplace path was added.** `5023150` implements the local marketplace but its
   “cleanup” commit message and changed files do not record why the earlier skills-dir-only decision
   was reopened. An ADR may record that dual installation exists; it should not invent the rationale.
2. **Why Gemini omitted the fence in the trigger runs.** Prompt size and buried instructions are a
   documented correlation and plausible mechanism, not proven causation. An ADR can record the
   external-diff and absolute-anchor choices and their observed evidence, but should preserve this
   uncertainty.

The bounded eight-block limit on the status-stub hook is resolved evidence, not an open question: an
ADR must describe bounded conformance against accidental model output, not guaranteed isolation from
an adversarial or indefinitely nonconforming model.
