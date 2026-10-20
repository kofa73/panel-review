# Panel Review

Three-way **blind** code/design review. Claude, OpenAI Codex (GPT), and Google Gemini each
review the same scope independently, then re-argue every issue until they either agree or hand it
to you. The tool **hunts for issues and presents them to a human — it is not an autonomous
authority.**

Built on the original version: https://github.com/jcputney/agent-peer-review.

> **Requirements & status.** Use a current version of Claude Code. The referee spawns two nested
> Agent layers, so `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` must allow at least two. The default is
> sufficient from Claude Code 2.1.219 onward; 2.1.217 and 2.1.218 default to one. Start every review
> session with `CLAUDE_CODE_FORK_SUBAGENT=0`; [the runtime reference](docs/agent-runtimes.md) records
> the current host and CLI requirements, measurements, and upgrade probes. The Claude agents pin
> `model: opus`, but organization restrictions and `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1` can change
> the model that runs. The project is work in progress; update Claude Code before reporting a host
> runtime issue.

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
than a written instruction. Measurements: `issues/archive/25-fork-mode-backgrounds-seat-agents.md`.

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
(`issues/archive/57-seats-rebuild-the-repository-under-review.md`).

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
panel-review:start --uncommitted --seat-timeout 1800              # override the CLI-seat timeout
panel-review:start --uncommitted --debate-low                      # debate even an all-low set
panel-review:start --base main --review-profile domain-review      # select a configured profile
panel-review:start --uncommitted focus on the new locking           # steer the seats (trailing text)
panel-review:start --base main --instructions auto                  # let the referee derive context
panel-review:resume                               # pick up an interrupted run
panel-review:continue [unresolved|contested]      # re-debate a finished run's leftovers
panel-review:result <ID>                          # retrieve a validated finished verdict by artifact ID
panel-review:discard                              # delete the saved review (the reset)
```

Only `panel-review:start` takes a scope, review-profile selector, or instructions — the run remembers
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
panel-review uses the configured default profile or its built-in generic software profile.
`--review-profile` accepts a configured name, a direct path, or the reserved selector
`builtin:generic`:

```
panel-review:start --base main \
  --review-profile /home/developer/.config/panel-review/profiles/domain-review.md
