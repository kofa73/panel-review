# Panel Review

Three-way **blind** code/design review. Claude, OpenAI Codex (GPT), and Google Gemini each
review the same scope independently, then re-argue every issue until they either agree or hand it
to you. The tool **hunts for issues and presents them to a human — it is not an autonomous
authority.**

Built on the original version: https://github.com/jcputney/agent-peer-review.

> **Requirements & status.** Use the **latest version of Claude Code** — panel-review spawns nested
> subagents (the referee spawns each seat) and relies on recent plugin/subagent behavior, so older
> versions may misbehave. The project is **work-in-progress**: as both this code and Claude Code
> evolve, you may hit rough edges. Update Claude Code (`claude update`) before reporting an issue.

---

## What it is

Three reviewers — **seats** — look at the same diff or question:

- **Claude**, run as a fresh subagent,
- **OpenAI Codex (GPT)**, via the `codex` CLI,
- **Google Gemini**, via the `agy` CLI.

A fourth participant, the **referee**, orchestrates but never reviews. It runs the seats, collects
their findings, and drives them to a verdict. The review proceeds in two phases:

1. **Round 0 (the blind pass).** Each seat reviews the scope on its own, with no knowledge of the
   others. The referee merges the three independent finding sets into a single list of **issues**.
2. **Debate.** For each issue, the referee shows every seat both sides of the argument and asks it
   to take a **stance** (support / reject). This repeats over a bounded number of rounds.

Three rules govern how it treats the result:

- **Unanimity or the human.** An issue is settled only when the seats are unanimous. Anything
  contested goes to you — there is no majority vote and no referee fact-checking inside the loop.
- **Nothing is hidden.** Every issue is shown, including rejected ones, with the reason it was
  dropped.
- **Graceful degradation.** Either peer seat — Codex or Gemini — may be missing or fail mid-review.
  The review runs with whatever seats engage (Claude plus at least one peer) and says which seat was
  down. One dead seat never aborts the review.

It extends the upstream `codex-peer-review` (Claude + Codex only); the additions are the Gemini
seat, the blind debate, and crash-resumable state.

### Prerequisite: tilth (code-intelligence MCP)

