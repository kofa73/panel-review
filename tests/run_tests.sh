#!/usr/bin/env bash
# Regression suite for the panel-review scripts that are STILL bash (resolve_diff,
# preflight, birth_index, run_seat, resolve_instructions, cleanup/discard) plus the
# protocol/template contracts. Self-contained: fixtures live in tests/fixtures/,
# this is plain bash with a tiny assert harness.
#
# The stateful scripts ported to Python (index, parse_block, decide_round,
# decide_degraded_round, merge_payload, sweep) are covered by tests/python/ via
# unittest. This script invokes that Python suite as a final gate (see the end), so
# `tests/run_tests.sh` still runs the whole regression in one command.
#
# Usage: tests/run_tests.sh            # run all (bash + python), nonzero if any fail
#        VERBOSE=1 tests/run_tests.sh  # also print each PASS
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
SC="$root/scripts"
TMP="$(mktemp -d /tmp/pr-tests.XXXXXX)"
PREFIX="pr-test-$$"
trap 'rm -rf "$TMP"; rm -rf /tmp/'"$PREFIX"'-* 2>/dev/null' EXIT

pass=0; fail=0
ok()   { pass=$((pass+1)); [ "${VERBOSE:-0}" = 1 ] && echo "  PASS: $1"; return 0; }
bad()  { fail=$((fail+1)); echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "        $2"; return 0; }
# assert_eq <name> <expected> <actual>
assert_eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2] got [$3]"; fi; }
# assert_exit <name> <want-code> <got-code>
assert_exit() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want exit $2 got $3"; fi; }
assert_file_contains() { if grep -Fq -- "$2" "$3"; then ok "$1"; else bad "$1" "missing [$2] in $3"; fi; }
assert_file_not_contains() { if grep -Fq -- "$2" "$3"; then bad "$1" "unexpected [$2] in $3"; else ok "$1"; fi; }
section() { echo; echo "## $1"; }

# ---------------------------------------------------------------------------
section "resolve_diff — combined tracked diff and no-HEAD fallback"
repo="$TMP/diff-repo"; mkdir -p "$repo"
(
  cd "$repo" || exit 1
  git init -q
  printf 'base\n' > tracked.txt
  git add tracked.txt
  git -c user.name=test -c user.email=test@example.invalid commit -qm initial
  printf 'staged\n' > tracked.txt; git add tracked.txt
  printf 'worktree\n' > tracked.txt
  "$SC/resolve_diff" uncommitted
) > "$TMP/diff.out" 2>"$TMP/diff.err"; assert_exit "tracked diff succeeds" 0 "$?"
assert_eq "tracked file has one combined patch" '1' "$(grep -c '^diff --git a/tracked.txt b/tracked.txt$' "$TMP/diff.out")"
grep -Fq '+worktree' "$TMP/diff.out"; assert_exit "combined patch reaches worktree" 0 "$?"
fresh="$TMP/fresh-repo"; mkdir -p "$fresh"
(
  cd "$fresh" || exit 1
  git init -q
  printf 'new\n' > staged.txt
  git add staged.txt
  "$SC/resolve_diff" uncommitted
) > "$TMP/fresh.out" 2>"$TMP/fresh.err"; assert_exit "no-HEAD staged fallback succeeds" 0 "$?"
grep -Fq 'new file mode' "$TMP/fresh.out"; assert_exit "no-HEAD fallback emits staged file" 0 "$?"

section "preflight — authenticated Codex status does not warn"
mockbin="$TMP/mockbin"; mkdir -p "$mockbin"
cat > "$mockbin/codex" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$CODEX_LOG"
if [ "$1" = login ] && [ "$2" = status ]; then
  printf '%s\n' 'Logged in using ChatGPT' >&2
fi
EOF
chmod +x "$mockbin/codex"
pf="$(CODEX_LOG="$TMP/codex.log" PATH="$mockbin:$PATH" "$SC/preflight" 2>&1)"; assert_exit "preflight succeeds with mocked Codex" 0 "$?"
case "$pf" in *"WARNING: run 'codex login'"*) bad "logged-in Codex does not warn";; *) ok "logged-in Codex does not warn";; esac
assert_eq "preflight calls codex login status" 'login status' "$(cat "$TMP/codex.log")"

section "protocol and template contracts"
protocol="$root/skills/panel-review-for-agent/references/protocol.md"
# The emit schema is single-sourced in prompts/schema/ (Concern E): the category
# revision field now lives in the stances fragment, not inline in debate.tmpl.
assert_file_contains "stances schema fragment exposes category revision" '"category"' "$root/prompts/schema/stances.txt"
assert_file_contains "debate template splices the stances schema" '{{SCHEMA_STANCES}}' "$root/prompts/debate.tmpl"
assert_file_contains "template describes selective rationale promotion" 'plus the `rationale` from a `reject`' "$root/prompts/debate.tmpl"
assert_file_contains "protocol uses degraded decision script" 'decide_degraded_round' "$protocol"
assert_file_contains "protocol delegates batch admission" 'sweep ingest-batch' "$protocol"
assert_file_contains "protocol uses coarse debate salvage" 'round" salvage-debate' "$protocol"
assert_file_contains "protocol forbids stance checkpoint globbing" 'Do not glob `*.stances.json`' "$protocol"
assert_file_contains "protocol defines complete two-block checkpoints" 'parsed `new_findings`, zero `status.nf.*`' "$protocol"
assert_file_contains "protocol delegates dropped-seat cleanup" 'sweep" drop-seat' "$protocol"
assert_file_contains "protocol reapplies the low-only gate" 'Low-severity stop gate (after each committed round)' "$protocol"
assert_file_contains "README uses general constrained-seat wording" 'any seat running in a constrained/sandboxed workspace' "$root/README.md"
assert_file_contains "README warns to run in an isolated environment (broad seat permissions)" 'isolated environment (Docker' "$root/README.md"
assert_file_contains "blind_pass template carries the scratch sentinel" '{{SCRATCH}}' "$root/prompts/blind_pass.tmpl"
assert_file_contains "debate template carries the scratch sentinel"     '{{SCRATCH}}' "$root/prompts/debate.tmpl"
assert_file_contains "protocol passes SCRATCH to assemble" 'SCRATCH=/tmp/$id/scratch.txt' "$protocol"
assert_file_contains "protocol snapshots the tracked tree" 'repo_guard" snapshot' "$protocol"
assert_file_contains "protocol verifies + restores the tree" 'repo_guard" verify' "$protocol"

# Final-report delivery is artifact-only: the referee returns a fixed stub and the
# main-context commands validate the artifact through one deterministic reader mode.
assert_file_contains "referee returns only the artifact-ready stub" 'PANEL_VERDICT_READY id=<id>' "$root/agents/panel-review-referee.md"
assert_file_contains "protocol requires durable artifact delivery" 'Artifact persistence is required for delivery' "$protocol"
assert_file_contains "start closes post-persistence cleanup crash window" 'artifact persistence succeeded but the referee' "$root/skills/start/SKILL.md"
for command in start resume continue; do
  skill="$root/skills/$command/SKILL.md"
  assert_file_contains "$command validates artifact-only delivery" 'read_verdict_artifact" --delivery' "$skill"
  if grep -Fq 'present the verdict verbatim' "$skill"; then
    bad "$command does not restate the verdict body" "stale verbatim-delivery instruction remains"
  else
    ok "$command does not restate the verdict body"
  fi
done

