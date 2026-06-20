# Continue a finished review (`--continue`) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to
> implement this plan task-by-task.

**Goal:** Add `/panel-review --continue [unresolved|contested]` to re-debate a finished run's
leftover issues with a fresh round budget, without re-reviewing settled issues.

**Architecture:** Re-opened issues become ordinary `open` issues with zeroed counters — identical to
a Round-0-gated run — so the referee's existing `mode=resume` path drives the continuation unchanged.
New logic lives in deterministic scripts (`index reopen`, `reopen`, `resume_check`) plus dispatcher
flag handling and one referee skip-cleanup exception.

**Tech Stack:** bash + jq. No test framework — verify each script with an ad-hoc `/tmp` fixture.

## Global Constraints

- `index.json` is written **only** through the `index` (and `sweep`) scripts — never hand-write it.
  The new `reopen` script delegates its `index.json` mutation to `index reopen`.
- Validate every `<ID>` with `panel_require_id`/`panel_valid_id` before any `rm`/path use.
- All `/tmp/<ID>/...` state writes are atomic (`panel_atomic_write`) where they touch `index.json`.
- `card_rev` is **bumped, never zeroed** (stale-card detection depends on monotonicity).
- `--continue` sources scope + limits from the finished run; never combine it with a scope/limit flag.
- Category vocabulary is exactly `both` | `unresolved` | `contested`.
- Counter reset on re-open: per selected issue `state→open`, `rounds_debated→0`,
  `peer_reviewed→false`, `fully_vetted→false`, `detail_contested→false`, `card_rev` bumped; global
  `round→0`, `committed_rounds→[]`. Evidence and origins are kept. Non-selected issues untouched.

---

### Task 1: `index reopen <ID> <category>` subcommand

**Files:**
- Modify: `skills/panel-review/scripts/index`

**Interfaces:**
- Produces: `index reopen <ID> both|unresolved|contested` — mutates `index.json`; exit 3 if no issue
  in that category exists; exit 2 on bad category.

- [ ] **Step 1: Add `reopen` to the lock list.** Change line 43 from
  `  put|bump|state|flag|commit-round|commit-sweep)` to
  `  put|bump|state|flag|commit-round|commit-sweep|reopen)`

- [ ] **Step 2: Add the `reopen` case** (in the second `case "$cmd"`, before the `*)` usage line):

```bash
  reopen)
         cat="${3-}"
         case "$cat" in both|unresolved|contested) ;; *) echo "index reopen: category must be both|unresolved|contested" >&2; exit 2;; esac
         # Count matches first so the caller can distinguish "nothing to do" (exit 3).
         n="$(jq --arg cat "$cat" '[.issues[] | select(
                ($cat=="both" and (.state=="unresolved" or .state=="contested"))
                or ($cat=="unresolved" and .state=="unresolved")
                or ($cat=="contested" and .state=="contested"))] | length' "$f")"
         if [ "$n" -eq 0 ]; then echo "index reopen: no $cat issue to re-open" >&2; exit 3; fi
         # Re-open selected issues + reset global counters; keep evidence; bump card_rev.
         mutate '
           .committed_rounds=[] | .round=0
           | (.issues[] | select(
               ($cat=="both" and (.state=="unresolved" or .state=="contested"))
               or ($cat=="unresolved" and .state=="unresolved")
               or ($cat=="contested" and .state=="contested")
             )) |= (.state="open" | .rounds_debated=0
                    | .peer_reviewed=false | .fully_vetted=false | .detail_contested=false
                    | .card_rev=((.card_rev//0)+1))
         ' --arg cat "$cat" ;;
```

- [ ] **Step 3: Update the usage line** (last `*)` echo) to include `reopen`:
  `  *) echo "usage: index {get|put|issue|bump|state|flag|commit-round|commit-sweep|reopen} <ID> ..." >&2; exit 2 ;;`

- [ ] **Step 4: Update the header doc block.** After the `index flag` doc line (around line 14), add:
```
#   index reopen <ID> both|unresolved|contested
#                 Re-open leftover issues for another debate cycle: matching issues
#                 -> state=open, rounds_debated=0, vetting flags false; global round=0,
#                 committed_rounds=[]. Keeps evidence. Exit 3 if no such issue.
```

