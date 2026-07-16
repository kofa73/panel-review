# Referee context-cost reduction history

Status: Completed

Priority: Not applicable; retained design and verification history

Source: retired `fix_plan.md`, `analysis-codex.md`, and the named review-run evidence below

## Purpose

This record preserves the evidence, alternatives, decisions, and completed work behind the referee
context-cost changes. It is input for later architectural-evolution research and qualifying ADRs; it
is not remaining implementation work.

The only still-open proposal from the retired plan is tracked separately in
[`09-referee-judgment-offload-experiment.md`](09-referee-judgment-offload-experiment.md).

## Original problem and evidence

Run `panel-20260712-050026-4302ac32`, reviewing darktable pixelpipe code under `/workspace/hanno`,
used about 71% of a five-hour Claude window in Round 0 and one debate round. The protocol completed
normally: four subagents were spawned and the repository guard remained clean. The cost combined
inherent deep review of large source files with avoidable growth in the long-lived referee context.

The referee was the largest consumer in that run: approximately 2.82 million weighted tokens, 52% of
the run, 86 turns, and a peak context near 253K. Repeated cache reads made retained context expensive
across every later turn.

Two concrete avoidable detours were identified:

1. After an opaque `sweep plan` schema rejection, the referee searched and read `scripts/sweep` to
   reconstruct the expected JSON. The accepted schema required per-seat objects containing
   `seat`, a string-valued `batch`, and `expected_ids`; the failed hand-written plan used top-level
   `seats`, `ids`, and risked the integer-versus-string batch trap.
2. The Claude seat returned its full raw result to the referee, which then embedded the same result
   again in a Bash heredoc. Both copies remained in the referee context.

A later high-cost trace, `panel-20260712-185806-61199f6f`, reinforced the general diagnosis: the
referee made 122 API calls and accounted for about 16.85 million cache-read tokens, while the three
CLI barriers together were a small cost center. `analysis-codex.md` then proposed coarse deterministic
round operations, phase-specific loading, and seat-owned Claude raw delivery as the primary remedies.

## Completed Track A: plan diagnostics and scaffold

`scripts/sweep` now owns the common debate-plan shape:

- `validate_plan` reports field-specific reasons while retaining exit status 2 for invalid input;
- diagnostics cover unknown keys, the `ids`/`expected_ids` mistake, top-level shape, non-string batch
  names, invalid seats and IDs, duplicate `(seat,batch)` pairs, and duplicate expected IDs;
- `sweep plan-scaffold <ID> <round> <seat>...` emits one batch named `"1"` per supplied current-panel
  seat with sorted open issue IDs;
- the referee supplies the current preflight panel because panel availability is re-evaluated each
  round and must not become sticky from prior engagement;
- scaffold output round-trips through `sweep plan`, so the referee no longer hand-writes the common
  plan or reads script source to recover its schema.

The implementation retained the uniform `sweep <verb> <id> <round> ...` grammar. Focused sweep tests,
the full suite, README, protocol, and script/test documentation were updated with the implementation.

## Completed Track C: keep Claude raw output out of referee context

### Alternatives considered

The first proposal was to use the background Agent runtime's output-file path and copy or extract the
Claude seat result without displaying it. Runtime inspection on Claude Code 2.1.207 established that
background Agents expose `outputFile` and `canReadOutputFile`, and that the output target points to a
JSONL subagent transcript rather than a plain final-message file.

The retained evidence came from Claude session `4c476d67-6f29-4e8f-91b0-329a476e147b` under
`~/.claude/projects/-workspace-hanno/`. Its top-level record at line 39 launched referee Agent
`a89e7eb08ef227e89` with an output path under
`/tmp/claude-1000/-workspace-hanno/4c476d67-6f29-4e8f-91b0-329a476e147b/tasks/`. The referee's
subagent transcript at `subagents/agent-a89e7eb08ef227e89.jsonl:36` recorded Claude review seat
`a9ce72721d5637a3e` with the same `outputFile`/`canReadOutputFile` metadata. The corresponding
`.output` path was a symlink to the seat's JSONL transcript. The checked-in Claude Code changelog at
the time also described a fix for background-agent completion notifications missing their output
file path.

The seat's 6,861-character fenced findings block then appeared in the referee context twice: first
inside an 8,083-character background-completion notification, and again in the referee's Bash
heredoc. This trace established why copying or extracting the runtime output file could remove only
the second copy.

That fact did not make transcript extraction suitable for the primary path:

- the background-completion notification injects the seat's final message into the parent referee
  context regardless of the transcript path;
- extracting the transcript would remove the second heredoc copy but not the first completion copy;
- selecting the intended response would couple the plugin to undocumented transcript and tool-call
  structure;
