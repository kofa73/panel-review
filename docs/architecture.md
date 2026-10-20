# Architecture and saved state

This page describes the current component boundaries and the files that carry a review run. The
[README](../README.md) defines the operator workflow and public behavior. [`CONTRACTS.md`](../CONTRACTS.md)
names executable ownership, and [`.claude/rules/scripts.md`](../.claude/rules/scripts.md) maps each
script to its implementation details.

## Components

Panel Review has three review seats and a referee. Claude, Codex, and Gemini inspect the same scope.
The referee coordinates them, clusters findings, runs debate, and writes the verdict. It does not
review the code or decide technical correctness on its own.

| Component | Owns | Entry point |
|---|---|---|
| Command skills | Parse public commands, check preconditions, dispatch the referee, and validate report delivery. | `skills/{start,status,resume,continue,result,discard}/SKILL.md` |
| Referee | Review orchestration, finding clustering, debate judgment, and verdict prose. | `agents/panel-review-referee.md` |
| Referee protocol | The canonical phase procedure and its judgment points. The bootstrap loads only the active marked phase. | `skills/panel-review-for-agent/references/protocol.md` via `scripts/read_protocol_phase` |
| Claude seat | One fresh, blind Claude review pass. It writes its validated response through `write_seat_raw`. | `agents/panel-review-claude-seat.md` |
| CLI barrier | Concurrent Codex and Gemini calls and their completion signal. It runs as a foreground Agent alongside the Claude seat. | `agents/panel-review-cli-barrier.md` and `scripts/await_seats` |
| Seat wrappers | Pin each CLI's invocation flags and model request, capture output, and report the model when available. | `scripts/run_codex`, `scripts/run_agy`, and `scripts/run_seat` |
| Round coordinator | Prepare and collect Round 0, prepare debate batches, gather verdict input, and commit the normal debate transaction. | `scripts/round` |
| State owners | Validate seat output and issue state, mutate the index, and project blind cards. | `scripts/seat_contract.py`, `scripts/index`, `scripts/sweep`, `scripts/project_card`, and `scripts/regen_cards` |
| Report boundary | Persist a durable verdict and validate it before user-visible delivery. | `scripts/write_verdict_artifact` and `scripts/read_verdict_artifact` |

The referee dispatches the CLI barrier and Claude seat together. Claude Code runs those foreground
Agent calls concurrently and returns control only after both finish. This keeps seat waiting outside
the referee's context. The Claude seat is spawned by its named agent type, never as a fork, so it
starts without the referee's findings or stance tally.

The normal path follows this sequence:

1. A command skill resolves the scope, settings, and review-profile snapshot, then creates a run.
2. The referee dispatches the blind Round-0 pass and retries down seats under the same frozen prompt.
3. The referee clusters independent findings and `birth_index` installs the initial issue index.
4. `round` prepares debate batches. Seats return stances and findings, and `sweep` validates and
   commits complete batches.
5. The referee writes a verdict. The command validates the artifact and returns its filename.