- [ ] **Step 5: Verify with a fixture.**
```bash
SC="$PWD/skills/panel-review/scripts"; T=/tmp/reopentest; rm -rf "$T"; mkdir -p "$T"
# index expects /tmp/<ID>/index.json; use a fake ID dir.
ID=reopen-fixture-0001; rm -rf "/tmp/$ID"; mkdir -p "/tmp/$ID"
cat > "/tmp/$ID/index.json" <<'JSON'
{"round":3,"committed_rounds":[1,2,3],"issues":[
 {"id":"i1","state":"unresolved","rounds_debated":2,"peer_reviewed":false,"fully_vetted":false,"detail_contested":false,"card_rev":5,"evidence_pro":[{"p":"x"}]},
 {"id":"i2","state":"contested","rounds_debated":4,"peer_reviewed":true,"fully_vetted":true,"detail_contested":true,"card_rev":9,"evidence_pro":[{"p":"y"}]},
 {"id":"i3","state":"accepted","rounds_debated":1,"card_rev":2}]}
JSON
"$SC/index" reopen "$ID" unresolved
jq -c '.round, .committed_rounds, (.issues[]|{id,state,rounds_debated,card_rev,ev:(.evidence_pro|length)})' "/tmp/$ID/index.json"
# Expected: round 0, committed_rounds [], i1 -> state open, rounds_debated 0, card_rev 6, ev 1
#           i2 unchanged (still contested, rounds_debated 4), i3 unchanged. Evidence kept on i1.
"$SC/index" reopen "$ID" contested && jq -c '.issues[]|select(.id=="i2")|{state,rounds_debated,peer_reviewed,fully_vetted,detail_contested}' "/tmp/$ID/index.json"
# Expected: i2 -> open, 0, false, false, false
"$SC/index" reopen "$ID" unresolved; echo "exit=$?"   # i1 is now open, no unresolved left -> exit 3
rm -rf "/tmp/$ID"
```
Expected: first reopen resets i1 + globals, keeps i2/i3 and i1's evidence; contested reopen resets
i2; the final call exits 3 (nothing to re-open).

---

### Task 2: `reopen` script (index reset + clear sweeps)

**Files:**
- Create: `skills/panel-review/scripts/reopen`

**Interfaces:**
- Consumes: `index reopen` (Task 1).
- Produces: `reopen --id ID --workdir DIR --category both|unresolved|contested` — re-opens the
  issues and clears `/tmp/<ID>/sweeps/`; prints the ID. Propagates `index reopen` exit 3.

- [ ] **Step 1: Write the script** (`chmod +x` after):

```bash
#!/usr/bin/env bash
# reopen — revive a FINISHED run's leftover issues for another debate cycle (the
# engine behind the dispatcher's `--continue`). Counterpart to init_run: init_run
# starts a run; reopen revives a finished one in place.
#
# Usage: reopen --id ID --workdir DIR --category both|unresolved|contested
#
# Resets the selected issues + global round counters via `index reopen` (the only
# writer of index.json), then CLEARS /tmp/<ID>/sweeps/. Clearing is mandatory:
# the referee's debate recovery scans sweeps/ and trusts committed_rounds (now [])
# to decide what to re-apply; a leftover sweep dir would be re-applied and corrupt
# the continuation. Afterwards the run looks like a Round-0-gated run (issues
# present, no committed sweeps) and mode=resume starts a clean debate at round 1.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"; . "$here/_panel_common.sh"

id="" workdir="" category=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --id) id="$2"; shift 2;;
    --workdir) workdir="$2"; shift 2;;
    --category) category="$2"; shift 2;;
    *) echo "reopen: unknown arg: $1" >&2; exit 2;;
  esac
done
panel_require_id "$id"
[ -n "$workdir" ] || { echo "reopen: need --workdir" >&2; exit 2; }
case "$category" in both|unresolved|contested) ;; *) echo "reopen: --category must be both|unresolved|contested" >&2; exit 2;; esac
[ -s "/tmp/$id/index.json" ] || { echo "reopen: no index for $id" >&2; exit 1; }

# index.json mutation (propagates exit 3 = nothing matched).
"$here/index" reopen "$id" "$category"

# Drop stale debate checkpoints so resume starts the debate clean. /tmp/$id is
# validated by panel_require_id above; only this subtree is removed.
rm -rf -- "/tmp/$id/sweeps"
mkdir -p "/tmp/$id/sweeps"

printf '%s\n' "$id"
```

