# Panel Review

Three-way **blind** code/design review. Claude, OpenAI Codex (GPT), and Google Gemini each
review the same scope independently, then re-argue every issue until they either agree or hand it
to you. The tool **hunts for issues and presents them to a human — it is not an autonomous
authority.**

Built on the original version: https://github.com/jcputney/agent-peer-review.

> **Requirements & status.** Use the **latest version of Claude Code** — panel-review spawns nested
> subagents (the referee spawns each seat) and relies on recent plugin/subagent behavior, so older
> versions may misbehave. Use Claude Code 2.1.219 or later for the default nested-subagent depth of
> three; 2.1.217 and 2.1.218 default to one and cannot run panel-review without an override. In every
> version, `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` must allow at least two layers; a value of `1`
> prevents the referee from spawning its seats and CLI barrier. The project is **work-in-progress**:
> as both this code and Claude Code
> evolve, you may hit rough edges. Update Claude Code (`claude update`) before reporting an issue.
> The Claude agents pin `model: opus`, but `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1` overrides those pins
> and applies `CLAUDE_CODE_SUBAGENT_MODEL`; when that variable is unset or `inherit`, it applies the
> main session's model. Organization restrictions can prevent the pin from binding, in which case
> Claude Code warns and uses an allowed model or falls back to the parent model.
> Since Claude Code 2.1.284, sessions without an explicit permission mode start in `auto` mode
> outside HIPAA organizations. Panel-review supports `auto`: a `PreToolUse` hook checks each gated
> agent's `SubagentHandback` status, and `SubagentStop` accepts empty or free-form closing text.
> Other permission modes keep the exact `SubagentStop` check. These hooks provide bounded runtime
> enforcement, not a security boundary.

### Allow panel state under `/tmp`

Panel-review keeps its canonical state and seat scratch under `/tmp`, outside the repository under
review. If any Claude Code settings source enables
`permissions.blockReadsOutsideWorkingDirectories`, add `/tmp` as an additional working directory.
Merge this object into either the repository settings at `.claude/settings.json` or the user settings
at `~/.claude/settings.json` (`$CLAUDE_CONFIG_DIR/settings.json` when that variable is set):

```json
{
  "permissions": {
    "additionalDirectories": ["/tmp"]
  }
}
```

Start a new Claude Code session after changing the file. As a session-only alternative, launch with
both the Claude Code grant and the marker that lets the script-only `preflight` verify how the
session was started:

```bash
PANEL_REVIEW_TMP_ADDED=1 CLAUDE_CODE_FORK_SUBAGENT=0 claude --add-dir /tmp
```

`preflight` refuses a detected outside-read block unless it also finds the persistent `/tmp` grant
or that launch marker. The marker is necessary because Claude Code does not expose its effective
`--add-dir` list to subprocesses.

### Start the session with fork mode off

A panel review **must** run in a session started with **`CLAUDE_CODE_FORK_SUBAGENT=0`**:

```bash
CLAUDE_CODE_FORK_SUBAGENT=0 claude
```

`preflight` **refuses to run a review** without it, so this is a hard requirement, not advice. It
cannot be fixed from inside a running session — the setting is read at session start, so you have to
start a new one.

**Why.** Claude Code turns *fork mode* on by default in interactive sessions (2.1.232+). Fork mode
schedules **every** subagent in the background and removes the Agent tool's `run_in_background`
parameter. The referee dispatches the Claude seat and the CLI barrier as two **blocking** Agent calls
and reads their output only after both return; backgrounded, it is instead woken once per seat and
has to decide, by instruction-following alone, not to collect on a partial wake. Turning fork mode
off restores the blocking dispatch — and, as a bonus, removes the `fork` subagent type from the
referee's tool schema, so the never-fork rule that protects seat blindness becomes structural rather
than a written instruction. Measurements: `issues/25-fork-mode-backgrounds-seat-agents.md`.

**Don't export it globally.** Putting `CLAUDE_CODE_FORK_SUBAGENT=0` in `~/.bashrc` turns forks off
for *all* your Claude Code work, including sessions that have nothing to do with panel-review and
benefit from `/subtask`. If you installed with `install.sh`, start a review from its repository with:

```bash
panel-review-session
```

The launcher runs `scripts/preflight` and stops if a hard check fails. It counts only
`.panel-review/<ID>/` directories containing the `.panel-run` marker file as saved reviews, then
starts `claude` with its arguments. The fork-mode setting stays in the launcher and Claude process;
it does not change the parent shell.
`install.sh` links the launcher into `~/.local/bin` by default. Set `PANEL_REVIEW_BIN_DIR=/path`
to choose another link directory, or set `PANEL_REVIEW_INSTALL_LAUNCHER=0` to skip the link.

For a marketplace install, keep your shell in the repository under review and invoke the launcher's
full path under the installed plugin tree. The launcher is at `bin/panel-review-session` there, and
the marketplace does not add that tree to `PATH`. You can also use an alias:

```bash
alias claude-review='CLAUDE_CODE_FORK_SUBAGENT=0 claude'
```

A `settings.json` `env` entry does work, but don't use it: it scopes to a *location* — your whole
account, or an entire repository — not to the activity. Every ordinary session there would lose
forks and `/subtask`, for the sake of the occasional review. Start the review session explicitly
instead.

---

## What it is

Three reviewers — **seats** — look at the same diff or question:

- **Claude**, run as a fresh subagent,
- **OpenAI Codex (GPT)**, via the `codex` CLI,
- **Google Gemini**, via the `agy` CLI.

