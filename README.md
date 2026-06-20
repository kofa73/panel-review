# Panel Review

Three-way **blind** code/design review. Claude, OpenAI Codex (GPT), and Google Gemini each
review the same scope independently, then re-argue every issue until they either agree or hand it
to you. The tool **hunts for issues and presents them to a human — it is not an autonomous
authority.**

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

---

## Using it

Run it from the repo you want reviewed.

```
/panel-review-init                 # one-time: check codex / agy / jq / git / profiles
/panel-review --base <branch>      # review your branch's changes vs <branch>
/panel-review --uncommitted        # review staged + unstaged + untracked changes
/panel-review --commit <SHA>       # review a single commit
/panel-review "<question>"         # validate an answer to a broad technical question
/panel-review --uncommitted --issue-rounds 3 --max-rounds 5   # override the loop limits
/panel-review --uncommitted --debate-low                      # debate even an all-low set
```

It returns one synthesized verdict. The review runs in a separate context, so it doesn't clutter
your conversation.

Three behaviors worth knowing before you run it:

- **No scope, no guess.** With no scope argument it prints the usage line and stops — it never
  guesses a base branch.
- **Low-severity gate.** If Round 0 surfaces only `low`-severity items, the tool stops *before* the
  debate, shows the Round-0 result, and asks whether to debate them anyway — debating an all-low set
  usually just burns tokens confirming non-issues. Continuing reuses Round 0 (no seat is re-run).
  Pass `--debate-low` to skip the gate.
- **Resumable.** If a run is interrupted — crash, token exhaustion, you stop it — its state
  survives. Re-invoke with the same scope and the tool offers to resume from where it stopped. If
  the code under review changed since the interruption, it asks before discarding the stale run.

The loop is bounded by a per-issue counter (`--issue-rounds`, default 2) and a global ceiling
(`--max-rounds`, default 4), so it always terminates.

---

## How it works

### The pieces

Five files implement the two phases described above — **three skills** (`skills/…`) and **two
agents** (`agents/…`). Skills are invokable procedures; agents are the contexts that run them. The
**dispatcher skill** and the **init skill** run in your conversation; the **referee agent** runs in
a separate context, with the **referee-protocol skill** preloaded into it, and spawns the two
**seat agents**.

| File | Kind | What it is | Invoked by |
|------|------|------------|------------|
| `skills/panel-review/SKILL.md` | skill | **The dispatcher.** Parses scope + limits, makes the resume-vs-fresh decision, mints/validates the run, spawns the referee agent, presents the verdict. Runs in your main conversation. | you, via `/panel-review` |
| `skills/panel-review-for-agent/SKILL.md` | skill | **The referee protocol.** The full blind-debate procedure. Preloaded into the referee agent (`user-invocable: false`); hidden from the `/` menu. | the referee agent (preloaded) |
| `agents/panel-review-referee.md` | agent | **The referee.** A separate context that runs the seats and never reviews code itself; it follows the referee-protocol skill. | the dispatcher skill |
| `agents/panel-review-claude-seat.md` | agent | **The Claude seat.** A cold, no-memory agent spawned fresh each pass. | the referee agent (never forked) |
| `skills/panel-review-init/SKILL.md` | skill | **Init.** Read-only prerequisite check. | you, via `/panel-review-init` |

### End-to-end flow

```
You: /panel-review --commit abc123
           │  (main conversation)
dispatcher ── parse scope (commit=abc123) + round limits; hash the diff
   (skill)  ── resume_check: fresh | resume | stale | moved | ambiguous  (asks you when needed)
           ── init_run (fresh) → mints a run id; spawn the referee agent with mode/id/scope/limits
           │  (separate context)
referee    ── Round 0: assemble one blind prompt, dispatch all 3 seats (Claude seat = fresh agent)
  (agent)  ── merge findings into issues (judgment); project blind cards
           ── debate sweeps: cards → seats → stances → transitions → commit (checkpointed)
           ── synthesize the verdict, then clean up
           │  (back in main conversation)
dispatcher ── presents that verdict verbatim
   (skill)
```

### What makes the review blind

Blindness is the whole point, and two choices enforce it:

- **No seat learns provenance or the tally.** No seat ever sees *who* raised a point or the stance
  count (the "2:1" vote) — those are the real conformity and antagonism triggers. Each seat *does*
  see every distinct technical point, its location, and both sides of the argument, so it can verify
  against the actual code. The referee holds all provenance; the **cards** the seats read carry
  none. A card is the Markdown rendering of an issue with provenance stripped out.
- **The Claude seat is a cold subagent, never forked.** It is spawned fresh each pass with no
  memory. A fork would inherit the referee's context and defeat blindness. So all three seats are
  genuinely independent and can fail independently.

### How an issue moves (transitions)

State follows the seats' **stances**, never whether an evidence array is populated. Each round, for
the seats that engaged (returned a parseable stance — at least 2 are needed to settle an issue):

- all `support` / `support_with_revision` → **accepted**
- all `reject` → **rejected**
- mix → stays **open** and carries to the next round; at the per-issue threshold or global ceiling
  it becomes **contested** (had ≥1 review pass) or **unresolved** (none)