- [ ] **Step 2: Verify with a fixture.**
```bash
SC="$PWD/skills/panel-review/scripts"; ID=reopen-fixture-0002; rm -rf "/tmp/$ID"; mkdir -p "/tmp/$ID/sweeps/round-1" "/tmp/$ID/sweeps/round-2"
cat > "/tmp/$ID/index.json" <<'JSON'
{"round":2,"committed_rounds":[1,2],"issues":[{"id":"i1","state":"contested","rounds_debated":3,"card_rev":4}]}
JSON
"$SC/reopen" --id "$ID" --workdir /tmp --category both
jq -c '.round,.committed_rounds,(.issues[]|{state,rounds_debated})' "/tmp/$ID/index.json"
ls "/tmp/$ID/sweeps"   # expect EMPTY (round-* dirs gone)
"$SC/reopen" --id "$ID" --workdir /tmp --category unresolved; echo "exit=$?"  # no unresolved -> exit 3
rm -rf "/tmp/$ID"
```
Expected: i1 → open/0, round 0, committed_rounds [], `sweeps/` emptied; second call exits 3.

---

### Task 3: `resume_check` emits `continuable <ID>`

**Files:**
- Modify: `skills/panel-review/scripts/resume_check`

**Interfaces:**
- Produces: a new verdict line `continuable <ID>` when the single matching run is *finished with
  leftovers* (no `open` issue, ≥1 `unresolved`/`contested`); otherwise `resume`/`moved`/etc as today.

- [ ] **Step 1: Add `continuable` to the header doc** (in the Output list, after the `resume` line):
```
#   continuable <ID>       finished run (no open issues) with unresolved/contested left -> --continue
```

- [ ] **Step 2: Replace the final match branch.** Change:
```bash
if [ "$m_scope" = "$scope" ] && [ "$m_iss" = "$iss" ] && [ "$m_mx" = "$mx" ] && [ "$m_dh" = "$dh" ]; then
  echo "resume $id"
else
  echo "moved $id"
fi
```
to:
```bash
if [ "$m_scope" = "$scope" ] && [ "$m_iss" = "$iss" ] && [ "$m_mx" = "$mx" ] && [ "$m_dh" = "$dh" ]; then
  # A FINISHED run has no open issues; if it also handed back unresolved/contested
  # issues it is continuable. An interrupted run still has open issues -> plain resume.
  # On any jq error, default to resume (open_n=1) — never mislabel as continuable.
  open_n="$(jq '[.issues[] | select(.state=="open")] | length' "/tmp/$id/index.json" 2>/dev/null || echo 1)"
  left_n="$(jq '[.issues[] | select(.state=="unresolved" or .state=="contested")] | length' "/tmp/$id/index.json" 2>/dev/null || echo 0)"
  if [ "$open_n" = "0" ] && [ "$left_n" != "0" ]; then
    echo "continuable $id"
  else
    echo "resume $id"
  fi
else
  echo "moved $id"
fi
```

- [ ] **Step 3: Verify with a fixture.** Build `.panel-review/<ID>/` marker + `/tmp/<ID>` state with
  matching manifest, then run `resume_check`:
```bash
SC="$PWD/skills/panel-review/scripts"; WD=/tmp/rc-wd; ID=rc-fixture-00000001
rm -rf "$WD" "/tmp/$ID"; mkdir -p "$WD/.panel-review/$ID" "/tmp/$ID"; echo "$ID" > "$WD/.panel-review/$ID/.panel-run"
DH=deadbeef
cat > "/tmp/$ID/manifest.json" <<JSON
{"id":"$ID","workdir":"$WD","scope":"uncommitted","limits":{"issue_rounds":2,"max_rounds":4},"diff_hash":"$DH"}
JSON
# (a) finished + leftovers -> continuable
echo '{"round":4,"committed_rounds":[1,2,3,4],"issues":[{"id":"i1","state":"contested"},{"id":"i2","state":"accepted"}]}' > "/tmp/$ID/index.json"
"$SC/resume_check" --workdir "$WD" --scope uncommitted --issue-rounds 2 --max-rounds 4 --diff-hash "$DH"   # -> continuable <ID>
# (b) still has an open issue -> resume
echo '{"round":2,"committed_rounds":[1,2],"issues":[{"id":"i1","state":"open"}]}' > "/tmp/$ID/index.json"
"$SC/resume_check" --workdir "$WD" --scope uncommitted --issue-rounds 2 --max-rounds 4 --diff-hash "$DH"   # -> resume <ID>
# (c) finished, no leftovers (all accepted) -> resume (will be cleaned up normally; not continuable)
echo '{"round":2,"committed_rounds":[1,2],"issues":[{"id":"i1","state":"accepted"}]}' > "/tmp/$ID/index.json"
"$SC/resume_check" --workdir "$WD" --scope uncommitted --issue-rounds 2 --max-rounds 4 --diff-hash "$DH"   # -> resume <ID>
# (d) changed diff -> moved
"$SC/resume_check" --workdir "$WD" --scope uncommitted --issue-rounds 2 --max-rounds 4 --diff-hash other   # -> moved <ID>
rm -rf "$WD" "/tmp/$ID"
```
Expected lines in order: `continuable …`, `resume …`, `resume …`, `moved …`.