- after a seat-owned write, the fenced block normally exists as tool input while the final assistant
  text is only a status stub, making transcript reconstruction more ambiguous.

The rejected fallback was therefore not merely unnecessary. It would have added a version-sensitive
recovery mechanism that reconstructed intent after the canonical write failed. The chosen failure
policy is to treat a missing or invalid raw file as a down Claude seat for that pass, record the
process failure, and never recover or inline content from the Agent transcript.

### Chosen contract and implementation

The Claude seat now receives the absolute derived raw destination in its assembled delivery
instructions. It constructs the complete fenced response in scratch, then invokes the dedicated
`write_seat_raw` helper. That helper:

- validates the run ID, round, optional batch, and every required fenced block;
- derives and restricts the destination under `/tmp/<ID>/raw/` rather than accepting an arbitrary
  output path;
- atomically installs the validated bytes; and
- is the Claude seat's sole permitted write outside its scratch directory.

After a successful write, the seat returns only `CLAUDE_SEAT_RAW_WRITTEN`; failure returns only
`CLAUDE_SEAT_RAW_FAILED`. The referee ignores the stub's content and collects the expected raw path.
There is no heredoc, transcript extraction, or returned-text fallback. Round 0, debate's required two
blocks, invalid input, missing writes, stale uncheckpointed raw data, and atomic installation are
covered by focused tests.

This preserves blindness: the seat writes only its own response, sees no other seat output or tally,
and remains a fresh, never-forked review subagent.

## Completed deterministic replacement for most of former Track B2

The retired plan considered offloading stance-to-payload synthesis to another model helper. Later
work made nearly all of that path deterministic instead:

- `round commit` selects complete active-plan batches and invokes `decide_round` or
  `decide_degraded_round`;
- those scripts own stance counting, coverage, counters, flags, evidence promotion, enum-field
  convergence, and forced terminal transitions;
- `merge_payload`, `sweep`, and `index` validate, merge, and commit the complete transaction
  atomically;
- `round commit` requests a judgment addendum without mutation only when prose revisions or new
  findings require actual referee judgment.

Moving these mechanics to a helper Agent would now replace deterministic code with model-mediated
work and is not proposed. The remaining Round-0 clustering and exceptional debate-judgment seams are
the conditional experiment in issue 09.

## Completed Track D and retained grammar decision

The debate protocol previously wrote expected IDs to `/tmp/$id/batch.$round.$batch.ids` but showed
`sweep ingest-batch` reading `/tmp/$id/batch.$round.$seat.$batch.ids`. The implementation standardized
on one shared file per batch:

```text
/tmp/$id/batch.$round.$batch.ids
```

No script behavior change was required because `cmd_ingest_batch` already accepts the expected-ID
path explicitly. Focused sweep tests, the full suite, and `git diff --check` passed after the protocol
correction.

`plan-scaffold` still accepts a syntactically required but operationally unused `<round>` argument.
This is deliberate. It preserves the uniform command grammar and avoids a migration hazard where an
old caller's numeric round could be accepted as a seat name. If the command grammar is ever redesigned
as a whole, change `main()`, `USAGE`, the protocol/SKILL call sites, and tests together; do not exempt
this one verb independently.

## Measurement and resulting decisions

The later version-1.0.8 representative run recorded in `pending.md` showed that coarse commands and
phase-specific loading reduced referee calls and input-context substantially relative to the earlier
baseline. The referee was no longer the dominant cost center; Claude review seats were. The
version-1.0.9 same-diff experiment then showed no API-call reduction from explicit seat batching and
multi-symbol lookup guidance, so those preferences were reverted while redundant-read avoidance,
sufficient-evidence stopping, and the absence of a hard tool-call cap were retained.

Consequences:

- keep the Opus referee unless a separate quality A/B supports a change;
- do not prioritize the CLI barrier, whose measured cost is small and whose wake-up role is required;
- do not assume a helper Agent is a saving: measure its cold-start cost and retained-context benefit;
- evaluate Round-0 judgment offload before any conditional debate-judgment offload;
- do not combine helper offload and model selection in one experiment.

Exact later benchmark totals, limitations, matched-pass comparisons, and run paths remain in
`pending.md`; `analysis-codex.md` remains the authoritative measured recommendation report.

## Deliberate non-goals

- Do not change the three-way blind protocol, unanimity-or-human lifecycle, or persistence model to
  reduce cost.
- Do not add controls that assume a malicious seat; the trust model rejects that security theatre.
- Do not treat deep seat-side investigation of large target files as an orchestration defect.
- A possible preference for outline/symbol inspection over full-file reads is a separate seat-quality
  experiment, not part of the referee-context design.
- Do not parse internal Agent transcripts as a normal or recovery dependency.