# --- blind-pass robustness (design-notes/blind-pass-robustness.md) ---------------
# Concern A: the diff body is EXTERNALIZED — blind_pass.tmpl references a file, it no
# longer inlines the {{DIFF}} body, and the protocol builds/passes {{DIFFINFO}}.
if grep -Fq -- '{{DIFF}}' "$root/prompts/blind_pass.tmpl"; then
  bad "blind_pass no longer inlines the diff body" "still carries the {{DIFF}} sentinel"
else
  ok "blind_pass no longer inlines the diff body"
fi
assert_file_contains "blind_pass carries a diff REFERENCE sentinel" '{{DIFFINFO}}' "$root/prompts/blind_pass.tmpl"
assert_file_contains "protocol builds the diff_info reference" 'diff_info.txt' "$protocol"
assert_file_contains "protocol passes DIFFINFO to assemble" 'DIFFINFO=/tmp/$id/diff_info.txt' "$protocol"
if grep -Fq -- 'DIFF=/tmp/$id/diff.txt' "$protocol"; then
  bad "protocol drops the inline DIFF= assemble arg" "still passes DIFF=/tmp/\$id/diff.txt"
else
  ok "protocol drops the inline DIFF= assemble arg"
fi
# Concern B: absolute anchors — WORKDIR sentinel in both templates, absolute scratch,
# an explicit agy tool-cwd directive, and absolute card paths in debate.
assert_file_contains "blind_pass carries the review-root anchor" '{{WORKDIR}}' "$root/prompts/blind_pass.tmpl"
assert_file_contains "debate carries the review-root anchor"     '{{WORKDIR}}' "$root/prompts/debate.tmpl"
assert_file_contains "blind_pass directs agy to set the tool cwd" 'working-directory / `cwd` parameter' "$root/prompts/blind_pass.tmpl"
assert_file_contains "debate directs agy to set the tool cwd"     'working-directory / `cwd` parameter' "$root/prompts/debate.tmpl"
assert_file_contains "protocol writes an ABSOLUTE scratch anchor" '"$workdir/.panel-review/$id/work" > /tmp/$id/scratch.txt' "$protocol"
assert_file_contains "protocol writes the review-root file" 'workdir.txt' "$protocol"
assert_file_contains "protocol collects ABSOLUTE card paths" '<workdir>/.panel-review/<id>/issue-<oid>.md' "$protocol"
# Concern C: the output contract is hoisted ABOVE the Files/Diff section in blind_pass.
of_line="$(grep -nF '## Output format' "$root/prompts/blind_pass.tmpl" | head -1 | cut -d: -f1)"
fd_line="$(grep -nF '## Files / Diff' "$root/prompts/blind_pass.tmpl" | head -1 | cut -d: -f1)"
if [ -n "$of_line" ] && [ -n "$fd_line" ] && [ "$of_line" -lt "$fd_line" ]; then
  ok "blind_pass hoists the output contract above the diff"
else
  bad "blind_pass output-contract ordering" "Output format line=$of_line Files/Diff line=$fd_line"
fi
# Concern E: single-sourced schema — sentinels in the templates, fragments exist and
# VALIDATE through parse_block (parser-behavior drift check, not string equality).
assert_file_contains "blind_pass splices the findings schema" '{{SCHEMA_FINDINGS}}' "$root/prompts/blind_pass.tmpl"
assert_file_contains "debate splices the new-findings schema"  '{{SCHEMA_FINDINGS}}' "$root/prompts/debate.tmpl"
for frag in findings stances; do
  [ -f "$root/prompts/schema/$frag.txt" ] && ok "schema fragment $frag.txt exists" || bad "schema fragment $frag.txt exists"
done
printf '```findings\n%s\n```\n' "$(cat "$root/prompts/schema/findings.txt")" > "$TMP/frag.findings.txt"
"$SC/parse_block" findings "$TMP/frag.findings.txt" x >/dev/null 2>&1
assert_exit "findings schema fragment validates through parse_block" 0 "$?"
printf '```stances\n%s\n```\n' "$(cat "$root/prompts/schema/stances.txt")" > "$TMP/frag.stances.txt"
"$SC/parse_block" stances "$TMP/frag.stances.txt" x >/dev/null 2>&1
assert_exit "stances schema fragment validates through parse_block" 0 "$?"
# field-shuffled variant: an unknown revision subfield is normalized away, not rejected.
printf '```stances\n%s\n```\n' '{"id":"i1","stance":"support_with_revision","revision":{"bogus_field":"x","severity":"high"}}' > "$TMP/frag.shuffled.txt"
shuf_out="$("$SC/parse_block" stances "$TMP/frag.shuffled.txt" x 2>/dev/null)"
assert_exit "field-shuffled stance still validates (normalized)" 0 "$?"
case "$shuf_out" in *bogus_field*) bad "unknown revision subfield normalized away" "leaked: $shuf_out";; *) ok "unknown revision subfield normalized away";; esac
# Concern F: new_findings is required-EMPTYABLE — an explicit `[]` (or empty) block is
# valid (exit 0), NOT malformed, so a seat with nothing new is not falsely repaired.
printf '```new_findings\n[]\n```\n' > "$TMP/nf.empty-array.txt"
"$SC/parse_block" new_findings "$TMP/nf.empty-array.txt" x >/dev/null 2>&1
assert_exit "empty-array new_findings block is valid (F)" 0 "$?"
assert_file_contains "debate asks to ALWAYS emit new_findings" 'ALWAYS emit this block' "$root/prompts/debate.tmpl"
assert_file_contains "protocol treats new_findings as required-emptyable" 'required-emptyable' "$protocol"
# Salvage is referee-owned (no script repair, no repair seat): the protocol carries the
# extract-first-else-empty anti-hallucination rule, and repair.tmpl is retired.
assert_file_contains "protocol salvage uses extract-first-else-empty wording" 'if and only if the seat genuinely raised nothing' "$protocol"
[ -e "$root/prompts/repair.tmpl" ] && bad "repair.tmpl is retired" "still present" || ok "repair.tmpl is retired"

# --- CLI-seat wait is a background Agent, never a backgrounded Bash job (the stalled-referee fix) ---
# Root cause it guards: a background Bash job does NOT re-invoke the sub-agent that launched it, so a
# referee that backgrounded await_seats stalled forever. The wait must go through an Agent.
spk="$protocol"
bar="$root/agents/panel-review-cli-barrier.md"
assert_file_contains "cli-barrier agent exists with the right name" 'name: panel-review-cli-barrier' "$bar"
assert_file_contains "cli-barrier agent is a non-reviewing wait barrier" 'wait barrier**, not a reviewer' "$bar"
assert_file_contains "cli-barrier runs await_seats detached in the background" 'run_in_background: true' "$bar"
assert_file_contains "cli-barrier waits via a bounded foreground loop" 'until [ -f' "$bar"
# The step-2 wait is a foreground Bash tool call inside a BACKGROUND subagent, so each wait is bounded
# by TWO timeouts: the Bash tool's 2-min default AND the ~10-min background-subagent stall abort
# (CLAUDE_ASYNC_AGENT_STALL_TIMEOUT_MS). The robust design keeps each wait SHORT (under the 2-min
# default) and loops, rather than one long wait that depends on the model raising the tool `timeout`.
assert_file_contains "cli-barrier waits in short chunks under the 2-min Bash default" 'timeout 100 bash -c' "$bar"
assert_file_contains "cli-barrier accounts for the background-subagent stall abort" 'CLAUDE_ASYNC_AGENT_STALL_TIMEOUT_MS' "$bar"
# Regression: must NOT reintroduce the fragile long-wait-with-raised-tool-timeout design.
if grep -Fq '570000' "$bar"; then bad "cli-barrier must not depend on raising the Bash tool timeout"; else ok "cli-barrier does not depend on a raised Bash tool timeout"; fi
# Match the command FORM ('timeout 540 bash'), not a prose mention of the number, so the doc can
# still cite `timeout 540` as the anti-pattern it explains against.
if grep -Fq 'timeout 540 bash' "$bar"; then bad "cli-barrier must not use a >2-min wait the Bash default truncates"; else ok "cli-barrier uses no >2-min blocking wait"; fi
assert_file_contains "protocol dispatches the cli-barrier Agent" 'panel-review:panel-review-cli-barrier' "$spk"
assert_file_contains "protocol writes the Round-0 barrier command to a script" 'cli_barrier.round0.sh' "$spk"
assert_file_contains "protocol explains why background Bash cannot wake a sub-agent" 're-invoke the sub-agent that launched it' "$spk"
# Regression guard: the OLD broken instruction (referee backgrounds await_seats itself) must be gone.
if grep -Fq 'ONE background Bash call' "$spk"; then bad "protocol must not background await_seats as a bash job"; else ok "protocol no longer backgrounds await_seats directly"; fi
if grep -Eq 'await_seats.*run_in_background' "$spk"; then bad "protocol must not pair await_seats with run_in_background"; else ok "await_seats is not backgrounded by the referee"; fi