The [README lifecycle section](../README.md#how-an-issue-moves-transitions) defines issue outcomes.
No seat sees finding origins or the stance tally. Cards omit both.

## State ownership

`/tmp/<ID>/` is the canonical run state. The workdir copy under `.panel-review/<ID>/` contains
regenerable blind cards and the `.panel-run` marker. `regen_cards` rebuilds the cards but does not
recreate the marker. `resume_check` discovers saved runs through the marker, so keep it with retained
state. `init_run` writes canonical state first and publishes the marker last. A marker therefore
means initialization reached that final step, though a later missing or corrupt file can still make
the run stale.

| Path | Owner and purpose |
|---|---|
| `/tmp/<ID>/manifest.json` | `init_run` records the run ID, workdir, scope, effective limits, diff hash, instructions, review-profile metadata, divergence snapshot, and creation time. |
| `/tmp/<ID>/review-profile.md` | `stage_review_profile` stores the exact profile bytes used by every seat and phase. The manifest keeps the source path and its size and hash as provenance. |
| `/tmp/<ID>/diff.txt` | `resolve_diff` writes the resolved diff used by the run. The manifest's `diff_hash` identifies its contents. |
| `/tmp/<ID>/round0.panel.json` and `/tmp/<ID>/round0.attempts.json` | `round` freezes the configured Round-0 panel and records initial, retry, and resume attempts. The same prompt and panel remain fixed while Round 0 is incomplete. |
| `/tmp/<ID>/index.json` | `index` and `sweep` own the canonical issue state. `birth_index` creates it from the referee's clustered findings. Cards and verdicts are derived from this index, never used to reconstruct it. |
| `/tmp/<ID>/sweeps/` | `sweep` owns debate plans and batch checkpoints. A complete batch retains its raw response, parsed stances and new findings, status, expected IDs, and source provenance together. |
| `/tmp/<ID>/raw/` and parsed outputs | Seat wrappers retain the raw responses; `parse_block` produces the parsed form. Round 0 considers a seat pass complete only when its raw response, successful parse status, and parsed output agree. |
| `/tmp/<ID>/origins/` | The referee's private records preserve finding origins, original wording, and stances. They are not projected onto cards. |
| `/tmp/<ID>/audit/` | `index commit-sweep` writes a human-readable record of committed issue changes. The review process does not read it back. |
| `/tmp/<ID>/epochs/` | `reopen` snapshots a finished debate cycle before `continue` reuses round-numbered paths. These snapshots are for inspection. |
| `/tmp/<ID>/work/<seat-token>/` | Each seat's scratch files stay outside the reviewed repository. This prevents an ordinary repository search from returning another seat's scratch as a hit; it does not restrict a seat that deliberately reads shared `/tmp` state. |
| `<workdir>/.panel-review/<ID>/issue-<id>.md` | `project_card` and `regen_cards` render the blind cards from `index.json`. They are a disposable cache. |
| `/tmp/<ID>.md` | `write_verdict_artifact` writes the durable report as a sibling of the state directory, so normal cleanup does not remove it. |

`panel_atomic_write` installs state files through a same-directory temporary file and rename. The
`index` and `sweep` commands are the only writers of `index.json`; `project_card` and `regen_cards`
are the only card writers. The workdir holds one review at a time. Concurrent sessions against the
same workdir are unsupported.

## Schemas

The validators in the named owners define accepted values. These shapes show the fields that readers
need to locate; they do not replace validation in code.

### Manifest

`manifest.json` contains:

```json
{
  "id": "panel-...",
  "workdir": "/path/to/repository",
  "scope": "...",
  "limits": {
    "issue_rounds": 2,
    "max_rounds": 4,
    "seat_timeout_seconds": 2400
  },
  "diff_hash": "...",
  "instructions": "...",
  "review_profile": {
    "selector": "builtin:generic",
    "source_path": "...",
    "size": 1,
    "sha256": "..."
  },
  "divergence_snapshot": {},
  "created": "YYYY-MM-DD HH:MM:SS"
}
```

The saved review profile bytes live separately in `review-profile.md`. Resume and continue reuse
that snapshot rather than loading its original source again.

### Issue index

`index.json` starts with this shape:

```json
{
  "issues": [],
  "round": 0,
  "phase": "round0",
  "committed_rounds": [],
  "evaluated_by": {}
}
```

After Round-0 birth, the index also carries `run_epoch`. Each issue has `id`, `claim`, `location`,
`category`, `severity`, `evidence_pro`, `evidence_contra`, `peer_reviewed`, `fully_vetted`,
`detail_contested`, `state`, and `rounds_debated`. Valid states are `open`, `accepted`, `rejected`,
`contested`, `unresolved`, and `merged`. An evidence-point location is a non-empty string or a
non-empty array of strings; points may also carry `precondition` and `impact`. `evaluated_by` maps
issue IDs to the seat names accumulated across passes. Round-0 birth initializes coverage from the
independent raisers; debate updates it. Detailed origins and per-round stances remain in the
referee-owned `origins/` files.

### Round and seat records

`round0.panel.json` freezes the configured panel. `round0.attempts.json` records each attempt kind,
availability, and the seats prepared for dispatch. Debate sweep directories hold the validated plan
and its per-seat batch artifacts. `seat_contract.py` owns the `findings`, `stances`, and
`new_findings` block fields and their phase cardinality. `panel_common.py` owns shared issue and
evidence predicates. Do not add a second schema in a prompt or consumer.

### Verdict artifact

`/tmp/<ID>.md` contains YAML frontmatter followed by the report body. Its frontmatter records `id`,
`run_epoch`, `status`, `scope`, `instructions`, review-profile selector/path/hash/size, round limits,
seat timeout, seats, rounds, creation and finish times, `diff_hash`, and `index_hash`. The artifact
reader validates those values before delivery. The main command receives only the filename and
minimal control status, never the report body.
