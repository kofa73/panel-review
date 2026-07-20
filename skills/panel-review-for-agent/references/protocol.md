# Panel Review — referee procedure (v10)

<!-- phase:common -->

This is the canonical step-by-step procedure. The `panel-review-for-agent` bootstrap loads its
marked phases through `read_protocol_phase`; never read this whole file directly. If an active phase
is missing after context compaction, reload only that phase (and `common` if needed), never proceed
from memory.

**Paths.** `$ROOT`, `$SC` (= `$ROOT/scripts`) and `$PR` (= `$ROOT/prompts`) were derived in
the bootstrap from the substituted plugin root. Re-derive them at the top of **every** Bash
command exactly as the bootstrap shows — `$CLAUDE_PLUGIN_ROOT` is empty in the shell, so never
read it at runtime.

---

## The wrapper scripts

All mechanics live in `scripts/` under the `panel-review` skill dir; prompt templates in
`prompts/`. **Never invoke `agy`/`codex`/`awk`/the parsing-or-counting `jq` directly, and never
retype a template.** The scripts own flag pinning, atomic writes, the index math, and the
byte-exact parsing.

**To confirm a wrapper's interface, run it — don't read its source.** The id-gated wrappers
(`sweep`, `index`, `repo_guard`, `await_seats`) print their usage on `-h`/`--help`, and `sweep`/
`index` also print it (exit 2) for a missing or unknown subcommand — *without* needing a valid run
id. The one-line signatures below plus the per-verb call sites in the flow are the authoritative
reference; grepping a script for its flags wastes a full source-read into your context.

```bash
# $ROOT/$SC/$PR are derived in the bootstrap (from the substituted plugin
# root); re-derive them at the top of every Bash command as the bootstrap shows.
"$SC/preflight"                              # env check; tail "CODEX: yes|no"/"GEMINI: yes|no"; exit 1 = core unusable (needs jq, git, work-tree, ≥1 peer)
"$SC/resolve_instructions" --id <id>         # manifest.instructions -> verbatim/none text (exit 0) OR compose sentinel (exit 3 = auto, you compose)
"$SC/assemble" TMPL KEY=file ...             # splice files into a template's {{KEY}} sentinels -> stdout
"$SC/repo_guard" snapshot --id <id> --workdir <dir>          # record tracked-tree baseline (git stash create SHA + sha256 manifest)
"$SC/repo_guard" verify   --id <id> --workdir <dir> --restore  # re-hash tracked files; auto-revert drift; nonzero + drift list = a seat touched the code
"$SC/run_codex" < prompt > raw 2> err        # Codex seat (pins --profile panel-review; sandbox BYPASSED so MCP/tilth + scratch work — repo_guard enforces integrity; auto-creates the profile)
"$SC/run_agy"   < prompt > raw 2> err        # Gemini seat (pins model/timeout/stdin)
"$SC/run_seat" --seat <codex|gemini> --tag <tag> --prompt <f> --raw <f> --parsed <f> [--label L]  # dispatch a CLI seat + parse; parse status on stdout (no repair — you salvage a 4/5, see "Salvage")
"$SC/await_seats" --id <id> --tag <tag> --prompt <f> [--seat-timeout S] --seat <s> --raw <f> --parsed <f> --status <f> [--label L] [ --seat ... ] --done <f>  # BARRIER: run ALL CLI seats concurrently (each via run_seat) in ONE job, write each seat's status + a combined --done summary, exit. You never background this yourself — the panel-review-cli-barrier Agent runs it (see the long-running-seats rule); never poll.
"$SC/parse_block" [--response <round0|debate>] <tag> <raw> [label]  # block -> validated JSONL; --response also enforces the phase's complete block set
"$SC/parse_block" --diagnose <tag> <raw>     # WHY each item was rejected (reason + offending line); use it to guide a salvage rewrite on exit 5
"$SC/check_draft" <tag> [file]               # SEAT-FACING pre-emit validator (thin wrapper over parse_block --diagnose); spliced into the seat prompt as {{CHECK}}, not called by the referee
"$SC/seat_contract.py" render <round0|debate> --panel-size <2|3> --check-command <command>  # authoritative seat-facing output contract (exceptional manual prompt assembly only; round uses the same module)
"$SC/write_seat_raw" --id <id> --round <0|N> [--batch <name>] < raw  # CLAUDE-SEAT ONLY: validate every required block and atomically install the derived raw path
"$SC/round" prepare-round0 <id> <configured seats...>               # resolve/snapshot/assemble both prompts + write the CLI barrier command; compact JSON result
"$SC/round" collect-round0 <id> [--final]                            # parse Claude raw + compact engagement/count summary; --final verifies/restores the guard
"$SC/round" prepare-debate <id> <configured seats...>               # common single-batch plan/cards/prompts/barrier + Claude delivery prompt
"$SC/round" collect-debate <id> [--final]                            # ingest batches/new findings + compact status; --final verifies/restores the guard
"$SC/round" salvage-debate <id> <codex|gemini> <batch> <salvaged-raw> # validate/install one canonical CLI .salvaged side file as a complete batch checkpoint
"$SC/round" commit <id> [--addendum <f>]                             # decide/merge/commit/regenerate + compact states/gate; exit 3 asks for judgment addendum
"$SC/round" verdict-input <id>                                      # compact stable manifest/panel/index/origin/guard facts for synthesis
"$SC/birth_index" --available "<seats>" --configured "<seats>" < issues.json   # clustered Round-0 issues -> full index.json (birth state/flags/coverage)
"$SC/index"   {get|put|issue|bump|state|flag|gate-status|delivery-status|commit-sweep} <id> ...   # ONLY writer of index.json
"$SC/project_card" --id <id> --workdir <dir> [--index-rev N] < issue.json   # one issue record -> its card
"$SC/regen_cards"  --id <id> --workdir <dir>                                # rebuild ALL cards from the index
"$SC/index"   commit-sweep <id> <round> <epoch>  # apply a WHOLE debate round atomically (payload JSON on stdin)
"$SC/sweep"   {begin|plan|plan-scaffold|extend-plan|ingest-batch|drop-seat|resume-plan|has|done|commit} <id> <round> ...  # checkpointed sweeps; scaffold/extend take panel seats
"$SC/decide_round" --id <id> --round N --configured "<seats>" --engaged "<seats>" --stances <f> [--advice <f>]  # normal Transitions table -> commit-sweep payload
"$SC/decide_degraded_round" --id <id> --round N --configured "<seats>" --engaged "<zero-or-one-seat>" --stances <f>  # terminal non-voting payload
"$SC/merge_payload" <base.json> < addendum.json   # fold referee additions into the payload (set_state replace, revise field-merge) — never append a 2nd entry for an id
"$SC/cleanup" --id <id> --workdir <dir>      # remove cards + /tmp state (ONLY after the verdict is produced)
"$SC/write_verdict_artifact" --id <id> < verdict.md   # durable /tmp/<id>.md copy; survives cleanup/discard
```