---

### Task 4: Referee preserves a finished-with-leftovers run

**Files:**
- Modify: `skills/panel-review-for-agent/SKILL.md` (cleanup section, ~lines 429-433)
- Modify: `agents/panel-review-referee.md` (job item 3, ~lines 38-40)

This task is documentation/protocol only (the referee is an LLM following this prose). No code test;
verify by re-reading that the two control-line exceptions are parallel and unambiguous.

- [ ] **Step 1: Replace the cleanup paragraph** in `panel-review-for-agent/SKILL.md`. Change:
```
After the verdict is persisted and ready to return, **clean up**:
`"$SC/cleanup" --id "$id" --workdir "$workdir"`. If you are returning without a final verdict
(error/abort), do **not** clean up — leave the state for resume. **Exception:** on the Round-0
severity gate (only-low) you persist the verdict but deliberately **skip cleanup** and append the
`<<<PANEL-GATE …>>>` line, so the run survives for the optional debate.
```
to:
```
After the verdict is persisted and ready to return, **clean up**:
`"$SC/cleanup" --id "$id" --workdir "$workdir"` — **unless** one of these holds, in which case you
persist the verdict but deliberately **skip cleanup** so the run survives:

- **Round-0 severity gate** (only-low): append the `<<<PANEL-GATE …>>>` line for the optional debate.
- **Leftovers to continue:** if the final index has any `unresolved` or `contested` issue, append a
  line `<<<PANEL-CONTINUABLE id=$id unresolved=<n> contested=<m>>>>` (counts from the final index),
  so the user can `/panel-review --continue` to debate them further.

If you are returning without a final verdict (error/abort), also do **not** clean up — leave the
state for resume.
```

- [ ] **Step 2: Update referee job item 3** in `agents/panel-review-referee.md`. Change:
```
3. **Return only the synthesized verdict.** Never return raw seat output, card text, or per-round
   transcripts. After producing the verdict, clean up; if you abort without a verdict, leave the
   state for resume.
```
to:
```
3. **Return only the synthesized verdict.** Never return raw seat output, card text, or per-round
   transcripts. After producing the verdict, clean up — **except** keep the run (skip cleanup) when
   you append a `<<<PANEL-GATE …>>>` (Round-0 low gate) or `<<<PANEL-CONTINUABLE …>>>` (any
   `unresolved`/`contested` issue remains, for `--continue`) control line. If you abort without a
   verdict, also leave the state for resume.
```

---

### Task 5: Dispatcher `--continue` handling

**Files:**
- Modify: `skills/panel-review/SKILL.md` (frontmatter, Step 1, new Step 1.5, Step 3, Step 5)

Documentation/protocol (the dispatcher is an LLM following this skill). Verify by re-reading for
consistency with `resume_check`/`reopen` interfaces. Use `$SC` as defined at the top of the skill.

- [ ] **Step 1: Frontmatter argument-hint.** Change the `argument-hint:` line to:
```
argument-hint: "--base <branch> | --uncommitted | --commit <SHA> | <question>  [--issue-rounds N] [--max-rounds N] [--debate-low]  | --continue [unresolved|contested]"
```

- [ ] **Step 2: Add parse sub-step 1c** (after sub-step 1b in Step 1):
```
1c. **`--continue [unresolved|contested]`** (optional). If present, set `CONT` to `both` (bare
   `--continue`), or to `unresolved` / `contested` if that word follows, and remove it (and its
   value) from the string. `--continue` continues a *finished* run and sources its scope and limits
   from the run itself, so it **must not** be combined with a scope flag/free-text,
   `--issue-rounds`, or `--max-rounds`: if anything remains after removing it, stop with exactly
   `--continue takes the scope and limits from the finished run; don't combine it with a scope or limit flag.`
   When `CONT` is unset, parse scope/limits as in steps 1, 1b, 2 below.