# --- The barrier owns await_seats' terminal state via an exit-code SENTINEL (the false-degrade fix) ---
# Root cause it guards: the barrier used to poll the --done file, which await_seats writes ONLY on a
# clean exit. A setup/usage error left no done-file, so the barrier polled its whole ~43-min budget
# and then falsely reported "seats did not finish" (a silent degraded review). It also could not tell
# a crashed detached job from a slow one, and a late write could land after the referee moved on.
assert_file_contains "cli-barrier takes a sentinel input path"                'sentinel=<path>' "$bar"
assert_file_contains "cli-barrier captures await_seats' exit code into the sentinel" 'rc=$?; printf' "$bar"
assert_file_contains "cli-barrier waits on the sentinel, not the done-file"   'until [ -f "<sentinel>"' "$bar"
assert_file_contains "cli-barrier reports await_seats_rc so the referee can tell setup-error from clean" 'await_seats_rc=' "$bar"
assert_file_contains "cli-barrier best-effort reaps a wedged job on budget exhaustion" 'pkill -f' "$bar"
assert_file_contains "protocol passes the Round-0 sentinel path to the barrier" 'sentinel=/tmp/<id>/await.round0.sentinel' "$spk"
assert_file_contains "protocol reads await_seats_rc and treats nonzero/absent as CLI seats down" 'await_seats_rc' "$spk"