Seat wrappers take the prompt on stdin and print the **final response only**; nonzero exit (incl.
CLI missing → 127) means that seat is down → **degrade, never abort.** `parse_block` exit **4**
means the seat returned no block at all (down / malfunctioned), distinct from an empty-but-present
block (ran, found nothing). **Run everything from cwd = `workdir` (repo root)** so seat
working-tree reads, scratch paths, and `repo_guard` all resolve against the same tree.

**CLI seats are long-running.** Run their prepared command only through the
`panel-review-cli-barrier` Agent; never run or background `await_seats` yourself. Pass the Agent the
`command`, `done`, and `sentinel` paths produced by `round prepare-*`. The barrier's own agent
definition owns how it launches and waits; on return, consume only its `await_seats_rc` result and
the status files through `round collect-*`.

Dispatch the CLI-barrier and fresh Claude-seat Agent calls together in one assistant response, both
with `run_in_background: false`. Multiple foreground Agent calls in one response run concurrently,
and the referee resumes only after every Agent returns. If preparation checkpointed one side, issue
only the remaining foreground call. Do not poll or narrate between dispatch and that combined return.

## The three seats

| Seat | How you run it | Blindness |
|------|----------------|-----------|
| Codex | `"$SC/run_codex" < prompt > raw` | fresh process each call |
| Gemini | `"$SC/run_agy" < prompt > raw` | fresh process each call |
| Claude | **fresh named subagent** `panel-review:panel-review-claude-seat` via the Agent tool, each pass | cold context |

For the Claude seat, spawn `subagent_type: panel-review:panel-review-claude-seat` with the
Claude-specific prompt returned by `round prepare-round0` / `round prepare-debate`. **Never fork**
(a fork inherits your context and destroys blindness). The delivery wrapper makes the seat pass its
complete response to `write_seat_raw`, which validates and atomically installs the expected raw path;
the Agent returns only `CLAUDE_SEAT_RAW_WRITTEN` or `CLAUDE_SEAT_RAW_FAILED`. Never copy, quote, or
write the Agent return. After both foreground Agents settle, `round collect-* --final` parses the
on-disk raw. Missing/invalid Claude raw fails closed: Claude is down for that pass, with no fallback
that returns findings or evidence into your context.

A "full panel" = every seat `preflight` reported available (either peer may be absent → run with the rest). An
**engaged** seat is one that returned a parseable block **this pass**. Settling a point needs
**≥2 engaged**. One dead seat ≠ aborted review; record it in Process notes.

---

# State model

`/tmp/<id>/index.json` is the **single source of truth**; cards are a regenerable cache. You keep
**nothing** in your conversation that isn't reconstructable from `/tmp/<id>/`.

**Keep your own context small — you re-read it on every turn.** Work from compact on-disk artifacts;
**never** `cat`/`Read` a large blob into your context to "look at it":

- **Never read the diff into your context.** The blind **seats** see the diff; you debate their
  *findings*. `resolve_diff` writes `/tmp/$id/diff.txt` (the canonical bytes) and the seat prompt
  carries only a **reference** to it (absolute path + size + sha256, spliced as `{{DIFFINFO}}`); the
  seats read the file themselves. You never need its bytes in conversation.
- **Never read raw seat output (`/tmp/$id/raw/*`) into your context.** It is parsed by `parse_block` /
  `sweep ingest-batch` into compact JSONL on disk; read a seat's *engagement status* (`status.*`) and
  the validated stances/findings the scripts produce, not the verbatim transcript.
- **Read only the slice a decision needs.** Per round, operate on `index get` output and the parsed
  per-seat JSON for the open issues — not the whole accumulated card set or every round's raw. Let the
  scripts (`decide_round`, `sweep`, `index`) do the bulk processing on disk and hand you back only what
  needs judgment.
- **Don't hand-write `jq` over internal state files** (`stances.*`, `sweeps/*`, `index.json`) to
  explain an anomaly. Their shapes are subtle — `stances.<round>.json` is **JSONL** (one object per
  line, *not* a JSON array), the stance-object field is `id` (not `issue_id`), and applying `.[]` to
  it throws `Cannot index string with string`. Use the sanctioned surfaces instead: `index get`/`index
  issue`/`index gate-status` for state, `inspect_run` for a run overview, and the human-facing
  `audit/round-<N>.md` trail for what changed each round. If you *must* touch a file directly, use the
  schemas below — don't guess field names.

Each issue record in the index:

```json
{"id":"i1","claim":"...","location":"file:line","category":"security|correctness|performance|maintainability|style",
 "severity":"critical|high|medium|low|style",
 "evidence_pro":[<point>...],"evidence_contra":[<point>...],
 "peer_reviewed":false,"fully_vetted":false,"detail_contested":false,
 "state":"open|accepted|rejected|contested|unresolved|merged",
 "rounds_debated":0,"card_rev":0}
```

A **point**: `{"location":"file:line"|["file:line",...]|"analysis","assertion":"<one fact>","precondition":"<opt>","impact":"<opt>"}`.

- Issue ids must be safe tokens (`i1`, `i2`, … — letters/digits/dot/dash/underscore only).
- `peer_reviewed` → true once ≥2 engaged seats have evaluated it (the settle threshold).
- `fully_vetted` → true only once **every configured seat** has evaluated it at least once; if it
  settles while any seat was down, it stays false **permanently** and is labelled "not fully vetted".
- `detail_contested` → existence accepted but a detail (severity/claim/location) never converged.
- `card_rev`/`rounds_debated` are bumped by the `index`/`sweep` scripts — never hand-edit them.

**Internal file schemas** (for the rare direct inspection the bullets above allow):

- `index.json` — a JSON **object**: `{"issues":[<issue record above>...],"committed_rounds":[<int>...],
  "round":<int>,"run_epoch":<int>}`. Only `index`/`sweep` write it.
