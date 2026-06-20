# Everyone Peer Review

Three-way **blind** code/design review: **Claude + OpenAI Codex (GPT) + Google Gemini (via the
`agy` CLI)** each review the same scope independently (Round 0, a "blind pass"), then re-evaluate
each issue over debate rounds. A third, architecturally different model catches things two similar
models miss. The tool **hunts for issues and presents them to a human — it is not an autonomous
authority.** It settles a point only when the seats are **unanimous**; anything contested goes to
you, and **every** issue is shown (including rejected ones, with why they were dropped).

It is an extension of the upstream `codex-peer-review` (Claude + Codex only); the additions are the
Gemini seat, the blind debate, and crash-resumable state.

---

## Using it

```
/everyone-peer-review-init                 # one-time: check codex / agy / jq / git / profiles
/everyone-peer-review --base <branch>      # review your branch's changes vs <branch>
/everyone-peer-review --uncommitted        # review staged + unstaged + untracked changes
/everyone-peer-review --commit <SHA>       # review a single commit
/everyone-peer-review "<question>"         # validate an answer to a broad technical question
/everyone-peer-review --uncommitted --issue-rounds 3 --max-rounds 5   # override the loop limits
/everyone-peer-review --uncommitted --debate-low                      # debate even an all-low finding set
```

Run it from the repo you want reviewed. With **no scope** it prints the usage line and stops — it
never guesses a base branch. It returns one synthesized verdict; the review runs in a separate
context so it doesn't clutter your conversation.

**Low-severity gate.** If the blind Round 0 surfaces only `low`-severity items, the tool **stops
before the debate**, presents the Round-0 result, and asks whether to debate them anyway — debating
an all-low set usually just burns tokens confirming non-issues. Continuing reuses Round 0 (no seat
is re-run). Pass `--debate-low` to skip the gate and always debate.

**Resumable.** If a run is interrupted (crash, token exhaustion, you stop it), its state survives.
Re-invoke with the same scope and the dispatcher offers to **resume** from where it stopped. If the
code under review changed since the interruption, it asks before discarding the stale run.

---

## The pieces

| File | What it is | Invoked by |
|------|------------|------------|
| `skills/everyone-peer-review/SKILL.md` | **Skill A — dispatcher.** Parses scope + limits, does the resume/fresh decision, mints/validates the run, dispatches, presents the verdict. Runs in your main conversation. | You, via `/everyone-peer-review` |
| `skills/everyone-peer-review-for-agent/SKILL.md` | **Skill B — the referee protocol.** The full blind-debate procedure. | Preloaded into the agent (`user-invocable: false`); not for the `/` menu |
| `agents/everyone-peer-reviewer.md` | **The referee agent.** Separate context; dispatches the seats, never reviews itself. | Spawned by Skill A |
| `agents/everyone-peer-review-seat.md` | **The Claude seat.** A cold, no-memory subagent spawned fresh each pass — the blind Claude reviewer. | Spawned by the referee (never forked) |
| `skills/everyone-peer-review-init/SKILL.md` | **Init.** Read-only prerequisite check. | You, via `/everyone-peer-review-init` |

### End-to-end flow

```
You: /everyone-peer-review --commit abc123
        │  (main conversation)
Skill A  ── parse scope (commit=abc123) + round limits; hash the diff
         ── resume_check: fresh | resume | stale | moved | ambiguous  (asks you when needed)
         ── init_run (fresh) → mints a run id; spawn the referee with mode/id/scope/limits
        │  (separate context — the referee agent)
Referee  ── Round 0: assemble one blind prompt, dispatch all 3 seats (Claude seat = fresh subagent)
         ── merge findings into issues (judgment); project blind cards
         ── debate sweeps: cards → seats → stances → transitions → commit (checkpointed)
         ── synthesize the verdict, then clean up
        │  (back in main conversation)
Skill A  ── presents that verdict verbatim
```

### Two structural choices that define the tool

- **The referee is blind to provenance, and so are the seats.** No seat ever learns *who* raised a
  point or the *stance tally* (the "2:1" vote) — those are the real conformity/antagonism triggers.
  What each seat *does* see is every distinct technical point and its location, both sides, to verify
  against the actual code. The referee holds all provenance; the **cards** the seats read carry none.
