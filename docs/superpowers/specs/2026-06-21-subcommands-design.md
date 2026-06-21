# Panel Review as a plugin with explicit subcommands — design

**Status:** proposed (design dialogue 2026-06-21)
**Goal:** Replace the single overloaded `/panel-review` command — which infers the user's intent
(fresh / resume / continue) from on-disk state and an `AskUserQuestion` — with a small set of
**explicit, deterministic** subcommands under a `panel-review` **plugin**. Each subcommand has one
job, one precondition, and one outcome.

## Why

The one-command design makes the tool guess what the user wants from state, and forces the user to
**re-state** the run's parameters so the guess matches:

- Resume is triggered by *re-typing the original scope*; it must match the stored scope.
- The later `--instructions` work made instructions part of the **resume identity**, so they had to
  be retyped **byte-for-byte** or the run was reported `moved`.
- `moved` therefore meant two unrelated things — "the code changed" *and* "you typed different
  guidance" — which is misleading.
- Disambiguation leaned on `AskUserQuestion` ("resume or fresh?"), which only exists because intent
  was implicit.

Explicit verbs remove the guessing: the user states intent directly, so the tool never has to infer
it, never has to match re-typed parameters, and the state logic shrinks to "does a session exist, and
in what state."

## User-facing commands

A `panel-review` plugin exposing five commands (plugin namespacing → the `plugin:skill` form):

| Command | Purpose | Takes | Precondition |
|---|---|---|---|
| `panel-review:start` | start a **fresh** review | scope (required) + instructions (optional) + limits | **no** session present |
| `panel-review:status` | list **all** sessions (normally one) + prereqs; **read-only** | — | always runs |
| `panel-review:resume` | pick up an **interrupted** run | limit overrides only | an interrupted session exists |
| `panel-review:continue` | re-debate a **finished** run's leftovers | `unresolved\|contested`; limit overrides only | a finished-with-leftovers session exists |
| `panel-review:discard` | delete **all** saved sessions for this workdir — normally one (reset) | — | runs whenever `.panel-review/` holds state |

`panel-review:start` is the **only** command that accepts scope and instructions. The session
remembers them; the others read them from the manifest.

`resume` and `continue` are **separate** because their signatures genuinely differ — `continue` takes
a leftover category, `resume` does not. Folding them into one verb would mean accepting-but-ignoring
an argument depending on hidden state, the exact mode-dependent behavior this redesign removes. The
shared **status precheck** (below) means a wrong guess is corrected with a pointer, not a failure — so
splitting costs the user nothing in discoverability.

> **Single-user, single-session mode — concurrent sessions on one workdir are not supported.** The
> tool assumes **one user running one Claude Code session** against a given workdir at a time. A
> workdir holds **exactly one** review session under normal use — `init_run` adopts an existing marker
> rather than minting a second, and `start` refuses when one already exists. **Running two `start`s
> concurrently against the same workdir is out of scope**: `init_run`'s adopt-on-lock means the loser
> silently receives the winner's ID, which is harmless for one user but undefined under true
> concurrency — don't do it (see Out of scope). More than one *session* can appear **only when the user
> interferes** with `.panel-review/`/`/tmp/` out of band — e.g. restoring a manifest from a backup *on
> top of* a live session, or copying a marker dir. `status` lists "all" and `discard` clears "all"
> purely so that this abnormal state is **inspectable and recoverable**; it is not an invitation to run
> several reviews at once. The docs and command output say so explicitly, so the wording is never
> mistaken for a feature.

### `panel-review:start`

- Parses scope (`--base`/`--uncommitted`/`--commit`/`<question>`), instructions (trailing text or
  `--instructions <text|auto>`), and limits — exactly the current Step 1 parsing.
