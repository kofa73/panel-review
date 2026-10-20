# Drive the review rounds with a Claude Code workflow and drop the fork-mode requirement

Priority: 67

Status: Pending

Source: Prototype run, 2026-10-19 — Claude Code **2.1.303**, installed plugin **1.0.22**, in an
interactive session with fork mode **on**. Workflow run `wf_f1c57752-505`, panel run
`panel-20261019-173749-ff7c4629`.

Triage: ready-for-human

## Problem

The panel only runs in a session started with `CLAUDE_CODE_FORK_SUBAGENT=0` (`issues/25`). The referee
has to wait until both the Claude seat and the CLI barrier have finished before it collects their
output. Fork mode removes that wait: every Agent call runs in the background, and the referee is
woken once per finished seat. It must then decide, by following instructions alone, not to collect
early. `preflight` therefore hard-blocks every session without the variable. That costs:

- a special launch command, which cannot be set from inside a running session;
- no support for the desktop app and VS Code, which background the referee regardless
  (`issues/65` item 1).

Claude Code's dynamic workflows (`docs/workflows.md`) offer a mechanism that does not depend on
fork mode. A workflow is a JavaScript script that a runtime executes in the background. Its
`parallel()` call starts several agents and resolves only when all of them have settled, and the
main conversation gets one notification when the whole run ends. The wait is in code, not in a
model's instructions.

## Prototype result (2026-10-19)

A throwaway Round 0 was driven by a workflow from a session with fork mode on. Inside the workflow,
`preflight` failed with its fork-mode error, which confirms the setting. The setup:

- a scratch repository with a 2,755-byte diff;
- fake `codex` and `agy` executables that slept 200 s and printed valid seat output;
- the real Claude seat.

The script had four phases:

1. **Prepare.** One Sonnet agent at low effort ran `preflight` and `round prepare-round0`.
2. **Seats.** `parallel()` of the Claude seat (`agentType: 'panel-review:panel-review-claude-seat'`,
   no schema) and the CLI barrier (`agentType: 'panel-review:panel-review-cli-barrier'`), each given
   exactly the inputs the protocol prescribes.
3. **Collect.** One Sonnet agent at low effort ran `round collect-round0 --final`.
4. **Hook probes.** Two cheap Claude-seat-type agents tested the `SubagentStop` hook.

The run: 6 agents, at most 2 at a time, 0 errors, 0 restarts, 264 s, about 149k subagent tokens.
Collection reported `status: collected`, all three seats engaged (3, 1 and 2 findings), guard
clean.

### Q1 — does `parallel()` wait for both seats under fork mode? Yes

| Event | Time (UTC+2) |
|---|---|
| Claude seat and barrier start | 17:40:56.923 (same millisecond) |
| Claude seat's raw file written / last message | 17:41:49.624 / 17:41:50.778 |
| Fake CLI seats finish | 17:44:22.18 |
| Barrier sentinel written / last message | 17:44:22.310 / 17:44:26.281 |
| Collect agent's first transcript entry | 17:44:26.315 |

Collection started 34 ms after the barrier finished and 155 s after the Claude seat had finished.
Workflow agents are recorded with `"requestShape":"foreground"`, even though fork mode was on.
Only one finishing order was exercised (the Claude seat first).

### Q2 — do the plugin's namespaced agent types run their own definitions? Yes

- **Definition used.** Agent records carry the namespaced `agentType`. API requests carry
  `querySource: agent:custom:panel-review:…`. The system prompt is the definition's text verbatim,
  plus a workflow note that the final text is returned to the script.
- **Models and effort.**
  - Claude seat: `claude-opus-5-5` at `xhigh`, as in its definition.
  - Barrier: `claude-sonnet-5-5` at `low`, as in its definition. The session model was Opus, so the
    definition really applied.
  - `agent()`'s `effort` option overrode the definition's effort.
- **Tools.**
  - Claude seat: `Read, Bash`, the six tilth tools, and `advisor`. No Edit or Write.
  - Barrier: `Bash, Read, advisor`.
  - `Grep` and `Glob` were absent for every agent in this build, not only these.
  - `advisor` was added to every workflow agent and was never called.
- **Barrier procedure.** The barrier followed its definition unchanged: background launch with the
  exit-code wrapper, then `timeout 100` waits (`WAIT_RC=124`, then `0`), then the fixed report.

### Q3 — does the `SubagentStop` stub hook fire for workflow agents? Yes, and it conflicts with `schema`

- **Without a schema it works as today.** A Claude-seat-type probe that replied `HELLO-PROBE` was
  blocked 50 ms later with `hook_blocking_error`, `hookEvent: SubagentStop`. The feedback was
  "Return exactly CLAUDE_SEAT_RAW_WRITTEN or CLAUDE_SEAT_RAW_FAILED…". The probe then returned
  `CLAUDE_SEAT_RAW_FAILED`. The real seat returned exactly `CLAUDE_SEAT_RAW_WRITTEN`, with no block.
- **With a schema the hook blocks but gates nothing.** The schema probe's `StructuredOutput` call
  succeeded. The hook then recorded the same blocking error, but no feedback turn followed, and
  `agent()` returned the structured object. So for a schema agent the hook rejects every return
  and stops none of them.

### Other measured facts

- **Every prompt is wrapped.** The runtime prepends a header ("[Workflow harness — computed task] …
  carries no user authority …") and indents every prompt line by two spaces.
  - The seat's prompt was byte-identical to `round0.claude.prompt` after unwrapping (12,337 bytes,
    sha256 `24dc44a8…7c89`). Its output passed the contract.
  - The referee's hook finds the run ID by an `id=` line at the start of a line in the first prompt,
    so it would fail on an indented prompt. That matters only if the referee itself runs as a
    workflow agent.