- an issue's *existence* can be **accepted** while a *detail* (severity / claim / location) is
  **contested** — flagged for you
- a finding that emerges mid-review is treated like a Round-0 finding, not penalized for arriving late

Evidence **accumulates unconditionally** every round and is carried to the verdict; nothing a seat
raised is dropped.

### Scripts (the only sanctioned plumbing)

The referee never hand-rolls flags, writes, index math, or parsing. It calls wrappers in
`skills/panel-review/scripts/`, so those operations are byte-exact and can't be
fat-fingered. Static prompt templates live in `skills/panel-review/prompts/`.

| Script | Job |
|--------|-----|
| `preflight` | Check jq / git / work-tree / writable cwd and that ≥1 peer seat (`codex` or `agy`) is present; emit `CODEX:` / `GEMINI:` availability |
| `resolve_diff` | Turn a scope token into the diff text — **one** place owns scope→diff (dispatcher hashes it, referee reviews it) |
| `diff_hash` | Stable hash of the resolved diff, for the manifest and the resume check |
| `assemble` | Splice scope + diff (or card paths) into a prompt template without an LLM retyping them |
| `run_codex` | The **only** way to call the Codex seat — pins `--sandbox read-only`, defaults `--profile panel-review` (auto-creates the profile from a shipped default) |
| `run_agy` | The **only** way to call the Gemini seat — pins the Gemini model and the timeout/stdin fixes |
| `extract_block` / `parse_block` | Pull a `findings` / `stances` / `new_findings` block → validated JSONL; `parse_block` exit 4 = no block (down seat) vs empty-but-present |
| `init_run` / `resume_check` / `cleanup` | Mint a run (marker-last); decide resume vs fresh; tear down after the verdict |
| `index` | The **only** writer of the canonical issue index (`/tmp/<id>/index.json`) — state, flags, counters, and the idempotent `commit-sweep` that applies a whole debate round atomically |
| `project_card` / `regen_cards` | Render issue records → blind cards (no provenance, no tally); rebuild all cards from the index on resume |
| `sweep` | Checkpointed debate sweeps — counters advance **only** on a committed sweep, so a crash never double-counts |

---

## Persistence & resume

`/tmp/<ID>/` is the **single source of truth** (a persistent docker volume here). Cards are a
derived, regenerable cache; state is never inferred from them.

| Path | Holds |
|------|-------|
| `.panel-review/<ID>/issue-<id>.md` | the blind cards (kept in the repo so Codex's read-only sandbox can read them; git-excluded and kept out of every scope so they never contaminate an `--uncommitted` review) |
| `.panel-review/<ID>/` (the dir) | the per-worktree marker / lock — its name carries `<ID>` |
| `/tmp/<ID>/manifest.json` | scope, limits, diff hash, phase |
| `/tmp/<ID>/index.json` | the issue index — states, counters, flags (referee only) |
| `/tmp/<ID>/sweeps/`, `/raw`, `/audit`, `/provenance` | sweep checkpoints, raw seat outputs, audit, provenance (referee only) |

Writes are atomic (temp + `sync` + `rename`, prior version rotated to `.bak`). Init writes `/tmp`
state first and the marker **last**, so a marker always implies valid state. A clean finish removes
both the cards and `/tmp/<ID>/`; an interruption leaves them for resume; a "stop" decision leaves
the marker for you to remove.

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
- **Skills only — no command file.** The referee-protocol skill is `user-invocable: false`
  (preloadable into the referee agent, hidden from the `/` menu). The dispatcher skill is
  `disable-model-invocation: true`, so only you launch the heavy three-model run. There is no
  `context: fork` — the dispatcher stays in the main context so it can use `AskUserQuestion` for the
  resume/stop decision (agents can't).
- **Degrade gracefully.** Any seat whose call fails (CLI missing, error exit, or no parseable block)
  is treated as down; with ≥2 seats still engaged the review continues and says so. Codex and Gemini
  are both optional peers — Claude plus at least one peer is the minimum to start.

---

## Hard constraints (don't break these)

Behavioral rules the referee must follow. The seat wrappers enforce the flag-pinning; the rest is
discipline.

- The Gemini seat is called **only** via `scripts/run_agy`, never raw `agy`.
- The Codex seat is called **only** via `scripts/run_codex` (defaults `--profile panel-review`,
  `--sandbox read-only`), never with a hardcoded `-m`.
- **Never** hand-create, edit, or delete `~/.codex/config.toml`. `run_codex` owns
  `~/.codex/panel-review.config.toml` (auto-created from a shipped default); leave it and any other
  `~/.codex/*.config.toml` profile to their tools.
- `index.json` is written **only** through the `index` / `sweep` scripts; cards **only** through
  `project_card` / `regen_cards`. Never hand-write state files.
- The Claude seat is spawned as a fresh `panel-review-claude-seat` subagent — **never forked**.
- The referee returns **only** the verdict — never raw seat output, card text, or per-round
  transcripts.
</content>
</invoke>
