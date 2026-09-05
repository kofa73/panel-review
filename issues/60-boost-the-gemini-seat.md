# Run the Gemini seat under agy's `/boost`

Priority: 60

Status: Pending

Source: Owner request, 2026-09-05 — observed `/boost` in interactive agy use (slower but
substantially better reasoning) and asked for it to be always on for the Gemini seat.
Installed agy at filing: **1.1.27**. Reference: <https://antigravity.google/docs/boost/>.

Triage: ready-for-human

## Problem

The Gemini seat runs whatever reasoning agy does by default. `/boost` produces noticeably better
analysis at the cost of speed, and that trade is the one this panel wants: a blind review seat is
quality-bound, not latency-bound, and the wrapper already budgets 15 minutes per attempt.
`scripts/run_agy` has no way to request it.

## What `/boost` actually is

Per Google's documentation, `/boost` is **not** a reasoning-effort dial. It is an on-demand
**multi-agent pipeline**:

1. A Primary Orchestrator reads the prompt, inspects workspace context, and decides which
   workstreams are needed.
2. **Subagents run in parallel in ephemeral isolated worktrees**, "constructing code solutions,
   performing root-cause debugging, and validating hypotheses through **local test execution**".
3. Results are synthesized, **regression checks run**, and failures feed automated correction cycles.

It is available on **paid plans only**, and is documented as working in "Antigravity 2.0 and
Antigravity CLI". Execution is described as ranging "from seconds to hours".

## The tension to resolve before adopting it

`/boost` is a *build-it-and-test-it* problem-solving pipeline. A panel seat is a **write-nothing,
read-only reviewer**. Three of the plugin's hard constraints sit directly in its path, and none of
them is a matter of the seat disobeying — the pipeline does these things by design:

1. **"Seats write nothing inside the repository under review — tracked or not, which rules out
   builds"** (`issues/57`). `/boost` runs local tests and regression checks. Anything it builds or
   writes inside the workdir is drift `repo_guard` was never designed to catch: `verify --restore`
   reverts *tracked*-file drift only, and untracked build output and `.git/worktrees/` bookkeeping
   are outside its reach.
2. **Ephemeral worktrees have to live somewhere.** A git worktree cut from the repository under
   review registers itself under that repository's `.git/`, i.e. inside the workdir. If that is what
   happens, `/boost` violates constraint 1 on every pass, silently. If instead the worktrees are cut
   inside agy's own managed scratch (`~/.gemini/antigravity-cli/scratch`), the constraint is
   satisfied — but that is an assumption, and agy is already the seat that *guesses* its own repo
   root (`AGENTS.md`, "Seat working directory"), so it is the seat least likely to put things where
   the panel expects.
3. **More agents, more search surface, same blindness requirement.** `/tmp/<ID>/` stays readable by
   every seat; `issues/24` closed the accidental-hit path by moving scratch *out* of the repo, not by
   confining anyone. A pipeline that fans out to parallel subagents multiplies the number of
   independent searches per pass, so the accidental-hit probability that motivated `issues/24` goes
   up, not down.

None of this makes the request wrong — it makes it a change with a measurable blast radius rather
than a flag flip. The measurements below are what turns it into one or the other.

## What is established

- **Slash commands are expanded in agy print mode, and the panel's prompt path is print mode.**
  `agy --help` on 1.1.27 documents `--disable-slash-commands  Disable slash command and skill
  expansion in print mode`, which only makes sense if expansion is on by default there.
- **The leading-command-then-newline form parses.** agy's changelog records "Fixed slash commands
  not being recognized when separated from their arguments by a newline or tab", and separately
  "Added support for stacking multiple leading slash commands in a single prompt". So
  `/boost\n<the whole seat prompt>` is the shape to use.
- **Nothing in the panel's prompts starts with a slash today**, so adding a leading command cannot
  collide with existing text: both templates begin with `{{SEAT_CONTRACT}}`, and
  `seat_contract.render_contract` starts with `You are performing…` / `You are continuing…`.
- **It is maintained.** agy 1.1.25 records "Fixed /boost failing at runtime by improving worker tool
  configurations" — consistent with the documented subagent pipeline.

## Measurements required before shipping

1. **Does it bind on `run_agy`'s invocation form?** `run_agy` feeds the prompt on **stdin with no
   `--print` flag** (see its header for why). That is print mode in effect, but the documentation
   says "Antigravity CLI" without distinguishing interactive from headless, and the owner's
   observation is interactive. Confirm from agy's CLI log that the command ran rather than being
   sent to the model as literal text.