# --- Packaging: every plugin agent the protocol dispatches must be TRACKED in git ---
# Root cause it guards: agents/panel-review-cli-barrier.md once existed on disk but was never
# `git add`ed, so the tracked diff would ship without it and a fresh clone/install could not resolve
# the first `subagent_type: panel-review:panel-review-cli-barrier` dispatch. `assert_file_contains`
# checks bytes on disk and would NOT catch that; only git tracking does.
section "packaging — every plugin agent file is tracked in git"
for f in "$root"/agents/*.md; do
  rel="agents/$(basename "$f")"
  if [ -n "$(git -C "$root" ls-files "$rel")" ]; then ok "$rel is tracked in git"
  else bad "$rel exists on disk but is NOT tracked in git" "a fresh clone/install would miss it; run: git add $rel"; fi
done
# And the inverse: every agent a skill dispatches via subagent_type must have a tracked file.
for a in $(grep -rhoE 'subagent_type[": ]+panel-review:panel-review-[a-z0-9-]+' "$root/skills" | grep -oE 'panel-review-[a-z0-9-]+' | sort -u); do
  if [ -n "$(git -C "$root" ls-files "agents/$a.md")" ]; then ok "dispatched agent $a.md is tracked in git"
  else bad "skill dispatches subagent $a but agents/$a.md is not tracked in git" "the first dispatch in a fresh install would fail"; fi
done

assert_file_contains "Claude seat exposes read-only tilth tools" 'mcp__tilth__tilth_search' "$root/agents/panel-review-claude-seat.md"
case "$(grep -F 'tools:' "$root/agents/panel-review-claude-seat.md")" in
  *mcp__tilth__tilth_write*) bad "Claude seat must NOT expose tilth write tool" ;;
  *) ok "Claude seat excludes tilth write tool" ;;
esac
assert_file_not_contains "Claude seat does not request batched evidence lookups" 'Batch independent evidence lookups' "$root/agents/panel-review-claude-seat.md"
assert_file_not_contains "Claude seat does not prefer multi-symbol lookup" 'one `tilth_search` multi-symbol query' "$root/agents/panel-review-claude-seat.md"
assert_file_contains "Claude seat avoids redundant reads" 'Avoid redundant evidence reads' "$root/agents/panel-review-claude-seat.md"
assert_file_contains "Claude seat stops after sufficient evidence" 'Stop exploratory calls once the output is supported' "$root/agents/panel-review-claude-seat.md"
assert_file_contains "Claude seat has no hard call cap" 'hard tool-call' "$root/agents/panel-review-claude-seat.md"
assert_file_contains "Claude delivery combines both debate blocks" 'For a debate response, put both' "$root/prompts/claude_delivery.tmpl"
assert_file_contains "Claude delivery validates and writes both debate blocks once" '`stances` and `new_findings` in that file and invoke this command once' "$root/prompts/claude_delivery.tmpl"
assert_file_contains "Claude delivery replaces redundant per-block validation" "the task prompt's separate per-block pre-emit validation command" "$root/prompts/claude_delivery.tmpl"
case "$(grep -F 'codex exec' "$root/scripts/run_codex")" in
  *--sandbox\ read-only*) bad "run_codex must no longer pin --sandbox read-only" ;;
  *--dangerously-bypass-approvals-and-sandbox*) ok "run_codex bypasses the sandbox" ;;
  *) bad "run_codex codex exec invocation unrecognized" ;;
esac
assert_file_contains "run_agy passes skip-permissions for tilth" '--dangerously-skip-permissions' "$root/scripts/run_agy"
# run_codex feeds the prompt on stdin (codex's documented [PROMPT]-or-stdin contract);
# unlike agy it has no flag that consumes the prompt, so stdin is parser-safe.
assert_file_contains "run_codex feeds the prompt via stdin" '< "$promptfile"' "$root/scripts/run_codex"

# ---------------------------------------------------------------------------
section "repo_guard — snapshot / verify / restore protects tracked files"
rg="$TMP/guard-repo"; mkdir -p "$rg"
(
  cd "$rg" || exit 1
  git init -q
  printf 'orig\n' > a.txt; printf 'keep\n' > b.txt
  git add .
  git -c user.name=test -c user.email=test@example.invalid commit -qm init
)
gid="$PREFIX-guard"; rm -rf "/tmp/$gid"
# issues-2026-07-04 #1: help/unknown verb reach usage WITHOUT a valid id.
"$SC/repo_guard" -h > "$TMP/rg.help" 2>&1; assert_exit "repo_guard -h -> exit 0" 0 "$?"
assert_file_contains "repo_guard -h prints usage" 'usage: repo_guard' "$TMP/rg.help"
"$SC/repo_guard" bogus > "$TMP/rg.bad" 2>&1; assert_exit "repo_guard unknown verb -> exit 2" 2 "$?"
grep -Fq 'invalid run id' "$TMP/rg.bad" && bad "repo_guard unknown verb leaked invalid-run-id" || ok "repo_guard unknown verb reaches usage before the id check"
"$SC/repo_guard" snapshot --id "$gid" --workdir "$rg" >/dev/null 2>&1; assert_exit "snapshot clean tree -> 0" 0 "$?"
"$SC/repo_guard" verify --id "$gid" --workdir "$rg" > "$TMP/guard.v1" 2>/dev/null; assert_exit "verify clean -> 0" 0 "$?"
assert_eq "clean verify emits no drift" '' "$(cat "$TMP/guard.v1")"
printf 'tampered\n' > "$rg/a.txt"
"$SC/repo_guard" verify --id "$gid" --workdir "$rg" > "$TMP/guard.v2" 2>/dev/null; assert_exit "modified tracked file -> exit 1" 1 "$?"
assert_file_contains "verify names the drifted file" 'modified: a.txt' "$TMP/guard.v2"
"$SC/repo_guard" verify --id "$gid" --workdir "$rg" --restore >/dev/null 2>&1; assert_exit "restore pass still reports drift (exit 1)" 1 "$?"
assert_eq "restore reverted the tracked file"      'orig' "$(cat "$rg/a.txt")"
"$SC/repo_guard" verify --id "$gid" --workdir "$rg" >/dev/null 2>&1; assert_exit "post-restore verify clean -> 0" 0 "$?"
mkdir -p "$rg/.panel-review/$gid/work"; echo scratch > "$rg/.panel-review/$gid/work/s.txt"
"$SC/repo_guard" verify --id "$gid" --workdir "$rg" >/dev/null 2>&1; assert_exit "untracked scratch is ignored -> 0" 0 "$?"
# A baseline taken on a DIRTY tree restores the dirty bytes, not HEAD.
gid2="$PREFIX-guard-dirty"; rm -rf "/tmp/$gid2"
printf 'dirty\n' > "$rg/a.txt"
"$SC/repo_guard" snapshot --id "$gid2" --workdir "$rg" >/dev/null 2>&1
printf 'tampered2\n' > "$rg/a.txt"
"$SC/repo_guard" verify --id "$gid2" --workdir "$rg" --restore >/dev/null 2>&1 || true
assert_eq "dirty-at-snapshot restores the dirty bytes (not HEAD)" 'dirty' "$(cat "$rg/a.txt")"
rm -rf "/tmp/$gid" "/tmp/$gid2"

# ---------------------------------------------------------------------------
section "birth_index — mechanical Round-0 state / flags / coverage"
id="$PREFIX-birth"; rm -rf "/tmp/$id"; mkdir -p "/tmp/$id"
cat > "$TMP/birth.specs.json" <<'EOF'
[
 {"id":"i1","claim":"all three raised","location":"a.c:1","category":"correctness","severity":"high","evidence_pro":[{"location":"a.c:1","assertion":"x"}],"raised_by":["codex","gemini","claude"]},
 {"id":"i2","claim":"two of three","location":"a.c:2","category":"security","severity":"medium","evidence_pro":[{"location":"a.c:2","assertion":"y"}],"raised_by":["codex","claude"]},
 {"id":"i3","claim":"single raiser","location":"a.c:3","category":"performance","severity":"low","evidence_pro":[{"location":"a.c:3","assertion":"z"}],"raised_by":["gemini"]},
 {"id":"i4","claim":"unanimous but detail diverges","location":"a.c:4","category":"correctness","severity":"high","evidence_pro":[{"location":"a.c:4","assertion":"w"}],"raised_by":["codex","gemini","claude"],"detail_divergence":true}
]
EOF
"$SC/birth_index" --available "codex gemini claude" --configured "codex gemini claude" < "$TMP/birth.specs.json" > "/tmp/$id/index.json" 2>/dev/null; assert_exit "birth_index full panel -> 0" 0 "$?"
echo '{}' > "/tmp/$id/manifest.json"
assert_eq "i1 unanimous -> accepted/peer/fully_vetted" 'accepted|true|true|false' "$(jq -r '.issues[]|select(.id=="i1")|"\(.state)|\(.peer_reviewed)|\(.fully_vetted)|\(.detail_contested)"' "/tmp/$id/index.json")"
assert_eq "i2 partial (2/3) -> open, not peer"          'open|false|false'        "$(jq -r '.issues[]|select(.id=="i2")|"\(.state)|\(.peer_reviewed)|\(.fully_vetted)"' "/tmp/$id/index.json")"
assert_eq "i3 single raiser -> open"                     'open'                    "$(jq -r '.issues[]|select(.id=="i3")|.state' "/tmp/$id/index.json")"
assert_eq "i4 unanimous + divergence -> accepted+detail_contested" 'accepted|true' "$(jq -r '.issues[]|select(.id=="i4")|"\(.state)|\(.detail_contested)"' "/tmp/$id/index.json")"
assert_eq "evaluated_by = the raisers (sorted unique)" '["claude","codex","gemini"]' "$(jq -c '.evaluated_by.i1' "/tmp/$id/index.json")"
assert_eq "i2 evaluated_by tracks 2 raisers"            '["claude","codex"]'         "$(jq -c '.evaluated_by.i2' "/tmp/$id/index.json")"
assert_eq "index installs cleanly (gate-status reads it)" '{"open":2,"low_only":false}' "$("$SC/index" gate-status "$id")"

section "birth_index — degraded panel: unanimous-but-down seat is not fully_vetted"
id="$PREFIX-birth-down"; rm -rf "/tmp/$id"; mkdir -p "/tmp/$id"
echo '[{"id":"i1","claim":"c","location":"a:1","category":"correctness","severity":"high","evidence_pro":[{"location":"a:1","assertion":"x"}],"raised_by":["codex","claude"]}]' \
  | "$SC/birth_index" --available "codex claude" --configured "codex gemini claude" > "/tmp/$id/index.json" 2>/dev/null
assert_eq "all-available (2) raised, gemini down -> accepted, NOT fully_vetted" 'accepted|true|false' "$(jq -r '.issues[]|select(.id=="i1")|"\(.state)|\(.peer_reviewed)|\(.fully_vetted)"' "/tmp/$id/index.json")"

section "birth_index — validation rejects bad input (exit 3)"
echo '[{"id":"i1","claim":"c","location":"a:1","category":"style","severity":"style","evidence_pro":[{"location":"a:1","assertion":"x"}],"raised_by":["codex","claude"]}]' \
  | "$SC/birth_index" --available "codex claude" --configured "codex claude" >/dev/null 2>&1; assert_exit "style severity -> exit 3" 3 "$?"
echo '[{"id":"i1","claim":"c","location":"a:1","category":"correctness","severity":"high","evidence_pro":[{"location":"a:1","assertion":"x"}],"raised_by":["gemini"]}]' \
  | "$SC/birth_index" --available "codex claude" --configured "codex claude" >/dev/null 2>&1; assert_exit "raiser not available -> exit 3" 3 "$?"
echo '[{"id":"i1","claim":"c","location":"a:1","category":"correctness","severity":"high","evidence_pro":[{"location":"a:1","assertion":"x"}],"raised_by":["codex"]},{"id":"i1","claim":"d","location":"a:2","category":"correctness","severity":"high","evidence_pro":[{"location":"a:2","assertion":"y"}],"raised_by":["codex"]}]' \
  | "$SC/birth_index" --available "codex claude" --configured "codex claude" >/dev/null 2>&1; assert_exit "duplicate id -> exit 3" 3 "$?"
echo '[{"id":"i1","claim":"c","location":"a:1","category":"correctness","severity":"high","evidence_pro":[],"raised_by":["codex"]}]' \
  | "$SC/birth_index" --available "codex claude" --configured "codex claude" >/dev/null 2>&1; assert_exit "empty evidence_pro -> exit 3" 3 "$?"
assert_eq "empty issue list -> empty debate index" '0|debate' "$(echo '[]' | "$SC/birth_index" --available "codex claude" --configured "codex claude" | jq -r '"\(.issues|length)|\(.phase)"')"

# ---------------------------------------------------------------------------
# run_seat needs a mock CLI on PATH. The mock writes to codex's `-o <file>` and
# is driven by MOCK_MODE + a per-test counter file so we can assert a SINGLE
# dispatch — run_seat no longer repairs; salvaging a slipped block is the
# referee's job (the seat has exited), so the wrapper just dispatches + parses.
seat_mockbin="$TMP/seatbin"; mkdir -p "$seat_mockbin"
cat > "$seat_mockbin/codex" <<'EOF'
#!/usr/bin/env bash
out=""; prev=""
for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
cat >/dev/null    # drain the prompt
n=0; [ -f "${MOCK_COUNT:-/dev/null}" ] && n="$(cat "$MOCK_COUNT")"; n=$((n+1)); echo "$n" > "$MOCK_COUNT"
good='{"claim":"c","location":"a.c:1","category":"correctness","severity":"high","points":[{"assertion":"x","location":"a.c:1"}]}'
bad='{"location":"a.c:1","category":"correctness","severity":"high","points":[{"assertion":"x","location":"a.c:1"}]}'
case "$MOCK_MODE" in
  good)      printf '```%s\n%s\n```\n' "$MOCK_TAG" "$good" > "$out" ;;
  malformed) printf '```%s\n%s\n```\n' "$MOCK_TAG" "$bad"  > "$out" ;;
  noblock)   printf 'I will not answer.\n' > "$out" ;;
esac
EOF
chmod +x "$seat_mockbin/codex"
cat > "$seat_mockbin/agy" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
printf '```findings\n%s\n```\n' '{"claim":"g","location":"a.c:1","category":"correctness","severity":"high","points":[{"assertion":"x","location":"a.c:1"}]}'
EOF
chmod +x "$seat_mockbin/agy"
seat_home="$TMP/seathome"; mkdir -p "$seat_home"
printf 'PROMPT\n' > "$TMP/seat.prompt"
run_seat_codex() { MOCK_TAG="$2" MOCK_MODE="$1" MOCK_COUNT="$TMP/seat.count.$3" PATH="$seat_mockbin:$PATH" HOME="$seat_home" \
  "$SC/run_seat" --seat codex --tag "$2" --prompt "$TMP/seat.prompt" --raw "$TMP/seat.raw.$3" --parsed "$TMP/seat.parsed.$3" "${@:4}" 2>/dev/null; }

section "run_seat — dispatch + parse, status on stdout (no repair)"
st="$(run_seat_codex good findings g1)"
assert_eq "clean findings -> status 0"          '0' "$st"
assert_eq "clean findings -> one parsed object" '1' "$(grep -c . "$TMP/seat.parsed.g1")"
assert_eq "parsed is _source-tagged"            'codex' "$(jq -r '._source' "$TMP/seat.parsed.g1")"
assert_eq "single dispatch (never repairs)"     '1' "$(cat "$TMP/seat.count.g1")"

section "run_seat — a malformed block is reported (status 5), never repaired"
st="$(run_seat_codex malformed findings r1)"
assert_eq "malformed -> status 5"             '5' "$st"
assert_eq "malformed still a single dispatch" '1' "$(cat "$TMP/seat.count.r1")"

section "run_seat — a no-block seat is down (status 4)"
st="$(run_seat_codex noblock findings r4)"
assert_eq "no block -> status 4"        '4' "$st"
assert_eq "down seat = single dispatch" '1' "$(cat "$TMP/seat.count.r4")"

section "run_seat — a malformed new_findings block is reported (status 5), never repaired"
st="$(run_seat_codex malformed new_findings nf1)"
assert_eq "malformed new_findings -> status 5"     '5' "$st"
assert_eq "malformed new_findings single dispatch" '1' "$(cat "$TMP/seat.count.nf1")"

section "run_seat — gemini routes through run_agy"
st="$(timeout 30 env MOCK_MODE=good MOCK_TAG=findings PATH="$seat_mockbin:$PATH" HOME="$seat_home" \
  "$SC/run_seat" --seat gemini --tag findings --prompt "$TMP/seat.prompt" --raw "$TMP/seat.raw.gem" --parsed "$TMP/seat.parsed.gem" 2>/dev/null)"
assert_eq "gemini seat -> status 0"      '0' "$st"
assert_eq "gemini parsed _source=gemini" 'gemini' "$(jq -r '._source' "$TMP/seat.parsed.gem")"

section "run_seat — usage guards"
"$SC/run_seat" --seat mistral --tag findings --prompt "$TMP/seat.prompt" --raw "$TMP/x" --parsed "$TMP/y" >/dev/null 2>&1; assert_exit "unknown seat -> usage exit 2" 2 "$?"
# the repair path is retired, so its old flag is now just an unknown arg.
"$SC/run_seat" --seat codex --tag findings --prompt "$TMP/seat.prompt" --raw "$TMP/x" --parsed "$TMP/y" --no-repair >/dev/null 2>&1; assert_exit "retired --no-repair -> usage exit 2" 2 "$?"

# ---------------------------------------------------------------------------
# await_seats — the barrier. Runs both CLI seats concurrently through run_seat in
# one job, writes each seat's final status + a combined summary, then exits 0.
# It reuses the seat mock CLIs above; we add a configurable-mode codex and a
# slow/down agy so we can drive the down-seat and outer-timeout paths.
await_mockbin="$TMP/awaitbin"; mkdir -p "$await_mockbin"
# codex: MODE=good emits a block; MODE=noblock emits prose (down, status 4).
cat > "$await_mockbin/codex" <<'EOF'
#!/usr/bin/env bash
out=""; prev=""; for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
cat >/dev/null
good='{"claim":"c","location":"a.c:1","category":"correctness","severity":"high","points":[{"assertion":"x","location":"a.c:1"}]}'
case "${MOCK_CODEX:-good}" in
  noblock) printf 'I will not answer.\n' > "$out" ;;
  *)       printf '```findings\n%s\n```\n' "$good" > "$out" ;;
esac
EOF
# agy: MODE=good emits a block; MODE=hang sleeps past the outer timeout.
cat > "$await_mockbin/agy" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
case "${MOCK_AGY:-good}" in
  hang) sleep 30 ;;
  *)    printf '```findings\n%s\n```\n' '{"claim":"g","location":"b.c:2","category":"correctness","severity":"high","points":[{"assertion":"y","location":"b.c:2"}]}' ;;
esac
EOF
chmod +x "$await_mockbin/codex" "$await_mockbin/agy"
await_home="$TMP/awaithome"; mkdir -p "$await_home"
printf 'PROMPT\n' > "$TMP/await.prompt"; mkdir -p "$TMP/await.raw"
# run await_seats with the given codex/agy mock modes + seat-timeout; returns its exit.
run_await() { # <codex-mode> <agy-mode> <seat-timeout> <suffix> [extra args...]
  MOCK_CODEX="$1" MOCK_AGY="$2" PATH="$await_mockbin:$PATH" HOME="$await_home" \
  "$SC/await_seats" --id "await-$4" --tag findings --prompt "$TMP/await.prompt" --seat-timeout "$3" \
    --seat codex  --raw "$TMP/await.raw/c.$4.txt" --parsed "$TMP/await.f.codex.$4.json"  --status "$TMP/await.st.codex.$4" \
    --seat gemini --raw "$TMP/await.raw/g.$4.txt" --parsed "$TMP/await.f.gemini.$4.json" --status "$TMP/await.st.gemini.$4" \
    --done "$TMP/await.done.$4" "${@:5}" 2>/dev/null; }

section "await_seats — both seats engage; per-seat status + combined summary"
run_await good good 0 ok; assert_exit "barrier exits 0" 0 "$?"
assert_eq "codex status 0"        '0' "$(cat "$TMP/await.st.codex.ok")"
assert_eq "gemini status 0"       '0' "$(cat "$TMP/await.st.gemini.ok")"
assert_eq "codex parsed _source"  'codex'  "$(jq -r '._source' "$TMP/await.f.codex.ok.json")"
assert_eq "gemini parsed _source" 'gemini' "$(jq -r '._source' "$TMP/await.f.gemini.ok.json")"
assert_file_contains "done lists codex 0"  'codex 0'  "$TMP/await.done.ok"
assert_file_contains "done lists gemini 0" 'gemini 0' "$TMP/await.done.ok"

section "await_seats — a down seat is status 4, the other still engages"
run_await noblock good 0 down; assert_exit "barrier still exits 0 with a down seat" 0 "$?"
assert_eq "down codex -> status 4"      '4' "$(cat "$TMP/await.st.codex.down")"
assert_eq "live gemini -> status 0"     '0' "$(cat "$TMP/await.st.gemini.down")"
assert_file_contains "done lists codex 4" 'codex 4' "$TMP/await.done.down"

section "await_seats — outer timeout reaps a hung seat (status 124), runs concurrently"
t0=$(date +%s); run_await good hang 2 to; rc=$?; el=$(( $(date +%s) - t0 ))
assert_exit "barrier exits 0 after reaping a hang" 0 "$rc"
assert_eq "hung gemini -> status 124"   '124' "$(cat "$TMP/await.st.gemini.to")"
assert_eq "fast codex still status 0"   '0'   "$(cat "$TMP/await.st.codex.to")"
if [ "$el" -lt 15 ]; then ok "barrier returns near the timeout (~${el}s), not the 30s hang"; else bad "barrier waited too long (${el}s)"; fi

section "await_seats — usage guards"
# issues-2026-07-04 #1: -h prints usage WITHOUT a valid id (before panel_require_id).
"$SC/await_seats" -h > "$TMP/await.help" 2>&1; assert_exit "await_seats -h -> exit 0" 0 "$?"
assert_file_contains "await_seats -h prints usage" 'usage: await_seats' "$TMP/await.help"
grep -Fq 'invalid run id' "$TMP/await.help" && bad "await_seats -h leaked invalid-run-id" || ok "await_seats -h reaches usage before the id check"
PATH="$await_mockbin:$PATH" HOME="$await_home" "$SC/await_seats" --id 'bad/id' --tag findings --prompt "$TMP/await.prompt" \
  --seat codex --raw "$TMP/r" --parsed "$TMP/p" --status "$TMP/s" --done "$TMP/d" >/dev/null 2>&1
assert_exit "invalid id -> exit 2" 2 "$?"
PATH="$await_mockbin:$PATH" HOME="$await_home" "$SC/await_seats" --id await-noseat --tag findings --prompt "$TMP/await.prompt" \
  --done "$TMP/d" >/dev/null 2>&1
assert_exit "no --seat block -> exit 2" 2 "$?"
PATH="$await_mockbin:$PATH" HOME="$await_home" "$SC/await_seats" --id await-noraw --tag findings --prompt "$TMP/await.prompt" \
  --seat codex --parsed "$TMP/p" --status "$TMP/s" --done "$TMP/d" >/dev/null 2>&1
assert_exit "seat missing --raw -> exit 2" 2 "$?"
# The barrier CANNOT use the done-file as its completion signal: every setup/usage error above exits
# nonzero and writes NO done-file, so an absent done-file is ambiguous between "still running" and
# "crashed at startup". This is exactly why the barrier wraps await_seats in an exit-code sentinel.
if [ -f "$TMP/d" ]; then bad "await_seats wrote a done-file despite a setup error"; else ok "await_seats writes no done-file on a setup error (barrier needs the sentinel)"; fi

section "protocol wording — the barrier's wait signal is the sentinel, never --done"
# The behavioral invariant above (no done-file on a setup error) is WHY the barrier must wait on the
# exit-code sentinel, not on --done (a RESULT file that appears only on a clean exit). But the debate
# protocol is prompt-driven: contradictory prose in the docs the referee/barrier actually read can
# route execution back to the old done-file wait, which hangs the whole budget on a setup error and
# then false-degrades the CLI seats. So guard those docs against the old "watches --done" / "--done
# is the wait signal" wording. A correct line always names the sentinel, so lines that do are
# excluded (they may still mention --done as a result file).
wording_docs=(
  "$root/skills/panel-review-for-agent/SKILL.md"
  "$protocol"
  "$root/agents/panel-review-cli-barrier.md"
  "$root/AGENTS.md"
  "$root/scripts/await_seats"
)
bad_wording=""
for f in "${wording_docs[@]}"; do
  grep -niE 'done is the wait signal' "$f" >/dev/null 2>&1 && bad_wording+=" ${f##*/}(wait-signal)"
  grep -niE 'watch(e[sd]|ing)?[^.]*--done' "$f" 2>/dev/null | grep -qvi sentinel && bad_wording+=" ${f##*/}(watches-done)"