- **Refuses if a session already exists** — `start` never silently destroys saved work; the user
  must clear it explicitly. The refusal is **state-aware**:
  - resumable / finished-with-leftovers →
    > A saved review exists (`<scope>`; instructions: «…»). `panel-review:resume` /
    > `panel-review:continue` to keep working it, or `panel-review:discard` to remove it.
  - **`diverged`** (the reviewed code changed since the snapshot — `resume_check`'s renamed `moved`
    verdict) → it can't be resumed or continued, so the only path forward is an explicit discard:
    > The working tree diverged from the reviewed snapshot — the code under review was modified since
    > this review started (`<scope>`; created `<time>`). It can't be resumed or continued; run
    > `panel-review:discard` before `panel-review:start`.
  This replaces the implicit "re-run resumes / different-scope asks to discard" behavior. Cleanly
  finished runs leave no session, so a normal next review is unaffected. A **stale** marker (its
  `/tmp/<ID>/` is gone) is cleaned first, then the fresh run proceeds.
  Note the `diverged` state is **expected, not corruption** — you started a review and kept coding —
  so the tone is "stale, discard to proceed," distinct from the `ambiguous` tamper guard.
  The message's noun **adapts to scope**: "working tree" for `--uncommitted` (staged/unstaged/untracked
  changed), "branch" for `--base X` (HEAD or the base moved), "commit" for `--commit SHA` (history
  rewritten). All resolve to the same machine condition — the freshly resolved diff's hash ≠ the stored
  `diff_hash`. (A `question=` scope has no diff, so it never diverges.)
- Otherwise: `init_run` → dispatch the referee `mode=fresh`. Unchanged downstream.

### `panel-review:status`

- Read-only. Never mutates, never dispatches. The user's window into the saved state.
- Runs `preflight` (seat/prereq availability — **subsumes `panel-review-init`**, which is retired)
  and inspects **every** marker under `.panel-review/` + each manifest/index.
- **Lists all sessions — normally exactly one.** Each entry shows its **creation time** (local
  wall-clock `yyyy-MM-dd HH:MM:SS`, read from the manifest), scope, instructions, limits, and state +
  progress:
  - interrupted (≥1 `open`) → progress (`round`, counts by state). "Pick it up with
    `panel-review:resume`."
  - finished with leftovers (`0` open, ≥1 `unresolved`/`contested`) → leftover counts. "Push it
    further with `panel-review:continue [unresolved|contested]`."
  - diverged (the current diff ≠ stored hash) → "the working tree diverged from the reviewed snapshot
    (the code under review was modified since this review started); it can't be resumed or continued —
    `panel-review:discard` before `panel-review:start`."
