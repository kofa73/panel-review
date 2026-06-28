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
assert_file_contains "template exposes category revision" '"category":"<opt>"' "$root/prompts/debate.tmpl"
assert_file_contains "template describes selective rationale promotion" 'plus the `rationale` from a `reject`' "$root/prompts/debate.tmpl"
assert_file_contains "protocol uses degraded decision script" 'decide_degraded_round' "$root/skills/panel-review-for-agent/SKILL.md"
retained_line="$(grep -nF 'Build the retained stance input' "$root/skills/panel-review-for-agent/SKILL.md" | head -1 | cut -d: -f1)"
degraded_line="$(grep -nF '"$SC/decide_degraded_round" --id "$id"' "$root/skills/panel-review-for-agent/SKILL.md" | head -1 | cut -d: -f1)"
if [ -n "$retained_line" ] && [ -n "$degraded_line" ] && [ "$retained_line" -lt "$degraded_line" ]; then
  ok "protocol builds retained stances before degraded decision"
else
  bad "protocol ordering for retained stances" "build line=$retained_line degraded line=$degraded_line"
fi
assert_file_contains "protocol delegates batch admission" 'sweep ingest-batch' "$root/skills/panel-review-for-agent/SKILL.md"
assert_file_contains "protocol delegates dropped-seat cleanup" 'sweep" drop-seat' "$root/skills/panel-review-for-agent/SKILL.md"
assert_file_contains "protocol reapplies the low-only gate" 'Low-severity stop gate (after each committed round)' "$root/skills/panel-review-for-agent/SKILL.md"
assert_file_contains "README uses general constrained-seat wording" 'any seat running in a constrained/sandboxed workspace' "$root/README.md"
assert_file_contains "README warns to run in an isolated environment (broad seat permissions)" 'isolated environment (Docker' "$root/README.md"
assert_file_contains "CLAUDE.md uses general constrained-seat wording" 'constrained/sandboxed workspace' "$root/CLAUDE.md"
assert_file_contains "blind_pass template carries the scratch sentinel" '{{SCRATCH}}' "$root/prompts/blind_pass.tmpl"
assert_file_contains "debate template carries the scratch sentinel"     '{{SCRATCH}}' "$root/prompts/debate.tmpl"
assert_file_contains "protocol passes SCRATCH to assemble" 'SCRATCH=/tmp/$id/scratch.txt' "$root/skills/panel-review-for-agent/SKILL.md"
assert_file_contains "protocol snapshots the tracked tree" 'repo_guard" snapshot' "$root/skills/panel-review-for-agent/SKILL.md"
assert_file_contains "protocol verifies + restores the tree" 'repo_guard" verify' "$root/skills/panel-review-for-agent/SKILL.md"
assert_file_contains "Claude seat exposes read-only tilth tools" 'mcp__tilth__tilth_search' "$root/agents/panel-review-claude-seat.md"
case "$(grep -F 'tools:' "$root/agents/panel-review-claude-seat.md")" in
  *mcp__tilth__tilth_write*) bad "Claude seat must NOT expose tilth write tool" ;;
  *) ok "Claude seat excludes tilth write tool" ;;
esac
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
# is driven by MOCK_MODE + a per-test counter file so we can exercise repair.
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
  good)               printf '```%s\n%s\n```\n' "$MOCK_TAG" "$good" > "$out" ;;
  malformed_then_good) if [ "$n" -eq 1 ]; then printf '```%s\n%s\n```\n' "$MOCK_TAG" "$bad" > "$out"; else printf '```%s\n%s\n```\n' "$MOCK_TAG" "$good" > "$out"; fi ;;
  always_malformed)   printf '```%s\n%s\n```\n' "$MOCK_TAG" "$bad" > "$out" ;;
  noblock)            printf 'I will not answer.\n' > "$out" ;;
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

section "run_seat — dispatch + parse, status on stdout"
st="$(run_seat_codex good findings g1)"
assert_eq "clean findings -> status 0"          '0' "$st"
assert_eq "clean findings -> one parsed object" '1' "$(grep -c . "$TMP/seat.parsed.g1")"
assert_eq "parsed is _source-tagged"            'codex' "$(jq -r '._source' "$TMP/seat.parsed.g1")"
assert_eq "single dispatch (no repair)"         '1' "$(cat "$TMP/seat.count.g1")"

section "run_seat — one-shot repair salvages a malformed block"
st="$(run_seat_codex malformed_then_good findings r1)"
assert_eq "malformed-then-good -> status 0"  '0' "$st"
assert_eq "exactly two dispatches (1 repair)" '2' "$(cat "$TMP/seat.count.r1")"
assert_eq "repaired content parsed"          'c' "$(jq -r '.claim' "$TMP/seat.parsed.r1")"

section "run_seat — repair retried once then gives up; --no-repair skips it"
st="$(run_seat_codex always_malformed findings r2)"
assert_eq "still malformed after repair -> status 5" '5' "$st"
assert_eq "repair attempted exactly once (2 calls)"  '2' "$(cat "$TMP/seat.count.r2")"
st="$(run_seat_codex always_malformed findings r3 --no-repair)"
assert_eq "--no-repair malformed -> status 5"        '5' "$st"
assert_eq "--no-repair makes a single dispatch"      '1' "$(cat "$TMP/seat.count.r3")"

section "run_seat — no-block seat is down (status 4), nothing to repair"
st="$(run_seat_codex noblock findings r4)"
assert_eq "no block -> status 4"          '4' "$st"
assert_eq "down seat not re-dispatched"   '1' "$(cat "$TMP/seat.count.r4")"

section "run_seat — repair extends to malformed new_findings blocks"
st="$(run_seat_codex malformed_then_good new_findings nf1)"
assert_eq "new_findings repaired -> status 0" '0' "$st"
assert_eq "new_findings two dispatches"       '2' "$(cat "$TMP/seat.count.nf1")"

section "run_seat — gemini routes through run_agy"
st="$(timeout 30 env MOCK_MODE=good MOCK_TAG=findings PATH="$seat_mockbin:$PATH" HOME="$seat_home" \
  "$SC/run_seat" --seat gemini --tag findings --prompt "$TMP/seat.prompt" --raw "$TMP/seat.raw.gem" --parsed "$TMP/seat.parsed.gem" 2>/dev/null)"
assert_eq "gemini seat -> status 0"      '0' "$st"
assert_eq "gemini parsed _source=gemini" 'gemini' "$(jq -r '._source' "$TMP/seat.parsed.gem")"
"$SC/run_seat" --seat mistral --tag findings --prompt "$TMP/seat.prompt" --raw "$TMP/x" --parsed "$TMP/y" >/dev/null 2>&1; assert_exit "unknown seat -> usage exit 2" 2 "$?"

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

section "protocol references the new deterministic helpers"
assert_file_contains "protocol uses birth_index"          'birth_index' "$root/skills/panel-review-for-agent/SKILL.md"
assert_file_contains "protocol uses run_seat"             'run_seat'    "$root/skills/panel-review-for-agent/SKILL.md"
assert_file_contains "protocol uses resolve_instructions" 'resolve_instructions' "$root/skills/panel-review-for-agent/SKILL.md"

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