done
if [ -z "$bad_wording" ]; then ok "no protocol doc treats --done as the barrier's wait signal"; else bad "stale --done-as-wait-signal wording present" "$bad_wording"; fi

# ---------------------------------------------------------------------------
# run_agy invocation contract. agy's `--print` TAKES the prompt as its argument;
# a bare `--print` + stdin desyncs parsing and silently drops --model and
# --print-timeout (agy then runs the ~/.gemini default model at the 5m default
# cap). The stub records argv (one token per line, per-call separators) and the
# piped prompt so we can assert the exact flags and the genuine model fallback.
agy_mockbin="$TMP/agybin"; mkdir -p "$agy_mockbin"
cat > "$agy_mockbin/agy" <<'EOF'
#!/usr/bin/env bash
{ printf '%s\n' "$@"; printf '<<<CALL>>>\n'; } >> "$AGY_ARGV"
cat >> "$AGY_STDIN"
n=0; [ -f "$AGY_COUNT" ] && n="$(cat "$AGY_COUNT")"; n=$((n+1)); echo "$n" > "$AGY_COUNT"
fb='```findings
{"claim":"g","location":"a.c:1","category":"correctness","severity":"high","points":[{"assertion":"x","location":"a.c:1"}]}
```'
case "${AGY_MODE:-good}" in
  good)              printf '%s\n' "$fb" ;;
  timeout_then_good) if [ "$n" -eq 1 ]; then printf 'Error: timed out waiting for response\n'; else printf '%s\n' "$fb"; fi ;;
  always_timeout)    printf 'Error: timed out waiting for response\n' ;;
esac
exit 0
EOF
chmod +x "$agy_mockbin/agy"
printf 'PLEASE REVIEW THIS DIFF SENTINEL-7Q\n' > "$TMP/agy.in"
run_agy_t() { # $1=mode $2=tag ; prompt on stdin (run_agy with no args)
  AGY_MODE="$1" AGY_ARGV="$TMP/agy.argv.$2" AGY_STDIN="$TMP/agy.stdin.$2" AGY_COUNT="$TMP/agy.count.$2" \
    PATH="$agy_mockbin:$PATH" timeout 30 "$SC/run_agy" < "$TMP/agy.in" > "$TMP/agy.out.$2" 2>"$TMP/agy.err.$2"
}

section "run_agy — invocation binds flags (no bare --print, prompt via stdin)"
run_agy_t good p1; assert_exit "primary good -> exit 0" 0 "$?"
if grep -Fxq -- '--print' "$TMP/agy.argv.p1"; then bad "run_agy must NOT pass a bare --print (it swallows --model)"; else ok "no bare --print token"; fi
assert_file_contains "passes --print-timeout=15m (=form, bound budget)" '--print-timeout=15m' "$TMP/agy.argv.p1"
assert_file_contains "passes --dangerously-skip-permissions"            '--dangerously-skip-permissions' "$TMP/agy.argv.p1"
if grep -Fxq -- 'Gemini 3.1 Pro (High)' "$TMP/agy.argv.p1"; then ok "primary model is Pro (High)"; else bad "primary model not Pro (High)"; fi
assert_file_contains "prompt reaches agy via stdin" 'SENTINEL-7Q' "$TMP/agy.stdin.p1"
assert_eq "primary success = single dispatch" '1' "$(cat "$TMP/agy.count.p1")"
assert_file_contains "primary output carries the findings block" '```findings' "$TMP/agy.out.p1"