A fourth participant, the **referee**, orchestrates but never reviews. It runs the seats, collects
their findings, and drives them to a verdict. The review proceeds in two phases:

1. **Round 0 (the blind pass).** Each seat reviews the scope on its own, with no knowledge of the
   others. A seat that produces no usable response is retried once before the pass degrades. The
   referee then merges the independent finding sets into a single list of **issues**. Only
   independent discoveries count in `raised_by`: a copied or near-verbatim finding counts once. The
   referee logs any dropped co-raiser and its text evidence as a blindness incident.
2. **Debate.** For each issue, the referee shows every seat both sides of the argument and asks it
   to take a **stance** (support / reject). This repeats over a bounded number of rounds.

Three rules govern how it treats the result:

- **Unanimity or the human.** In debate, an issue is accepted or rejected only when every seat
  engaged in that round agrees, with at least two seats engaged. Settlement uses only stances from
  seats engaged in the current round. It does not guarantee correctness, and a seat's earlier
  dissent does not block later settlement when that seat is absent. Mixed stances remain open until
  a round limit, then become contested. There is no majority vote or referee fact-checking inside
  the loop.
- **Nothing is hidden.** Every issue is shown, including rejected ones, with the reason it was
  dropped.
- **Graceful degradation.** Either peer seat — Codex or Gemini — may be missing or fail mid-review.
  A run is configured with Claude plus at least one available peer, but engagement is measured again
  on every pass. Any two engaged seats form the normal quorum; a pass with zero or one engaged seat
  takes the degraded terminal path. One dead seat never aborts the review.

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

### Read-only review contract and tracked-tree restoration

The seats may now **write throwaway scratch scripts** (to check arithmetic, parse, enumerate
cases) under a `/tmp/<ID>/work/` subtree, and Codex runs with its sandbox
bypassed so its MCP/tilth calls work. That scratch tree deliberately sits **outside the repository
under review**: when it lived inside, a seat running an ordinary repository-wide search got another
seat's raw output back as an unrequested search hit, which broke blindness through a correct action
(no seat had to disobey anything). Moving it removes that accidental hit; it is not confinement,
because `/tmp/<ID>/` remains readable by every seat by design.
Every seat is instructed to write **nothing inside the repository under review** — not tracked files,
and not untracked or git-ignored ones either, which in practice means **no builds**: no `make`,
`ninja`, `cargo build`, or anything else that writes into a build tree. Read-only checks are
explicitly encouraged instead (replaying a compile line with `-fsyntax-only`, `tsc --noEmit`, and so
on), because they settle real questions without touching the tree. Two reasons: a build tree that
nobody writes to is a safe shared input for all three seats, and a seat that starts a build blocks on
it — one measured Gemini pass spent 1m48s of its 2m54s waiting for a build it then never used
(`issues/57-seats-rebuild-the-repository-under-review.md`).

That instruction is a convenience, not a control, and only the tracked half of it is enforced: the
checkout is not preventively read-only, so the referee snapshots tracked worktree content and index
entries at the start (`scripts/repo_guard`) and, after every seat pass, detects and reverts honest
tracked-file or index drift and flags it loudly in the verdict's Process notes. This restores tracked
repository content and the saved index entries; it does not confine a seat, protect untracked files,
or protect anything outside the repository. Safety rests on that restoration plus the disposable
container the panel runs in — not on per-seat sandboxes.

> **⚠️ Run this in an isolated environment (Docker container or a throwaway VM).** To let the seats
> use tilth and run scratch scripts, all three run with **broad write/execute permissions**: Codex
> with its sandbox bypassed (`--dangerously-bypass-approvals-and-sandbox`), Gemini/`agy` with
> `--dangerously-skip-permissions`, and the Claude seat with `Bash`. `repo_guard` protects **only the
> tracked worktree content and index entries in the repository under review** — it does **not** confine
> a seat from touching the rest of the machine: other directories, your home dir, credentials, the
> network. Treat a panel run as executing untrusted agentic code with your user's privileges, and
> isolate it accordingly. Do not run it directly on a host you care about.

---

## Installing

Two independent ways to install, pick one:

- **`./install.sh`** (script-based). Copies `.claude-plugin/`, `skills/`, `agents/`, `scripts/`,
  `hooks/`, `prompts/`, `profiles/`, `assets/`, `bin/`, and `CONTRACTS.md` into
  `~/.claude/skills/panel-review` as a skills-directory plugin (override target with
  `CLAUDE_DIR=/path ./install.sh`). It links `panel-review-session` into `~/.local/bin` by default.
  Set `PANEL_REVIEW_BIN_DIR=/path` to choose another directory or
  `PANEL_REVIEW_INSTALL_LAUNCHER=0` to skip the link. It leaves an existing path entry in place and
  reports that it did not replace it. If the link directory is not on `PATH`, the installer prints
  its path. It also warns if a user- or project-level agent file could shadow a plugin agent. Remove
  any reported stale agent files yourself. Run `/reload-plugins` (or restart Claude Code) afterward.
