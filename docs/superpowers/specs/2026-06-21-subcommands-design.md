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

> **Multiple sessions are not a supported mode.** A workdir holds **exactly one** session under normal
> use — `init_run` enforces this (it adopts an existing marker rather than minting a second), and
> `start` refuses when one already exists. More than one can appear **only when the user interferes** with
> `.panel-review/`/`/tmp/` out of band — e.g. restoring a manifest from a backup *on top of* a live
> session, or copying a marker dir. `status` lists "all" and `discard` clears "all" purely so that this
> abnormal state is **inspectable and recoverable**; it is not an invitation to run several reviews at
> once. The docs and command output say so explicitly, so the wording is never mistaken for a feature.

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

- **The automatic cleanup / reset.** Removes **every** session for this workdir: for each marker under
  `.panel-review/<ID>/` it `cleanup`s both the marker **and** its `/tmp/<ID>/` state, then drops the
  `.panel-review/` dir (and its git-exclude line). Reports each `<.panel-review/<ID>/`, `/tmp/<ID>/>`
  pair it removed. In the normal one-session case "all" is just the one; in the `ambiguous` case it
  clears the lot, so the user never has to guess which marker is real.
- IDs are validated before any `rm` (the existing `cleanup`/`panel_require_id` guard), so it only ever
  touches this workdir's `.panel-review/` and the `/tmp/<ID>/` dirs those valid markers name. Leftover
  `/tmp/<ID>/` state whose marker has a **non-ID (garbage) name** can't be safely mapped → it is left
  for **manual** cleanup, with the path named (see below).
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
  `resume`/`continue`/`status` treat it as "no usable session" and tell the user it was cleared
  (naming `.panel-review/<ID>/`). No state to remove under `/tmp/`.

## Verdict artifact (survives cleanup)

A clean finish tears down the session (`.panel-review/<ID>/` + `/tmp/<ID>/`), so today the verdict
lives **only** in the conversation transcript. To give the user a durable, movable copy without
polluting the working tree, the referee **writes the verdict to a markdown file under `/tmp/` that
cleanup does not touch**.

- **Path:** `/tmp/<ID>.md` — a **sibling** of `/tmp/<ID>/`, not inside it, so the `rm -rf /tmp/<ID>`
  in cleanup leaves it intact. The ID already begins with `panel-<timestamp>-…`, so the filename is
  self-identifying and unique.
- **When:** whenever a verdict is **produced**, not only at cleanup — so preserved runs (gated /
  finished-with-leftovers) also get a file, and a `continue` that produces a new verdict refreshes it.
  Decoupling from cleanup means every verdict the user sees has a matching file.
- **Contents:** a self-contained report — a metadata header (scope; instructions/"prompt"; limits;
  seats that engaged + any down; rounds; `created` + finished local times; `diff_hash` for
  correlation; the ID) followed by the verdict markdown verbatim. The **full diff is not embedded** —
  it is large and reproducible from the scope; the `diff_hash` is the reference.
- **Surfacing:** the command (`start`/`resume`/`continue`) appends one line after the verdict — e.g.
  *"Saved to `/tmp/<ID>.md` — move it somewhere permanent to keep it (`/tmp` is cleared on reboot)."*
  The referee writes the file; the command knows the ID, so it prints the path.
- **`discard` writes nothing** — it abandons a session without producing a verdict; any prior verdict
  already has its `/tmp/<ID>.md` from when it was shown.

This is **independent of the subcommand split** — it applies equally to the current single-command
tool — so it can land separately if desired.

## What gets simpler

- **`AskUserQuestion` nearly disappears.** Intent is in the verb, so there is no "resume or fresh?"
  prompt. The only remaining question is the **low-severity gate** (debate-low) inside a `start`,
  `resume`, or `continue` run. `diverged`/`ambiguous` become deterministic exits.
- **`resume_check`'s gate drops to `scope` + `diff_hash`.** Instructions leave the resume identity
  entirely (shown by `status`/the redirect instead of matched); limits leave it too (overridable). The
  instruction-in-resume-identity comparison added on 2026-06-21 is **removed**.
- **One session per workdir** stays the invariant; `status` inspects it, `discard` clears it.

## Architecture / change set

The deterministic scripts already do the work; this is mostly **re-packaging the dispatcher prose**
into per-command skills and deleting the intent-inference.

1. **Plugin layout.** Convert the `panel-review` skill into a plugin exposing `start`, `status`,
   `resume`, `continue`, `discard` (addressed as `panel-review:<cmd>`). The internal skill
   (`panel-review-for-agent`) and the seat agents and `scripts/` are unchanged in role.