section "run_agy — print-timeout (exit 0 + error tail) triggers the Flash fallback"
run_agy_t timeout_then_good p2; assert_exit "fallback recovers -> exit 0" 0 "$?"
assert_eq "primary timeout + fallback = two dispatches" '2' "$(cat "$TMP/agy.count.p2")"
if grep -Fxq -- 'Gemini 3.5 Flash (High)' "$TMP/agy.argv.p2"; then ok "fallback model is Flash (High)"; else bad "fallback did not switch to Flash (High)"; fi
assert_file_contains "fallback output carries the findings block" '```findings' "$TMP/agy.out.p2"
assert_file_contains "logs the fallback switch" 'retrying with fallback' "$TMP/agy.err.p2"

section "run_agy — both models time out -> seat fails (exit 1)"
run_agy_t always_timeout p3; assert_exit "both fail -> exit 1" 1 "$?"
assert_eq "both attempts dispatched" '2' "$(cat "$TMP/agy.count.p3")"
assert_file_contains "reports both-model failure" 'both primary' "$TMP/agy.err.p3"

# ---------------------------------------------------------------------------
section "resolve_instructions — verbatim / none resolved, auto -> sentinel"
id="$PREFIX-instr"; rm -rf "/tmp/$id"; mkdir -p "/tmp/$id"
echo '{"instructions":""}' > "/tmp/$id/manifest.json"
out="$("$SC/resolve_instructions" --id "$id")"; rc=$?
assert_exit "empty instructions -> exit 0" 0 "$rc"
assert_eq "empty -> the standard none line" '(none — review the diff on its own terms)' "$out"
echo '{"instructions":"Focus on the redis TTL logic."}' > "/tmp/$id/manifest.json"
out="$("$SC/resolve_instructions" --id "$id")"; assert_exit "verbatim -> exit 0" 0 "$?"
assert_eq "verbatim author text passed through" 'Focus on the redis TTL logic.' "$out"
echo '{"instructions":"auto"}' > "/tmp/$id/manifest.json"
out="$("$SC/resolve_instructions" --id "$id" 2>/dev/null)"; rc=$?
assert_exit "auto -> compose sentinel exit 3" 3 "$rc"
assert_eq "auto prints the compose sentinel" '__PANEL_COMPOSE_INSTRUCTIONS__' "$out"
rm -f "/tmp/$id/manifest.json"
"$SC/resolve_instructions" --id "$id" >/dev/null 2>&1; assert_exit "missing manifest -> exit 1" 1 "$?"