All three seats use [`tilth`](https://github.com/jahala/tilth) for AST-aware code
navigation. Install it in at least read-only mode (add `--edit` if you also want your
agents to use tilth for editing elsewhere — panel-review's review stays read-only either
way), and register it with each host the seats run under:

    cargo install tilth        # or: npx tilth   (then ensure it's on PATH)

    tilth install claude-code  # Claude seat
    tilth install codex        # Codex seat
    tilth install antigravity  # Gemini/agy seat

If `tilth` is missing a seat loses code navigation but still reviews from the diff;
panel-review does not install or manage tilth.

### Read-only by construction

The seats may now **write throwaway scratch scripts** (to check arithmetic, parse, enumerate
cases) under a git-ignored `.panel-review/<ID>/work/` subtree, and Codex runs with its sandbox
bypassed so its MCP/tilth calls work. The **code under review is still never modified**: the referee
snapshots the tracked tree at the start (`scripts/repo_guard`) and, after every seat pass, reverts
any tracked-file change and flags it loudly in the verdict's Process notes. Integrity is enforced by
that guard plus the disposable container the panel runs in — not by per-seat sandboxes.

> **⚠️ Run this in an isolated environment (Docker container or a throwaway VM).** To let the seats
> use tilth and run scratch scripts, all three run with **broad write/execute permissions**: Codex
> with its sandbox bypassed (`--dangerously-bypass-approvals-and-sandbox`), Gemini/`agy` with
> `--dangerously-skip-permissions`, and the Claude seat with `Bash`. `repo_guard` protects **only the
> code under review** (it reverts changes to tracked files in your repo) — it does **not** confine a
> seat from touching the rest of the machine: other directories, your home dir, credentials, the
> network. Treat a panel run as executing untrusted agentic code with your user's privileges, and
> isolate it accordingly. Do not run it directly on a host you care about.

---

## Installing

Two independent ways to install, pick one:

- **`./install.sh`** (script-based). Copies `.claude-plugin/`, `skills/`, `agents/`, `scripts/`,
  `prompts/`, `assets/` into `~/.claude/skills/panel-review` as a skills-directory plugin (override
  target with `CLAUDE_DIR=/path ./install.sh`). Removes the old pre-plugin layout first. Run
  `/reload-plugins` (or restart Claude Code) afterward.
- **`/plugin marketplace add` + `/plugin install`** (Claude Code's plugin manager). This repo's
  `.claude-plugin/marketplace.json` lists itself as a plugin whose `source` is `.` (the repo root),
  so it doubles as its own local marketplace — no separate marketplace repo needed:

      /plugin marketplace add /path/to/panel-review
      /plugin install panel-review@panel-review

  Claude Code copies the plugin into its own versioned cache (`~/.claude/plugins/cache`), separate
  from `install.sh`'s target. `/plugin marketplace update panel-review` refreshes it after you pull
  new commits.

---

## Using it

`panel-review` is a **plugin** with five explicit subcommands — each has one job, one
precondition, one outcome. Intent is in the verb, so the tool never has to guess whether you mean
to start fresh or pick up where you left off. Run them from the repo you want reviewed.

```
panel-review:status                              # read-only: prereqs + any saved review's state
panel-review:start --base <branch>                # review your branch's changes vs <branch>
panel-review:start --uncommitted                  # review staged + unstaged + untracked changes
panel-review:start --commit <SHA>                 # review a single commit
panel-review:start "<question>"                   # validate an answer to a broad technical question
panel-review:start --uncommitted --issue-rounds 3 --max-rounds 5   # override the loop limits
panel-review:start --uncommitted --debate-low                      # debate even an all-low set
panel-review:start --uncommitted focus on the new locking           # steer the seats (trailing text)
panel-review:start --base main --instructions auto                  # let the referee derive context
panel-review:resume                               # pick up an interrupted run
panel-review:continue [unresolved|contested]      # re-debate a finished run's leftovers
panel-review:discard                              # delete the saved review (the reset)
```

Only `panel-review:start` takes a scope or instructions — the session remembers them, and
`panel-review:resume`/`panel-review:continue` read them back from the manifest rather than asking
you to retype them.

It returns one synthesized verdict. The review runs in a separate context, so it doesn't clutter
your conversation. The verdict is also saved to a durable file at **`/tmp/<ID>.md`** (see
[Persistence & resume](#persistence--resume)).

### Steering the review with instructions

By default the seats get the diff, a one-line scope label, and read access to the tree — no
statement of *intent*. You can supply that focus, which is shown to all three seats (blindness is
preserved — same text to everyone) and to the debate rounds. It is **emphasis, not a limit**: it
directs attention but never overrides the review's own rules or suppresses a defect found outside
its scope.

Two ways to pass it, and **positionality matters**:

- **Trailing text (keyword-less).** With a diff scope (`--base`/`--uncommitted`/`--commit`), any
  free text left after the flags is the instruction. Put it **last**, after the scope and any
  `--issue-rounds`/`--max-rounds`:
  ```
  panel-review:start --uncommitted --max-rounds 3 focus on error handling in the parser
  ```
  Limitation: this text **must not contain `--`-looking tokens** — they get parsed as flags. For
  that, use the explicit form.
- **`--instructions <text>` (explicit, escape hatch).** Must be the **last** flag; *everything*
  after it is taken verbatim — newlines and `--`-looking tokens included — and nothing past it is
  parsed as a flag:
  ```
  panel-review:start --base main --instructions check the --max-rounds handling and the retry path
  ```
  Use it for multi-line guidance or text containing flag-like tokens. Give instructions **either**
  as trailing text **or** via `--instructions`, not both.
- **`--instructions auto`.** The referee writes a few neutral sentences of context from *outside*
  the diff — branch name, the branch's commit subjects, `git status` — and feeds that to the seats.
  It deliberately does **not** paraphrase the diff (that would push one interpretation onto all
  three independent seats). Note `auto` has little to draw on for `--uncommitted` (no commits yet);
  it's most useful with `--base`/`--commit`.

Notes:
- A bare **`<question>`** scope (no diff) has no separate instructions channel — the question text
  *is* the scope.
- Instructions are **not** part of a run's resume identity — `panel-review:status` shows what's
  stored, and `panel-review:resume`/`panel-review:continue` adopt them from the manifest rather than
  comparing a retyped value. Only `panel-review:start` accepts instructions at all; passing them to
  `resume`/`continue` is a hard error (there's nothing to apply them to — the manifest already has
  its own).

Three more behaviors worth knowing before you run it:

- **No scope, no guess.** With no scope argument `panel-review:start` prints the usage line and
  stops — it never guesses a base branch.
- **Low-severity gate.** If Round 0 surfaces only `low`-severity items, the tool stops *before* the
  debate, shows the Round-0 result, and asks whether to debate them anyway — debating an all-low set
  usually just burns tokens confirming non-issues. Continuing reuses Round 0 (no seat is re-run).
  Pass `--debate-low` to skip the gate.
- **Resumable.** If a run is interrupted — crash, token exhaustion, you stop it — its state
  survives. `panel-review:status` shows it, and `panel-review:resume` picks it up from where it
  stopped. If the code under review changed since the interruption (**diverged**), neither `resume`
  nor `continue` will touch it — `panel-review:discard` it and `panel-review:start` fresh.

The loop is bounded by a per-issue counter (`--issue-rounds`, default 2) and a global ceiling
(`--max-rounds`, default 4), so it always terminates.

### Slow seats and timeouts (optional)

**You normally set nothing.** A review needs no timeout configuration: each CLI seat is allowed up to
~40 min (`await_seats`' `--seat-timeout`, default 2400 s), and the CLI-seat barrier waits for them in
short (< 2 min) polling chunks that stay under Claude Code's Bash-tool timeout *and* its
background-subagent stall timeout by design, so nothing is truncated out of the box. (You do **not**
need `BASH_DEFAULT_TIMEOUT_MS` / `BASH_MAX_TIMEOUT_MS`: the barrier never asks for a longer single
Bash call, so raising the Bash ceiling has no effect here.)

You only tune this if you deliberately let seats run **longer than ~40 min** — e.g. you raise the
per-seat cap with `PANEL_REVIEW_SEAT_TIMEOUT=<seconds>`. Then two limits also have to move, or a slow
seat is abandoned mid-run and the review silently degrades to the seats that did finish:

1. **The barrier's poll budget** — raise the retry cap in `agents/panel-review-cli-barrier.md`
   step 2 (currently 26) so `cap × ~100 s` comfortably exceeds your new per-seat cap.
2. **Claude Code's background-subagent stall timeout** — raise `CLAUDE_ASYNC_AGENT_STALL_TIMEOUT_MS`
   (default `600000`, i.e. 10 min) so a background Agent that goes quiet through a long run is not
   aborted as "stalled". Put it in the `env` block of a settings file — pick the file by who it
   should apply to:

   | File | Applies to |
   | :--- | :--- |
   | `~/.claude/settings.json` | you, in every project |
   | `<reviewed-repo>/.claude/settings.json` | everyone working in that repo (checked in) |
   | `<reviewed-repo>/.claude/settings.local.json` | just you, just that repo (gitignore it) |

   Add exactly (match the value to your longest seat, in ms — e.g. 60 min):

   ```json
   {
     "env": {
       "CLAUDE_ASYNC_AGENT_STALL_TIMEOUT_MS": "3600000"
     }
   }
   ```

   Claude Code reads `env` from the file at startup, so it applies however `claude` was launched;
   restart the session after editing. A real shell environment variable of the same name wins over
   the settings entry if both are set.

---

## How it works

### The pieces

`panel-review` is a **skills-directory plugin** — a single tree with its own
`.claude-plugin/plugin.json`, loaded as `panel-review@skills-dir`. Its components are namespaced
`panel-review:<name>`, so they can't clash with anything else in `~/.claude/skills/`.

| File | Kind | What it is | Invoked by |
|------|------|------------|------------|
| `skills/start/SKILL.md` | skill | Parses scope + instructions + limits, refuses if a session already exists, mints the run, spawns the referee. | you, via `panel-review:start` |
| `skills/status/SKILL.md` | skill | **Read-only.** Lists the saved session(s) + prereqs. | you, via `panel-review:status` (also model-invocable) |
| `skills/resume/SKILL.md` | skill | Picks up an interrupted run (limit overrides only; scope/instructions adopted from the manifest). | you, via `panel-review:resume` |
| `skills/continue/SKILL.md` | skill | Re-debates a finished run's `unresolved`/`contested` leftovers. | you, via `panel-review:continue` |
| `skills/discard/SKILL.md` | skill | Deletes all saved sessions for this workdir (the reset). | you, via `panel-review:discard` |
| `skills/panel-review-for-agent/SKILL.md` | skill | **The referee protocol.** The full blind-debate procedure. Preloaded into the referee agent (`user-invocable: false`); hidden from the `/` menu. | the referee agent (preloaded) |
| `agents/panel-review-referee.md` | agent | **The referee.** A separate context that runs the seats and never reviews code itself; it follows the referee-protocol skill. | `start`/`resume`/`continue` |
| `agents/panel-review-claude-seat.md` | agent | **The Claude seat.** A cold, no-memory agent spawned fresh each pass. | the referee agent (never forked) |

`start`/`resume`/`continue`/`discard` are `disable-model-invocation: true` — only you trigger them
(critical for `discard`, so the model never autonomously wipes a session). `status` is read-only and
left model-invocable.

### End-to-end flow

```
You: panel-review:start --commit abc123
           │  (main conversation)
start      ── parse scope (commit=abc123) + round limits; hash the diff
   (skill)  ── refuse-if-session-exists precondition (state-aware message if one does)
           ── init_run (fresh) → mints a run id; spawn the referee agent with mode/id/scope/limits
           │  (separate context)
referee    ── Round 0: assemble one blind prompt, dispatch all 3 seats (Claude seat = fresh agent)
  (agent)  ── merge findings into issues (judgment); project blind cards
           ── debate sweeps: cards → seats → stances → transitions → commit (checkpointed)
           ── synthesize the verdict, then clean up
           │  (back in main conversation)
start      ── presents that verdict verbatim
   (skill)
```

An interrupted or finished-with-leftovers session is picked up the same way via
`panel-review:resume`/`panel-review:continue` instead of `start`'s precondition+`init_run` step —
they adopt scope/limits/instructions from the manifest and run `resume_check`
(`fresh | resume | continuable | stale | diverged | ambiguous`) to decide whether to act or redirect
you to the right command.

### What makes the review blind

Blindness is the whole point, and two choices enforce it:

- **No seat ever sees *who* raised a point or the stance count** (the "2:1" vote) — those are the
  real conformity and antagonism triggers. Each seat *does* see every distinct technical point, its
  location, and both sides of the argument, so it can verify against the actual code. The referee
  alone knows each point's **origins**; the **cards** the seats read carry none. A card is the
  Markdown rendering of an issue with those origins stripped out.
- **The Claude seat is a cold subagent, never forked.** It is spawned fresh each pass with no
  memory. A fork would inherit the referee's context and defeat blindness. So all three seats are
  genuinely independent and can fail independently.

### How an issue moves (transitions)

An issue's **state** follows the **stances** the seats take on it, never whether an evidence array
is populated. Two small vocabularies drive everything below.

Each engaged seat takes one of three **stances** on an issue:

- `support` — valid as stated.
- `support_with_revision` — valid, but a detail (severity, claim, or location) should change.
- `reject` — not valid.

An issue occupies one of five **states**:

- **open** — not yet settled; carries into the next round.
- **accepted** — settled: every engaged seat supported it (`support` or `support_with_revision`).
- **rejected** — settled: every engaged seat rejected it.
- **contested** — still split at the round limit, but reviewed (≥1 round with the 2-seat quorum) — handed to you.
- **unresolved** — unsettled at the round limit and never reviewed (the 2-seat quorum was never met) — handed to you.

Each round, for the seats that engaged (returned a parseable stance — at least 2 are needed to
settle an issue), the state advances:

- supported by all seats (stance: `support` / `support_with_revision`) → **accepted**
- rejected by all seats (stance: `reject`) → **rejected**
- mix stances → stays **open** and carries to the next round; at the per-issue threshold or global ceiling
  it becomes **contested** (had ≥1 review pass) or **unresolved** (none)
- an issue's *existence* can be **accepted** while a *detail* (severity / claim / location) is
  **contested** — flagged for you
- a finding that emerges mid-review is treated like a Round-0 finding, not penalized for arriving late
  — though one raised near the global ceiling may run out of rounds to reach the 2-seat quorum, ending
  **unresolved** (or **contested**, if it gets one split review pass first)

Beyond its state, each issue record also carries three boolean **flags**, two **counters**, and its
**evidence**:

- **flags** — `peer_reviewed` (≥2 engaged seats have evaluated it, the settle threshold),
  `fully_vetted` (every configured seat has evaluated it at least once), and `detail_contested`
  (existence accepted, but a detail — severity / claim / location — never converged).
- **counters** — `rounds_debated` (committed debate rounds the issue has been through) and `card_rev`
  (a revision number bumped on every change, used to detect a stale projected card). Neither is the
  stance tally: the 2:1 vote is never stored on the issue, only in `origins/`.
- **evidence** — the `pro` and `contra` points the seats raised, merged and deduplicated (only points
  at the same location and mechanism are merged). Evidence **accumulates unconditionally** every
  round and is carried to the verdict; nothing a seat raised is dropped.

### The wrapper scripts

The referee never hand-rolls flags, writes, index math, or parsing. It calls wrappers in
`${CLAUDE_PLUGIN_ROOT}/scripts/`, so those operations are byte-exact and can't be fat-fingered.
Static prompt templates live in `${CLAUDE_PLUGIN_ROOT}/prompts/` (`blind_pass.tmpl`,
`debate.tmpl`, and `repair.tmpl` — the last re-asks a seat to fix only the JSON shape of a
malformed block, using its own prior output plus `parse_block --diagnose` output).

| Script | Job |
|--------|-----|
| `preflight` | Check jq / git / work-tree / writable cwd and that ≥1 peer seat (`codex` or `agy`) is present; emit `CODEX:` / `GEMINI:` availability |
| `resolve_diff` | Turn a scope token into the diff text — **one** place owns scope→diff (`start`/`resume`/`continue` hash it, referee reviews it) |
| `diff_hash` | Stable hash of the resolved diff, for the manifest and the resume/diverged check |
| `assemble` | Splice scope + diff (or card paths) into a prompt template without an LLM retyping them |
| `resolve_instructions` | Resolve `manifest.instructions` to the seat-facing text for the two deterministic cases (verbatim author text, or the "(none …)" line); returns a compose **sentinel** (exit 3) for `auto`, the only case that needs the referee to write neutral context |
| `run_codex` | The **only** way to call the Codex seat — defaults `--profile panel-review` (auto-creates the profile from a shipped default) and runs with the sandbox **bypassed** (`--dangerously-bypass-approvals-and-sandbox`, the only mode where Codex's MCP/tilth runs and it can write scratch; integrity is enforced by `repo_guard`, not this sandbox) |
| `repo_guard` | Protect the **code under review**: `snapshot` records the tracked tree (a `git stash create` SHA + a sha256 manifest) at the start; `verify --restore` after each seat pass detects, reverts, and reports any tracked-file drift. Untracked scratch and the `.panel-review/` cache are left alone |
| `run_agy` | The **only** way to call the Gemini seat — pins the model, a 15-min `--print-timeout` budget, and the flag-binding invocation (prompt on **stdin with no bare `--print`**, since agy's `--print` takes the prompt as its argument and would otherwise swallow `--model`); falls back from the primary Gemini model to a faster one if the primary fails or exhausts its `--print-timeout` (whose expiry prints `Error: timed out waiting for response`) |
| `run_seat` | Dispatch one **CLI** seat (Codex or Gemini) for a tag, parse the block, and run the one-shot shape repair (diagnose → `repair.tmpl` with the seat's own output → re-dispatch) automatically; prints the final parse status. The Claude seat is a subagent, not a CLI, so it is driven by the referee directly. **CLI seats are long-running** (minutes; `run_agy` up to ~34 min across its two 15-min model attempts), longer than the Bash tool's foreground timeout (2 min default, 10 min max), so the seats run **in the background**, never foreground (a foreground dispatch is killed mid-pass and the empty raw file reads as a down seat) |
| `await_seats` | **Barrier** over the CLI seats: runs them all concurrently (each through `run_seat`, so parse + repair are unchanged) inside **one** job, waits for every seat with a configurable per-seat outer timeout (`--seat-timeout`, default 2400s — the backstop `run_codex` otherwise lacks), writes each seat's final status plus one combined `--done` summary, and exits. It is run by the **`panel-review-cli-barrier` Agent**, not backgrounded by the referee directly: a background **Bash** job does **not** re-invoke the sub-agent that launched it (its completion is routed to the root session and dropped, stalling the referee), whereas a background **Agent** reliably wakes its spawner. So a pass spawns two background Agents — the CLI barrier and the Claude seat — for two reliable wakes instead of the per-seat polling loop that made the referee burn turns re-reading its whole context |
| `panel-review-cli-barrier` (agent) | Thin, non-reviewing helper subagent the referee spawns **background** each pass: it `bash`-runs the `await_seats` command the referee wrote — wrapped so `await_seats`' exit code is always written to a **completion sentinel** — then watches that sentinel (not the `--done` file, which exists only on a clean run) via bounded foreground waits in its own tiny context, and returns once `await_seats` has fully exited. Its return is the event that wakes the referee; the sentinel's exit code tells the referee whether the seats actually ran (`0`) or hit a setup error / wedged (nonzero / absent → CLI seats down for the pass, no false "settled" and no late writes). Exists solely because a background Agent — unlike a background Bash job — reliably re-invokes its spawning sub-agent |
| `extract_block` / `parse_block` | Pull a `findings` / `stances` / `new_findings` block → validated JSONL; `parse_block` exit 4 = no block (down seat) vs empty-but-present, exit 5 = malformed (block present, zero valid). `parse_block --diagnose` reports *why* each item was rejected (reason + offending line) to drive a one-shot repair |
| `check_draft` | **Seat-facing** pre-emit validator, spliced into each seat prompt as `{{CHECK}}` (never called by the referee): a seat runs it on the JSONL it is about to fence so it can fix malformed items *before* emitting. A thin wrapper over `parse_block --diagnose` (same validator, no second schema to drift). Closes the silent-drop gap: `parse_block`'s normal mode discards individual malformed lines with only an unseen stderr note (it fails hard only when the *whole* block is unparseable), so a seat that emits some good and some bad items would otherwise lose the bad ones with no repair |
| `birth_index` | Turn the referee's clustered Round-0 finding-to-issue map into the full `index.json` — assigns each issue's birth state, vetting flags, and `evaluated_by` coverage by the birth-unanimity rule (the deterministic half of clustering; the referee still owns the merge itself) |
| `decide_round` / `decide_degraded_round` | Build normal (≥2 seats) and degraded (0–1 seat) debate payloads. Both update private `evaluated_by` coverage in the same atomic commit; the degraded path only emits terminal unresolved/contested states and eligible `fully_vetted` flags |
| `merge_payload` | Fold the referee's addendum (synthesized claims, `add_issues`, fold-reopen) into the `decide_round` payload with `commit-sweep`'s per-key semantics (`set_state` replace, `revise` field-merge) — so additions never become a duplicate `set_state`/`revise` that rejects the round |
| `init_run` / `resume_check` / `cleanup` | Mint a run (marker-last); decide resume/continuable/diverged/stale/ambiguous; tear down after the verdict |
| `inspect_run` | Pure, read-only per-run inspector for `panel-review:status` — never repairs, never writes |
| `discard` | The fault-tolerant traversal behind `panel-review:discard` — removes every session for the workdir |
| `set_limits` | Writes a `--issue-rounds`/`--max-rounds` override back into a run's manifest, for `resume`/`continue` |
| `reopen` | The engine behind `panel-review:continue` — revives a **finished** run's `unresolved`/`contested` leftovers for another debate cycle: `index reopen` bumps `run_epoch` and clears `committed_rounds`, then `/tmp/<ID>/sweeps/` is cleared so `resume` starts a clean debate at round 1. Counterpart to `init_run` |
| `index` | The **only** writer of the canonical issue index (`/tmp/<id>/index.json`) — state, flags, private coverage, counters, `gate-status`, and the idempotent `commit-sweep` that applies a whole debate round atomically (and emits that round's human-readable `audit/round-<N>.md` trail as a side effect, best-effort) |
| `project_card` / `regen_cards` | Render issue records → blind cards (no origins, no tally); rebuild all cards from the index on resume |
| `write_card` | Atomic single-card write (temp + fsync + rename, `.bak` rotation) over `panel_atomic_write`, for the card writes `project_card`/`regen_cards` don't own |
| `sweep` | Checkpointed debate sweeps — owns batch plans, parse/ID validation, checkpoint retention, dropped-seat cleanup, and resume plans; counters advance **only** on a committed sweep |
| `write_verdict_artifact` | Write the durable verdict to the `/tmp/<ID>.md` sibling of `/tmp/<ID>/` (outside it, so `cleanup`/`discard` never delete it); best-effort — its failure must not block returning the verdict to the user |

---

## Persistence & resume

`/tmp/<ID>/` is the **single source of truth** (a persistent docker volume here). Cards are a
derived, regenerable cache; state is never inferred from them.

> **Single-user, single-session mode.** Panel-review assumes **one user running one Claude Code
> session** against a given workdir at a time. A workdir holds **exactly one** review at a time, and
> running it from **two sessions against the same workdir simultaneously is not supported** — the
> marker/lock model is built for a single session, not for concurrent runs. (This isn't a race to
> work around; it's an explicit scope boundary.)

| Path | Holds |
|------|-------|
| `.panel-review/<ID>/issue-<id>.md` | the blind cards (kept in the repo so any seat running in a constrained/sandboxed workspace — e.g. a seat under an externally-imposed read-only mount — can still read them; git-excluded and kept out of every scope so they never contaminate an `--uncommitted` review) |
| `.panel-review/<ID>/` (the dir) | the per-worktree marker / lock — its name carries `<ID>` |
| `/tmp/<ID>/manifest.json` | scope, limits, diff hash, phase |
| `/tmp/<ID>/index.json` | the **issue index** — the authoritative record of every issue: its state (e.g. `accepted`), flags, counters, and evidence (all defined under [How an issue moves](#how-an-issue-moves-transitions)); cards are rendered from it and the verdict is read off it (referee only) |
| `/tmp/<ID>/sweeps/` | one subdir per **sweep** — a sweep is one full pass over the open issues across all engaged seats (i.e. one debate round). Holds each seat's cached output so an interrupted round resumes without re-running finished seats; **read back on resume** (referee only) |
| `/tmp/<ID>/raw/` | each seat's verbatim response text, before parsing; **read back** — `parse_block` turns these into findings/stances, and resume reuses them (referee only) |
| `/tmp/<ID>/origins/` | who raised each point, its original wording, and the per-round stances — the data the blind cards omit; **read back** by the referee to track review coverage and to attribute findings in the verdict (referee only) |
| `/tmp/<ID>/audit/` | `round-<N>.md` — a human-readable trail of the issue-field changes applied in each debate round (state, flag, severity/claim/location revisions, evidence, new issues), written mechanically by `index commit-sweep`; **for inspection only — never read back by the process** |

Writes are atomic (temp + `sync` + `rename`, prior version rotated to `.bak`). Init writes `/tmp`
state first and the marker **last**, so a marker always implies valid state. A clean finish removes
both the cards and `/tmp/<ID>/`; an interruption leaves them for `panel-review:resume`. Use
`panel-review:status` to inspect a saved session and `panel-review:discard` to remove it.

Setting **`PANEL_REVIEW_KEEP_TMP=true`** makes both `cleanup` and `discard` keep `/tmp/<ID>/` (the
manifest, index, sweeps, raw seat output, and audit trail) for post-mortem inspection while still
removing the workspace state (the cards, the marker, and the `.git/info/exclude` line). The durable
verdict at `/tmp/<ID>.md` survives regardless.

### The durable verdict file (`/tmp/<ID>.md`)

The session state above is torn down on a clean finish, so the verdict would otherwise live **only**
in your conversation transcript. To give you a movable copy, the referee writes every verdict to
**`/tmp/<ID>.md`** — a **sibling** of `/tmp/<ID>/`, deliberately *not* inside it, so the
`rm -rf /tmp/<ID>` in `cleanup`/`discard` never touches it. It is written **whenever a verdict is
produced** (the low-severity gate, a finished-with-leftovers run, or a final finish), so every
verdict you see has a matching file; a `continue` or a debated gate **overwrites** the same path
(the prior copy rotates to `/tmp/<ID>.md.bak`). The file is self-contained: a YAML frontmatter header
(`id`, `scope`, `instructions`, `limits`, `seats`, `rounds`, `created`/`finished`, `diff_hash`)
followed by the verdict markdown verbatim — the full diff is not embedded (it is large and
reproducible from the scope; `diff_hash` is the reference). Writing it is **best-effort**: if it
fails (e.g. `/tmp` full), the verdict is still returned, just without the pointer line. **`/tmp` is
cleared on reboot — move the file somewhere permanent to keep it.**

### Continuing a finished review

A review that ends with **contested** or **unresolved** issues is **kept**, not cleaned up (just like
the Round-0 low-severity gate). Push those issues further with:

- `panel-review:continue` — re-debate both contested and unresolved
- `panel-review:continue unresolved` — only unresolved
- `panel-review:continue contested` — only contested

`continue` takes **no scope and no instructions** — it adopts them, along with the round limits,
from the finished run's manifest (passing any of them is a hard error; `panel-review:status` shows
what's stored, and `--issue-rounds`/`--max-rounds` may still be overridden). It re-resolves the diff:
if the code under review changed since the snapshot (**diverged**), it refuses — `panel-review:discard`
before `panel-review:start` is the only way forward. The selected issues return to **open** with their
per-issue and the global round counters reset to zero, so they get a full budget again; their
accumulated evidence is kept, and already-settled issues are carried into the new verdict unchanged.
If the run turns out not to be finished-with-leftovers (still mid-debate), `continue` redirects you to
`panel-review:resume` instead of failing blankly.

---

## Key design decisions

- **Referee, not reviewer.** The orchestrating agent never reviews the code. That separation is what
  made the design blind: the old design's orchestrator was also the Claude reviewer and remembered
  its own findings. Splitting the roles and using a fresh subagent for the Claude seat is what makes
  Claude actually blind.
- **No per-seat evidence cap; hide the tally instead.** You can't hide the *count of distinct
  technical points* without crippling review — the reviewer needs the concrete located facts. But
  that count is **not** a seat headcount: all of a side's points can come from one seat, so showing
  them doesn't reveal the 2:1 stance, which is what's actually hidden. Merge only points at the same
  location with the same mechanism; when unsure, don't merge.
- **Unanimity or the human.** No majority rule, no referee fact-checking inside the loop. The loop
  only filters clear false positives; everything else is presented for you to decide.
- **Explicit verbs, no intent-guessing.** `start`/`resume`/`continue`/`discard`/`status` each have one
  job and one precondition; the tool never infers fresh-vs-resume from on-disk state. The only
  remaining `AskUserQuestion` is the low-severity gate (debate the all-low Round-0 set, or finish).
  `diverged`/`ambiguous` are deterministic exits, not prompts.
- **Skills only — no command file.** The referee-protocol skill is `user-invocable: false`
  (preloadable into the referee agent, hidden from the `/` menu). The four side-effecting command
  skills (`start`/`resume`/`continue`/`discard`) are `disable-model-invocation: true`, so only you
  trigger them; `status` is read-only and stays model-invocable.
- **Degrade gracefully.** Any seat whose call fails (CLI missing, error exit, or no parseable block)
  is treated as down; with ≥2 seats still engaged the review continues and says so. Codex and Gemini
  are both optional peers — Claude plus at least one peer is the minimum to start.

---

## Hard constraints (don't break these)

Behavioral rules the referee must follow. The seat wrappers enforce the flag-pinning; the rest is
discipline.

- The Gemini seat is called **only** via `scripts/run_agy`, never raw `agy`.
- The Codex seat is called **only** via `scripts/run_codex` (defaults `--profile panel-review`; runs
  with the sandbox bypassed so MCP/tilth + scratch work), never with a hardcoded `-m`.
- **Never** hand-create, edit, or delete `~/.codex/config.toml`. `run_codex` owns
  `~/.codex/panel-review.config.toml` (auto-created from a shipped default); leave it and any other
  `~/.codex/*.config.toml` profile to their tools.
- The code under review is **never modified**: `scripts/repo_guard` snapshots the tracked tree and
  auto-reverts any tracked-file change after every seat pass. Seats write only to `.panel-review/<ID>/work/`.
- `index.json` is written **only** through the `index` / `sweep` scripts; cards **only** through
  `project_card` / `regen_cards`. Never hand-write state files.
- The Claude seat is spawned as a fresh `panel-review:panel-review-claude-seat` subagent — **never forked**.
- The referee returns **only** the verdict — never raw seat output, card text, or per-round
  transcripts.
</content>
</invoke>