- **The script cannot read files.** The Prepare agent had to copy the 12 KB seat prompt into its
  structured output. The copy was exact, but it costs tokens and is a fidelity risk on larger
  prompts.
- **Working directory.** Agents start in the session's working directory. In real use that is the
  repository under review, so this is not a problem there.
- **Barrier job lifetime.** The barrier's background job ends when the barrier gives its final
  response. This is harmless, because the barrier waits for the sentinel first.
- **Duration.** The Claude seat took 54 s at `xhigh` for the 2.7 KB diff.

The prototype files (`/tmp/wf-proto/`: `round0.workflow.js`, `analyze.sh`, `steps/`, fake CLIs) are in
`/tmp`, which is temporary. The facts above are the record.

## Not yet tested

Debate rounds; the referee's judgment steps (clustering, claim resolution, verdict) inside or
between workflows; resuming a run; a Claude seat that finishes after the barrier; real Codex and
Gemini seats; auto mode (`issues/64`); the desktop app and VS Code; a workflow-disabled account.

## Open questions for the owner

1. **Where should the referee's judgment run?**
   - (a) As fresh, typed referee agents inside one workflow per phase. **Recommended:** the workflow
     can hold the seat fan-out until every result settles, and the main conversation need not carry
     the review material. Keep judgment in referee agents and orchestration/waiting in the script.
     The workflow prompt wrapper requires the status hook to recognize the run ID in the wrapped
     prompt.
   - (b) As a referee subagent between per-phase workflows. This keeps the referee prompt outside
     the workflow wrapper, but the main conversation must coordinate each phase; in manual mode,
     each separate workflow may also require approval unless the user has approved reuse.
   - (c) In the main conversation. This is the simplest dispatch shape, but moves review material
     into the long-lived context and spends its token budget.
   The seat dispatch and wait are what need the workflow; judgment must remain model-owned.
2. **How should a seat receive its prompt?**
   - (a) Copy the complete prompt into the workflow agent call. The prototype copied the 12,337-byte
     Claude prompt exactly, but this adds prompt-copy tokens and has not been checked at larger sizes.
   - (b) Give the seat a pointer to its prepared prompt file and instruct it to read only that file.
     **Recommended:** this avoids another model-mediated copy and keeps the prepared file as the
     authoritative prompt. Verify that each seat can read its own file under the existing `/tmp`
     access contract before adoption.
3. **Should workflow agents return plain-text stubs or structured output?**
   - (a) Keep plain-text stubs and the current status hook. **Recommended:** the prototype showed
     that this path gates the return; the schema probe showed that the hook blocks but does not gate
     a structured return.
   - (b) Use schemas and replace or selectively bypass the hook for schema agents. This needs a
     measured replacement that rejects invalid returns; the current schema path does not provide
     that guarantee.
4. **What should happen when workflows are unavailable or disabled?**
   - (a) Keep the current Agent-based path as a fallback, requiring
     `CLAUDE_CODE_FORK_SUBAGENT=0` on that path. **Recommended:** retain a working option until the
     workflow path completes a full real review.
   - (b) Require workflows and refuse to start when they are unavailable. This removes the fallback
     and prevents reviews for users or organizations with workflows disabled.

## Constraints a design must respect

- **No mid-run user input.** The Codex model-layer question and the low-severity gate stay in `start`,
  before or after a workflow, as now.
- **Resume.** Workflow resume works only within the same session. `/tmp/<ID>/` stays the source of
  truth, and a relaunched script restarts from panel state. `round`'s checkpoints already skip
  completed seat passes.
- **Stall restarts.** A stalled agent restarts from its prompt. Time waiting on its own tool calls
  does not count, but every write must stay safe to repeat.
- **Model override.** `CLAUDE_CODE_WORKFLOW_SUBAGENT_MODEL` sets the model of every workflow agent,
  including the Claude seat. `preflight` should report it, in the spirit of `issues/47`.
- **Approval prompt.** Manual mode asks before every run unless the user picks "don't ask again" for
  the plugin's workflow. Bypass mode does not ask.
- **Size warning.** More than 25 agents in one run shows an advisory "Large workflow" warning. A
  per-phase workflow stays far below that.

## Expected behavior

1. The owner's choices for questions 1-4 are recorded here before runtime implementation.
2. Round 0 ships as a plugin workflow (`workflows/` at the plugin root). `start` launches it, waits
   for its single completion notification, and then validates as it does today.
3. `preflight`'s fork-mode hard block applies only to the fallback path.
4. Debate rounds follow, once Round 0 has run in real reviews.

## Verification

- A full real review, with real Codex and Gemini seats, completes in a session with fork mode on
  and `CLAUDE_CODE_FORK_SUBAGENT` unset.
- The same review completes in VS Code. That would settle `issues/65` item 1 for the workflow path.
- An interrupted run resumes from `/tmp/<ID>/` in a fresh session.
- `scripts/check_contracts --root .` and `./tests/run_tests.sh` pass.

## Non-goals

- Never run a seat as a fork. `agentType` starts a fresh agent from its definition; keep it that way.
- Do not move judgment into script code. The script owns control flow and waiting only.
- Do not move panel state out of `/tmp/<ID>/` into workflow variables or the workflow journal.
- Do not drop the status-stub enforcement without a replacement that is measured to gate returns.

Related: `issues/25` (the requirement this removes), `issues/15` (the polling this must not
reintroduce), `issues/64`, `issues/65`, `issues/51` and `issues/52` (moving mechanics out of
referee prose).