# ---------------------------------------------------------------------------
section "cleanup / discard — PANEL_REVIEW_KEEP_TMP preserves /tmp diagnostics"
keeprepo="$TMP/keep-repo"; mkdir -p "$keeprepo"; ( cd "$keeprepo" && git init -q )
id="$PREFIX-keep"; rm -rf "/tmp/$id"; mkdir -p "/tmp/$id"; echo '{"id":"x"}' > "/tmp/$id/manifest.json"
mkdir -p "$keeprepo/.panel-review/$id"; echo "$id" > "$keeprepo/.panel-review/$id/.panel-run"
PANEL_REVIEW_KEEP_TMP=true "$SC/cleanup" --id "$id" --workdir "$keeprepo" 2>/dev/null
assert_eq "KEEP_TMP cleanup removes the marker"     'gone'    "$([ -d "$keeprepo/.panel-review/$id" ] && echo here || echo gone)"
assert_eq "KEEP_TMP cleanup preserves /tmp/<id>"    'kept'    "$([ -d "/tmp/$id" ] && echo kept || echo gone)"
# Default behavior (env var unset/false) must purge /tmp/<id>. The test runner may
# itself export PANEL_REVIEW_KEEP_TMP=true (it is a documented diagnostic toggle), so
# clear it explicitly here — otherwise this case silently inherits the ambient value
# and stops testing the default at all.
mkdir -p "$keeprepo/.panel-review/$id"; echo "$id" > "$keeprepo/.panel-review/$id/.panel-run"
env -u PANEL_REVIEW_KEEP_TMP "$SC/cleanup" --id "$id" --workdir "$keeprepo" 2>/dev/null
assert_eq "default cleanup removes /tmp/<id>"       'gone'    "$([ -d "/tmp/$id" ] && echo kept || echo gone)"
# Same env-var sensitivity holds for explicit false.
mkdir -p "/tmp/$id"; echo '{"id":"x"}' > "/tmp/$id/manifest.json"
mkdir -p "$keeprepo/.panel-review/$id"; echo "$id" > "$keeprepo/.panel-review/$id/.panel-run"
PANEL_REVIEW_KEEP_TMP=false "$SC/cleanup" --id "$id" --workdir "$keeprepo" 2>/dev/null
assert_eq "KEEP_TMP=false cleanup removes /tmp/<id>" 'gone'   "$([ -d "/tmp/$id" ] && echo kept || echo gone)"
id="$PREFIX-keep2"; rm -rf "/tmp/$id"; mkdir -p "/tmp/$id"; echo '{}' > "/tmp/$id/manifest.json"
mkdir -p "$keeprepo/.panel-review/$id"; echo "$id" > "$keeprepo/.panel-review/$id/.panel-run"
PANEL_REVIEW_KEEP_TMP=true "$SC/discard" --workdir "$keeprepo" >/dev/null
assert_eq "KEEP_TMP discard preserves /tmp/<id>"    'kept'    "$([ -d "/tmp/$id" ] && echo kept || echo gone)"
assert_eq "KEEP_TMP discard still clears .panel-review" 'gone' "$([ -d "$keeprepo/.panel-review" ] && echo here || echo gone)"
rm -rf "/tmp/$id"
# Default discard purges /tmp/<id> too (again clearing the ambient toggle).
id="$PREFIX-keep3"; rm -rf "/tmp/$id"; mkdir -p "/tmp/$id"; echo '{}' > "/tmp/$id/manifest.json"
mkdir -p "$keeprepo/.panel-review/$id"; echo "$id" > "$keeprepo/.panel-review/$id/.panel-run"
env -u PANEL_REVIEW_KEEP_TMP "$SC/discard" --workdir "$keeprepo" >/dev/null
assert_eq "default discard removes /tmp/<id>"       'gone'    "$([ -d "/tmp/$id" ] && echo kept || echo gone)"
rm -rf "/tmp/$id"
# Explicit false discards /tmp/<id> as well (symmetry with the cleanup=false case).
id="$PREFIX-keep4"; rm -rf "/tmp/$id"; mkdir -p "/tmp/$id"; echo '{}' > "/tmp/$id/manifest.json"
mkdir -p "$keeprepo/.panel-review/$id"; echo "$id" > "$keeprepo/.panel-review/$id/.panel-run"
PANEL_REVIEW_KEEP_TMP=false "$SC/discard" --workdir "$keeprepo" >/dev/null
assert_eq "KEEP_TMP=false discard removes /tmp/<id>" 'gone'   "$([ -d "/tmp/$id" ] && echo kept || echo gone)"
rm -rf "/tmp/$id"