- `stances.<round>.json` — **JSONL**, one stance object per line, assembled by `round commit` from the
  active plan's complete engaged-seat checkpoints. Per line:
  ```json
  {"id":"i3","stance":"support|reject","_source":"codex","fid":"codex-1","revision":{"severity":"…","location":"…","category":"…","claim":"…"},"rationale":"…","evidence":<point>,"new_evidence":<point>}
  ```
  `id`, `stance`, `_source`, `fid` are always present. `revision` is optional on support and is
  discarded from reject; reject requires a non-empty `rationale`, while support rationale is
  optional. `evidence`/`new_evidence` are optional. It is a stream of objects, **not** an array — read it line-by-line (`while read` /
  `[json.loads(l) for l in f]`), the way `decide_round` does; `jq '.[]'` over it is wrong.

**Origins are yours alone.** Keep origin seats, Round-0 agreement count, original raw wording, and
per-round stances in `/tmp/<id>/origins/` (write them with any atomic means, e.g. `index`-style temp
files or `project_card`'s sibling `write_card`). The per-round field-mutation audit trail in
`/tmp/<id>/audit/round-<N>.md` is written **for you** by `index commit-sweep` as it applies each
round — you do not write it. The `audit/` trail is for human inspection only; nothing reads it back.
**None of this ever enters a card or a seat prompt.** `project_card` only renders the
reviewer-facing fields, so the origins never leak even if adjacent.

---

<!-- /phase:common -->
<!-- phase:salvage -->

## Salvage — recovering a slipped seat block (referee-owned)

When a seat's block does not parse, **you** recover it — there is no script repair and no
re-dispatch of a "repair seat." Rationale: the seat that wrote the block has exited, so any
re-invocation is a fresh, cold model whose only input is the raw file on disk — the *same* input you
have, and you are the mind that must consume the findings anyway. Routing the fix through a redundant
extra seat buys nothing; and deciding *"is this a real review or a down-seat stub?"* is a judgment,
not a grep heuristic. So on a non-engaged parse status you do it yourself. This is the **one**
sanctioned exception to "never read raw seat output": read **only that one seat's** raw, and only when
its parse failed. Blindness holds — you already see every finding, so reading one seat's own text
leaks nothing.

The parse status (from `parse_block`, or from `sweep ingest-batch`'s batch status in debate) tells you
which case you are in:

- **Status 5 — a block is present but malformed.** A review happened; the JSON shape merely slipped.
  No stub-vs-review judgment is needed — fix the shape (below). This is the common case.
- **Status 4 — no fenced block at all.** Ambiguous: either a **down-seat stub** (an error, a timeout,
  a refusal, empty output) or a **complete prose review the seat forgot to fence**. Read the raw and
  judge. If it is a stub → the seat is **down for this pass** (leave the status 4; record it in
  Process notes; do NOT invent findings to fill a block — that only manufactures noise). If it is a
  real review → recover it (below).

**To recover** (both 4-with-a-review and 5): rewrite the raw as the *well-formed raw the seat should
have produced* — write it to a **side file** (`<raw>.salvaged`, so the original prose survives for
inspection), then re-run the same parse/ingest against the side file:

- Re-home the substance the seat **already stated** into the correct fenced block(s) — do **not**
  re-review, do **not** add, drop, or re-severity anything. The seat-facing prompt contains the exact
  shape rendered by `seat_contract.py`; `parse_block --diagnose <tag> <raw>` names each violation to
  fix. For `findings`/
  `new_findings`, the evidence facts and any `precondition`/`impact` belong INSIDE a `points[]` entry
  alongside its `assertion` and `location`, never at the top level.
- Emit an **empty** block (`[]`/no lines) if and only if the seat genuinely raised nothing. Never
  fabricate an item to fill it; never drop an item the seat actually stated. If one item truly cannot
  be reconstructed from what the seat wrote, drop just that item rather than guessing.
- **Debate carries two blocks in one raw** (`stances` + `new_findings`). Re-emit **both** coherently
  so `sweep ingest-batch` gets a complete raw — you are repairing sweep's *input*, never bypassing its
  validation (it still requires exactly one stance per expected ID). Register the canonical side file
  with `round salvage-debate`; it installs both parsed blocks as one checkpoint. A genuine stub (no
  real stances) is not salvageable here — let the debate retry/drop-seat flow handle it. This command
  is CLI-only: Claude output is validated before installation and is retried/dropped, never salvaged.

```bash
# Round 0 (findings): re-parse the salvaged side file.
"$SC/parse_block" findings "/tmp/$id/raw/round0.$seat.txt.salvaged" "$seat" > /tmp/$id/f.$seat.json
echo "$?" > /tmp/$id/status.$seat

# Debate (both blocks): install the canonical side file through the coarse interface.
"$SC/round" salvage-debate "$id" "$seat" "$batch" \
  "/tmp/$id/raw/round$round.$seat.$batch.txt.salvaged"
```

---

<!-- /phase:salvage -->
<!-- phase:round0 -->

# Mode: fresh

## Round 0 — blind pass

**Normal path — use the coarse module.** Run `preflight`, form the configured panel from Claude plus
the available peer seat(s), then call:

```bash
"$SC/round" prepare-round0 "$id" <configured seats...>
```

Its compact JSON gives `prompt` for the CLI seats, `claude_prompt` for the fresh Claude Agent, and
the CLI barrier's `command`/`done`/`sentinel` paths. It owns diff resolution, the guard snapshot,
saved-review-profile validation/reference, absolute path anchors, seat-contract rendering, prompt
assembly, and the barrier command; do not
repeat those mechanics. Exit 3 with `status=needs_auto_instructions` is the sole normal-path pause:
write a few neutral sentences based on branch name, commit subjects, and status—not an interpretation
of the diff—to the returned path, then call `prepare-round0` again. A diff-hash mismatch is a hard
stop.

Spawn the CLI barrier from those returned paths and the fresh Claude seat with `claude_prompt`, then
take no turns until both Agents have returned. Call `round collect-round0 "$id" --final` once; its
JSON is the authoritative engagement/count/guard summary. A CLI parse status 4/5 may use the lazily
loaded `salvage` phase and then be recollected. A missing Claude raw means the seat failed closed and
is down—never salvage from its short Agent stub. Continue with clustering below.

1. **Merge findings into issues (your judgment — this is the one place you cluster).** Read every
   finding. Two findings become one issue **only if** they are at the **same location/code-path
   AND the same failure mechanism**.
   - **Union** matching points' differing `precondition`/`impact` into one point — but only if
     non-contradictory; if they conflict (e.g. `x>0` vs `x<0`), keep the points **separate**.
   - **Different call sites / locations of the same *pattern* stay distinct** (three sites passing
     NULL = three points, not one). **When unsure, do not merge.**
   - **Drop nothing and truncate nothing.** Show all materially-different points, both sides.
   - This is also the test for folding a later `new_findings` item into an existing issue.

2. **Emit your clustered issues; `birth_index` assigns birth state.** Your merge (step 1) is the
   judgment; the *birth state* it implies is mechanical, so build a finding-to-issue **map** and hand
   it to `birth_index` rather than computing states by hand. For each clustered issue write one JSON
   object: `claim`, `location`, `category`, `severity`, `evidence_pro` (the merged points), the
   `raised_by` list (the available seats that independently raised it), and `detail_divergence:true`
   if the raisers agreed it exists but differed on severity/location. Assign ids `i1,i2,…`. **Drop
   `severity:style`** issues from this map (keep them aside for the Style section — `birth_index`
   rejects a style issue rather than debate it). Record origins (which seats, raw wording) under
   `/tmp/<id>/origins/`. Then:

   ```bash
   # /tmp/$id/issues.map.json = a JSON array of the clustered issues described above.
   "$SC/birth_index" --available "<seats that returned parseable findings>" \
     --configured "<full panel from preflight>" < /tmp/$id/issues.map.json > /tmp/$id/index.new.json
   ```
   `birth_index` applies the birth-unanimity rule exactly — all available seats (and ≥2) raised it →
   `accepted`/`peer_reviewed=true`, `fully_vetted` only if that set is the whole configured panel,
   `detail_contested` from `detail_divergence`; otherwise `open`/`peer_reviewed=false` — and writes
   `evaluated_by` from each issue's raisers. The result is a complete index.

3. **Install the index and project cards:**

   ```bash
   "$SC/index" put "$id" < /tmp/$id/index.new.json      # birth_index already set evaluated_by:{issue_id:[Round-0 raisers]}
   "$SC/regen_cards" --id "$id" --workdir "$workdir"     # render every issue's card
   ```

If after merge there are no `open` issues — everything settled at birth or only style remains —
skip straight to synthesis and finish normally. Otherwise query `index gate-status`; load `gate`
only if `low_only` is true and this fresh run does not have `debate-low=true`. If not, proceed to the
debate loop.

<!-- /phase:round0 -->
<!-- phase:gate -->

### Round-0 severity gate (fresh mode only)

Round 0 already cost three blind passes. Query `"$SC/index" gate-status "$id"`; if `low_only` is
`true` and this run was **not** invoked with `debate-low=true`, **do not enter the debate loop** — debating an all-low
set rarely changes the outcome and burns tokens on confirmations. Instead:

1. **Synthesize the verdict now** over the Round-0 findings. They are **not yet peer-reviewed** —
   list the low items under **Minor** and add a Process note: *"Debate skipped — Round 0 surfaced
   only low-severity findings; re-run / continue to debate them."* Show every finding as usual.
2. **Persist** the durable report with
   `write_verdict_artifact --id $id < /tmp/$id/verdict.new.md`, but **do NOT clean up.** Leave
   `/tmp/<id>` and the cards intact so the human can opt into the debate via a `mode=resume`
   dispatch. Artifact persistence is required for delivery: on failure use the bootstrap's
   persistence-failure return and leave the run intact.
3. After the durable write succeeds, use the bootstrap's success return. The launching command
   validates the incomplete artifact plus canonical low-only state, presents its snapshot pointer,
   and asks the human whether to debate anyway. On "yes" it re-dispatches you in `mode=resume` (which
   always proceeds to the debate loop, reusing this Round 0 — no seat is re-run).

If `debate-low=true`, skip this gate and debate normally.

<!-- /phase:gate -->
<!-- phase:debate -->

## Debate loop

Defaults: per-issue threshold `issue-rounds=2`, global ceiling `max-rounds=4` (both from the
manifest). A **round = one full sweep over all currently-open issues** across all engaged seats.
`round` counts debate sweeps starting at 1.

For `round = 1, 2, … max-rounds`, while any issue is `open`:

**Common single-batch path — use the coarse module.** Before calling it, use the current cards to
decide whether the set needs the exceptional pagination in steps 4–7; do not register a common plan
and then try to replace it. Otherwise, re-run `preflight`, form this pass's configured panel from
Claude plus the available peer seat(s), then call
`"$SC/round" prepare-debate "$id" <configured seats...>`.
Its JSON gives the round/epoch, shared CLI prompt, optional Claude-specific prompt, and barrier paths.
Spawn one CLI barrier per returned entry and a fresh Claude Agent only when `claude_prompt` is
non-null; a missing entry/prompt is already checkpointed and must not be re-dispatched. Issue every
returned Agent call together in one assistant response with `run_in_background: false`; they run
concurrently, and the referee resumes only after every Agent returns. Then call
`"$SC/round" collect-debate "$id" --final`; use its batch statuses and engaged list.
Load `salvage` only for a failed CLI block. After rewriting both blocks to the canonical side file,
call `round salvage-debate`, then call `round collect-debate` again; recollection reads the completed
checkpoint instead of the malformed original. Retry each still-non-complete batch once, and use
`sweep drop-seat` if it still fails. Claude raw already passed strict pre-write validation; if it is
missing, empty, or incomplete, retry the fresh Claude seat once and then drop it—never read the
status stub as review content.

Steps 1–7 below document the invariants and the exceptional multi-batch path. Do not repeat their
normal preparation/ingest/guard commands after the coarse calls. If the open card set genuinely
needs pagination, use steps 4–7 to register the explicit multi-batch plan; `prepare-debate` owns only
the common one-batch shape.

1. `OPEN=$( "$SC/index" get "$id" | jq -r '.issues[]|select(.state=="open")|.id' )`. If empty → done.
2. `epoch="$(jq -r '.run_epoch // 0' "/tmp/$id/index.json")"`
3. `"$SC/sweep" begin "$id" $round "$epoch"` and `"$SC/regen_cards" --id "$id" --workdir "$workdir"` (cards
   reflect all accumulated evidence). Collect the open cards' **absolute paths**
   `<workdir>/.panel-review/<id>/issue-<oid>.md` (absolute for the same reason the
   scratch dir is — agy guesses its own repo root, so a relative card path can drift).
4. **Generate the common single-batch plan.** After `sweep begin`, have `sweep plan-scaffold` read
   the open issue IDs and build one batch for every seat in the current panel. Save its stdout, then
   do not hand-write the JSON. The trailing seats are the current panel from `preflight`, because
   that panel is rechecked on resume and is not stored in `index.json`:

   ```bash
   # Full-panel example; omit any peer that the current preflight reported unavailable.
   "$SC/sweep" plan-scaffold "$id" "$round" codex gemini claude > /tmp/$id/plan.$round.json
   # Exact shape ("batch" is a quoted string):
   # {"batches":[{"seat":"codex","batch":"1","expected_ids":["i3","i4","i5"]},...]}
   ```

5. **Over-budget:** a single card always goes **whole** to every engaged seat. If the *set* of
   open cards exceeds the context budget, paginate into deterministic batches (by severity, then
   file+line) — but every batch goes to all engaged seats. The round is the union of its batches.
   For each batch, write its exact, sorted issue-id set once to
   `/tmp/$id/batch.$round.$batch.ids`; step 7 uses it to ensure a partially parsed response is not
   checkpointed as complete.
   The scaffold emits only the common single-batch plan. If pagination is actually needed, replace
   the scaffolded file with the corresponding multi-batch shape. Then register the final plan once:

   ```bash
   "$SC/sweep" plan "$id" "$round" "$epoch" /tmp/$id/plan.$round.json
   ```
6. **Assemble + dispatch** to each seat/batch not already recorded this round (`"$SC/sweep" has`):

   ```bash
   printf '%s\n' "$OPEN_CARD_PATHS" > /tmp/$id/cards.$round.txt
   # /tmp/$id/instructions.txt was resolved in Round 0 step 2; on a resume that began at the
   # debate loop, regenerate it the same way if absent before assembling. Same for the scratch
   # dir + its sentinel file (Round 0 step 3) — recreate both if a resume skipped Round 0.
   mkdir -p "$workdir/.panel-review/$id/work"
   # Absolute scratch + review root (recreate if a resume skipped Round 0), same as Round 0 step 3.
   [ -f /tmp/$id/scratch.txt ] || printf '%s\n' "$workdir/.panel-review/$id/work" > /tmp/$id/scratch.txt
   [ -f /tmp/$id/workdir.txt ] || printf '%s\n' "$workdir" > /tmp/$id/workdir.txt
   printf '%s stances\n' "$SC/check_draft" > /tmp/$id/check.stances.txt
   "$SC/seat_contract.py" render debate --panel-size "$panel_size" \
     --check-command "$SC/check_draft stances" > /tmp/$id/seat_contract.debate.md
   "$SC/assemble" "$PR/debate.tmpl" WORKDIR=/tmp/$id/workdir.txt \
     CARDS=/tmp/$id/cards.$round.txt INSTRUCTIONS=/tmp/$id/instructions.txt \
     PROFILEINFO=/tmp/$id/review_profile_info.txt \
     SCRATCH=/tmp/$id/scratch.txt SEAT_CONTRACT=/tmp/$id/seat_contract.debate.md \
     TILTH=$PR/tilth_guide.txt > /tmp/$id/debate.$round.prompt
   # run each seat/batch -> /tmp/$id/raw/round$round.<seat>.<batch>.txt
   ```
   Spawn a **fresh** `panel-review:panel-review-claude-seat` subagent for the Claude seat each round.
7. **Ingest batches through `sweep`.** The plan was registered in step 5. After each response, use
   `sweep ingest-batch`; it parses `stances` and `new_findings` from the same raw, requires exactly
   one stance for every expected ID, and retains the complete two-block bundle only for
   `status=complete`. `missing`, `empty`, `malformed`, `partial`, and `wrong_ids` remain retryable.
   The `new_findings` block is
   **required-emptyable** (debate.tmpl asks the seat to *always* emit it, `[]` when nothing is new),
   so:
   - an **empty `[]`** block (parse exit 0, zero objects) = the seat raised nothing new;
   - an **absent** block (parse exit 4) is now malformed, and a **malformed** block (exit 5) is a
     format slip — both are yours to **salvage** (see "Salvage"), exactly like Round-0 `findings`.

   Debate salvage is where the two-blocks-in-one-raw case bites: `stances` and `new_findings` live in
   the **same** raw, which `sweep ingest-batch` reads as one checkpoint. If a
   seat's raw fails to parse, do **not** re-dispatch a repair seat — read that one raw and rewrite it
   well-formed to `<raw>.salvaged`, re-emitting **both** blocks coherently (a genuine stub with no real
   stances is not salvageable — let step 8's retry/drop-seat handle it). Register that exact canonical
   side path with `round salvage-debate`; do not invoke `sweep` or write `status.nf.*` yourself. This
   salvage path applies to CLI seats. Claude's `write_seat_raw` validates both blocks before installing
   them, so a failed Claude delivery is retried/dropped rather than reconstructed from its fixed stub.

   ```bash
   # Same barrier as Round 0, per BATCH: write the await_seats command for this batch's
   # prompt to a script (--tag new_findings parses the new-findings block; `sweep
   # ingest-batch` re-reads the SAME raw file for stances below), then run it via the
   # cli-barrier Agent — never background await_seats yourself (it would not wake you).
   printf '%s\n' "$SC/await_seats --id $id --tag new_findings --prompt /tmp/$id/debate.$round.prompt --seat codex --raw /tmp/$id/raw/round$round.codex.$batch.txt --parsed /tmp/$id/nf.$round.codex.json --status /tmp/$id/status.round$round.codex.$batch --seat gemini --raw /tmp/$id/raw/round$round.gemini.$batch.txt --parsed /tmp/$id/nf.$round.gemini.json --status /tmp/$id/status.round$round.gemini.$batch --done /tmp/$id/await.round$round.$batch.txt" > /tmp/$id/cli_barrier.round$round.$batch.sh
   ```
   Spawn the **CLI barrier** as a `panel-review:panel-review-cli-barrier` Agent
   (`command=/tmp/<id>/cli_barrier.round$round.$batch.sh`, `done=/tmp/<id>/await.round$round.$batch.txt`,
   `sentinel=/tmp/<id>/await.round$round.$batch.sentinel`, `workdir=<repo root>`; on its return an
   `await_seats_rc` that is nonzero or `absent` means the seats did not run this batch — treat those
   CLI seats as down for the batch and note it in Process notes) and the **fresh Claude seat** as its
   own Agent alongside it (it cannot run inside `await_seats`). Issue every barrier and Claude-seat
   call together in one assistant response, each with `run_in_background: false`; the foreground
   calls run concurrently and the referee resumes only after every Agent returns. An over-budget
   round adds one barrier Agent per extra batch to that same parallel call group. Never poll or
   narrate between dispatch and the combined return (see the long-running-seats rule).

   ```bash
   # Ingest the original seat raw. If salvage is needed, use round salvage-debate;
   # do not point this low-level command at the side file yourself.
   "$SC/sweep" ingest-batch "$id" "$round" "$epoch" "$seat" "$batch" \
     /tmp/$id/batch.$round.$batch.ids /tmp/$id/raw/round$round.$seat.$batch.txt
   ```
   **Guard the tree** once every seat of the round has returned (same as Round 0 — append, don't
   overwrite, so earlier rounds' violations survive in the verdict):

   ```bash
   mkdir -p /tmp/$id/origins
   "$SC/repo_guard" verify --id "$id" --workdir "$workdir" --restore >> /tmp/$id/origins/guard.debate.txt || true
   ```
   Any drift is reverted from the snapshot and carried into the verdict's Process notes.
8. **Engaged = COMPLETE this pass.** A batch is complete only when its retained raw, exact-ID stances,
   parsed `new_findings`, zero `status.nf.*`, expected IDs, and source record were installed together.
   Because `.out` is published last as the completion marker, a published `.out` with any missing
   companion is corrupt state and `sweep has`/`resume-plan` fail closed rather than downgrading it to
   a retryable missing batch.
   A seat is engaged only when all of its planned batches are `complete` in
   `"$SC/sweep" resume-plan "$id"`. A seat with any other batch status is not engaged.
9. **Retry every non-complete batch once, THEN re-check engagement.** A malformed batch first gets a
   **salvage** attempt (see "Salvage": rewrite the raw well-formed, install it through
   `round salvage-debate`); missing, empty, partial, wrong-ID, or an unsalvageable stub gets a fresh
   dispatch.
   If any batch still fails, run `"$SC/sweep" drop-seat "$id" "$round" "$seat"`; this discards all
   of that seat's checkpoints and marks it dropped in the recovery plan. Do not hand-delete files.
   Do not glob `*.stances.json`: `round commit` selects only complete batches belonging to engaged
   seats from the active plan.

<!-- /phase:debate -->
<!-- phase:degraded -->

   If fewer than two seats remain, continue to `round commit`; it selects only the active plan's
   complete batches and invokes `decide_degraded_round`. That path records coverage and produces only
   `unresolved`/`contested` plus eligible `fully_vetted` flags; it cannot bump, revise, accept, reject,
   or promote evidence.

<!-- /phase:degraded -->
<!-- phase:debate -->

10. **Decide each open issue's outcome — `round commit` owns the mechanical transaction.** First call:

   ```bash
   "$SC/round" commit "$id"
   ```

   When no prose revision or new finding needs judgment, it runs the normal/degraded decision,
   commits atomically, regenerates cards, and returns compact engaged/state/gate data. Exit 3 with
   `status=needs_judgment_addendum` is not a failure and makes no index mutation: read only the
   returned advice/new-finding files, perform step 11's judgment, write the payload-shaped addendum,
   then call `round commit "$id" --addendum /tmp/$id/addendum.$round.json`. An explicit `{}` records
   that judgment was performed but required no payload addition.

   Internally, `decide_round` applies the
   Transitions table below (stance counting, `bump`, `peer_reviewed`/`fully_vetted`, enum-field
   convergence, **and the forced-terminal-at-limits rule**) to the open issues and emits ONE
   commit-sweep payload, carrying every `reject`/revision rationale and `new_evidence` as evidence
   **verbatim, stripped of seat identity and any tally** — that is what keeps the accumulated
   evidence blind. A support rationale is promoted only when at least one proposed revision differs
   from the canonical issue; exact no-op revisions and their rationale do not change the card. Do
   **not** hand-build this payload or concatenate stance files: `round commit`
   selects only complete active-plan batches and invokes `decide_round` (without mutating
   `index.json` until the complete payload is ready).
   `--configured` is the panel from `preflight`; `--engaged` is the subset that engaged this round
   (step 8). `decide_round` **validates** the stances against `--engaged`: exactly one canonical
   `support`/`reject` stance per (engaged seat, open issue), non-empty rationale on reject, no
   unknown/duplicate `_source`, no omissions — a violation is a hard
   error (exit 3) and means a seat block was incomplete/garbled, so **salvage or re-dispatch that
   seat** (don't hand-edit the stances). It also runs a **blindness scan** over the free text it
   promotes verbatim onto cards (reject/effective-revision `rationale`, `new_evidence`): a stance that names a seat, references
   the other reviewers, or states a tally is a hard error (**exit 5**, no payload). Re-dispatch that
   one seat asking it to restate the **same technical substance** with no reference to other
   reviewers / their count / their agreement — a content reword (a genuine re-review by the seat),
   distinct from the shape-only **salvage** you do on a slipped block — then re-parse and re-run
   `decide_round`. Cumulative per-issue `evaluated_by` is private index metadata:
   initialize it from Round-0 engaged seats, then `decide_round`/`decide_degraded_round` include the
   update in their payload and `index commit-sweep` persists it atomically. `decide_round`
   does **no judgment**: it never picks a winning value for the prose `claim` field. A `support`
   without a revision endorses the current values; one with a revision proposes different effective
   values, so an enum change is adopted only when
   **every** supporting seat's effective value agrees). It never clusters new findings — that is
   step 11. (It is the single builder of the round payload, the way `parse_block` is the single
   parser; keeping the whole round in one uncommitted payload is what makes a crash before the coarse
   commit completes leave round N **wholly unapplied**.)
11. **Add the judgment `decide_round` can't — as an ADDENDUM supplied to `round commit`.**
   Build `/tmp/$id/addendum.$round.json` (a payload-shaped object) holding only your additions:
   - **Prose `claim` revisions** — read `/tmp/$id/advice.$round.json`. For each `prose_revisions`
     entry, your call: synthesize ONE merged `claim` → a `revise` for that id; or if the proposals
     genuinely conflict → `set_flag detail_contested=true`; or, if they are mere wording
     refinements → nothing (the original claim stands). **Never** write a claim/evidence string
     that names or counts seats.
   - **New findings.** For each `new_findings` item, either **fold** it into an existing issue (same
     merge test as Round 0 step 4) or add a NEW issue via `add_issues`. A fold adds every materially
     distinct point as `add_evidence`. **Preserve its current state** when the new evidence is
     cumulative or reinforces its current outcome; evidence appearing later is not by itself a
     reason to re-debate a settled issue. Reopen it with `set_state {open}` only when the evidence
     **materially conflicts with its current outcome** and the issue has remaining debate budget
     under both limits. If conflicting evidence arrives after either limit is exhausted, preserve
     the forced-terminal rule: hand the issue off as `contested` when it has been peer reviewed,
     otherwise `unresolved`, rather than leaving it open. This conflict test is referee judgment.
     Do not revise canonical issue fields from one later finding alone; carry its detail in the
     evidence for the seats or verdict.
     For a genuinely new issue, apply the birth-unanimity check **only** among seats engaged in this
     pass: if every engaged seat (and ≥2) raised it, birth it `accepted` with `peer_reviewed=true`
     (`fully_vetted=true` only when those raisers cover the full configured panel); otherwise birth
     it `open` with `peer_reviewed=false`. In the same addendum, set `evaluated_by[<new id>]` to all
     same-pass raisers, sorted and unique — including the single raiser of a non-unanimous open issue.
     `index commit-sweep` permits that coverage entry to target its same-transaction `add_issues`
     record while all other mutation types remain existing-only.
   - **Addendum shape.** The addendum is payload-shaped for `round commit --addendum`. A `revise`
     entry wraps the changed enum/prose fields under **`fields`** (a flat `claim` is rejected before
     any mutation); `set_state`/`set_flag` carry `id` (+ `flag`):

     ```json
     {"revise":[{"id":"i4","fields":{"claim":"<merged prose>"}}],
      "set_state":[{"id":"i4","state":"open"}],
      "set_flag":[{"id":"i4","flag":"detail_contested","value":true}]}
     ```
   - **Describe additions; do not merge or commit them yourself.** The deterministic decision may
     already contain a `set_state` or `revise` for an issue you are also touching. The coarse command
     reconciles those overlaps: the addendum's state wins, while revised fields are deep-merged.
     After writing the addendum, return to step 10's `round commit --addendum` call. It exclusively
     validates and merges the addendum, installs the complete payload atomically, commits the round
     once, and regenerates the cards. If it rejects the addendum, fix the addendum and retry; the
     canonical payload and index remain untouched. If the returned gate data has `low_only=true` and
     `debate-low` is false, load `gate`; otherwise continue or finish without loading that phase.

<!-- /phase:debate -->
<!-- phase:gate -->

12. **Low-severity stop gate (after each committed round).** Once the round commits, query
    `"$SC/index" gate-status "$id"`. If `low_only` is true and the run was **not** invoked with
    `debate-low=true`, **stop the loop** rather than spend the remaining
    budget confirming low items — the same rationale as the Round-0 gate, reapplied so a later round
    that whittles the open set down to all-low doesn't keep burning tokens. Then, exactly as the
    Round-0 gate: synthesize the verdict so far (open low items under **Minor**, with a Process note
    *"Debate stopped early — only low-severity findings remained open; continue/resume to debate
    them."*), persist the durable report
    (`write_verdict_artifact --id $id < /tmp/$id/verdict.new.md`), and leave `/tmp/<id>` and the cards
    intact. Artifact persistence is required for delivery: on failure use the bootstrap's
    persistence-failure return and keep the run. On success use its success return. The launching
    command validates the low-only snapshot, presents its
    filename, and asks whether to keep debating; on "yes" it re-dispatches you in `mode=resume`, which
    resumes the loop. If `debate-low=true`, skip this gate and continue the loop.

<!-- /phase:gate -->
<!-- phase:debate -->

`converged = no issue in state "open"`. Stop the loop when converged or at the ceiling.

---

# Transitions — unanimity, otherwise the human

Per open issue, on the stances of the seats that **engaged this round** (returned a parseable
stance). `support` affirms issue existence and may independently propose revised fields. This table is the **spec
`decide_round` implements** (the way the per-tag schema is the spec `parse_block` enforces): the
script decides every row mechanically except the two prose calls it cannot make — synthesizing a
merged `claim`, and clustering new findings — which it hands to you (step 10).

| Condition | Result |
|-----------|--------|
| New issue, **all available seats (≥2)** raised it in one pass | **accepted** (terminal — birth) |
| ≥2 engaged, all `support` | existence **accepted**; `peer_reviewed=true` |
| ≥2 engaged, all `reject` | **rejected** (terminal); `peer_reviewed=true` |
| Existence accepted; engaged seats converge on a revised detail | adopt the new value (audit-logged) |
| Existence accepted; a detail not yet converged, under limits | stays **open** |
| Existence accepted; a detail still unconverged at limits | **accepted** + `detail_contested=true` |
| ≥2 engaged, mix of support and reject, under both limits | stays **open**, carry forward |
| `open` at per-issue threshold OR global ceiling, ≥1 peer-review pass | **contested** (terminal) |
| `open` at threshold/ceiling, 0 peer-review passes | **unresolved** (terminal) |
| <2 engaged after retry, issue already `peer_reviewed` | **contested** (terminal); + `fully_vetted` if the lone seat completes coverage |
| <2 engaged after retry, issue never `peer_reviewed` | **unresolved** (terminal) |
| New finding belongs to an existing issue and reinforces its outcome | **merged**; state preserved |
| Folded evidence materially conflicts with the current outcome, with debate budget remaining | **open** for peer review |
| Folded evidence conflicts after an issue/global limit | **contested** if peer reviewed, otherwise **unresolved** |

- **No majority rule. You never pick a winning value** — conflicting revisions → accepted +
  `detail_contested`, surfaced for the human.
- An issue that reaches ≥2 engaged seats gets `peer_reviewed=true` (in the round payload).
- **`fully_vetted`** flips to `true` the round in which the **last configured seat** finally
  evaluates the issue — including a seat that was down at Round 0 but re-engages later. The private
  index `evaluated_by` map tracks that set and is updated atomically with the round. It never reverts.
- **Security findings use this exact table** — no vote-skip, no auto-escalation — but are listed
  separately and prominently in the verdict.

---

<!-- /phase:debate -->
<!-- phase:recovery -->

# Mode: resume

You keep nothing in conversation; reconstruct everything from `/tmp/<id>/`.

**Two dispatches land here, both handled by the one recovery below:** an **interrupted** run
(`resume` after a crash mid-debate) or a **continued** run (`continue` re-debating a *finished* run's
leftovers). For a continued run the launching command already ran `reopen` **in the main context,
before spawning you**, so the index you inherit is a **freshly reopened** one — and this exact shape
is NORMAL, not corruption:

- `run_epoch` is **> 0** and `committed_rounds` is **`[]`** (reopen bumped the epoch and cleared the
  committed list for the new cycle);
- the reopened leftover issues are back to `state:open`, `rounds_debated:0`, flags cleared, while
  issues that settled in an earlier epoch stay `accepted`/`rejected` (they were not reopened) — an
  accepted issue with `rounds_debated≥1` sitting next to `committed_rounds:[]` is expected here, not a
  contradiction;
- `round` is `0`, so `sweep resume-plan` reports the next round as **1**: a continued run **restarts
  round numbering at 1 within the new epoch** (rounds are per-epoch, never a global counter — do not
  expect them to continue from the previous cycle's last number). The previous epoch's full record is
  archived under `/tmp/$id/epochs/epoch-<n>/`.

**Do not diagnose this as damage.** Never hand-compare `index.json` against `index.json.bak` (or their
mtimes) to infer a "prior resume attempt" or "corrupted state": a reopen legitimately makes the live
index diverge from its own just-rotated `.bak`, and that divergence *is* the transition above. Trust
`sweep resume-plan` (it validates `run_epoch`) for what to recover; never reconstruct state from
`.bak`. When `run_epoch > 0`, label the verdict a **continuation** (see the Rounds line in synthesis).

1. Read `/tmp/$id/manifest.json` (scope, limits, `instructions`, and review-profile metadata — the launching command adopted
   these from the manifest and confirmed via `resume_check` that the diff hash is unchanged; a
   diverged or stale run would not have dispatched you). The source profile path is provenance only;
   every resumed prompt uses `/tmp/$id/review-profile.md`. If `/tmp/$id/instructions.txt` is absent (resume before Round 0
   finished resolving it), regenerate it via Round 0 step 2 before any seat prompt is assembled.
2. **Re-run `"$SC/preflight"`** — the environment may have changed since the interrupted run (e.g.
   a peer seat is now down, or back). The CURRENT `CODEX: yes|no` / `GEMINI: yes|no` define the configured panel for the
   rest of this run; note any change in Process notes. (A seat absent now simply can't engage; a
   seat that returns means `fully_vetted` can still complete later.)
3. `"$SC/regen_cards" --id "$id" --workdir "$workdir"` — rebuild every card from the index
   (replaces stale cards, quarantines orphans). State is **never** read back from cards.
4. **Round 0 recovery:** if the index has no issues, Round 0 never completed. Re-run only the seats
   whose `/tmp/$id/raw/round0.<seat>.txt` is missing/empty, reuse the cached ones, then do the merge
   + index build as in fresh mode.
5. **Debate recovery:** run `"$SC/sweep" resume-plan "$id"`. It validates the epoch and reports the
   next uncommitted round plus each planned batch as `complete`, `missing`, or `dropped`. Reuse only
   `complete` batches; dispatch only `missing` batches; treat `dropped` seats as down. Rebuild the
   round payload from the retained parsed outputs and `sweep commit` exactly as in a fresh round. On
   the common single-batch path, `round prepare-debate` performs this reconciliation: it preserves
   completed checkpoints (and their seats in this interrupted round's effective panel), extends the
   stored plan for unplanned current-panel seats, reactivates already-planned dropped seats that have
   returned, and drops only incomplete planned seats that current preflight no longer configures. An
   exceptional multi-batch plan stays on the manual recovery path.
   The `committed_rounds` guard makes this safe even if the crash happened mid-commit.
6. Never restart a committed sweep; never re-bump a committed round.

A run that was **gated at Round 0** (only-low) has a complete index with no committed sweeps, so
this recovery simply finds nothing to recover and starts the debate loop at round 1 — exactly the
human's intent when they chose to continue. Do **not** re-apply the gate on resume.

---

<!-- /phase:recovery -->
<!-- phase:verdict -->

# Verdict synthesis

Run `"$SC/round" verdict-input "$id"` and read that single compact result. It contains the stable
manifest, configured panel, final index, structured origins, and guard facts needed below; do not
re-read those state files separately. Present **everything**, surfacing origins only here. Severity
→ headings: `critical`/`high` → **Critical**, `medium` →
**Important**, `low` → **Minor**, `style` → **Style notes**.

```markdown
## Panel Review — {scope}
**Seats:** {seats that engaged — e.g. Claude + Codex (GPT) + Gemini}{" — {down seat(s)} unavailable" if any peer was down}
**Rounds:** {N debate rounds this cycle}{ — continuation (epoch {run_epoch}) if run_epoch>0} ({converged | ceiling reached})
**Issues:** {X} total

### Security (if any — listed first, prominent)
- `file:line` — {claim} — **state: {accepted|contested|rejected|unresolved}**{; not fully vetted}
  - Evidence for / against (as applicable)

### Critical / Important / Minor   (accepted issues, by severity)
- `file:line` — {claim}{ — ⚠ detail contested: {which detail}}{ — not fully vetted}
  - Evidence: {pro points}
  - Flagged by: {seats}   ·   independent Round-0 support: {n}

### Contested (reviewers held positions — you decide)
- `file:line` — {claim}
  - For: {pro points}   ·   Against: {contra points}
  - Disputed facts / how to check: {…}

### Unresolved (raised but not panel-reviewed — too few engaged seats, or cap with no passes)
- `file:line` — {claim} — {why unresolved}

### Rejected (raised then dropped)
- `file:line` — {claim} — raised because {pro}; dropped because {contra}

### Merged
- {merged claim} → folded into `{surviving id}` — {merge rationale}

### Style notes
- `file:line` — {note}

### Process notes
- independent Round-0 support per accepted issue; notable field mutations ("high → low on agreement")
- seat health: timeouts, retries, or any configured seat down; any blind-leak-check result
- **guard violations:** if `/tmp/$id/origins/guard.round0.txt` or `guard.debate.txt` is non-empty, list
  each drifted tracked file **loudly** here ("⚠ a seat modified `<file>` during review; reverted from
  the start-of-review snapshot") — the review continued, but a seat broke the read-only contract
```

Before cleanup, persist the final verdict to the durable artifact that outlives cleanup/discard.
Artifact persistence is required for delivery; if it fails, use the bootstrap's
persistence-failure return and leave the run intact:

```bash
"$SC/write_verdict_artifact" --id "$id" < /tmp/$id/verdict.new.md
```

After the verdict is persisted, **clean up**:
`"$SC/cleanup" --id "$id" --workdir "$workdir"` — **unless** one of these holds, in which case you
persist the verdict but deliberately **skip cleanup** so the run survives:

- **Low-severity gate:** keep the run for the optional debate.
- **Leftovers to continue:** keep the run if the final index has any `unresolved` or `contested`
  issue, so the user can `panel-review:continue [unresolved|contested]` to debate them further.

After persistence and conditional cleanup, use the bootstrap's success return. The launching
command derives gate/continuation status from the validated artifact and retained canonical index;
never return the verdict body or a second copy of those counts.

If an error or abort prevents verdict persistence, also do **not** clean up: leave the run state
intact for `panel-review:resume` and use the bootstrap's review-failure return.

<!-- /phase:verdict -->