- **The Claude seat is a separate cold subagent**, spawned fresh each pass and **never forked** (a
  fork would inherit the referee's context and defeat blindness). So all three seats are genuinely
  independent and can fail independently.

### How an issue moves (transitions)

State follows the seats' **stances**, never whether an evidence array is populated. Per open issue,
on the seats that engaged this round (returned a parseable stance, ≥2 needed to settle):

- all `support` / `support_with_revision` → **accepted**
- all `reject` → **rejected**
- mix → stays **open** and carries forward; at the per-issue threshold or global ceiling it becomes
  **contested** (had ≥1 review pass) or **unresolved** (none)
- existence can be **accepted** while a detail (severity/claim/location) is **contested** — flagged
  for you
- a new finding emerging mid-review is treated like a Round-0 finding, not penalized for arriving late

Evidence **accumulates unconditionally** every round and is carried to the verdict; nothing a seat
raised is dropped. The loop is bounded by a per-issue counter (`--issue-rounds`, default 2) and a
global ceiling (`--max-rounds`, default 4), so it always terminates.

### Scripts (the only sanctioned plumbing)

In `skills/everyone-peer-review/scripts/` — wrappers so flags, atomic writes, the index math, and
parsing are byte-exact and can't be fat-fingered:

| Script | Job |
|--------|-----|
| `preflight` | Check codex / jq / git / work-tree / writable cwd / profiles; report whether `agy` (Gemini) is present |
| `resolve_diff` | Turn a scope token into the diff text — **one** place owns scope→diff (dispatcher hashes it, agent reviews it) |
| `diff_hash` | Stable hash of the resolved diff, for the manifest and the resume check |
| `assemble` | Splice scope + diff (or card paths) into a prompt template without an LLM retyping them |
| `run_codex` | The **only** way to call the Codex seat — pins `--sandbox read-only`, defaults `--profile peer-review` |
| `run_agy` | The **only** way to call the Gemini seat — pins the Gemini model and the timeout/stdin fixes |
| `extract_block` / `parse_block` | Pull a `findings` / `stances` / `new_findings` block → validated JSONL; `parse_block` exit 4 = no block (down seat) vs empty-but-present |
| `init_run` / `resume_check` / `cleanup` | Mint a run (marker-last); decide resume vs fresh; tear down after the verdict |
| `index` | The **only** writer of the canonical issue index (`/tmp/<id>/index.json`) — state, flags, counters, and the idempotent `commit-sweep` that applies a whole debate round atomically |
| `project_card` / `regen_cards` | Render issue records → blind Markdown cards (no provenance, no tally); rebuild all cards from the index on resume |
| `sweep` | Checkpointed debate sweeps — counters advance **only** on a committed sweep, so a crash never double-counts |

Static prompt templates live in `skills/everyone-peer-review/prompts/`.

---

## Persistence & resume

`/tmp/<ID>/` is the **single source of truth** (a persistent docker volume here); cards are a
derived, regenerable cache. State is never inferred from cards.

| Path | Holds |
|------|-------|
| `.everyone-peer-review/<ID>/issue-<id>.md` | the blind cards (in the repo so Codex's read-only sandbox can read them; git-excluded and kept out of every scope so they never contaminate an `--uncommitted` review) |
| `.everyone-peer-review/<ID>/` (the dir) | the per-worktree marker / lock — its name carries `<ID>` |
| `/tmp/<ID>/manifest.json` | scope, limits, diff hash, phase |
| `/tmp/<ID>/index.json` | the issue index — states, counters, flags (referee only) |
| `/tmp/<ID>/sweeps/`, `/raw`, `/audit`, `/provenance` | sweep checkpoints, raw seat outputs, audit, provenance (referee only) |

Writes are atomic (temp + `sync` + `rename`, prior version rotated to `.bak`). Init writes `/tmp`
state first and the marker **last**, so a marker always implies valid state. A clean finish removes
both the cards and `/tmp/<ID>/`; an interruption leaves them for resume; a "stop" decision leaves the
marker for you to remove.

---

## Key design decisions

- **Referee, not reviewer.** The orchestrating agent never reviews the code — that's what made the
  old design non-blind (the orchestrator was also the Claude reviewer and remembered its own
  findings). Splitting the roles and using a fresh subagent for the Claude seat is what makes Claude
  actually blind.
- **No per-seat evidence cap, hide the tally instead.** You can't hide the *count of distinct
  technical points* without crippling review (the reviewer needs the concrete located facts). But
  the distinct-point count is **not** a seat headcount — all of a side's points can come from one
  seat — so showing them doesn't reveal the 2:1 stance, which is what's hidden. Merge only points at
  the same location with the same mechanism; when unsure, don't merge.
- **Unanimity or the human.** No majority rule, no referee fact-checking inside the loop. The loop
  only filters clear false positives; everything else is presented for you to decide.
- **Skills only — no command file**, and **Skill B is `user-invocable: false`** (preloadable into the
  agent; hidden from the `/` menu). Skill A is `disable-model-invocation: true` so only you launch
  the heavy three-model run. No `context: fork` — the dispatcher stays in the main context so it can
  use `AskUserQuestion` for the resume/stop decision (subagents can't).
- **Degrade gracefully.** If `agy`/Gemini is missing or every Gemini call fails, the review runs
  2-way (Claude + Codex) and says so. One dead seat never aborts the review.

---

## Hard constraints (don't break these)

Behavioral rules the agent must follow (the seat wrappers enforce the flag-pinning part; the rest is
discipline):

- The Gemini seat is called **only** via `scripts/run_agy`, never raw `agy`.
- The Codex seat is called **only** via `scripts/run_codex` (defaults `--profile peer-review`,
  `--sandbox read-only`), never with a hardcoded `-m`.
- **Never** create, edit, or delete `~/.codex/config.toml` or any `~/.codex/*.config.toml` — the
  Codex profiles are owned by `/codex-peer-review init`.
- `index.json` is written **only** through the `index`/`sweep` scripts; cards **only** through
  `project_card`/`regen_cards`. Never hand-write state files.
- The Claude seat is spawned as a fresh `everyone-peer-review-seat` subagent — **never forked**.
- The referee returns **only** the verdict — never raw seat output, card text, or per-round transcripts.
```