- **`/plugin marketplace add` + `/plugin install`** (Claude Code's plugin manager). This repo's
  `.claude-plugin/marketplace.json` lists itself as a plugin whose `source` is `.` (the repo root),
  so it doubles as its own local marketplace — no separate marketplace repo needed:

      /plugin marketplace add /path/to/panel-review
      /plugin install panel-review@panel-review

  Claude Code copies the plugin into its own versioned cache (`~/.claude/plugins/cache`), separate
  from `install.sh`'s target. `/plugin marketplace update panel-review` refreshes it after you pull
  new commits. The marketplace install does not create a PATH link; run `bin/panel-review-session`
  from the plugin tree or use the alias above.

---

## Using it

`panel-review` is a **plugin** with six explicit subcommands — each has one job, one
precondition, one outcome. Intent is in the verb, so the tool never has to guess whether you mean
to start fresh or pick up where you left off. Run them from the repo you want reviewed.

```
panel-review:status                              # read-only: prereqs + any saved review's state
panel-review:start --base <branch>                # review your branch's changes vs <branch>
panel-review:start --uncommitted                  # review staged + unstaged + untracked changes
panel-review:start --commit <SHA>                 # review a single commit
panel-review:start "<topic>"                      # review a free-text topic or question (no diff)
panel-review:start --uncommitted --issue-rounds 3 --max-rounds 5   # override the loop limits
panel-review:start --uncommitted --debate-low                      # debate even an all-low set
panel-review:start --base main --review-profile /path/domain-review.md  # replace generic priorities
panel-review:start --uncommitted focus on the new locking           # steer the seats (trailing text)
panel-review:start --base main --instructions auto                  # let the referee derive context
panel-review:resume                               # pick up an interrupted run
panel-review:continue [unresolved|contested]      # re-debate a finished run's leftovers
panel-review:result <ID>                          # retrieve a validated finished verdict by artifact ID
panel-review:discard                              # delete the saved review (the reset)
```

Only `panel-review:start` takes a scope, review-profile path, or instructions — the run remembers
them, and `panel-review:resume`/`panel-review:continue` reuse the saved profile snapshot and read the
other values from the manifest rather than asking you to retype them.

It writes one synthesized verdict to **`/tmp/<ID>.md`** and returns only that filename plus any
minimal gate/continuation status. The review and report body stay in a separate context, so they do
not clutter your conversation. See [Persistence & resume](#persistence--resume).

### Steering the review with instructions

By default the seats get a **reference** to the diff (its canonical bytes on disk — an absolute
path plus size + sha256, not the body spliced into the prompt), a one-line scope label, and read
access to the tree — no statement of *intent*. You can supply that focus, which is shown to all three seats (blindness is
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
- A bare **`<topic>`** scope reviews that text without a diff and has no separate instructions
  channel. The text itself is the scope, whether it names a code topic or asks a technical question.
- Instructions are **not** part of a run's resume identity — `panel-review:status` shows what's
  stored, and `panel-review:resume`/`panel-review:continue` adopt them from the manifest rather than
  comparing a retyped value. Only `panel-review:start` accepts instructions at all; passing them to
  `resume`/`continue` is a hard error (there's nothing to apply them to — the manifest already has
  its own).

### Selecting a review profile

Every run uses one review profile: a reusable investigation method containing priorities, domain
invariants, execution variants, false-positive filters, and severity guidance. With no flag,
panel-review uses its built-in generic software profile, preserving the existing review behavior.
Supply a project-specific profile explicitly when appropriate:

```
panel-review:start --base main \
  --review-profile /home/developer/.claude/skills/darktable-review/references/review-profile.md
```

The source must be a readable regular, non-empty UTF-8 file no larger than 64 KiB. `start` resolves
the path and snapshots the exact bytes into `/tmp/<ID>/review-profile.md`; the manifest records the
resolved source path, byte size, and SHA-256. Every seat reads that one saved snapshot in Round 0 and
debate. Editing, moving, or deleting the source afterward cannot alter the run, and
`resume`/`continue` never reload it.

The profile changes investigation priorities; it cannot redefine panel-owned scope, roles,
read-only rules, output blocks, finding fields, issue lifecycle, or consensus semantics. An external
profile replaces the built-in generic priority catalogue rather than being appended to it.
`--review-profile` must appear before `--instructions`, because `--instructions` consumes all
remaining text.

Four more behaviors worth knowing before you run it:

- **No scope, no guess.** With no scope argument `panel-review:start` prints the usage line and
  stops — it never guesses a base branch.
- **Low-severity gate.** After Round 0 and after every committed debate round, if every remaining open
  issue is `low`, the tool pauses before spending another round, writes a report snapshot, shows its
  filename, and asks whether to keep debating or finish there — debating an all-low set usually just
  burns tokens confirming non-issues. Continuing reuses all completed work; no completed pass is
  re-run. Pass `--debate-low` to skip these stops.
- **Resumable.** If a run is interrupted — crash, token exhaustion, you stop it — its state
  survives. `panel-review:status` shows it, and `panel-review:resume` picks it up from where it
  stopped. Round 0 freezes its configured panel and exact blind prompt, retains complete seat passes,
  and records each prepared attempt. A currently available configured seat that was down in an
  uncommitted Round 0 may be tried again because the earlier failure may have gone away; a newly
  available seat joins later debate rather than changing the saved blind pass. Once the Round-0 issue
  index is installed, that blind pass is committed and is not rerun. If the code under review changed
  since the interruption (**diverged**), neither `resume` nor `continue` will dispatch seats. For
  `--uncommitted`, new runs report new and removed untracked paths plus whether tracked content
  changed. Older runs can infer newly added paths from their saved diff, but may lack the tracked
  baseline needed to classify tracked changes. Remove a stray file or add it to `.git/info/exclude`,
  then retry. Resume and continue proceed only if the resolved diff hash matches the saved diff hash.
  Editing a tracked `.gitignore` changes the reviewed diff too. For a deliberate scope change,
  `panel-review:discard` the run and `panel-review:start` fresh.
- **Agent orchestration failures fail closed.** If Claude Code refuses a referee dispatch before it
  starts with `Concurrent subagent limit reached`, do not run referee work in the main context or
  retry the dispatch. A nested Agent failure also stops the review and keeps the checkpoint. After
  every referee Agent call, including a failed call or a `PANEL_REVIEW_FAILED` return, the command
  validates the saved artifact. It delivers a valid report even if the final return failed. If no
  valid artifact exists, start a fresh conversation (normally `/clear`) and invoke
  `panel-review:resume`. Treat these failures as orchestration failures, not a down-seat pass.

The loop is bounded by a per-issue counter (`--issue-rounds`, default 2) and a global ceiling
(`--max-rounds`, default 4), so it always terminates.

### Slow seats and timeouts (optional)

**You normally set nothing.** `await_seats` allows each CLI seat up to 2400 s (40 min) by default
(`PANEL_REVIEW_SEAT_TIMEOUT`). The barrier waits for up to 26 × 100 s (about 43 min), and its
detached Bash call has an explicit `timeout` of 2700000 ms (45 min). In unattended Claude Code
sessions (`claude -p`, Agent SDK, CI, or cloud), background commands default to 30 min, or 10 min
for a text-prompt `-p` run; the explicit 45-minute timeout overrides that default and is below the
two-hour maximum. Terminal CLI sessions have no Claude Code background-command time limit.

At these settings, neither `BASH_DEFAULT_TIMEOUT_MS` nor `BASH_MAX_TIMEOUT_MS` changes the barrier
budget: its per-command timeout is explicit and below the two-hour maximum. Neither changes the
per-seat timeout or the barrier's retry count. In unattended sessions only, set
`BASH_MAX_TIMEOUT_MS` if you need to allow a background timeout longer than two hours.

If you deliberately allow seats to run **longer than 40 min**, raise `PANEL_REVIEW_SEAT_TIMEOUT`,
the explicit background `timeout` in [step 1 of the CLI barrier](agents/panel-review-cli-barrier.md),
and its retry cap in step 2 together. Keep the retry budget longer than the per-seat cap and the
background timeout longer than the retry budget. In unattended sessions, a background timeout
cannot exceed two hours unless you raise Claude Code's maximum. Otherwise a slow seat is abandoned
mid-run and the review degrades to the seats that did finish.

---

## How it works

### The pieces

`panel-review` is a **skills-directory plugin** — a single tree with its own
`.claude-plugin/plugin.json`, loaded as `panel-review@skills-dir`. Its components are namespaced
`panel-review:<name>`, so they can't clash with anything else in `~/.claude/skills/`.

| File | Kind | What it is | Invoked by |
|------|------|------------|------------|
| `skills/start/SKILL.md` | skill | Parses scope + review profile + instructions + limits, refuses if a session already exists, mints the run, and spawns the referee; a stale run is retained for manual recovery or explicit discard. | you, via `panel-review:start` |
| `skills/status/SKILL.md` | skill | **Read-only.** Lists the saved session(s) + prereqs and reports missing or invalid run state as stale. | you, via `panel-review:status` (also model-invocable) |
| `skills/resume/SKILL.md` | skill | Picks up an interrupted run (limit overrides only; scope/instructions adopted from the manifest); stale state is retained for manual recovery or explicit discard. | you, via `panel-review:resume` |
| `skills/continue/SKILL.md` | skill | Re-debates a finished run's `unresolved`/`contested` leftovers; stale state is retained for manual recovery or explicit discard. | you, via `panel-review:continue` |
| `skills/result/SKILL.md` | skill | **Read-only.** Validates and retrieves a finished durable verdict by exact artifact ID; never resumes or re-runs seats. | you, via `panel-review:result <ID>` (also model-invocable) |
| `skills/discard/SKILL.md` | skill | Deletes all saved sessions for this workdir (the reset). | you, via `panel-review:discard` |
| `skills/panel-review-for-agent/SKILL.md` | skill | **The referee bootstrap and return contract.** Preloaded into the referee agent (`user-invocable: false`); validates its task, exposes narrow phase loading, and owns fixed referee returns. Hidden from the `/` menu. | the referee agent (preloaded) |
| `skills/panel-review-for-agent/references/protocol.md` | reference | **The canonical phased procedure.** `read_protocol_phase` loads only the marked sections needed for the current state. | the referee bootstrap |
| `agents/panel-review-referee.md` | agent | **The referee.** A separate context that runs the seats and never reviews code itself; it follows the referee-protocol skill. | `start`/`resume`/`continue` |
| `agents/panel-review-claude-seat.md` | agent | **The Claude seat.** A cold, no-memory agent spawned fresh each pass. | the referee agent (never forked) |
| `agents/panel-review-cli-barrier.md` | agent | **The CLI-seat wait barrier.** A thin non-reviewing foreground Agent run in parallel with the Claude seat; it runs `await_seats` and returns after the CLI seats settle. | the referee agent |

`start`/`resume`/`continue`/`discard` are `disable-model-invocation: true` — only you trigger them
(critical for `discard`, so the model never autonomously wipes a session). `status` and `result` are
read-only and left model-invocable.

### End-to-end flow

```
You: panel-review:start --commit abc123
           │  (main conversation)
start      ── parse scope (commit=abc123) + profile + round limits; hash the diff
   (skill)  ── refuse-if-session-exists precondition (state-aware message if one does)
           ── init_run (fresh) → mints a run id; spawn the referee agent with mode/id/scope/limits
           │  (separate context)
referee    ── Round 0: assemble one blind prompt, dispatch seats, retry actual down responses once
  (agent)  ── merge findings into issues (judgment); project blind cards
           ── debate sweeps: cards → seats → stances → transitions → commit (checkpointed); retry
               each non-complete batch once
           ── synthesize + persist the verdict; return the fixed success/write-failure/review-failure status; clean up when eligible
           │  (back in main conversation)
start      ── validates the artifact; reports only `/tmp/<ID>.md` + minimal control status
   (skill)
```

An interrupted or finished-with-leftovers session is picked up the same way via
`panel-review:resume`/`panel-review:continue` instead of `start`'s precondition+`init_run` step —
they adopt scope/limits/instructions from the manifest, reuse the saved profile, and run `resume_check`
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
  memory. A fork would inherit the referee's context and defeat blindness. Each seat starts Round 0
  independently, but accidental exposure can still happen. The referee checks origins for copied
  text and counts a non-independent finding once. Shared conclusions alone do not count as copying.

Keeping promoted text blind is then **referee judgment with a narrow scripted backstop**. The
discriminator is *attribution*, not vocabulary: "the Claude seat's prompt anchors the wrong path" is
a fact about the code and must survive verbatim, while "the Claude seat flagged this" reveals who
raised the point. The noun phrase is identical, so no word list can separate them — and the referee
is the only participant holding the origins map. It therefore checks every string it promotes and
rewords what attributes or counts. `decide_round` adds one mechanical backstop over the seat text it
carries verbatim: a tally of reviewers or a statement that they agree. That pair is never a technical
fact about any codebase, so it is safe to automate. A match withholds only that string — the stance
still counts, the round still commits — and is reported to the referee to restate or drop.

### How an issue moves (transitions)

An issue's **state** follows the **stances** the seats take on it, never whether an evidence array
is populated. Two small vocabularies drive everything below.

Each engaged seat takes one of two **stances** on an issue:

- `support` — the issue exists. It may include a `revision` proposing different severity, claim,
  category, or location values; without one, it endorses the current values.
- `reject` — the issue is not valid. It requires counter-evidence in `rationale`; any `revision` is
  discarded because a rejected issue has no fields to revise.

Revision fields equal to the current issue are no-ops. Other revision values are adopted only under
the convergence rules below.

An issue occupies one of five **states**:

- **open** — not yet settled; carries into the next round.
- **accepted** — settled: every seat engaged in the settling round supported it (at least two).
- **rejected** — settled: every seat engaged in the settling round rejected it (at least two).
- **contested** — still split at the round limit, but reviewed (≥1 round with the 2-seat quorum) — handed to you.
- **unresolved** — unsettled at the round limit and never reviewed (the 2-seat quorum was never met) — handed to you.

Each round, for the seats that engaged (returned a parseable stance — at least 2 are needed to
settle an issue), the state advances:

- supported by all seats (stance: `support`) → **accepted**
- rejected by all seats (stance: `reject`) → **rejected**
- mix stances → stays **open** and carries to the next round; at the per-issue threshold or global ceiling
  it becomes **contested** (had ≥1 review pass) or **unresolved** (none)
- an issue's *existence* can be **accepted** while a *detail* (severity / claim / category / location) is
  **contested** — flagged for you
- a genuinely new finding that emerges mid-review is treated like a Round-0 finding, not penalized
  for arriving late — though one raised near the global ceiling may run out of rounds to reach the
  2-seat quorum, ending **unresolved** (or **contested**, if it gets one split review pass first)
- a later finding folded into an existing issue adds its materially distinct evidence without
  changing that issue's state when it reinforces the current outcome; it reopens the issue only when
  the evidence materially conflicts with that outcome and debate budget remains. At a limit, the
  forced terminal human handoff still applies instead of leaving the issue open

The verdict's "Flagged by" list uses each issue's birth-pass origins. Debate-born issues have zero
independent Round-0 support.

Beyond its state, each issue record also carries three boolean **flags**, two **counters**, and its
**evidence**:

- **flags** — `peer_reviewed` (≥2 engaged seats have evaluated it, the settle threshold),
  `fully_vetted` (every configured seat has evaluated it at least once), and `detail_contested`
  (existence accepted, but a detail — severity / claim / location — never converged).
- **counter** — `rounds_debated` (committed debate rounds the issue has been through). It is not the
  stance tally: the 2:1 vote is never stored on the issue, only in `origins/`.
- **evidence** — the `pro` and `contra` points the seats raised, merged and deduplicated (only points
  at the same location and mechanism are merged). Materially distinct evidence accumulates every
  round and is carried to the verdict. A copied Round-0 finding is represented once, while its issue
  remains open for debate when only one independent raiser remains.

### The wrapper scripts

The referee never hand-rolls flags, writes, index math, or parsing. It calls wrappers in
`${CLAUDE_PLUGIN_ROOT}/scripts/`, so those operations are byte-exact and can't be fat-fingered.
Static reviewer prompt templates live in `${CLAUDE_PLUGIN_ROOT}/prompts/` (`blind_pass.tmpl` and
`debate.tmpl`); `claude_delivery.tmpl` adds only the Claude Agent's validated file-delivery
instructions. The built-in generic investigation priorities live in `profiles/default.md`; `init_run`
snapshots either it or the explicitly supplied external profile before publishing the run marker.
A slipped block is not re-asked of the seat via a template — the seat has exited, so
recovering it is the referee's job (see "Salvage" in the referee protocol), not a script's.
`scripts/seat_contract.py` is the authoritative owner of seat blocks, fields, stance values,
normalization, phase cardinality, and their rendered instructions. `round` renders that contract into
both templates, while `parse_block`, `write_seat_raw`, `sweep`, and `decide_round` consume the same
data and validation rules. Each template says that code under review resolves under its **absolute
review root** and directs a seat to set its tool `cwd` to that path. Round 0's diff file and the saved
review profile are outside the root and are supplied by full absolute path; debate's cards are under
the root, while its saved profile is outside it. Both phases put seat scratch outside the root and
supply its full absolute path. agy expands a leading slash command on the Gemini seat's stdin
print-mode path, so slash-command expansion stays enabled and `check_contracts` requires the prose
seat contract at the start of each prompt. The panel does not currently prepend `/boost`; issue 60
gates that change on live checks of boost's worktree writes, output shape, runtime, and entitlement
behavior. agy runs tools in its own sandbox and infers the repo root. A short,
unanchored print-mode probe on agy 1.4.3 from `/workspace/panel-review` resolved both `pwd` and Git's
root correctly, but realistic-size behavior remains unmeasured. Keep the absolute path until that
comparison is done. The blind prompt references the diff **file** instead of inlining its body. A
240 KB inline diff correlated with the Gemini seat returning prose instead of a fenced block, and
the historical >99 KB prompt-size result has not been replayed on agy 1.4.3. Keep prompts lean and
the contract salient (issue 27).

The plugin gates two model-return boundaries: Claude seat → referee and referee → main command. In
`auto` mode, Claude Code delivers each report through `SubagentHandback`, so a `PreToolUse` hook
checks the hand-back message for an exact Claude-seat status or an exact referee status with the run
ID from its original Agent task. After a hand-back passes, the later `SubagentStop` hook accepts the
auto-mode closing text, which may be empty or free-form. If no accepted auto-mode hand-back is
recorded, `SubagentStop` checks the final message itself. In other permission modes,
`SubagentStop` validates the final message directly. The hook denies at most one invalid hand-back per subagent; if retry state is
unavailable or a later hand-back is still invalid, it replaces the message with a fixed failure stub
and allows it. That stub is `CLAUDE_SEAT_RAW_FAILED` or
`PANEL_REVIEW_FAILED id=<ID>`. If the referee task ID and an exact stub ID are both unavailable, the
hook uses `id=unavailable`; the main command still validates the saved artifact before delivery. An
invalid referee retry while its stop hook is already active may stop rather than loop indefinitely.
These hooks provide bounded runtime enforcement, not a security boundary.
`read_verdict_artifact --delivery` remains the independent authority for user-visible report delivery.

Command skills parse user requests and dispatch the referee. The referee coordinates
independent seat reviews and synthesizes the verdict. `round` owns round orchestration,
and `seat_contract.py` owns the seat-output contract. The wrappers handle exact state,
parsing, and persistence operations. See [CONTRACTS.md](CONTRACTS.md) for machine-checked
ownership and [.claude/rules/scripts.md](.claude/rules/scripts.md) for per-script editing
details.

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
| `.panel-review/<ID>/.panel-run` | the run-marker file, published last after canonical `/tmp/<ID>/` state is in place |
| `.panel-review/<ID>/` (the dir) | the per-worktree marker / lock — its name carries `<ID>`; only directories containing `.panel-run` count as published runs |
| `/tmp/<ID>/work/<seat-token>/` | seat scratch — each seat's own throwaway scripts and temp files, in a subdir it names itself. Deliberately outside the repository under review, so no seat's repository-wide search can return another seat's work as a hit |
| `/tmp/<ID>/manifest.json` | scope, limits, diff hash, and review-profile source path/size/SHA-256 |
| `/tmp/<ID>/review-profile.md` | exact saved profile bytes used by every seat and every phase; the original source path is provenance only |
| `/tmp/<ID>/round0.panel.json` | the configured panel frozen for the blind pass; current preflight filters which of these seats may be retried but never changes this set **Read back on resume and verdict synthesis** (referee only) |
| `/tmp/<ID>/index.json` | the **issue index** — the authoritative record of every issue: its state (e.g. `accepted`), flags, counters, and evidence (all defined under [How an issue moves](#how-an-issue-moves-transitions)); cards are rendered from it and the verdict is read off it (referee only) |
| `/tmp/<ID>/sweeps/` | one subdir per **sweep** — a sweep is one full pass over the open issues across all engaged seats (i.e. one debate round). A complete seat/batch checkpoint binds the retained raw, exact-ID stances, parsed `new_findings`, zero parse status, expected IDs, and source provenance; interrupted rounds resume without re-running complete batches. **Read back on resume** (referee only) |
| `/tmp/<ID>/raw/` | each seat's verbatim response text, before parsing; **read back** — `parse_block` turns these into findings/stances. In Round 0, `round` retains non-empty raw + zero parse status + parsed output as one complete seat checkpoint, so retry/resume dispatches only down or incomplete seats (referee only) |
| `/tmp/<ID>/round0.attempts.json` | deterministic history of prepared Round-0 attempts (`initial`, the single same-invocation `retry`, and later `resume` attempts), including the available and dispatched seats; `round verdict-input` combines it with final Round-0 statuses for Process notes **Read back on resume and verdict synthesis** (referee only) |
| `/tmp/<ID>/codex-model.txt` | the model and reasoning effort the Codex seat **actually bound**, as Codex reported them on its own config summary — written by `run_codex` (the barrier supplies the path), surfaced by `round verdict-input` as `seat_models.codex`, and stated in the verdict's Process notes. The profile pin is only what was asked for; a reviewed repository's own `.codex/config.toml` outranks it (referee only) |
| `/tmp/<ID>/agy-model.txt` | the label agy logged as **bound** (`model=`) on the last successful Gemini pass, next to the pin that pass requested (`requested=`) — written by `run_agy` (the barrier supplies the path), surfaced by `round verdict-input` as `seat_models.gemini`, and stated in the verdict's Process notes. Best effort: it reads an internal agy log line, so nothing depends on it (referee only) |
| `/tmp/<ID>/agy-logs/` | agy's own CLI log for each Gemini attempt (`run_agy` passes `--log-file` here when agy offers it). agy then writes nothing to its default log directory, so this is where a failed Gemini pass is diagnosed. `run_agy` reads the current attempt's log once, right after it succeeds, to write `agy-model.txt`; after that the logs are **for inspection only — never read back by the process**, and are removed with the run directory unless `PANEL_REVIEW_KEEP_TMP=true` |
| `/tmp/<ID>/origins/` | who raised each point, its original wording, and the per-round stances — the data the blind cards omit; `round0.origins.txt` records post-drop Round-0 raisers, `epoch-<epoch>.round-<N>.origins.txt` records debate-born issues' same-pass raisers and original finding text, and `independence.round0.txt` records dropped co-raisers and their text evidence; the birth-pass record supplies "Flagged by", while only Round-0 origins supply independent Round-0 support; **read back** by the referee (referee only) |
| `/tmp/<ID>/audit/` | `round-<N>.md` — a human-readable trail of the issue-field changes applied in each debate round (state, flag, severity/claim/location revisions, evidence, new issues), written mechanically by `index commit-sweep`; **for inspection only — never read back by the process** |
| `/tmp/<ID>/epochs/epoch-<n>/` | a snapshot of a finished debate cycle, taken by `reopen` when `panel-review:continue` starts the next cycle. Because per-round artifacts are named `round<N>`/`round-<N>` with **no epoch component**, the new cycle's round 1 overwrites the previous cycle's round 1 in place; this archive preserves the prior cycle's raws/prompts/sweeps/audit/index/verdict. **For inspection only — never read back by the process** |

Writes are atomic (temp + `sync` + `rename`, prior version rotated to `.bak`). Init writes `/tmp`
state first and `.panel-review/<ID>/.panel-run` **last**, so a marker directory counts as a published
run only after initialization completes; later corruption or missing files can still make the run
stale. A clean finish removes both the cards and `/tmp/<ID>/`; an interruption leaves them for
`panel-review:resume`. If status, start,
resume, or continue finds missing or invalid run state, it leaves the marker and any existing
`/tmp/<ID>/` files intact for manual recovery. Use `panel-review:discard` only to abandon and remove
the stale run.

Setting **`PANEL_REVIEW_KEEP_TMP=true`** makes both `cleanup` and `discard` keep `/tmp/<ID>/` (the
manifest, index, sweeps, raw seat output, audit trail, and the seats' scratch) for post-mortem inspection while still
removing the workspace state (the cards, the marker, and the `.git/info/exclude` line). The durable
verdict at `/tmp/<ID>.md` survives regardless.

### The durable verdict file (`/tmp/<ID>.md`)

The session state above is torn down on a clean finish, so the referee writes every verdict to the
standalone **`/tmp/<ID>.md`** report — a **sibling** of `/tmp/<ID>/`, deliberately *not* inside it, so the
`rm -rf /tmp/<ID>` in `cleanup`/`discard` never touches it. It is written **whenever a verdict is
produced** (the low-severity gate, a finished-with-leftovers run, or a final finish), and it is the
only surface that carries the report body; a `continue` or a debated gate **overwrites** the same path
(the prior copy rotates to `/tmp/<ID>.md.bak`, and `continue` additionally snapshots it into that
cycle's `/tmp/<ID>/epochs/epoch-<n>/`). The file is self-contained: a YAML frontmatter header
(`id`, `run_epoch`, `status`, `scope`, `instructions`, review-profile path/hash/size, `limits`, `seats`, `rounds`,
`created`/`finished`, `diff_hash`, `index_hash`)
followed by the verdict markdown verbatim — the full diff is not embedded (it is large and
reproducible from the scope; `diff_hash` is the reference). Writing it is required for delivery: if
it fails (e.g. `/tmp` full), the run is kept for resume, cleanup is skipped, and the command does not
claim completion. The referee's fixed return distinguishes `PANEL_VERDICT_WRITE_FAILED id=<ID>` for
that persistence failure from `PANEL_REVIEW_FAILED id=<ID>` for an earlier review/orchestration
failure; successful persistence returns `PANEL_VERDICT_READY id=<ID>`. **`/tmp` is cleared on reboot
— move the file somewhere permanent to keep it.**

Before an auto-mode Agent result enters its caller, the plugin's `PreToolUse` hook checks the
`SubagentHandback` message for the exact fixed response and blocks prose-prefixed or wrong-ID
variants with at most one correction for the same subagent. If retry state is unavailable or a later
hand-back is still invalid, the hook replaces its message with `CLAUDE_SEAT_RAW_FAILED` or
`PANEL_REVIEW_FAILED id=<ID>` and allows it, so rejected review text does not reach the caller and
retries cannot continue indefinitely. If neither the task transcript nor an exact referee stub
supplies an ID, the hook uses `PANEL_REVIEW_FAILED id=unavailable`; the caller still validates the
saved artifact before delivery. After a hand-back passes, the `SubagentStop` hook accepts the closing
text because it is not the delivered report. If no accepted auto-mode hand-back is recorded,
`SubagentStop` checks the final message itself. In other permission modes,
`SubagentStop` checks the final message directly. A malformed referee retry made while the stop hook
is already active may stop.
Neither hook carries or reconstructs the verdict; the artifact reader below remains the delivery
authority. These checks are bounded runtime conformance enforcement, not an absolute isolation or
security guarantee.

After every referee Agent call, including a refused dispatch, a failed tool call, a failed final
response, or a `PANEL_REVIEW_FAILED` return, `start`, `resume`, and `continue` call
`read_verdict_artifact --delivery` with the run's expected ID, scope, diff hash, and continuation
epoch. Only a validated finished artifact or canonical low-only snapshot produces a filename;
existence alone is not treated as completion. The report body never passes through the main
conversation. If a hard session/quota limit leaves no main-conversation turn for that check,
reset the quota and run `panel-review:result <ID>`. This read-only command validates `/tmp/<ID>.md`
and prints the recorded review-profile path/hash followed by the verdict body, without depending on
the normally removed workspace marker or re-running any seat. Legacy artifacts without profile
metadata remain readable and print only their body.

### Continuing a finished review

A review that ends with **contested** or **unresolved** issues is **kept**, not cleaned up (just like
the Round-0 low-severity gate). Push those issues further with:

- `panel-review:continue` — re-debate both contested and unresolved
- `panel-review:continue unresolved` — only unresolved
- `panel-review:continue contested` — only contested

`continue` takes **no scope, review profile, or instructions** — it adopts the stored values and
saved profile, along with the round limits, from the finished run (passing any of them is a hard error; `panel-review:status` shows
what's stored, and `--issue-rounds`/`--max-rounds` may still be overridden). It re-resolves the diff:
if the code under review changed since the snapshot (**diverged**), it refuses to continue. For an
uncommitted scope, use the reported paths to identify stray untracked files. Remove a stray file or
add it to `.git/info/exclude`, then retry. The saved run proceeds only if its resolved diff hash
matches the saved diff hash. A tracked `.gitignore` edit changes the reviewed diff too. For an
intentional scope change, discard the run and start fresh. The selected issues return to **open** with their
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
- **Explicit verbs, no intent-guessing.** `start`/`resume`/`continue`/`discard`/`status`/`result` each have one
  job and one precondition; the tool never infers fresh-vs-resume from on-disk state. The only
  remaining `AskUserQuestion` is the low-severity gate (keep debating the all-low open set, or finish).
  `diverged`/`ambiguous` are deterministic exits, not prompts.
- **Skills only — no command file.** The referee-protocol skill is `user-invocable: false`
  (preloadable into the referee agent, hidden from the `/` menu). The four side-effecting command
  skills (`start`/`resume`/`continue`/`discard`) are `disable-model-invocation: true`, so only you
  trigger them; `status` and `result` are read-only and stay model-invocable.
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
- **The Codex model pin is a request, not a guarantee.** Codex layers a reviewed repository's own
  `.codex/config.toml` (and a `config.toml` in the cwd) *above* the `--profile panel-review` layer
  that carries the pin, so such a repository decides which model reviews it. That file belongs to the
  user, so the panel does not override it: `preflight` reports the condition and `panel-review:start`
  asks before minting a run, and `run_codex` records what actually bound so the verdict's Process
  notes state the truth either way.
- **The Gemini pins go stale when agy retires a model.** An unlisted label fails the attempt at
  startup (agy 1.1.13, 1.4.2) or silently runs the user's `settings.json` default (1.1.10).
  `preflight` reports a pin that `agy models` does not list and `panel-review:start` asks; the fix is
  a new label in `scripts/run_agy`, verified with `tests/live/agy_model_binding.sh`.
- **Never** hand-create, edit, or delete `~/.codex/config.toml`. `run_codex` owns
  `~/.codex/panel-review.config.toml` (auto-created from a shipped default); leave it and any other
  `~/.codex/*.config.toml` profile to their tools.
- Seats must write nothing inside the repository under review — tracked or not, which rules out
  builds into a build tree; read-only compile checks are encouraged in their place.
  `scripts/repo_guard` snapshots tracked worktree content and index entries and
  detects and auto-reverts honest tracked-file or index drift after every seat pass. This restoration
  is not confinement and does not protect untracked files or paths outside the repository. Intended
  seat writes stay under `/tmp/<ID>/work/` (outside the repository under review), except that the
  Claude seat passes its complete
  response to `write_seat_raw`, which can write only the derived `/tmp/<ID>/raw/` path.
- `index.json` is written **only** through the `index` / `sweep` scripts; cards **only** through
  `project_card` / `regen_cards`. Never hand-write state files.
- The Claude seat is spawned as a fresh `panel-review:panel-review-claude-seat` subagent — **never forked**.
- Claude-seat evidence-efficiency guidance is advisory; it must not impose a hard tool-call cap or
  stop a review before the evidence and material revision fields are complete.
- The referee persists the verdict and returns **only** a fixed ready/failure stub — never the report
  body, raw seat output, card text, or per-round transcripts. The main conversation receives only a
  validated filename plus minimal gate/continuation status.