2. **`start`** = current Step 1 (parse) + Step 2 (resolve+hash) + the `fresh` branch of Step 3 +
   Step 4 dispatch, plus the **refuse-if-session-exists** precondition (any non-`fresh`/`stale`
   verdict → stop and point at `resume`/`continue`/`discard`; `stale` → clean the dead marker and
   proceed).
3. **`status`** = `preflight` + **enumerate every marker** under `.panel-review/` (classify each via
   `resume_check`/the index) + per-manifest read of creation time/scope/instructions/limits, formatted
   as a list (one entry in the normal case). New, read-only; a small formatter, inline in the skill.
4. **`resume`** = adopt scope/limits/instructions from the manifest + Step 2 diff-hash gate + the
   interrupted branch, minus every `AskUserQuestion`; adds the limit-override write-back, the
   no-scope/no-instructions guard, and the redirect for non-interrupted states.
5. **`continue`** = same as `resume` for the finished-with-leftovers branch, plus the category +
   `reopen` (the existing continue-leftovers logic), and its own redirect.
6. **`discard`** = iterate **every** marker under `.panel-review/`, `cleanup` each (marker +
   `/tmp/<ID>/`), drop the now-empty `.panel-review/` dir and its git-exclude line, and report each
   removed `<.panel-review/<ID>/`, `/tmp/<ID>/>` pair.
7. **`resume_check`**: remove `--instructions` from the gate (revert that part of the 2026-06-21
   change); keep `--scope`/`--diff-hash`; **rename the `moved` verdict to `diverged`** (one pass across
   `resume_check`, the dispatcher, and the continue-leftovers spec). Resulting verdict set:
   `fresh|resume|continuable|stale|diverged|ambiguous` — the commands route on it.
8. **`init_run`**: store the manifest `created` as **local wall-clock `yyyy-MM-dd HH:MM:SS`** (was ISO
   `date -Is`) so `status` can display it and the user can spot, e.g., a backup-restored session. (If
   machine-sortability is ever needed, keep the ISO value in a separate field; for now the human form
   is the only consumer.) Set once at creation, so it travels with a restored manifest unchanged.
9. **Referee**: at verdict time, **write the verdict report to `/tmp/<ID>.md`** (the survives-cleanup
   artifact above) before any teardown. Otherwise unchanged.
10. **Commands (`start`/`resume`/`continue`)**: after presenting the verdict, append the one-line
    *"Saved to `/tmp/<ID>.md` …"* pointer (they know the ID).
11. **Templates / `index` / `reopen` / `sweep`**: unchanged. Instructions are still stored in the
    manifest and injected into the seat prompts as today; only the *resume-identity* use of
    instructions is dropped.
12. **Retire `panel-review-init`** — `status` covers prereqs.

## Migration / compatibility notes

- This **changes the entry UX**: the old `/panel-review <scope>` becomes `panel-review:start <scope>`,
  and "re-run the same command to resume" goes away — resume is now `panel-review:resume`, continue
  `panel-review:continue`. The README and argument hints are rewritten around the verbs.
- Pre-existing manifests carry an `instructions` field (or not — `// ""`); since instructions leave
  the gate, old sessions resume regardless. No state migration needed.
- `agents/` references to `/panel-review …` flags are updated to the verbs (e.g.
  `agents/panel-review-referee.md` mentions `--continue`). The `.superpowers/sdd/` files are
  **left untouched** — they are historical build artifacts (task reports, diffs), not interface, and
  rewriting them would falsify the record.

## Out of scope

- Multi-session / cross-workdir management and a `--resume <ID>` selector — unnecessary under the
  one-session-per-workdir invariant; revisit only if that invariant is relaxed.
- Partial-issue continuation (still whole categories only).
- Any change to the blind-debate engine, the seats, or the index math.

## Resolved decisions

1. **`discard` is act-and-report — no typed confirm.** Typing the command is itself the intent, and a
   rare mistaken invocation (e.g. tab-completion) is low-harm: it only removes local, regenerable
   state, and the just-shown verdict survives as the saved artifact (below). It reports each pair it
   removed.
2. **`status` shows machine state only**, not the last verdict. The session is still on disk, so the
   user can read the files directly; and a cleanly finished run's verdict was already shown (and saved,
   below). No need to re-render it.
3. ~~Rename the `moved` verdict.~~ **`diverged`** ("moved" read like files were relocated; the state
   means the reviewed code/diff changed since the snapshot). Prose stays "the code changed since this
   review." The token rename spans `resume_check`, the dispatcher, and the continue-leftovers spec —
   one pass (change-set item 7).

## Testing

No bash test harness in the repo; verify each command path with ad-hoc fixtures: build a small
`.panel-review/<ID>/` marker + `/tmp/<ID>/{manifest,index}.json` in a temp git repo, run the command's
script steps, and assert the verdict/output and the manifest mutation with `jq` — mirroring how the
continue-leftovers and epoch work were checked.