```

- [ ] **Step 3: Add a new "Step 1.5 — `--continue` path" section** immediately before "Step 2":
````
## Step 1.5 — `--continue` path (only when `CONT` is set)

Adopt the finished run's scope + limits instead of parsing them:

```bash
base="$PWD/.panel-review"
ids=(); for d in "$base"/*/; do [ -f "$d/.panel-run" ] && ids+=("$(basename "$d")"); done
[ "${#ids[@]}" -eq 1 ] || { echo "Need exactly one finished run to continue (found ${#ids[@]} in .panel-review/)."; exit 1; }
ID="${ids[0]}"; man="/tmp/$ID/manifest.json"
[ -s "$man" ] || { echo "The finished run's state was cleaned up; nothing to continue."; exit 1; }
scope="$(jq -r '.scope' "$man")"; ISS="$(jq -r '.limits.issue_rounds' "$man")"; MAX="$(jq -r '.limits.max_rounds' "$man")"
```

Now run **Step 2** (resolve + hash the CURRENT diff for that `scope`) and the **Step 3
`resume_check`** call, then require its verdict to be `continuable <ID>`:

- `moved <ID>` → the code moved since the finished run. Stop: "The code under review changed since finished run `<ID>`; run a fresh review instead." (this is the scope/diff gate)
- `resume <ID>` → the run still has open issues (interrupted, not finished). Stop: "Run `<ID>` isn't finished — resume it without `--continue`."
- `stale`/`ambiguous`/`fresh`/other → stop with the matching message.

On `continuable <ID>`, confirm the requested category exists, re-open, and dispatch:

```bash
have="$(jq --arg c "$CONT" '[.issues[] | select(($c=="both" and (.state=="unresolved" or .state=="contested")) or (.state==$c))] | length' "/tmp/$ID/index.json")"
[ "$have" -gt 0 ] || { echo "Run $ID has no $CONT issue to continue."; exit 1; }
"$SC/reopen" --id "$ID" --workdir "$PWD" --category "$CONT"
```

Dispatch the `panel-review-referee` agent (Step 4 form) with `mode=resume`, `id=$ID`, the adopted
`scope`/`issue-rounds`/`max-rounds`, and `debate-low=true`. Present its verdict per Step 5. (Then
skip the normal Step 2/3 below — they were just run here.)
````

- [ ] **Step 4: Add a `continuable` bullet to Step 3** (after the `resume <ID>` bullet), for the
  normal no-`--continue` flow:
```
- **`continuable <ID>`** → a prior run on this exact scope **finished** with leftover
  `unresolved`/`contested` issues and was preserved (not cleaned up). **Ask the user**
  (`AskUserQuestion`): *Run `<ID>` finished with leftovers — continue debating them, start fresh, or
  stop?*
  - Continue → `"$SC/reopen" --id "<ID>" --workdir "$PWD" --category both`; dispatch `mode=resume`,
    `id=<ID>`, `debate-low=true`.
  - Fresh → `"$SC/cleanup" --id "<ID>" --workdir "$PWD"` then `init_run` a new ID; dispatch `mode=fresh`.
  - Stop → halt; leave the run for the user.
```

- [ ] **Step 5: Extend Step 5 for the continuable control line.** Reword the existing "No gate line"
  bullet to "No control line" and add, after the gate bullet:
```
- **`<<<PANEL-CONTINUABLE id=<ID> unresolved=<n> contested=<m>>>>` present** → the run finished with
  leftovers and was preserved (not cleaned up). Present the verdict verbatim **with that line
  removed**, then append one line: *"`<n>` unresolved, `<m>` contested remain — run `/panel-review
  --continue [unresolved|contested]` to debate them further, or remove `.panel-review/<ID>/` to
  discard."* Do **not** clean up.
```

---

### Task 6: User docs

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add a "Continuing a finished review" subsection** under "Persistence & resume" (after
  the paragraph ending "…leaves the marker for you to remove."):
```
### Continuing a finished review

A review that ends with **contested** or **unresolved** issues is **kept**, not cleaned up (just like
the Round-0 low-severity gate). Push those issues further with:

- `/panel-review --continue` — re-debate both contested and unresolved
- `/panel-review --continue unresolved` — only unresolved
- `/panel-review --continue contested` — only contested

`--continue` reuses the finished run's scope and round limits (don't pass them again) and re-resolves
the diff: if the code under review changed, it refuses and asks for a fresh review. The selected
issues return to **open** with their per-issue and the global round counters reset to zero, so they
get a full budget again; their accumulated evidence is kept, and already-settled issues are carried
into the new verdict unchanged.
```

- [ ] **Step 2: Verify** the `--continue` forms and reset semantics in the new subsection match the
  spec (both categories, scope/limits inherited, diff gate, counters fresh, evidence kept).

---

## Notes for the executor

- Tasks 1-3 are independently testable bash; run their fixture blocks and paste the output in the
  task report. Tasks 4-6 are protocol/doc edits — verify by re-reading against the script interfaces
  (no runtime test).
- After all tasks: a manual end-to-end sanity check is out of scope for automated review (it needs a
  live codex/agy run); the final whole-branch review should confirm the control-flow wiring instead.