section "reopen — archives the finished epoch, then resets for the next cycle"
# A finished run: i1 accepted (settled a prior round), i2 contested (the leftover).
# reopen must (a) snapshot the whole finished record into epochs/epoch-<prev>/ before
# the next cycle's round-N filenames clobber it, (b) reset the live index for a fresh
# debate, (c) wipe+recreate sweeps. Regression for the continue data-loss/round-restart
# investigation (issues-2026-07-11): night round-1 raws were overwritten with no .bak.
rid="$PREFIX-reopen1"; rm -rf "/tmp/$rid" "/tmp/$rid.md" "/tmp/$rid.md.bak"
mkdir -p "/tmp/$rid/raw" "/tmp/$rid/audit" "/tmp/$rid/sweeps/round-1"
cat > "/tmp/$rid/index.json" <<'JSON'
{"issues":[{"id":"i1","claim":"c","location":"f:1","category":"performance","severity":"medium","evidence_pro":[],"evidence_contra":[],"peer_reviewed":true,"fully_vetted":true,"detail_contested":false,"state":"accepted","rounds_debated":1,"card_rev":2},{"id":"i2","claim":"c","location":"f:2","category":"correctness","severity":"high","evidence_pro":[],"evidence_contra":[],"peer_reviewed":true,"fully_vetted":true,"detail_contested":false,"state":"contested","rounds_debated":2,"card_rev":5}],"round":2,"phase":"debate","committed_rounds":[1,2],"run_epoch":0,"evaluated_by":{"i1":["claude","codex","gemini"],"i2":["claude","codex","gemini"]}}
JSON
echo "NIGHT round1 claude raw" > "/tmp/$rid/raw/round1.claude.1.txt"
echo "# round-1 audit" > "/tmp/$rid/audit/round-1.md"
echo "sweep-round1-data" > "/tmp/$rid/sweeps/round-1/claude.1.out"
echo "NIGHT VERDICT BODY" > "/tmp/$rid.md"
"$SC/reopen" --id "$rid" --category contested >/dev/null 2>&1; assert_exit "reopen matched contested" 0 "$?"
# live index reset for the new cycle
assert_eq "reopen resets round to 0"          '0'    "$(jq -r '.round' "/tmp/$rid/index.json")"
assert_eq "reopen bumps run_epoch"            '1'    "$(jq -r '.run_epoch' "/tmp/$rid/index.json")"
assert_eq "reopen clears committed_rounds"    '[]'   "$(jq -c '.committed_rounds' "/tmp/$rid/index.json")"
assert_eq "reopened leftover back to open"    'open' "$(jq -r '.issues[]|select(.id=="i2")|.state' "/tmp/$rid/index.json")"
assert_eq "prior-epoch accepted issue kept"   'accepted' "$(jq -r '.issues[]|select(.id=="i1")|.state' "/tmp/$rid/index.json")"
# archive preserves the finished record the next cycle would overwrite
assert_file_contains "archive keeps round-1 raw"   'NIGHT round1 claude raw' "/tmp/$rid/epochs/epoch-0/raw/round1.claude.1.txt"
assert_file_contains "archive keeps the verdict"   'NIGHT VERDICT BODY'      "/tmp/$rid/epochs/epoch-0/verdict.md"
assert_file_contains "archive keeps the audit"     'round-1 audit'          "/tmp/$rid/epochs/epoch-0/audit/round-1.md"
assert_eq "archived index is the finished (pre-reset) one" '2' "$(jq -r '.round' "/tmp/$rid/epochs/epoch-0/index.json")"
assert_eq "archived index kept i2 contested"       'contested' "$(jq -r '.issues[]|select(.id=="i2")|.state' "/tmp/$rid/epochs/epoch-0/index.json")"
assert_eq "sweeps wiped for the new cycle"         'gone' "$([ -e "/tmp/$rid/sweeps/round-1" ] && echo present || echo gone)"
assert_eq "sweeps dir recreated"                   'yes'  "$([ -d "/tmp/$rid/sweeps" ] && echo yes || echo no)"

# No leftover to reopen: exit 3, index untouched, NO spurious archive.
rid2="$PREFIX-reopen2"; rm -rf "/tmp/$rid2"; mkdir -p "/tmp/$rid2"
cat > "/tmp/$rid2/index.json" <<'JSON'
{"issues":[{"id":"i1","claim":"c","location":"f:1","category":"performance","severity":"medium","evidence_pro":[],"evidence_contra":[],"peer_reviewed":true,"fully_vetted":true,"detail_contested":false,"state":"accepted","rounds_debated":1,"card_rev":2}],"round":1,"phase":"debate","committed_rounds":[1],"run_epoch":0,"evaluated_by":{"i1":["claude","codex"]}}
JSON
"$SC/reopen" --id "$rid2" --category both >/dev/null 2>&1; assert_exit "reopen with nothing to reopen exits 3" 3 "$?"
assert_eq "no-match makes no archive"    'no' "$([ -d "/tmp/$rid2/epochs" ] && echo yes || echo no)"
assert_eq "no-match leaves index untouched" '1|0' "$(jq -r '"\(.round)|\(.run_epoch)"' "/tmp/$rid2/index.json")"
rm -rf "/tmp/$rid" "/tmp/$rid.md" "/tmp/$rid.md.bak" "/tmp/$rid2"

section "protocol references the new deterministic helpers"
assert_file_contains "protocol uses birth_index"          'birth_index' "$protocol"
assert_file_contains "protocol uses run_seat"             'run_seat'    "$protocol"
assert_file_contains "protocol uses resolve_instructions" 'resolve_instructions' "$protocol"
assert_file_contains "protocol waits via await_seats barrier" 'await_seats' "$protocol"

# ---------------------------------------------------------------------------
# Python suite — the coverage for the migrated stateful scripts (index, parse_block,
# decide_round, decide_degraded_round, merge_payload, sweep). Run it here so this one
# command still exercises the whole pipeline. python3 is a required dependency.
section "python unit tests (migrated scripts via unittest)"
if py_out="$(python3 -m unittest discover -s "$here/python" 2>&1)"; then
  ok "python unittest suite — $(printf '%s\n' "$py_out" | grep -oE 'Ran [0-9]+ tests' | head -1)"
else
  bad "python unittest suite" "$(printf '%s\n' "$py_out" | tail -20)"
fi

# ---------------------------------------------------------------------------
echo
echo "================================"
echo "  PASS: $pass   FAIL: $fail"
echo "================================"
[ "$fail" -eq 0 ]