2. **Where do the worktrees and any test output land?** The decisive measurement. Run a boosted pass
   against a scratch repository, then check: `git worktree list` in the workdir, `.git/worktrees/`,
   `git status --porcelain` including untracked files, and `repo_guard verify`. If anything lands
   inside the workdir, `/boost` cannot be adopted as-is and this issue becomes a question about
   whether agy can be pointed elsewhere.
3. **Does it change the output shape?** The seat contract requires a fenced JSONL block and nothing
   else. If the pipeline prepends a plan, a worker summary, or a regression report, `parse_block`
   sees a malformed or missing block (status 4/5) and the seat is salvaged or dropped every round.
4. **Does it fit the timeout budget?** "Seconds to hours" against `PRINT_TIMEOUT="15m"` and
   `WALL_TIMEOUT=1020`, with a fallback attempt costing a second full budget. Measure a real
   Round-0-sized prompt end to end. If boosted passes routinely exceed 15m, this issue must raise
   both values — a separate decision from turning `/boost` on.
5. **How does it fail without entitlement?** Paid plans only. Establish what an unentitled account
   gets: a clean error (fine — `attempt()` reads it as a failed attempt), or the prompt silently
   running unboosted (fine but invisible), or the literal text `/boost` reaching the model (not
   fine — it corrupts the first line of the seat prompt). Case three decides whether `preflight`
   needs an entitlement check.

## Expected behavior

- `scripts/run_agy` prepends the boost command to the prompt it feeds agy, as a **wrapper-owned
  prefix** — the assembled prompt file the panel froze at Round 0 stays byte-identical on disk, so
  the recorded prompt artifact and the Codex seat's prompt remain the same text. The prefix belongs
  in `run_agy` for the same reason the model pin does: seats are called only through their wrapper.
- The seat prompt's write-nothing rule is restated in a form a *sub*agent will also see, or this
  issue records that it cannot be and what that costs. The rule currently addresses "you, the seat";
  under `/boost` the entity doing the writing is a worker the seat spawned.
- The wrapper header explains what `/boost` is (multi-agent, worktrees, test execution), why it is
  on, the agy version it was measured on, and what measurement 2 found. That last part is the one a
  future reader needs most.
- An escape hatch exists: an environment override (e.g. `AGY_BOOST=0`) or a single named constant at
  the top of the wrapper, next to `PRIMARY_MODEL`. Do not bury the on/off decision inside the
  invocation line.
- `check_contracts` gains whatever pin keeps the prefix from being silently dropped, in the
  structural form `issues/46` asks for — assert that the wrapper prepends *a* leading command, not
  the exact English of the header sentence.

## Verification

- A boosted `run_agy` run against a real Round-0 prompt returns a block `parse_block` accepts at
  exit 0, and agy's CLI log shows the command was recognized.
- Measurement 2's checks are clean after a boosted pass: no new worktree, no untracked file, and no
  `repo_guard` drift inside the workdir.
- The same run with the escape hatch off produces the unboosted behavior, unchanged.
- Wall-clock time for the boosted pass is recorded in this issue, against `PRINT_TIMEOUT`.
- `scripts/check_contracts --root .` and `./tests/run_tests.sh` pass.
- One real three-seat review completes with the Gemini seat boosted, and its verdict is compared
  against an unboosted run of the same scope — the point of the change is review quality, so it
  should be observed, not assumed.

## Non-goals

- Do not boost the Codex or Claude seats. This is an agy feature; the panel does not need the three
  seats to reason identically, only to review the same material blind.
- Do not change the model pins here (`issues/21`) or the print-timeout detection (`issues/59`),
  even though both are in the same file.
- Do not raise `PRINT_TIMEOUT` / `WALL_TIMEOUT` as part of this issue unless measurement 4 forces
  it; if it does, state the new values and the measurement that justified them.
- Do not add `--disable-slash-commands`; adopting `/boost` requires expansion to stay on. See
  `issues/61` for that flag's decision and for the invariant it makes necessary.
- Do not weaken `repo_guard` or the write-nothing rule to accommodate the pipeline. If measurement 2
  shows `/boost` writes inside the workdir, the answer is to relocate it or drop it, not to stop
  checking.