- When there are **no** sessions → "no saved review; `panel-review:start <scope>` to start one."
- In the normal **single-session** case the ID is omitted (noise — internal to the marker dir and
  `/tmp/<ID>/`). When the list has **more than one** — the interference case — `status` flags it
  *("more than one saved review; this only happens if `.panel-review/`/`/tmp/` was edited out of band —
  multiple reviews aren't supported")* and **shows each entry's `.panel-review/<ID>/` + `/tmp/<ID>/`**
  so the user can tell them apart by creation time and remove specific ones by hand if they don't just
  `panel-review:discard` the lot. Creation time is what makes the odd one out — e.g. a backup-restored
  manifest — easy to spot.

### `panel-review:resume` (interrupted run)

- **No scope, no instructions** — both come from the manifest; passing either is a hard error:
  > `panel-review:resume` takes the scope and instructions from the saved review; it doesn't accept
  > them. `panel-review:status` shows what's stored.
- **Limits may be overridden** (`--issue-rounds`/`--max-rounds`) and are **written back to the
  manifest** so the referee picks them up. Limits don't invalidate cached work — they only bound the
  loop — so an override is safe; scope/instructions are not overridable because they would invalidate
  Round-0 output produced under the original values.
- Runs only when the session is **interrupted** (≥1 `open`). Otherwise it points the user at the right
  command instead of failing blankly (the **redirect**, below).
- Dispatches the referee `mode=resume`, `debate-low=true`. Re-runs only missing seats/rounds; reopens
  nothing.

### `panel-review:continue [unresolved|contested]` (finished run's leftovers)

- Same no-scope/no-instructions rule and the same limit-override-written-back rule as `resume`.
- The **category** selects which leftovers to reopen (`both` when omitted). This is the signature
  difference from `resume`; it is meaningful only here, because reopening leftovers is an operation
  only the finished-run branch performs.
- Runs only when the session is **finished with leftovers** (`0` open, ≥1 leftover). Otherwise it
  redirects.
- Confirms the requested category has ≥1 issue, `reopen`s it, then dispatches `mode=resume`,
  `debate-low=true`.

### The redirect (shared precheck for `resume` / `continue`)

Both commands first read the session state (`resume_check` + the index). If it isn't the state this
command handles, the command **names the right command with the `status` one-liner of details — it
does not auto-run it** (auto-running would re-introduce implicit behavior, and `continue` would have
to assume a category on the user's behalf):

| Session state | `panel-review:resume` | `panel-review:continue` |
|---|---|---|
| interrupted (≥1 open) | **resumes** | "Not finished — it was interrupted mid-debate. Did you mean `panel-review:resume`? `<details>`" |
| finished w/ leftovers | "Nothing to resume. There's a finished review you can continue — `panel-review:continue`? `<details>`" | **continues** |
| none | "No saved review. Start one: `panel-review:start <scope>`." | same |
| diverged (code changed) | "The working tree diverged from the reviewed snapshot (code modified since this review started); it can't be resumed or continued — `panel-review:discard` before `panel-review:start`." | same |

`<details>` = the one-liner `status` prints (scope, instructions, progress/leftover counts), no ID.

**`diverged` gates both.** Resuming an interrupted run also re-resolves the diff and compares the stored
hash; if the tree changed, the cached cards reference stale code, so resume is as unsound as continue.
Both exit with the same message.

### `panel-review:discard`

- **The automatic cleanup / reset.** Removes **every** session for this workdir, then drops the
  `.panel-review/` dir (and its git-exclude line). In the normal one-session case "all" is just the
  one; in the `ambiguous` case it clears the lot, so the user never has to guess which marker is real.
- **Traversal (does not call `cleanup` per id).** The existing `cleanup` script runs
  `panel_require_id` and **hard-fails on an invalid id** (`cleanup:19`); a naïve loop calling it per
  marker would abort at the first garbage-named marker under `set -e` and leave the valid sessions
  uncleaned. `discard` instead does its own fault-tolerant pass:
  1. **Enumerate** the marker dirs under `.panel-review/` and **partition** by `panel_valid_id`.
  2. For each **valid** id → `rm -rf /tmp/<id>` and record the `<.panel-review/<id>/`, `/tmp/<id>/>`
     pair as removed. **The id-validation gate is mandatory before the `rm`** — a garbage marker name
     like `foo bar` would otherwise word-split into `rm -rf /tmp/foo /tmp/bar`. So an **invalid** name
     is *recorded as skipped* and its `/tmp` state is **left untouched** (it can't be safely mapped) —
     matching the "non-ID garbage left for manual cleanup, path named" promise.
  3. **`rm -rf .panel-review/`** wholesale (clears every marker — valid and garbage — plus strays like
     `.init.lock`) and remove its git-exclude line (`panel_git_exclude_del`). **Not** recreated — a
     reset leaves no dir and no exclude entry behind.
  4. **Report** every removed pair and every skipped path.
  Only `/tmp/<id>/` state and the in-tree `.panel-review/` go, consistent with `cleanup`. (If the
  deferred verdict-artifact plan lands, the sibling `/tmp/<id>.md` is **not** removed — `rm -rf
  /tmp/<id>` doesn't touch it.)
- The escape hatch the strict-`start`-precondition needs: a user blocked by an unwanted session runs
  `discard`, then `start`. Exits cleanly (no-op) if there is nothing to remove.
- It says "all," but normally clears exactly **one** — see the one-session note above. When it removes
  more than one it states so, since that only happens after out-of-band interference (e.g. a
  backup-restored manifest), and reports each pair removed so the action is auditable.

**Cleanup, in one line:** automatic → `panel-review:discard`; manual → remove the `.panel-review/<ID>/`
marker dir **and** its matching `/tmp/<ID>/` state dir yourself.

## Defensive states (not commands)

Two states are corruption guards the happy path cannot produce; they get no command of their own
(`status` reports them, the action commands bail on them), and every message **names both state
locations** so the user can fix it by hand:

- **ambiguous** — more than one valid marker in `.panel-review/`. The one-session invariant is
  enforced at creation (`init_run` takes `.init.lock`, then **adopts** any existing marker instead of
  minting a second), so this only arises out-of-band: manual edits to `.panel-review/`, an older tool
  version, leftovers, or a filesystem where `flock` doesn't hold (NFS/SMB/some overlays). `status` is
  the exception that **does** surface it — it *lists* the sessions (with creation times) and flags the
  state — precisely so the user can see what happened. The action commands must **not** guess which
  marker is real, so `resume`/`continue` bail rather than act on one. Recovery is just the reset —
  `discard` nukes them all, so the user doesn't have to identify the real one:
  > More than one review marker under `.panel-review/` (only possible if it was edited out of band).
  > `panel-review:discard` clears them all (then `panel-review:start` for a new review), or remove the
  > `.panel-review/<ID>/` + `/tmp/<ID>/` pairs by hand — `panel-review:status` lists them with creation
  > times.
- **stale** — a marker whose `/tmp/<ID>/` state is gone. `start` cleans the dead marker and proceeds;
  `resume`/`continue` (which mutate anyway) clean it and tell the user it was cleared (naming
  `.panel-review/<ID>/`). **`status`, being read-only, must NOT claim it cleared anything** — it
  reports the marker *remains* stale and names `.panel-review/<ID>/` for the user (or `discard`) to
  remove. No state to remove under `/tmp/`.

## Verdict artifact — split out (deferred)

The durable `/tmp/<ID>.md` verdict artifact, once part of this design, is **moved to its own plan**:
`docs/superpowers/specs/2026-06-21-verdict-artifact.md`. It is **independent of the subcommand split**
(it applies equally to the current single-command tool) and will be done **later, separately**. This
spec therefore assumes nothing about it — a clean finish still tears the session down as today.

## What gets simpler

- **`AskUserQuestion` nearly disappears.** Intent is in the verb, so there is no "resume or fresh?"
  prompt. The only remaining question is the **low-severity gate** (debate-low) inside a `start`,
  `resume`, or `continue` run. `diverged`/`ambiguous` become deterministic exits.
- **`resume_check`'s gate drops to `scope` + `diff_hash`.** Instructions leave the resume identity
  entirely (shown by `status`/the redirect instead of matched); limits leave it too (overridable). The
  instruction-in-resume-identity comparison added on 2026-06-21 is **removed**.
- **One session per workdir** stays the invariant; `status` inspects it, `discard` clears it.

## Architecture / change set

This is mostly **re-packaging the dispatcher prose** into per-command skills and deleting the
intent-inference — but **not purely** repackaging: two scripts need real behavioral edits, because
the new commands lean on them in ways the current single-command flow never did. Specifically,
`status` needs a **pure (write-free) per-session inspector** that the current `resume_check` cannot
provide (item 3), and `discard` needs an explicit **fault-tolerant traversal** the current per-id
`cleanup` loop cannot give under `set -e` (item 6). The rest is genuine repackaging.

1. **Plugin packaging.** Convert the `panel-review` skill into a **skills-directory plugin** — a
   single tree under `~/.claude/skills/panel-review/` carrying its own
   `.claude-plugin/plugin.json` (`"name": "panel-review"`). It loads as `panel-review@skills-dir`
   with **no marketplace and no install step beyond the copy**; commands are namespaced
   `panel-review:<cmd>`. Layout:

   ```
   ~/.claude/skills/panel-review/
     .claude-plugin/plugin.json              name "panel-review" → the namespace
     skills/start/SKILL.md                   → panel-review:start
     skills/status/SKILL.md                  → panel-review:status
     skills/resume/SKILL.md                  → panel-review:resume
     skills/continue/SKILL.md                → panel-review:continue
     skills/discard/SKILL.md                 → panel-review:discard
     skills/panel-review-for-agent/SKILL.md  internal (see frontmatter below)
     agents/panel-review-referee.md          moved inside the plugin tree
     agents/panel-review-claude-seat.md      moved inside the plugin tree
     scripts/…                               the existing deterministic scripts
   ```

   The seat agents and `scripts/` are unchanged in **role** — they only **move** into the plugin
   tree. Because the directory is a plugin (its `.claude-plugin/plugin.json` makes the whole
   `panel-review/` folder a plugin, not a loose skill), the generic command-folder names
   (`start`, `status`, …) are **always namespaced** (`panel-review:start`) and **cannot clash**
   with anything in `~/.claude/skills/`. A skills-dir plugin is **discovered in place** (not copied
   into the plugin cache), so the bundled scripts keep a stable path — but they still switch to
   `${CLAUDE_PLUGIN_ROOT}` (item 11) for correctness if distribution ever widens.

   **Per-command frontmatter:**

   | Skill | `disable-model-invocation` | `user-invocable` | rationale |
   |---|---|---|---|
   | `start`, `resume`, `continue`, `discard` | `true` | default | side effects — only the user triggers them (carries the current skill's flag). Critical for `discard` so the model never autonomously wipes a session. |
   | `status` | **omitted** | default | read-only; left model-invocable so a question like "what's the state of my review?" can auto-run it. |
   | `panel-review-for-agent` | **omitted** | `false` | hidden from the `/` menu via `user-invocable: false`, **not** `disable-model-invocation` — that flag *also* blocks preloading the skill into the referee subagent, which this skill depends on. |

   Each subcommand also carries its **own** `argument-hint` — the current single overloaded hint
   splits per verb (`start` keeps scope+instructions+limits; `resume`/`continue` show only limit
   overrides + `continue`'s category; `status`/`discard` take none).
2. **`start`** = current Step 1 (parse) + Step 2 (resolve+hash) + the `fresh` branch of Step 3 +
   Step 4 dispatch, plus the **refuse-if-session-exists** precondition (any non-`fresh`/`stale`
   verdict → stop and point at `resume`/`continue`/`discard`; `stale` → clean the dead marker and
   proceed).
3. **`status`** = `preflight` + **enumerate every marker** under `.panel-review/` + per-manifest read
   of creation time/scope/instructions/limits, formatted as a list (one entry in the normal case). New,
   read-only; a small formatter, inline in the skill.
   - **`status` cannot reuse `resume_check`.** That script (a) **writes** — it repairs a corrupt
     `index.json` from `index.json.bak` via `panel_atomic_write` (`resume_check:52-55`); (b) returns
     only `ambiguous` when more than one marker exists (`:44`), never classifying each entry; and (c)
     compares **command-arg** inputs, not manifest-derived values (`:70`). All three conflict with a
     read-only, per-entry `status`.
   - **New, separate script `inspect_run --id ID --workdir DIR`** (a clean pure/read-only script, **not**
     a mode of `resume_check` — `resume_check` keeps its repair + command-arg contract for the action
     commands; a read-only flag bolted onto it would be easy to regress into writing). It
     validates/parses **one** manifest + index **without any recovery write**,
     resolves **that manifest's own** diff to compare against its stored `diff_hash`, and returns a
     structured state/progress result (`interrupted|continuable|diverged|stale` + counts). `status`
     iterates the markers, calling `inspect_run` per ID, and **lists even if `preflight` fails** —
     reporting unavailable prerequisites *beside* the saved state, not instead of it. Repair and
     stale-marker cleanup stay in the **action** commands only.
4. **`resume`** = adopt scope/limits/instructions from the manifest + Step 2 diff-hash gate + the
   interrupted branch, minus every `AskUserQuestion`; adds the limit-override write-back, the
   no-scope/no-instructions guard, and the redirect for non-interrupted states.
5. **`continue`** = same as `resume` for the finished-with-leftovers branch, plus the category +
   `reopen` (the existing continue-leftovers logic), and its own redirect.
6. **`discard`** = the fault-tolerant traversal in the `discard` section above — enumerate markers,
   partition by `panel_valid_id`, `rm -rf /tmp/<id>` for valid ids (validation gate **before** the
   `rm`), record garbage-named markers as *skipped* without touching their `/tmp`, then `rm -rf` the
   whole `.panel-review/` dir + drop its git-exclude line, and report removed pairs + skipped paths.
   It **does not** call the per-id `cleanup` script (whose `panel_require_id` would abort the loop on a
   garbage marker under `set -e`). Leaves any future `/tmp/<id>.md` verdict artifact intact (deferred
   plan).
7. **`resume_check`**: remove `--instructions` from the gate (revert that part of the 2026-06-21
   change); keep `--scope`/`--diff-hash`; **rename the `moved` verdict to `diverged`** (one pass across
   `resume_check`, the dispatcher, and the continue-leftovers spec). Resulting verdict set:
   `fresh|resume|continuable|stale|diverged|ambiguous` — the commands route on it.
8. **`init_run`**: store the manifest `created` as **local wall-clock `yyyy-MM-dd HH:MM:SS`** (was ISO
   `date -Is`) so `status` can display it and the user can spot, e.g., a backup-restored session. (If
   machine-sortability is ever needed, keep the ISO value in a separate field; for now the human form
   is the only consumer.) Set once at creation, so it travels with a restored manifest unchanged.
9. **Templates / `index` / `reopen` / `sweep`**: unchanged. Instructions are still stored in the
   manifest and injected into the seat prompts as today; only the *resume-identity* use of
   instructions is dropped.
10. **Retire `panel-review-init`** — `status` covers prereqs.
11. **Script paths → `${CLAUDE_PLUGIN_ROOT}`.** Replace the hardcoded
    `SC="$HOME/.claude/skills/panel-review/scripts"` (and any sibling path) in every command skill
    and `panel-review-for-agent` with `${CLAUDE_PLUGIN_ROOT}/scripts`. Under the chosen skills-dir
    install this resolves to the same location, so it is **not** load-breaking today; it matters only
    if the plugin is ever served from a marketplace (where the plugin is copied into a cache and
    out-of-tree paths break). Low risk, mechanical, done for portability.
    - **Verified (CC 2.1.185).** `${CLAUDE_PLUGIN_ROOT}` is resolved by **skill-content
      substitution** — Claude Code expands the literal in the `SKILL.md` text *before* the model
      runs the bash block — **not** as a shell env var (it is `<UNSET>` in the Bash-tool shell;
      only `CLAUDECODE`, `CLAUDE_CODE_*`, `CLAUDE_EFFORT` are exported). Two consequences for
      maintainers: (a) the literal `${CLAUDE_PLUGIN_ROOT}` must appear **verbatim** in the skill
      text — don't build it dynamically, and don't read `$CLAUDE_PLUGIN_ROOT` from the environment
      at runtime (it's empty there; the bundled scripts correctly avoid this, deriving their own dir
      via `dirname "$0"` and taking paths as args). (b) It's content-substitution, so it works in
      the command skills **and** in `panel-review-for-agent` once that skill's text is rendered into
      the referee. The documented per-skill fallback `${CLAUDE_SKILL_DIR}/../../scripts` also
      resolves (each command skill sits two levels below the plugin root) if this ever regresses.
      A one-line comment guards the `SC=`/`PR=` lines in each skill so the literal isn't refactored
      away.
12. **`install.sh` cutover.** install.sh copies the **single plugin tree** into
    `~/.claude/skills/panel-review/` (instead of three skills + two agents into separate dirs) and
    keeps the exec-bit fix-up on `scripts/`. It must **remove the pre-plugin layout** on install —
    the old `~/.claude/skills/{panel-review,panel-review-for-agent,panel-review-init}` plain skills
    and `~/.claude/agents/panel-review-{referee,claude-seat}.md` — because **both project- and
    user-level** `agents/` definitions **outrank a plugin agent** (plugin agents are lowest priority,
    Claude Code `sub-agents.md:175`), so a stale same-named copy at *either* scope silently shadows the
    plugin's. Removing the user-level copies is necessary but **not sufficient** — also warn on any
    project-level `.claude/agents/panel-review-*.md`. Removal/uninstall for the user: delete the folder
    or `claude plugin disable panel-review@skills-dir`.
13. **Qualify every internal component reference.** Once the skills and agents live in the plugin they
    are **namespaced**, and bare-name references can silently fail to resolve (Claude Code `changelog.md`
    fix #25834: *"plugin agent skills silently failing to load when referenced by bare name instead of
    fully-qualified plugin name"*). Rewrite:
    - the referee's preload `skills:\n  - panel-review-for-agent` →
      `skills:\n  - panel-review:panel-review-for-agent` (`agents/panel-review-referee.md`);
    - every seat spawn `subagent_type: panel-review-claude-seat` →
      `panel-review:panel-review-claude-seat` (`skills/panel-review-for-agent/SKILL.md:86,288,477`);
    - the dispatcher's referee invocation → `subagent_type: panel-review:panel-review-referee`.
    Newer Claude Code resolves bare names when unambiguous, but the qualified form is robust and
    self-documenting. Put the **exact** five command names *and* these qualified internal names in the
    load smoke test (item 14).
14. **Plugin-integration smoke test** (detailed in Testing). Load checks script fixtures can't cover:
    `claude plugin validate`, plugin discovery/namespace resolution, the internal skill being hidden,
    preload into the referee, and the seat spawn. **No programmatic version floor** — the referee
    spawning each seat is a *nested* subagent that needs a recent Claude Code, but a pinned version
    number would rot (both this repo and Claude Code move fast) and the failure mode is a **visible**
    spawn error, not silent corruption. So the requirement is **documented** ("use the latest Claude
    Code") in the README rather than checked in `preflight`/`install.sh`. `claude --version` exists
    (`2.1.x`) if a check is ever wanted, but it is deliberately not added now.

## Migration / compatibility notes

- This **changes the entry UX**: the old `/panel-review <scope>` becomes `panel-review:start <scope>`,
  and "re-run the same command to resume" goes away — resume is now `panel-review:resume`, continue
  `panel-review:continue`. The README and argument hints are rewritten around the verbs.
- **Distribution stays local.** install.sh installs the plugin into `~/.claude/skills/panel-review/`
  (a skills-dir plugin, `panel-review@skills-dir`); no marketplace. The cutover removes the old
  non-plugin skills/agents (change-set item 14) so the new plugin's components aren't shadowed by
  stale user-level copies.
- Pre-existing manifests carry an `instructions` field (or not — `// ""`); since instructions leave
  the gate, old sessions resume regardless. No state migration needed.
- `agents/` references to `/panel-review …` flags are updated to the verbs (e.g.
  `agents/panel-review-referee.md` mentions `--continue`). The `.superpowers/sdd/` files are
  **left untouched** — they are historical build artifacts (task reports, diffs), not interface, and
  rewriting them would falsify the record.

## Out of scope

- Multi-session / cross-workdir management and a `--resume <ID>` selector — unnecessary under the
  one-session-per-workdir invariant; revisit only if that invariant is relaxed.
- **Concurrent `start` on the same workdir (single-user, single-session mode).** Two `start`s racing
  against one workdir is unsupported by design. `init_run` mints/`mkdir`s `/tmp/<ID>` *before* taking
  `.init.lock` and, after the lock, **silently adopts** any existing marker and returns the winner's
  ID — indistinguishable from a freshly created one (`init_run:43-48,69-77`). Under one user this never
  triggers; under true concurrency the loser could dispatch `mode=fresh` against the winner's manifest.
  A clean fix exists (have `init_run` return `created <id>` vs `exists <id>` and make `start` refuse on
  `exists`) and is **welcome if cheap**, but it is **not a blocker** — the single-session assumption
  (see the "Single-user, single-session mode" note above) makes the race unreachable in practice.
- Partial-issue continuation (still whole categories only).
- Any change to the blind-debate engine, the seats, or the index math.

## Resolved decisions

1. **`discard` is act-and-report — no typed confirm.** Typing the command is itself the intent, and a
   rare mistaken invocation (e.g. tab-completion) is low-harm: it only removes local, regenerable
   state, and the just-shown verdict is still in the conversation transcript (and, once the deferred
   verdict-artifact plan lands, in `/tmp/<ID>.md`). It reports each pair it removed.
2. **`status` shows machine state only**, not the last verdict. The session is still on disk, so the
   user can read the files directly; and a cleanly finished run's verdict was already shown in the
   transcript. No need to re-render it.
3. ~~Rename the `moved` verdict.~~ **`diverged`** ("moved" read like files were relocated; the state
   means the reviewed code/diff changed since the snapshot). Prose stays "the code changed since this
   review." The token rename spans `resume_check`, the dispatcher, and the continue-leftovers spec —
   one pass (change-set item 7).
4. **Skills-dir plugin via `install.sh`, not a marketplace.** One user plus a few others, no real
   test suite (testing is install-and-use), so a marketplace's discovery/versioning/auto-update buys
   nothing and adds a cache-copy step; the plugin installs straight to `~/.claude/skills/panel-review/`.
   Generic command-folder names (`start`, …) are safe because plugin namespacing always prefixes them
   (`panel-review:start`) — the clash concern only applies to *loose* skills in `~/.claude/skills/`,
   which these are not. Switch to a marketplace only if distribution widens (then item 11's
   `${CLAUDE_PLUGIN_ROOT}` becomes load-critical).
5. **`status` stays model-invocable; the internal skill uses `user-invocable: false`.** The four
   action verbs get `disable-model-invocation: true` (side effects — the model must not trigger them,
   especially `discard`). `status` is read-only, so it's left model-invocable to answer status
   questions. `panel-review-for-agent` is hidden with `user-invocable: false` rather than
   `disable-model-invocation`, because the latter would also stop it being preloaded into the referee
   subagent — which it requires. (Frontmatter table in change-set item 1.)

## Testing

**Script-level (as today).** No bash test harness in the repo; verify each command path with ad-hoc
fixtures: build a small `.panel-review/<ID>/` marker + `/tmp/<ID>/{manifest,index}.json` in a temp git
repo, run the command's script steps, and assert the verdict/output and the manifest mutation with
`jq` — mirroring how the continue-leftovers and epoch work were checked. Add cases for the two new
behaviors: `inspect_run` makes **no writes** (diff the `/tmp/<ID>/` tree before/after; assert a corrupt
`index.json` is *not* repaired), and `discard` clears valid sessions **while** a garbage-named marker
is present (assert valid `/tmp/<id>` gone, garbage `/tmp` untouched and its path reported, `.panel-review/`
removed).

**Plugin-integration (script fixtures can't cover these).** Discovery, namespace resolution, hidden
internal skill, and plugin-agent loading need a real host:

- `claude plugin validate <plugin-root>` (consider `--strict`);
- load from `~/.claude/skills/panel-review/` (or `claude --plugin-dir <root>` for dev) and assert the
  **five exact** `panel-review:<verb>` commands appear and **no** user-invocable internal protocol does;
- preload of `panel-review:panel-review-for-agent` into the referee and a successful spawn of
  `panel-review:panel-review-claude-seat`;
- a **shadow check** — warn if a project- *or* user-level `.claude/agents/panel-review-*.md` exists,
  since either outranks the plugin agent.