panel-review:start --base main --review-profile domain-review
panel-review:start --base main --review-profile builtin:generic
```

Panel-review classifies selectors by syntax. A value beginning with `/`, `./`, `../`, or `~/`, or
containing `/`, is a path. A bare value is a configured name. The reserved selector
`builtin:generic` always selects the built-in profile. The source must be a readable regular,
non-empty UTF-8 file no larger than 64 KiB. `start` resolves the selector and snapshots the exact
bytes into `/tmp/<ID>/review-profile.md`; the manifest records the selector, resolved source path,
byte size, and SHA-256. Every seat reads that one saved snapshot in Round 0 and debate. Editing,
moving, or deleting the source afterward cannot alter the run, and `resume`/`continue` never reload
it.

The profile changes investigation priorities; it cannot redefine panel-owned scope, roles,
read-only rules, output blocks, finding fields, issue lifecycle, or consensus semantics. An external
profile replaces the built-in generic priority catalogue rather than being appended to it.
`--review-profile` must appear before `--instructions`, because `--instructions` consumes all
remaining text.

### User configuration

Panel-review reads user defaults from
`${XDG_CONFIG_HOME:-$HOME/.config}/panel-review/config.json`. A missing file keeps the built-in
defaults: `builtin:generic`, `issue_rounds=2`, `max_rounds=4`, `seat_timeout_seconds=2400`, and
`cleanup.keep_tmp=false`. The shared plugin ships no profile registrations or project-specific
defaults.

The version 1 config has these optional sections and fields:

```json
{
  "version": 1,
  "profiles": {},
  "defaults": {
    "review_profile": "builtin:generic",
    "issue_rounds": 2,
    "max_rounds": 4,
    "seat_timeout_seconds": 2400
  },
  "cleanup": {
    "keep_tmp": false
  }
}
```

Each `profiles` value must be a full absolute source path. Panel-review validates the selected file
with the review-profile size, regular-file, non-empty, and UTF-8 rules above. It rejects malformed
JSON, unsupported versions, unknown keys, wrong types, and invalid values before creating a run
marker. Set `defaults.review_profile` to a configured name or selector. An explicit
`--review-profile` takes precedence, and `builtin:generic` bypasses any configured default.

For a new run, each execution setting uses this precedence: command option, config default, then
built-in default. The manifest saves the effective profile selector, round limits, and seat timeout.
`resume` and `continue` ignore config defaults. Their explicit `--issue-rounds`, `--max-rounds`, and
`--seat-timeout` options update the saved manifest before dispatch. A config change affects new runs
only. Invalid overrides stop before dispatch, and `continue` does not reopen the run. The CLI
barrier's two-hour platform limit currently caps `seat_timeout_seconds` at 7110.

`cleanup` and `discard` read the current `cleanup.keep_tmp` value when they run. A missing config
uses `false`; an invalid config stops either command before it deletes workspace or `/tmp` state.
When true, cleanup removes the marker and cards but keeps `/tmp/<ID>/` for diagnostics. The durable
verdict at `/tmp/<ID>.md` survives either policy. `PANEL_REVIEW_KEEP_TMP` and
`PANEL_REVIEW_SEAT_TIMEOUT` are rejected with migration guidance; use `cleanup.keep_tmp`, config
defaults, or `--seat-timeout` instead.

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

The loop is bounded by `issue_rounds` and `max_rounds`. New runs use config defaults or the built-in
values of 2 and 4. Explicit command options override them for that run.

### Seat timeouts

`seat_timeout_seconds` limits each CLI seat's wall time. It defaults to 2400 seconds and can be set
in `defaults.seat_timeout_seconds` or overridden per run with `--seat-timeout`. `round` passes the
saved value to every Round 0 and debate barrier, including retries and continuation cycles. The
barrier derives its wait budget from the same value, so the outer wait allows the seat timeout and
its shutdown grace to finish. The timeout applies to Codex and Gemini; Claude runs as a separate
subagent.

---

## How it works

Command skills parse requests and dispatch the referee. The referee follows the canonical protocol,
while scripts own exact state changes, parsing, and persistence. See the
[architecture and saved-state reference](docs/architecture.md) for the component map and schemas.
`start`, `resume`, `continue`, and `discard` require a direct user invocation. `status` and `result`
are read-only and may be invoked by the model.

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
The index also stores review coverage, whether issue details remain contested, debate-round counts,
and `pro`/`contra` evidence. The exact fields and their owner are listed in the
[architecture reference](docs/architecture.md#schemas). [`CONTRACTS.md`](CONTRACTS.md) names the
machine-checked owners.

---

## Persistence & resume

`/tmp/<ID>/` is the canonical run state. The cards under `.panel-review/<ID>/` are a regenerable
workdir cache. The `.panel-run` marker identifies saved runs for normal resume discovery.
`regen_cards` does not recreate it. The [architecture reference](docs/architecture.md#state-ownership)
documents the state directory, schemas, and writer ownership.

Panel-review supports one user and one Claude Code session per workdir. A workdir holds one review;
concurrent runs against the same workdir are unsupported. A clean finish removes the run state. An
interrupted run keeps it for `panel-review:resume`. If a command finds missing or invalid state, it
leaves the files in place for recovery or explicit `panel-review:discard`.

Set `cleanup.keep_tmp=true` to keep `/tmp/<ID>/` for inspection when cleanup or discard removes the
cards, marker, and `.git/info/exclude` entry. The saved verdict survives either way.

### The durable verdict file (`/tmp/<ID>.md`)

Each verdict is written to `/tmp/<ID>.md`, beside `/tmp/<ID>/`. It is the only file that carries the
report body. The command validates the artifact before returning its filename; the report body and
seat transcripts do not enter the main conversation. If the write fails, the run stays available for
resume and the command does not claim completion. `/tmp` is cleared on reboot, so copy the report to
permanent storage if you need to keep it.

Use `panel-review:result <ID>` to validate and print a finished report by ID. It does not resume the
run or call any seats. The artifact's frontmatter and validation rules are in the
[architecture reference](docs/architecture.md#schemas).

### Continuing a finished review

A review that ends with **contested** or **unresolved** issues is **kept**, not cleaned up (just like
the Round-0 low-severity gate). Push those issues further with:

- `panel-review:continue` — re-debate both contested and unresolved
- `panel-review:continue unresolved` — only unresolved
- `panel-review:continue contested` — only contested

`continue` takes **no scope, review profile, or instructions** — it adopts the stored values and
saved profile from the finished run (passing any of them is a hard error; `panel-review:status` shows
what's stored). It may override `--issue-rounds`, `--max-rounds`, and `--seat-timeout`; each explicit
override is saved before dispatch. It re-resolves the diff:
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

## Design record

The [ADRs](docs/adr/) hold accepted architecture decisions. [Evolution](docs/evolution.md) records
how the design changed and links to supporting records. This README and the
[architecture reference](docs/architecture.md) describe current behavior.

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
