#!/usr/bin/env bash
# Regression suite for the panel-review scripts that are STILL bash (resolve_diff,
# preflight, run_seat, resolve_instructions, cleanup/discard) plus the
# protocol/template contracts. Self-contained: fixtures live in tests/fixtures/,
# this is plain bash with a tiny assert harness.
#
# Python script interfaces, including birth_index, extract_block, and the stateful
# modules, are covered by black-box cases here and/or tests/python/ via unittest.
# This script invokes the Python suite as a final gate (see the end), so
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
assert_file_contains_text() {
  local normalized
  normalized="$(tr '\n' ' ' < "$3" | sed 's/[[:space:]][[:space:]]*/ /g')"
  case "$normalized" in *"$2"*) ok "$1";; *) bad "$1" "missing normalized text [$2] in $3";; esac
}
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
empty_claude_config="$TMP/empty-claude-config"; mkdir -p "$empty_claude_config"
cat > "$mockbin/codex" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$CODEX_LOG"
if [ "$1" = login ] && [ "$2" = status ]; then
  printf '%s\n' 'Logged in using ChatGPT' >&2
fi
EOF
chmod +x "$mockbin/codex"
# preflight reads `agy models` to check the Gemini seat's pins (issue 63). Mock it so the
# suite never calls the network: it prints $AGY_LISTING_FILE (empty = listing unreadable),
# and fails when AGY_MODELS_FAIL=1.
cat > "$mockbin/agy" <<'EOF'
#!/bin/sh
if [ "$1" = models ]; then
  [ "${AGY_MODELS_FAIL:-0}" = 1 ] && exit 1
  [ -n "${AGY_LISTING_FILE:-}" ] && cat "$AGY_LISTING_FILE"
  exit 0
fi
exit 0
EOF
chmod +x "$mockbin/agy"
# CLAUDE_CODE_FORK_SUBAGENT=0 is a hard prerequisite (issue 25), and the suite must be
# runnable from any session, so set it explicitly here rather than inheriting it.
pf="$(CLAUDE_CODE_FORK_SUBAGENT=0 CLAUDE_CONFIG_DIR="$empty_claude_config" CODEX_LOG="$TMP/codex.log" PATH="$mockbin:$PATH" "$SC/preflight" 2>&1)"; assert_exit "preflight succeeds with mocked Codex" 0 "$?"
case "$pf" in *"WARNING: run 'codex login'"*) bad "logged-in Codex does not warn";; *) ok "logged-in Codex does not warn";; esac
assert_eq "preflight calls codex login status" 'login status' "$(cat "$TMP/codex.log")"

section "preflight — fork mode gate (issue 25)"
# Only the literal "0" counts as off: unset means the harness default, which is ON in
# interactive sessions from Claude Code 2.1.232, so the gate must refuse unset too.
for bad_value in "" "1" "false" "off"; do
  if [ -z "$bad_value" ]; then
    out="$(env -u CLAUDE_CODE_FORK_SUBAGENT CLAUDE_CONFIG_DIR="$empty_claude_config" PATH="$mockbin:$PATH" CODEX_LOG="$TMP/codex2.log" "$SC/preflight" 2>&1)"; rc=$?
    label="unset"
  else
    out="$(CLAUDE_CODE_FORK_SUBAGENT="$bad_value" CLAUDE_CONFIG_DIR="$empty_claude_config" PATH="$mockbin:$PATH" CODEX_LOG="$TMP/codex2.log" "$SC/preflight" 2>&1)"; rc=$?
    label="$bad_value"
  fi
  assert_exit "preflight blocks with CLAUDE_CODE_FORK_SUBAGENT=$label" 1 "$rc"
  case "$out" in *"CLAUDE_CODE_FORK_SUBAGENT=0 claude"*) ok "block names the remedy ($label)";; *) bad "block names the remedy ($label)";; esac
done

section "preflight — outside-workdir read block (issue 62)"
pf_repo="$TMP/preflight-repo"; mkdir -p "$pf_repo/.claude"
git -C "$pf_repo" init -q
cat > "$pf_repo/.claude/settings.json" <<'EOF'
{"permissions":{"blockReadsOutsideWorkingDirectories":true}}
EOF
(
  cd "$pf_repo" || exit 1
  CLAUDE_CODE_FORK_SUBAGENT=0 CLAUDE_CONFIG_DIR="$empty_claude_config" \
    CODEX_LOG="$TMP/codex3.log" PATH="$mockbin:$PATH" "$SC/preflight"
) > "$TMP/preflight-block.out" 2>&1; rc=$?
assert_exit "preflight blocks outside-workdir setting" 1 "$rc"
assert_file_contains "preflight names blocking project file" "$pf_repo/.claude/settings.json" "$TMP/preflight-block.out"
assert_file_contains "preflight prints exact additionalDirectories config" '"additionalDirectories": ["/tmp"]' "$TMP/preflight-block.out"
assert_file_contains "preflight names repository config path" "repository: $pf_repo/.claude/settings.json" "$TMP/preflight-block.out"
assert_file_contains "preflight names user config path" "user:       $empty_claude_config/settings.json" "$TMP/preflight-block.out"
assert_file_contains "preflight prints add-dir launch" 'PANEL_REVIEW_TMP_ADDED=1 CLAUDE_CODE_FORK_SUBAGENT=0 claude --add-dir /tmp' "$TMP/preflight-block.out"

cat > "$empty_claude_config/settings.json" <<'EOF'
{"permissions":{"additionalDirectories":["/tmp"]}}
EOF
(
  cd "$pf_repo" || exit 1
  CLAUDE_CODE_FORK_SUBAGENT=0 CLAUDE_CONFIG_DIR="$empty_claude_config" \
    CODEX_LOG="$TMP/codex4.log" PATH="$mockbin:$PATH" "$SC/preflight"
) > "$TMP/preflight-configured.out" 2>&1; rc=$?
assert_exit "configured /tmp grant satisfies preflight" 0 "$rc"
assert_file_not_contains "configured /tmp grant emits no block" 'blockReadsOutsideWorkingDirectories blocks' "$TMP/preflight-configured.out"

rm "$empty_claude_config/settings.json"
(
  cd "$pf_repo" || exit 1
  PANEL_REVIEW_TMP_ADDED=1 CLAUDE_CODE_FORK_SUBAGENT=0 CLAUDE_CONFIG_DIR="$empty_claude_config" \
    CODEX_LOG="$TMP/codex5.log" PATH="$mockbin:$PATH" "$SC/preflight"
) > "$TMP/preflight-add-dir.out" 2>&1; rc=$?
assert_exit "add-dir launch marker satisfies preflight" 0 "$rc"

section "preflight — a Codex config layer above the profile (issue 47)"
# Codex layers cwd/tree/repo config ABOVE `--profile panel-review`, so a reviewed
# repository's own .codex/config.toml decides which model reviews it. Measured live on
# codex-cli 0.153.4. preflight only REPORTS it (the file is the user's), so the machine
# line must flip and the human block must name both sides of the difference.
pin_home="$TMP/codex-pin-home"; mkdir -p "$pin_home/.codex"
cat > "$pin_home/.codex/panel-review.config.toml" <<'EOF'
model = "pinned-model"
model_reasoning_effort = "pinned-effort"
EOF
layer_repo="$TMP/codex-layer-repo"; mkdir -p "$layer_repo/.codex"
git -C "$layer_repo" init -q
cat > "$layer_repo/.codex/config.toml" <<'EOF'
model = "repo-model"
model_reasoning_effort = "repo-effort"

[some_table]
model = "must-not-be-read"
EOF
(
  cd "$layer_repo" || exit 1
  CLAUDE_CODE_FORK_SUBAGENT=0 CLAUDE_CONFIG_DIR="$empty_claude_config" HOME="$pin_home" \
    CODEX_LOG="$TMP/codex6.log" PATH="$mockbin:$PATH" "$SC/preflight"
) > "$TMP/preflight-layer.out" 2>&1; rc=$?
assert_exit "a Codex model layer is a warning, not a hard failure" 0 "$rc"
assert_file_contains "layer report is machine-readable"  'CODEX_MODEL_LAYER: yes' "$TMP/preflight-layer.out"
assert_file_contains "layer report names the file"       "$layer_repo/.codex/config.toml" "$TMP/preflight-layer.out"
assert_file_contains "layer report shows its values"     'model = repo-model   model_reasoning_effort = repo-effort' "$TMP/preflight-layer.out"
assert_file_contains "layer report shows the pin"        'panel-review pins model = pinned-model   model_reasoning_effort = pinned-effort' "$TMP/preflight-layer.out"
# A `model` under a [table] is a different key; reading it would report a phantom override.
assert_file_not_contains "table-scoped model is not read" 'must-not-be-read' "$TMP/preflight-layer.out"
# The seat-detection tail must stay parseable, with the newer lines ahead of it. The
# mocked agy prints no listing here, so its pin check reads "unknown".
tail4="$(tail -n4 "$TMP/preflight-layer.out" | tr '\n' ' ')"
case "$tail4" in
  'GEMINI_PIN_UNLISTED: unknown CODEX_MODEL_LAYER: yes CODEX: yes GEMINI: yes ') ok "tail order stays GEMINI_PIN_UNLISTED, CODEX_MODEL_LAYER, CODEX, GEMINI";;
  *) bad "tail order stays GEMINI_PIN_UNLISTED, CODEX_MODEL_LAYER, CODEX, GEMINI" "got [$tail4]";;
esac

clean_repo="$TMP/codex-clean-repo"; mkdir -p "$clean_repo"
git -C "$clean_repo" init -q
(
  cd "$clean_repo" || exit 1
  CLAUDE_CODE_FORK_SUBAGENT=0 CLAUDE_CONFIG_DIR="$empty_claude_config" HOME="$pin_home" \
    CODEX_LOG="$TMP/codex7.log" PATH="$mockbin:$PATH" "$SC/preflight"
) > "$TMP/preflight-nolayer.out" 2>&1; rc=$?
assert_exit "no Codex layer -> preflight succeeds" 0 "$rc"
assert_file_contains "no layer -> machine line says no" 'CODEX_MODEL_LAYER: no' "$TMP/preflight-nolayer.out"
assert_file_not_contains "no layer -> no warning block" 'above the panel-review profile' "$TMP/preflight-nolayer.out"

section "preflight — a Gemini seat pin agy no longer lists (issue 63)"
# agy 1.4.2 dropped both pinned labels; an unlisted label hard-errors on 1.1.13/1.4.2 and
# ran the settings.json default silently on 1.1.10. preflight reads `agy models` (no
# quota) and REPORTS a pin that is missing, never blocks. Pins are read from run_agy so a
# model bump needs no test edit.
pf_pin() { sed -n "s/^$1=\"\(.*\)\"$/\1/p" "$SC/run_agy"; }
pf_primary="$(pf_pin PRIMARY_MODEL)"; pf_fallback="$(pf_pin FALLBACK_MODEL)"
run_pf_listing() { # $1 = listing file ("" = none), $2 = output file, rest = extra env
  local listing="$1" out="$2"; shift 2
  env CLAUDE_CODE_FORK_SUBAGENT=0 CLAUDE_CONFIG_DIR="$empty_claude_config" CODEX_LOG="$TMP/codex-pin.log" \
    AGY_LISTING_FILE="$listing" PATH="$mockbin:$PATH" "$@" "$SC/preflight" > "$out" 2>&1
}
printf 'gemini-x-high\t%s\ngemini-y-high\t%s\nclaude-z\tClaude Z (High)\n' "$pf_primary" "$pf_fallback" > "$TMP/agy-listing.both"
run_pf_listing "$TMP/agy-listing.both" "$TMP/preflight-pins-ok.out"; rc=$?
assert_exit "listed pins -> preflight succeeds" 0 "$rc"
assert_file_contains "listed pins -> machine line says no" 'GEMINI_PIN_UNLISTED: no' "$TMP/preflight-pins-ok.out"
assert_file_not_contains "listed pins -> no warning block" 'does not list the Gemini seat' "$TMP/preflight-pins-ok.out"
assert_file_not_contains "listed pins -> no unchecked note" 'were not checked' "$TMP/preflight-pins-ok.out"

# A label that only EXTENDS the pin must not count as listing it.
printf 'gemini-x-highest\t%s-extra\ngemini-y-high\t%s\ngemini-n-new\tGemini 9 New (High)\nclaude-z\tClaude Z (High)\n' "$pf_primary" "$pf_fallback" > "$TMP/agy-listing.noprimary"
run_pf_listing "$TMP/agy-listing.noprimary" "$TMP/preflight-pins-missing.out"; rc=$?
assert_exit "an unlisted pin is a warning, not a hard failure" 0 "$rc"
assert_file_contains "unlisted pin -> machine line says yes" 'GEMINI_PIN_UNLISTED: yes' "$TMP/preflight-pins-missing.out"
assert_file_contains "unlisted pin -> names the pin and its value" "PRIMARY_MODEL = \"$pf_primary\"" "$TMP/preflight-pins-missing.out"
assert_file_not_contains "unlisted pin -> the listed pin is not named" 'FALLBACK_MODEL =' "$TMP/preflight-pins-missing.out"
assert_file_contains "unlisted pin -> shows the Gemini models on offer" 'Gemini 9 New (High)' "$TMP/preflight-pins-missing.out"
assert_file_not_contains "unlisted pin -> never offers a non-Gemini model" 'Claude Z' "$TMP/preflight-pins-missing.out"

printf 'gemini-x-high\ngemini-y-high\n' > "$TMP/agy-listing.slugs"
run_pf_listing "$TMP/agy-listing.slugs" "$TMP/preflight-pins-slugs.out"
assert_file_contains "slug-only listing -> unknown, not missing" 'GEMINI_PIN_UNLISTED: unknown' "$TMP/preflight-pins-slugs.out"
assert_file_not_contains "slug-only listing -> no false warning" 'does not list the Gemini seat' "$TMP/preflight-pins-slugs.out"
run_pf_listing "$TMP/agy-listing.both" "$TMP/preflight-pins-fail.out" AGY_MODELS_FAIL=1; rc=$?
assert_exit "failed agy models -> preflight still succeeds" 0 "$rc"
assert_file_contains "failed agy models -> unknown" 'GEMINI_PIN_UNLISTED: unknown' "$TMP/preflight-pins-fail.out"

section "run_codex — human output mode records the model that actually bound (issue 47)"
# `-o` yields the final message in BOTH output modes, so --json is not needed for it
# (verified on codex-cli 0.153.4). Human mode is preferred because it prints the resolved
# config summary — the model that actually bound — to stderr, which --json replaces with a
# thread id. The mock reproduces that stderr shape, including a decoy "model:" line in the
# prompt echo AFTER the summary's closing rule.
rc_mockbin="$TMP/runcodexbin"; mkdir -p "$rc_mockbin"
cat > "$rc_mockbin/codex" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$CODEX_ARGS_LOG"
out=""; prev=""; for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
cat >/dev/null
{
  echo "Reading prompt from stdin..."
  echo "OpenAI Codex v0.153.4"
  echo "--------"
  echo "workdir: $PWD"
  echo "model: bound-model"
  echo "provider: openai"
  echo "reasoning effort: bound-effort"
  echo "session id: 0000"
  echo "--------"
  echo "user"
  echo "model: decoy-from-the-prompt"
} >&2
printf 'SEAT RESPONSE\n' > "$out"
printf 'human transcript on stdout\n'
EOF
chmod +x "$rc_mockbin/codex"
rc_home="$TMP/runcodexhome"; mkdir -p "$rc_home"
rc_model="$TMP/runcodex-model.txt"
rc_out="$(printf 'PROMPT\n' | CODEX_ARGS_LOG="$TMP/runcodex.args" CODEX_SEAT_MODEL_FILE="$rc_model" \
  HOME="$rc_home" PATH="$rc_mockbin:$PATH" "$SC/run_codex" 2>/dev/null)"; rc=$?
assert_exit "run_codex succeeds" 0 "$rc"
assert_eq "run_codex relays only the -o response" 'SEAT RESPONSE' "$rc_out"
assert_file_not_contains "run_codex no longer passes --json" '--json' "$TMP/runcodex.args"
assert_file_contains "run_codex still pins the profile" '--profile panel-review' "$TMP/runcodex.args"
assert_eq "records the bound model"  'model=bound-model'   "$(sed -n '1p' "$rc_model")"
assert_eq "records the bound effort" 'effort=bound-effort' "$(sed -n '2p' "$rc_model")"
# The record must come from the config summary, never from the echoed prompt below it.
assert_file_not_contains "decoy prompt line does not win" 'decoy-from-the-prompt' "$rc_model"
# No destination set -> no file, and the seat pass is unaffected.
rc_out2="$(printf 'PROMPT\n' | CODEX_ARGS_LOG="$TMP/runcodex.args2" HOME="$rc_home" \
  PATH="$rc_mockbin:$PATH" "$SC/run_codex" 2>/dev/null)"
assert_eq "no destination -> seat still works" 'SEAT RESPONSE' "$rc_out2"
assert_file_not_contains "add-dir launch marker emits no block" 'blockReadsOutsideWorkingDirectories blocks' "$TMP/preflight-add-dir.out"

rm "$pf_repo/.claude/settings.json"
cat > "$empty_claude_config/settings.json" <<'EOF'
{"permissions":{"blockReadsOutsideWorkingDirectories":true}}
EOF
(
  cd "$pf_repo" || exit 1
  CLAUDE_CODE_FORK_SUBAGENT=0 CLAUDE_CONFIG_DIR="$empty_claude_config" \
    CODEX_LOG="$TMP/codex6.log" PATH="$mockbin:$PATH" "$SC/preflight"
) > "$TMP/preflight-user-block.out" 2>&1; rc=$?
assert_exit "preflight blocks user outside-workdir setting" 1 "$rc"
assert_file_contains "preflight names blocking user file" "$empty_claude_config/settings.json" "$TMP/preflight-user-block.out"

section "structural prompt and protocol contracts"
"$SC/check_contracts" --root "$root" > "$TMP/contracts.out" 2>&1; rc=$?
assert_exit "structural instruction contracts pass" 0 "$rc"
assert_file_contains "contract checker reports success" 'instruction contracts: OK' "$TMP/contracts.out"

section "rendered seat contract — runtime parser accepts its examples"
"$SC/seat_contract.py" render round0 --panel-size 2 --check-command "$SC/check_draft findings" > "$TMP/contract.round0.txt"
"$SC/parse_block" --response round0 findings "$TMP/contract.round0.txt" x >/dev/null 2>&1
assert_exit "rendered round0 contract validates through parse_block" 0 "$?"
"$SC/seat_contract.py" render debate --panel-size 3 --check-command "$SC/check_draft stances" > "$TMP/contract.debate.txt"
"$SC/parse_block" --response debate stances "$TMP/contract.debate.txt" x >/dev/null 2>&1
assert_exit "rendered debate stance contract validates through parse_block" 0 "$?"
"$SC/parse_block" --response debate new_findings "$TMP/contract.debate.txt" x >/dev/null 2>&1
assert_exit "rendered debate new-findings contract validates through parse_block" 0 "$?"
# Unknown object fields are stripped during normalization even when source fields are shuffled.
printf '```stances\n%s\n```\n' '{"id":"i1","stance":"support","revision":{"bogus_field":"x","severity":"high"}}' > "$TMP/frag.shuffled.txt"
shuf_out="$("$SC/parse_block" stances "$TMP/frag.shuffled.txt" x 2>/dev/null)"
assert_exit "field-shuffled stance still validates (normalized)" 0 "$?"
case "$shuf_out" in *bogus_field*) bad "unknown revision subfield normalized away" "leaked: $shuf_out";; *) ok "unknown revision subfield normalized away";; esac
# A valid empty new-findings block distinguishes "nothing new" from a missing or malformed block.
printf '```new_findings\n[]\n```\n' > "$TMP/nf.empty-array.txt"
"$SC/parse_block" new_findings "$TMP/nf.empty-array.txt" x >/dev/null 2>&1
assert_exit "empty-array new_findings block is valid" 0 "$?"
[ -e "$root/prompts/repair.tmpl" ] && bad "repair.tmpl is retired" "still present" || ok "repair.tmpl is retired"

# --- Packaging: every plugin agent the protocol dispatches must be TRACKED in git ---
# Root cause it guards: agents/panel-review-cli-barrier.md once existed on disk but was never
# `git add`ed, so the tracked diff would ship without it and a fresh clone/install could not resolve
# the first `subagent_type: panel-review:panel-review-cli-barrier` dispatch. File presence alone
# would not catch that; only git tracking does.
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
assert_eq "dirty-at-snapshot preserves the original index entry" 'orig' "$(git -C "$rg" show :a.txt)"
assert_eq "dirty-at-snapshot remains unstaged after restore" ' M a.txt' "$(git -C "$rg" status --porcelain -- a.txt)"
# Restoring a dirty worktree must preserve a distinct staged version from the same snapshot.
gid3="$PREFIX-guard-staged"; rm -rf "/tmp/$gid3"
printf 'staged\n' > "$rg/a.txt"
git -C "$rg" add a.txt
printf 'worktree\n' > "$rg/a.txt"
"$SC/repo_guard" snapshot --id "$gid3" --workdir "$rg" >/dev/null 2>&1
printf 'tampered-staged\n' > "$rg/a.txt"
git -C "$rg" add a.txt
"$SC/repo_guard" verify --id "$gid3" --workdir "$rg" --restore > "$TMP/guard.staged" 2>/dev/null; assert_exit "staged and worktree drift is reported" 1 "$?"
assert_eq "restore keeps the snapshot's staged version" 'staged' "$(git -C "$rg" show :a.txt)"
assert_eq "restore keeps the snapshot's worktree version" 'worktree' "$(cat "$rg/a.txt")"
assert_eq "distinct staged and worktree versions remain distinct" 'MM a.txt' "$(git -C "$rg" status --porcelain -- a.txt)"
# Staging an already-dirty snapshot changes only index state; verify must still see and undo it.
git -C "$rg" reset -q HEAD -- a.txt
gid4="$PREFIX-guard-index-only"; rm -rf "/tmp/$gid4"
printf 'dirty-index-only\n' > "$rg/a.txt"
"$SC/repo_guard" snapshot --id "$gid4" --workdir "$rg" >/dev/null 2>&1
git -C "$rg" add a.txt
"$SC/repo_guard" verify --id "$gid4" --workdir "$rg" > "$TMP/guard.index-only" 2>/dev/null; assert_exit "index-only drift is reported" 1 "$?"
assert_file_contains "index-only drift names the path" 'index modified: a.txt' "$TMP/guard.index-only"
assert_eq "index-only drift reports no worktree change" '1' "$(wc -l < "$TMP/guard.index-only" | tr -d ' ')"
"$SC/repo_guard" verify --id "$gid4" --workdir "$rg" --restore >/dev/null 2>&1; assert_exit "index-only restore reports drift" 1 "$?"
assert_eq "index-only restore keeps the dirty worktree bytes" 'dirty-index-only' "$(cat "$rg/a.txt")"
assert_eq "index-only restore returns the original index entry" 'orig' "$(git -C "$rg" show :a.txt)"
assert_eq "index-only restore leaves the file unstaged" ' M a.txt' "$(git -C "$rg" status --porcelain -- a.txt)"
# A run created before index.entries existed can recover the saved stage-0 index from its stash parent.
gid5="$PREFIX-guard-legacy-index"; rm -rf "/tmp/$gid5"
"$SC/repo_guard" snapshot --id "$gid5" --workdir "$rg" >/dev/null 2>&1
rm -f "/tmp/$gid5/guard/index.entries"
git -C "$rg" add a.txt
"$SC/repo_guard" verify --id "$gid5" --workdir "$rg" --restore > "$TMP/guard.legacy-index" 2>/dev/null; assert_exit "legacy snapshot index drift is restored" 1 "$?"
assert_file_contains "legacy snapshot reports index-only drift" 'index modified: a.txt' "$TMP/guard.legacy-index"
assert_eq "legacy snapshot keeps dirty worktree bytes" 'dirty-index-only' "$(cat "$rg/a.txt")"
assert_eq "legacy snapshot restores the saved index entry" 'orig' "$(git -C "$rg" show :a.txt)"
# A legacy clean snapshot of a merge commit must use the merge tree, not its second parent's tree.
rg_merge="$TMP/guard-merge"; mkdir -p "$rg_merge"
(
  cd "$rg_merge" || exit 1
  git init -q -b main
  git config user.name test
  git config user.email test@example.invalid
  printf 'base\n' > base.txt
  git add base.txt
  git commit -qm base
  git checkout -qb topic
  printf 'topic\n' > topic.txt
  git add topic.txt
  git commit -qm topic
  git checkout -q main
  printf 'main\n' > main.txt
  git add main.txt
  git commit -qm main
  git merge --no-ff -qm 'merge topic' topic
)
gid8="$PREFIX-guard-legacy-merge"; rm -rf "/tmp/$gid8"
merge_index_before="$(git -C "$rg_merge" ls-files --stage)"
"$SC/repo_guard" snapshot --id "$gid8" --workdir "$rg_merge" >/dev/null 2>&1
rm -f "/tmp/$gid8/guard/index.entries"
"$SC/repo_guard" verify --id "$gid8" --workdir "$rg_merge" --restore > "$TMP/guard.legacy-merge" 2> "$TMP/guard.legacy-merge.err"; assert_exit "legacy clean merge snapshot reports no drift" 0 "$?"
assert_eq "legacy clean merge emits no drift" '' "$(cat "$TMP/guard.legacy-merge")"
assert_eq "legacy clean merge keeps all index entries" "$merge_index_before" "$(git -C "$rg_merge" ls-files --stage)"
assert_eq "legacy clean merge remains clean" '' "$(git -C "$rg_merge" status --porcelain)"
# A stash-like message without the stash parent structure is ambiguous and must not be guessed.
git -C "$rg_merge" commit --amend -qm 'WIP on main: ambiguous baseline'
gid9="$PREFIX-guard-legacy-ambiguous"; rm -rf "/tmp/$gid9"
"$SC/repo_guard" snapshot --id "$gid9" --workdir "$rg_merge" >/dev/null 2>&1
rm -f "/tmp/$gid9/guard/index.entries"
"$SC/repo_guard" verify --id "$gid9" --workdir "$rg_merge" > "$TMP/guard.legacy-ambiguous" 2> "$TMP/guard.legacy-ambiguous.err"; assert_exit "ambiguous legacy stash-like baseline fails closed" 2 "$?"
assert_file_contains "ambiguous legacy baseline explains the failure" 'ambiguous stash-shaped baseline' "$TMP/guard.legacy-ambiguous.err"
# A path first staged after the snapshot returns to untracked state; its worktree bytes are left alone.
gid6="$PREFIX-guard-new-index"; rm -rf "/tmp/$gid6"
"$SC/repo_guard" snapshot --id "$gid6" --workdir "$rg" >/dev/null 2>&1
printf 'new staged file\n' > "$rg/new.txt"
git -C "$rg" add new.txt
"$SC/repo_guard" verify --id "$gid6" --workdir "$rg" --restore > "$TMP/guard.new-index" 2>/dev/null; assert_exit "new index path is reported" 1 "$?"
assert_file_contains "new index path has an index drift entry" 'index added: new.txt' "$TMP/guard.new-index"
assert_eq "new staged path is removed from the index" '' "$(git -C "$rg" ls-files -- new.txt)"
assert_eq "new staged path remains outside the tracked-file boundary" 'new staged file' "$(cat "$rg/new.txt")"
# A failed stash snapshot during a merge conflict must stop the review instead of falling back to HEAD.
rg_conflict="$TMP/guard-conflict"; mkdir -p "$rg_conflict"
git -C "$rg_conflict" init -q -b main
git -C "$rg_conflict" config user.name test
git -C "$rg_conflict" config user.email test@example.invalid
printf 'base\n' > "$rg_conflict/a.txt"
git -C "$rg_conflict" add a.txt
git -C "$rg_conflict" commit -qm base
git -C "$rg_conflict" checkout -qb topic
printf 'topic\n' > "$rg_conflict/a.txt"
git -C "$rg_conflict" commit -qam topic
git -C "$rg_conflict" checkout -q main
printf 'main\n' > "$rg_conflict/a.txt"
git -C "$rg_conflict" commit -qam main
git -C "$rg_conflict" merge topic >/dev/null 2>&1 || true
gid7="$PREFIX-guard-conflict"; rm -rf "/tmp/$gid7"
"$SC/repo_guard" snapshot --id "$gid7" --workdir "$rg_conflict" > "$TMP/guard.conflict.out" 2> "$TMP/guard.conflict.err"; assert_exit "unmerged tracked state refuses an invalid baseline" 2 "$?"
assert_file_contains "snapshot explains why the unmerged state was refused" 'cannot snapshot dirty tracked state without a valid stash baseline' "$TMP/guard.conflict.err"
rm -rf "/tmp/$gid" "/tmp/$gid2" "/tmp/$gid3" "/tmp/$gid4" "/tmp/$gid5" "/tmp/$gid6" "/tmp/$gid7" "/tmp/$gid8" "/tmp/$gid9"

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
assert_eq "birth issue has only the current fields" 'category,claim,detail_contested,evidence_contra,evidence_pro,fully_vetted,id,location,peer_reviewed,rounds_debated,severity,state' "$(jq -r '.issues[0]|keys|sort|join(",")' "/tmp/$id/index.json")"
assert_eq "evaluated_by = the raisers (sorted unique)" '["claude","codex","gemini"]' "$(jq -c '.evaluated_by.i1' "/tmp/$id/index.json")"
assert_eq "i2 evaluated_by tracks 2 raisers"            '["claude","codex"]'         "$(jq -c '.evaluated_by.i2' "/tmp/$id/index.json")"
assert_eq "index installs cleanly (gate-status reads it)" '{"open":2,"low_only":false}' "$("$SC/index" gate-status "$id")"

section "birth_index — a filtered Round-0 co-raiser does not create birth consensus"
id="$PREFIX-birth-copy"; rm -rf "/tmp/$id"; mkdir -p "/tmp/$id"
fixture="$root/tests/fixtures/round0-independence/byte-identical.json"
assert_eq "duplicate fixture findings are byte-identical" 'true' "$(jq -r '.raw.codex == .raw.gemini' "$fixture")"
assert_eq "expected issue map keeps one independent raiser" '["codex"]' "$(jq -c '.issues[0].raised_by' "$fixture")"
jq -c '.issues' "$fixture" > "$TMP/birth.copy.specs.json"
"$SC/birth_index" --available "codex gemini" --configured "codex gemini" < "$TMP/birth.copy.specs.json" > "/tmp/$id/index.json" 2>/dev/null; assert_exit "birth_index byte-identical fixture -> 0" 0 "$?"
assert_eq "filtered duplicate co-raiser -> open with one origin" 'open|false|["codex"]' "$(jq -r '(.issues[]|select(.id=="i1")|"\(.state)|\(.peer_reviewed)") + "|" + (.evaluated_by.i1|tojson)' "/tmp/$id/index.json")"

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
stance='{"id":"i1","stance":"support"}'
case "$MOCK_MODE" in
  good)      printf '```%s\n%s\n```\n' "$MOCK_TAG" "$good" > "$out" ;;
  malformed)
    if [ "$MOCK_TAG" = new_findings ]; then
      printf '```stances\n%s\n```\n```new_findings\n%s\n```\n' "$stance" "$bad" > "$out"
    else
      printf '```%s\n%s\n```\n' "$MOCK_TAG" "$bad" > "$out"
    fi
    ;;
  noblock)   printf 'I will not answer.\n' > "$out" ;;
esac
EOF
chmod +x "$seat_mockbin/codex"
cat > "$seat_mockbin/agy" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
fb='```findings
{"claim":"g","location":"a.c:1","category":"correctness","severity":"high","points":[{"assertion":"x","location":"a.c:1"}]}
```'
case "${MOCK_MODE:-good}" in
  timeout_1128_prose)
    printf 'I traced the caller in a.c and noticed that when len == 0 the\n'
    printf '[agy] print timeout after 15m with turn in progress; returning partial output\n' >&2 ;;
  timeout_1128_with_block)
    printf '%s\nStill investigating second file before timeout...\n' "$fb"
    printf '[agy] print timeout after 15m with turn in progress; returning partial output\n' >&2 ;;
  *)
    printf '%s\n' "$fb" ;;
esac
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

section "run_seat — gemini routes through run_agy (and suppresses partial stdout when both models time out)"
st="$(timeout 30 env MOCK_MODE=good MOCK_TAG=findings PATH="$seat_mockbin:$PATH" HOME="$seat_home" \
  "$SC/run_seat" --seat gemini --tag findings --prompt "$TMP/seat.prompt" --raw "$TMP/seat.raw.gem" --parsed "$TMP/seat.parsed.gem" 2>/dev/null)"
assert_eq "gemini seat -> status 0"      '0' "$st"
assert_eq "gemini parsed _source=gemini" 'gemini' "$(jq -r '._source' "$TMP/seat.parsed.gem")"

printf 'stale\n' > "$TMP/seat.parsed.gem_to"
st="$(timeout 30 env MOCK_MODE=timeout_1128_prose MOCK_TAG=findings PATH="$seat_mockbin:$PATH" HOME="$seat_home" \
  "$SC/run_seat" --seat gemini --tag findings --prompt "$TMP/seat.prompt" --raw "$TMP/seat.raw.gem_to" --parsed "$TMP/seat.parsed.gem_to" 2>/dev/null)"
assert_eq "gemini both-model 1.1.28+ timeout (prose) -> status 4" '4' "$st"
assert_eq "gemini both-model timeout leaves --raw empty (no partial prose for salvage)" '' "$(cat "$TMP/seat.raw.gem_to")"
assert_eq "gemini both-model timeout clears --parsed" '' "$(cat "$TMP/seat.parsed.gem_to")"

printf 'stale\n' > "$TMP/seat.parsed.gem_tob"
st="$(timeout 30 env MOCK_MODE=timeout_1128_with_block MOCK_TAG=findings PATH="$seat_mockbin:$PATH" HOME="$seat_home" \
  "$SC/run_seat" --seat gemini --tag findings --prompt "$TMP/seat.prompt" --raw "$TMP/seat.raw.gem_tob" --parsed "$TMP/seat.parsed.gem_tob" 2>/dev/null)"
assert_eq "gemini both-model 1.1.28+ timeout (with partial block) -> status 4, never engaged" '4' "$st"
assert_eq "gemini both-model timeout with block leaves --raw empty" '' "$(cat "$TMP/seat.raw.gem_tob")"
assert_eq "gemini both-model timeout with block clears --parsed" '' "$(cat "$TMP/seat.parsed.gem_tob")"

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

section "await_seats — points run_codex at the run's model record (issue 47)"
# The barrier is the only dispatcher that knows the run id, so it is where the Codex
# model record gets its destination. Without this wiring `round verdict-input` has no
# `seat_models` and the verdict can only repeat the pin it asked for.
rec_mockbin="$TMP/awaitrecbin"; mkdir -p "$rec_mockbin"
cat > "$rec_mockbin/codex" <<'EOF'
#!/usr/bin/env bash
out=""; prev=""; for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
cat >/dev/null
printf 'OpenAI Codex v0.153.4\n--------\nmodel: barrier-model\nreasoning effort: barrier-effort\n--------\nuser\n' >&2
printf '```findings\n%s\n```\n' '{"claim":"c","location":"a.c:1","category":"correctness","severity":"high","points":[{"assertion":"x","location":"a.c:1"}]}' > "$out"
EOF
chmod +x "$rec_mockbin/codex"
rec_id="$PREFIX-modelrec"
PATH="$rec_mockbin:$PATH" HOME="$TMP/awaitrechome" \
  "$SC/await_seats" --id "$rec_id" --tag findings --prompt "$TMP/await.prompt" --seat-timeout 0 \
    --seat codex --raw "$TMP/await.raw/c.rec.txt" --parsed "$TMP/await.f.codex.rec.json" \
    --status "$TMP/await.st.codex.rec" --done "$TMP/await.done.rec" >/dev/null 2>&1
assert_exit "barrier exits 0 with the model record wired" 0 "$?"
assert_eq "codex still engages" '0' "$(cat "$TMP/await.st.codex.rec")"
assert_file_contains "barrier records the bound model under the run"  'model=barrier-model'   "/tmp/$rec_id/codex-model.txt"
assert_file_contains "barrier records the bound effort under the run" 'effort=barrier-effort' "/tmp/$rec_id/codex-model.txt"

cat > "$rec_mockbin/agy" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = --help ]; then echo "  --log-file   Override CLI log file path" >&2; exit 0; fi
log=""; prev=""; for a in "$@"; do [ "$prev" = --log-file ] && log="$a"; prev="$a"; done
cat >/dev/null
[ -n "$log" ] && printf 'Propagating selected model override to backend: label="Gemini Barrier (High)"\n' >> "$log"
printf '```findings\n%s\n```\n' '{"claim":"g","location":"a.c:1","category":"correctness","severity":"high","points":[{"assertion":"x","location":"a.c:1"}]}'
EOF
chmod +x "$rec_mockbin/agy"
PATH="$rec_mockbin:$PATH" HOME="$TMP/awaitrechome" \
  "$SC/await_seats" --id "$rec_id" --tag findings --prompt "$TMP/await.prompt" --seat-timeout 0 \
    --seat gemini --raw "$TMP/await.raw/g.rec.txt" --parsed "$TMP/await.f.gemini.rec.json" \
    --status "$TMP/await.st.gemini.rec" --done "$TMP/await.done.rec.g" >/dev/null 2>&1
assert_exit "barrier exits 0 with the Gemini model record wired" 0 "$?"
assert_eq "gemini still engages" '0' "$(cat "$TMP/await.st.gemini.rec")"
assert_file_contains "barrier records the Gemini bound label under the run" 'model=Gemini Barrier (High)' "/tmp/$rec_id/agy-model.txt"

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
  good)
    printf '%s\n' "$fb" ;;
  quote_timeout_mid_content)
    printf 'Note: run_agy treats `Error: timed out waiting for response` and `[agy] print timeout after 15m with turn in progress; returning partial output` as timeout markers.\n\n%s\n' "$fb" ;;
  timeout_then_good)
    # agy <=1.1.18: prints error as the last line of stdout and exits 0.
    if [ "$n" -eq 1 ]; then printf 'Partial analysis...\nError: timed out waiting for response\n'; else printf '%s\n' "$fb"; fi ;;
  always_timeout)
    printf 'Error: timed out waiting for response\n' ;;
  timeout_1120_then_good)
    # agy 1.1.20: prints `Error: timeout waiting for response` on stderr, 0 bytes on stdout, exits 1.
    if [ "$n" -eq 1 ]; then printf 'Error: timeout waiting for response\n' >&2; exit 1; else printf '%s\n' "$fb"; fi ;;
  always_timeout_1120)
    printf 'Error: timeout waiting for response\n' >&2; exit 1 ;;
  timeout_1120_exit0_then_good)
    # Wording-tolerant stderr detector check even if exit code is 0.
    if [ "$n" -eq 1 ]; then printf 'Error: timeout waiting for response\n' >&2; else printf '%s\n' "$fb"; fi ;;
  timeout_1128_then_good)
    # agy 1.1.28+ (measured on 1.4.3): partial stdout, warning on stderr, exits 0.
    if [ "$n" -eq 1 ]; then
      printf 'I traced the caller in a.c and noticed that when len == 0 the'
      printf '[agy] print timeout after 15m with turn in progress; returning partial output\n' >&2
    else
      printf '%s\n' "$fb"
    fi ;;
  always_timeout_1128)
    printf 'TRUNCATED_PARTIAL_STDOUT\n'
    printf '[agy] print timeout after 15m with turn in progress; returning partial output\n' >&2 ;;
  truncated_1128_then_good)
    # agy 1.1.28+: truncation note on stderr after partial output.
    if [ "$n" -eq 1 ]; then
      printf 'Partial output before stream drop\n'
      printf 'error: stream reset (response may be truncated)\n' >&2
    else
      printf '%s\n' "$fb"
    fi ;;
  cascade_timeout_then_good)
    # agy 1.1.20+ / 1.4.3 pre-cascade timeout on stderr.
    if [ "$n" -eq 1 ]; then
      printf 'error: timeout waiting for cascade to start running\n' >&2
      exit 1
    else
      printf '%s\n' "$fb"
    fi ;;
esac
exit 0
EOF
chmod +x "$agy_mockbin/agy"
printf 'PLEASE REVIEW THIS DIFF SENTINEL-7Q\n' > "$TMP/agy.in"
run_agy_t() { # $1=mode $2=tag ; prompt on stdin (run_agy with no args)
  AGY_MODE="$1" AGY_ARGV="$TMP/agy.argv.$2" AGY_STDIN="$TMP/agy.stdin.$2" AGY_COUNT="$TMP/agy.count.$2" \
    PATH="$agy_mockbin:$PATH" timeout 30 "$SC/run_agy" < "$TMP/agy.in" > "$TMP/agy.out.$2" 2>"$TMP/agy.err.$2"
}

# The pins themselves are read out of run_agy rather than duplicated here, so a model
# bump does not need a test edit. Their FORM (display label, never a slug; fallback
# distinct from primary) is owned by scripts/check_contracts' agy-model-pin-form
# invariant, covered in tests/python/test_contract_consistency.py; what the tests
# below fix is that the pinned string reaches agy intact.
agy_pin() { sed -n "s/^$1=\"\(.*\)\"$/\1/p" "$SC/run_agy"; }
PRIMARY_PIN="$(agy_pin PRIMARY_MODEL)"; FALLBACK_PIN="$(agy_pin FALLBACK_MODEL)"
# The value agy received for --model on call $2 of the recorded argv file $1.
# Reads the token AFTER --model, which is exactly what a desynced parse (e.g. a
# bare --print swallowing the flag) would get wrong.
agy_model_arg() { awk -v want="$2" 'BEGIN{c=1} $0=="<<<CALL>>>"{c++; prev=""; next} {if (c==want && prev=="--model") {print; exit} prev=$0}' "$1"; }

section "run_agy — invocation binds flags (no bare --print, prompt via stdin)"
# Both pins must be readable; every assertion below compares against them, and the
# form check that owns them lives in check_contracts (see the note above).
if [ -n "$PRIMARY_PIN" ] && [ -n "$FALLBACK_PIN" ]; then ok "both model pins readable from run_agy"; else bad "model pin not found in run_agy" "primary=[$PRIMARY_PIN] fallback=[$FALLBACK_PIN]"; fi
run_agy_t good p1; assert_exit "primary good -> exit 0" 0 "$?"
if grep -Fxq -- '--print' "$TMP/agy.argv.p1"; then bad "run_agy must NOT pass a bare --print (it swallows --model)"; else ok "no bare --print token"; fi
assert_file_contains "passes --print-timeout=15m (=form, bound budget)" '--print-timeout=15m' "$TMP/agy.argv.p1"
assert_file_contains "passes --dangerously-skip-permissions"            '--dangerously-skip-permissions' "$TMP/agy.argv.p1"
# One argv token, immediately after --model, byte-identical to the pin: the label
# contains spaces, so a quoting slip would split it and agy would bind something
# else without erroring.
assert_eq "primary --model receives the exact primary pin" "$PRIMARY_PIN" "$(agy_model_arg "$TMP/agy.argv.p1" 1)"
assert_file_contains "prompt reaches agy via stdin" 'SENTINEL-7Q' "$TMP/agy.stdin.p1"
assert_eq "primary success = single dispatch" '1' "$(cat "$TMP/agy.count.p1")"
assert_file_contains "primary output carries the findings block" '```findings' "$TMP/agy.out.p1"

run_agy_t quote_timeout_mid_content p1q; assert_exit "quoting timeout phrase mid-stdout -> exit 0" 0 "$?"
assert_eq "mid-stdout quote does not trigger fallback" '1' "$(cat "$TMP/agy.count.p1q")"
assert_file_contains "mid-stdout quote preserves findings block" '```findings' "$TMP/agy.out.p1q"

section "run_agy — print-timeout (<=1.1.18, 1.1.20, 1.1.28+/1.4.3) triggers the fallback model"
# 1) agy <=1.1.18: exit 0 + `Error: timed out waiting for response` at end of stdout
run_agy_t timeout_then_good p2; assert_exit "<=1.1.18 timeout: fallback recovers -> exit 0" 0 "$?"
assert_eq "<=1.1.18 timeout + fallback = two dispatches" '2' "$(cat "$TMP/agy.count.p2")"
assert_eq "second dispatch --model receives the exact fallback pin" "$FALLBACK_PIN" "$(agy_model_arg "$TMP/agy.argv.p2" 2)"
assert_file_contains "fallback output carries the findings block" '```findings' "$TMP/agy.out.p2"
assert_file_not_contains "primary's partial stdout is not leaked on fallback success" 'Partial analysis' "$TMP/agy.out.p2"
assert_file_contains "logs the fallback switch" 'retrying with fallback' "$TMP/agy.err.p2"

# 2) agy 1.1.20: exit 1 + `Error: timeout waiting for response` on stderr, empty stdout
run_agy_t timeout_1120_then_good p2_1120; assert_exit "1.1.20 timeout (exit 1 + stderr): fallback recovers -> exit 0" 0 "$?"
assert_eq "1.1.20 timeout + fallback = two dispatches" '2' "$(cat "$TMP/agy.count.p2_1120")"
assert_eq "1.1.20 second dispatch --model receives the exact fallback pin" "$FALLBACK_PIN" "$(agy_model_arg "$TMP/agy.argv.p2_1120" 2)"
assert_file_contains "1.1.20 stderr timeout line forwarded verbatim" 'Error: timeout waiting for response' "$TMP/agy.err.p2_1120"
assert_file_contains "1.1.20 fallback output carries the findings block" '```findings' "$TMP/agy.out.p2_1120"

run_agy_t timeout_1120_exit0_then_good p2_1120_e0; assert_exit "1.1.20 stderr wording caught even on exit 0 -> fallback recovers" 0 "$?"
assert_eq "1.1.20 stderr wording on exit 0 triggers fallback" '2' "$(cat "$TMP/agy.count.p2_1120_e0")"

run_agy_t cascade_timeout_then_good p2_casc; assert_exit "pre-cascade timeout on stderr: fallback recovers -> exit 0" 0 "$?"
assert_eq "pre-cascade timeout + fallback = two dispatches" '2' "$(cat "$TMP/agy.count.p2_casc")"
assert_file_contains "pre-cascade timeout forwarded on stderr" 'error: timeout waiting for cascade to start running' "$TMP/agy.err.p2_casc"

# 3) agy 1.1.28+ (measured on 1.4.3): exit 0 + partial stdout + `[agy] print timeout ...` on stderr
run_agy_t timeout_1128_then_good p2_1128; assert_exit "1.1.28+/1.4.3 timeout (exit 0 + partial stdout + stderr warning): fallback recovers -> exit 0" 0 "$?"
assert_eq "1.1.28+ timeout + fallback = two dispatches" '2' "$(cat "$TMP/agy.count.p2_1128")"
assert_eq "1.1.28+ second dispatch --model receives the exact fallback pin" "$FALLBACK_PIN" "$(agy_model_arg "$TMP/agy.argv.p2_1128" 2)"
assert_file_contains "1.1.28+ stderr timeout warning forwarded verbatim" '[agy] print timeout after 15m with turn in progress; returning partial output' "$TMP/agy.err.p2_1128"
assert_file_not_contains "1.1.28+ primary's partial stdout is discarded when fallback succeeds" 'I traced the caller' "$TMP/agy.out.p2_1128"
assert_file_contains "1.1.28+ fallback output carries the findings block" '```findings' "$TMP/agy.out.p2_1128"

# 4) agy 1.1.28+ truncation note on stderr (`(response may be truncated)`)
run_agy_t truncated_1128_then_good p2_trunc; assert_exit "1.1.28+ truncation note on stderr triggers fallback -> exit 0" 0 "$?"
assert_eq "1.1.28+ truncation note + fallback = two dispatches" '2' "$(cat "$TMP/agy.count.p2_trunc")"
assert_file_contains "1.1.28+ truncation note forwarded on stderr" '(response may be truncated)' "$TMP/agy.err.p2_trunc"

section "run_agy — both models time out -> seat fails (exit 1) across all shapes"
run_agy_t always_timeout p3; assert_exit "<=1.1.18 both fail -> exit 1" 1 "$?"
assert_eq "<=1.1.18 both attempts dispatched" '2' "$(cat "$TMP/agy.count.p3")"
assert_eq "<=1.1.18 both fail -> stdout suppressed" '' "$(cat "$TMP/agy.out.p3")"
assert_file_contains "<=1.1.18 reports both-model failure" 'both primary' "$TMP/agy.err.p3"

run_agy_t always_timeout_1120 p3_1120; assert_exit "1.1.20 both fail -> exit 1" 1 "$?"
assert_eq "1.1.20 both attempts dispatched" '2' "$(cat "$TMP/agy.count.p3_1120")"
assert_eq "1.1.20 both fail -> stdout empty" '' "$(cat "$TMP/agy.out.p3_1120")"
assert_file_contains "1.1.20 stderr timeout forwarded" 'Error: timeout waiting for response' "$TMP/agy.err.p3_1120"
assert_file_contains "1.1.20 reports both-model failure" 'both primary' "$TMP/agy.err.p3_1120"

run_agy_t always_timeout_1128 p3_1128; assert_exit "1.1.28+ both fail -> exit 1" 1 "$?"
assert_eq "1.1.28+ both attempts dispatched" '2' "$(cat "$TMP/agy.count.p3_1128")"
assert_eq "1.1.28+ both fail -> fallback partial stdout suppressed" '' "$(cat "$TMP/agy.out.p3_1128")"
assert_file_contains "1.1.28+ stderr timeout warning forwarded" '[agy] print timeout after 15m with turn in progress; returning partial output' "$TMP/agy.err.p3_1128"
assert_file_contains "1.1.28+ reports both-model failure" 'both primary' "$TMP/agy.err.p3_1128"

section "run_agy — records the label agy logged as bound (issue 63)"
# With AGY_SEAT_MODEL_FILE set, run_agy probes `agy --help` (agy prints it to stderr) for
# --log-file, gives each attempt its own log, and after a SUCCESSFUL attempt writes the
# propagated label. The mock fails its first call when asked, and then logs the
# settings.json default exactly as agy 1.4.2 does for a rejected label: that line must
# not reach the record.
agyrec_bin="$TMP/agyrecbin"; mkdir -p "$agyrec_bin"
cat > "$agyrec_bin/agy" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = --help ]; then
  echo "Usage of agy:" >&2
  [ "${AGY_HAS_LOG_FILE:-1}" = 1 ] && echo "  --log-file                      Override CLI log file path" >&2
  exit 0
fi
printf '%s\n' "$*" >> "$AGY_ARGV"
cat >/dev/null
n=0; [ -f "$AGY_COUNT" ] && n="$(cat "$AGY_COUNT")"; n=$((n+1)); echo "$n" > "$AGY_COUNT"
model=""; log=""; prev=""
for a in "$@"; do
  [ "$prev" = --model ] && model="$a"; [ "$prev" = --log-file ] && log="$a"; prev="$a"
done
if [ "${AGY_FAIL_FIRST:-0}" = 1 ] && { [ "$n" -eq 1 ] || [ "${AGY_FAIL_ALL:-0}" = 1 ]; }; then
  [ -n "$log" ] && printf 'I1020 model_config_manager.go:340] Propagating selected model override to backend: label="Settings Default (High)"\n' >> "$log"
  echo "error: invalid model selection" >&2
  exit 1
fi
if [ "${AGY_TIMEOUT_1128_FIRST:-0}" = 1 ] && [ "$n" -eq 1 ]; then
  [ -n "$log" ] && printf 'I1020 model_config_manager.go:340] Propagating selected model override to backend: label="%s"\n' "$model" >> "$log"
  printf 'Partial primary output...\n'
  printf '[agy] print timeout after 15m with turn in progress; returning partial output\n' >&2
  exit 0
fi
[ -n "$log" ] && printf 'I1020 model_config_manager.go:340] Propagating selected model override to backend: label="%s"\n' "$model" "$model" >> "$log"
printf 'OK\n'
EOF
chmod +x "$agyrec_bin/agy"
run_agy_rec() { # $1 = tag, rest = extra env
  local tag="$1"; shift
  env AGY_ARGV="$TMP/agyrec.argv.$tag" AGY_COUNT="$TMP/agyrec.count.$tag" \
    AGY_SEAT_MODEL_FILE="$TMP/agyrec.$tag/agy-model.txt" PATH="$agyrec_bin:$PATH" "$@" \
    timeout 30 "$SC/run_agy" < "$TMP/agy.in" > "$TMP/agyrec.out.$tag" 2>/dev/null
}
run_agy_rec r1; assert_exit "recording run succeeds" 0 "$?"
assert_file_contains "the attempt logs beside the record" "--log-file $TMP/agyrec.r1/agy-logs/" "$TMP/agyrec.argv.r1"
assert_eq "the attempt's log is kept for diagnostics" '1' "$(find "$TMP/agyrec.r1/agy-logs" -type f | wc -l | tr -d ' ')"
assert_eq "primary success -> records the bound label" "model=$PRIMARY_PIN" "$(sed -n 1p "$TMP/agyrec.r1/agy-model.txt")"
assert_eq "primary success -> records what was requested" "requested=$PRIMARY_PIN" "$(sed -n 2p "$TMP/agyrec.r1/agy-model.txt")"
run_agy_rec r2 AGY_FAIL_FIRST=1; assert_exit "fallback recovers while recording" 0 "$?"
assert_eq "fallback success -> records the fallback label" "model=$FALLBACK_PIN" "$(sed -n 1p "$TMP/agyrec.r2/agy-model.txt")"
assert_file_not_contains "a failed attempt's propagation line is not recorded" 'Settings Default' "$TMP/agyrec.r2/agy-model.txt"
assert_eq "each attempt gets its own log" '2' "$(find "$TMP/agyrec.r2/agy-logs" -type f | wc -l | tr -d ' ')"
run_agy_rec r2_to AGY_TIMEOUT_1128_FIRST=1; assert_exit "1.1.28+ exit-0 timeout on primary -> fallback recovers while recording" 0 "$?"
assert_eq "1.1.28+ primary timeout -> records the fallback label, not the timed-out primary" "model=$FALLBACK_PIN" "$(sed -n 1p "$TMP/agyrec.r2_to/agy-model.txt")"
# Both attempts fail: neither failed attempt's log (which names the settings.json
# default) may create a record.
run_agy_rec r4 AGY_FAIL_FIRST=1 AGY_FAIL_ALL=1; assert_exit "both attempts fail while recording -> exit 1" 1 "$?"
if [ -e "$TMP/agyrec.r4/agy-model.txt" ]; then bad "failed attempts never create a record"; else ok "failed attempts never create a record"; fi
assert_eq "both failed attempts still kept their logs" '2' "$(find "$TMP/agyrec.r4/agy-logs" -type f | wc -l | tr -d ' ')"
# A record from an earlier pass must not survive a successful pass that recorded nothing,
# or the verdict would name an older pass's model.
mkdir -p "$TMP/agyrec.r3"; printf 'model=Stale Earlier Pass\nrequested=x\n' > "$TMP/agyrec.r3/agy-model.txt"
run_agy_rec r3 AGY_HAS_LOG_FILE=0; assert_exit "agy without --log-file still runs" 0 "$?"
assert_file_not_contains "agy without --log-file -> flag not passed" '--log-file' "$TMP/agyrec.argv.r3"
if [ -e "$TMP/agyrec.r3/agy-model.txt" ]; then bad "agy without --log-file -> an older record is removed"; else ok "agy without --log-file -> an older record is removed"; fi
assert_file_contains "agy without --log-file -> output still relayed" 'OK' "$TMP/agyrec.out.r3"

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

section "init_run — review profile validation and snapshot"
profile_repo="$TMP/profile-repo"; mkdir -p "$profile_repo"; git -C "$profile_repo" init -q
printf '# Domain profile\n\nProbe the domain invariant.\n' > "$TMP/domain-profile.md"
profile_hash="$("$SC/diff_hash" < "$TMP/domain-profile.md")"
profile_size="$(wc -c < "$TMP/domain-profile.md" | tr -d ' ')"
id="$("$SC/init_run" --workdir "$profile_repo" --scope 'question=test' --issue-rounds 2 --max-rounds 4 \
  --diff-hash "$(printf '' | "$SC/diff_hash")" --instructions '' --review-profile "$TMP/domain-profile.md")"
assert_eq "manifest emits the documented run metadata" 'created,diff_hash,divergence_snapshot,id,instructions,limits,review_profile,scope,workdir' "$(jq -r 'keys|sort|join(",")' "/tmp/$id/manifest.json")"
assert_eq "external profile bytes are snapshotted exactly" "$profile_hash" "$("$SC/diff_hash" < "/tmp/$id/review-profile.md")"
assert_eq "external profile path is resolved" "$(realpath "$TMP/domain-profile.md")" "$(jq -r '.review_profile.source_path' "/tmp/$id/manifest.json")"
assert_eq "external profile hash is recorded" "$profile_hash" "$(jq -r '.review_profile.sha256' "/tmp/$id/manifest.json")"
assert_eq "external profile size is recorded" "$profile_size" "$(jq -r '.review_profile.size' "/tmp/$id/manifest.json")"
inspection="$("$SC/inspect_run" --id "$id" --workdir "$profile_repo")"
assert_eq "status metadata carries the profile path" "$(realpath "$TMP/domain-profile.md")" "$(jq -r '.review_profile.source_path' <<<"$inspection")"
assert_eq "status metadata carries the profile hash" "$profile_hash" "$(jq -r '.review_profile.sha256' <<<"$inspection")"
PANEL_REVIEW_KEEP_TMP=false "$SC/cleanup" --id "$id" --workdir "$profile_repo"

default_repo="$TMP/default-profile-repo"; mkdir -p "$default_repo"; git -C "$default_repo" init -q
id="$("$SC/init_run" --workdir "$default_repo" --scope 'question=test' --issue-rounds 2 --max-rounds 4 \
  --diff-hash "$(printf '' | "$SC/diff_hash")" --instructions '')"
assert_eq "built-in profile is snapshotted exactly" "$("$SC/diff_hash" < "$root/profiles/default.md")" "$("$SC/diff_hash" < "/tmp/$id/review-profile.md")"
assert_eq "built-in profile source is recorded" "$(realpath "$root/profiles/default.md")" "$(jq -r '.review_profile.source_path' "/tmp/$id/manifest.json")"
PANEL_REVIEW_KEEP_TMP=false "$SC/cleanup" --id "$id" --workdir "$default_repo"

for invalid in missing empty binary large directory; do
  invalid_repo="$TMP/invalid-$invalid"; mkdir -p "$invalid_repo"; git -C "$invalid_repo" init -q
  case "$invalid" in
    missing) invalid_path="$TMP/no-such-profile.md";;
    empty) invalid_path="$TMP/empty-profile.md"; : > "$invalid_path";;
    binary) invalid_path="$TMP/binary-profile.md"; printf '\377' > "$invalid_path";;
    large) invalid_path="$TMP/large-profile.md"; dd if=/dev/zero of="$invalid_path" bs=65537 count=1 status=none;;
    directory) invalid_path="$TMP";;
  esac
  "$SC/init_run" --workdir "$invalid_repo" --scope 'question=test' --issue-rounds 2 --max-rounds 4 \
    --diff-hash "$(printf '' | "$SC/diff_hash")" --instructions '' --review-profile "$invalid_path" >/dev/null 2>&1
  assert_exit "$invalid review profile fails" 1 "$?"
  markers="$(find "$invalid_repo/.panel-review" -name .panel-run -print 2>/dev/null | wc -l | tr -d ' ')"
  assert_eq "$invalid review profile creates no marker" 0 "$markers"
done
duplicate_repo="$TMP/duplicate-profile"; mkdir -p "$duplicate_repo"; git -C "$duplicate_repo" init -q
"$SC/init_run" --workdir "$duplicate_repo" --scope 'question=test' --issue-rounds 2 --max-rounds 4 \
  --diff-hash "$(printf '' | "$SC/diff_hash")" --review-profile "$TMP/domain-profile.md" \
  --review-profile "$TMP/domain-profile.md" >/dev/null 2>"$TMP/duplicate-profile.err"
assert_exit "duplicate review profile flag fails as usage" 2 "$?"
assert_file_contains "duplicate review profile error is clear" 'duplicate --review-profile' "$TMP/duplicate-profile.err"

section "uncommitted divergence diagnostics and hash-based resume"
divergence_repo="$TMP/divergence-repo"; mkdir -p "$divergence_repo"; git -C "$divergence_repo" init -q
git -C "$divergence_repo" config user.name test
git -C "$divergence_repo" config user.email test@example.invalid
printf 'base\n' > "$divergence_repo/tracked.txt"
git -C "$divergence_repo" add tracked.txt
git -C "$divergence_repo" commit -qm initial
printf 'reviewed change\n' >> "$divergence_repo/tracked.txt"
resolve_uncommitted_hash() {
  (cd "$divergence_repo" && "$SC/resolve_diff" uncommitted) > "$TMP/divergence.diff" || return 1
  "$SC/diff_hash" < "$TMP/divergence.diff"
}
snapshot_hash="$(resolve_uncommitted_hash)"
cp "$TMP/divergence.diff" "$TMP/snapshot.diff"
id="$("$SC/init_run" --workdir "$divergence_repo" --scope uncommitted --issue-rounds 2 --max-rounds 4 \
  --diff-hash "$snapshot_hash" --instructions '')"
printf 'seat scratch\n' > "$divergence_repo/seat_scratch.py"
current_hash="$(resolve_uncommitted_hash)"
inspection="$("$SC/inspect_run" --id "$id" --workdir "$divergence_repo")"
assert_eq "status marks an added untracked file as diverged" 'diverged' "$(jq -r '.state' <<<"$inspection")"
assert_eq "status names the new untracked file" 'seat_scratch.py' "$(jq -r '.divergence.new_untracked_paths[0]' <<<"$inspection")"
assert_eq "status distinguishes unchanged tracked content" 'false' "$(jq -r '.divergence.tracked_content_changed' <<<"$inspection")"
resume_output="$("$SC/resume_check" --workdir "$divergence_repo" --scope uncommitted --diff-hash "$current_hash")"
assert_eq "resume check keeps its verdict first" "diverged $id" "$(sed -n '1p' <<<"$resume_output")"
resume_details="$(sed -n '2s/^divergence //p' <<<"$resume_output")"
assert_eq "resume check names the new untracked file" 'seat_scratch.py' "$(jq -r '.new_untracked_paths[0]' <<<"$resume_details")"
cp "$TMP/snapshot.diff" "/tmp/$id/diff.txt"
jq 'del(.divergence_snapshot)' "/tmp/$id/manifest.json" > "$TMP/legacy-manifest.json"
assert_exit "legacy manifest rewrite succeeds" 0 "$?"
cp "$TMP/legacy-manifest.json" "/tmp/$id/manifest.json"
legacy_inspection="$("$SC/inspect_run" --id "$id" --workdir "$divergence_repo")"
assert_eq "older run infers paths from its saved diff" 'saved-diff-paths' "$(jq -r '.divergence.source' <<<"$legacy_inspection")"
assert_eq "older run still names a new untracked file" 'seat_scratch.py' "$(jq -r '.divergence.new_untracked_paths[0]' <<<"$legacy_inspection")"
assert_eq "older run reports the tracked-change status as unknown" 'null' "$(jq -r '.divergence.tracked_content_changed' <<<"$legacy_inspection")"
rm -f "$divergence_repo/seat_scratch.py"
restored_hash="$(resolve_uncommitted_hash)"
assert_eq "removing the stray file restores the original diff hash" "$snapshot_hash" "$restored_hash"
resume_output="$("$SC/resume_check" --workdir "$divergence_repo" --scope uncommitted --diff-hash "$restored_hash")"
assert_eq "the unchanged run can resume after hash restoration" "resume $id" "$resume_output"
PANEL_REVIEW_KEEP_TMP=false "$SC/cleanup" --id "$id" --workdir "$divergence_repo"

section "resume_check / inspect_run — malformed index is stale without backup recovery"
corrupt_repo="$TMP/corrupt-index-repo"; mkdir -p "$corrupt_repo"; git -C "$corrupt_repo" init -q
id="$("$SC/init_run" --workdir "$corrupt_repo" --scope 'question=test' --issue-rounds 2 --max-rounds 4 \
  --diff-hash "$(printf '' | "$SC/diff_hash")" --instructions '')"
# A parseable backup ensures the former recovery branch would have rewritten the live index.
cp "/tmp/$id/index.json" "/tmp/$id/index.json.bak"
backup_before="$(cat "/tmp/$id/index.json.bak")"
printf '{malformed index\n' > "/tmp/$id/index.json"
corrupt_before="$(cat "/tmp/$id/index.json")"
inspection="$("$SC/inspect_run" --id "$id" --workdir "$corrupt_repo")"
assert_eq "status marks a malformed index stale" 'stale' "$(jq -r '.state' <<<"$inspection")"
assert_eq "status leaves the malformed index untouched" "$corrupt_before" "$(cat "/tmp/$id/index.json")"
assert_eq "status leaves the valid backup untouched" "$backup_before" "$(cat "/tmp/$id/index.json.bak")"
resume_output="$("$SC/resume_check" --workdir "$corrupt_repo" --scope 'question=test' \
  --diff-hash "$(printf '' | "$SC/diff_hash")")"
assert_eq "resume check marks a malformed index stale" "stale $id" "$resume_output"
assert_eq "resume check leaves the malformed index untouched" "$corrupt_before" "$(cat "/tmp/$id/index.json")"
assert_eq "resume check leaves the valid backup untouched" "$backup_before" "$(cat "/tmp/$id/index.json.bak")"
PANEL_REVIEW_KEEP_TMP=false "$SC/cleanup" --id "$id" --workdir "$corrupt_repo"

section "large uncommitted divergence snapshots and reports"
large_divergence_repo="$TMP/large-divergence-repo"; mkdir -p "$large_divergence_repo"; git -C "$large_divergence_repo" init -q
git -C "$large_divergence_repo" config user.name test
git -C "$large_divergence_repo" config user.email test@example.invalid
printf 'base\n' > "$large_divergence_repo/tracked.txt"
git -C "$large_divergence_repo" add tracked.txt
git -C "$large_divergence_repo" commit -qm initial
# Long but valid Linux paths make the JSON exceed the per-argument limit with fewer git subprocesses.
segment="$(printf '%230s' '' | tr ' ' x)"
deep_path=""
for ((i=0; i<15; i++)); do
  deep_path="${deep_path:+$deep_path/}$segment"
done
deep_dir="$large_divergence_repo/$deep_path"
mkdir -p "$deep_dir"
for ((i=0; i<45; i++)); do
  printf -v name 'baseline-%04d-%0100d.txt' "$i" "$i"
  printf 'baseline\n' > "$deep_dir/$name"
done
large_id="$("$SC/init_run" --workdir "$large_divergence_repo" --scope uncommitted --issue-rounds 2 --max-rounds 4 \
  --diff-hash "$(printf '0%.0s' {1..64})" --instructions '')"
assert_exit "large uncommitted snapshot initializes" 0 "$?"
assert_eq "large snapshot retains all initial paths" '45' "$(jq -r '.divergence_snapshot.untracked_paths_b64|length' "/tmp/$large_id/manifest.json")"
if [ "$(wc -c < "/tmp/$large_id/manifest.json")" -gt 131072 ]; then ok "large snapshot exceeds Linux's per-argument limit"; else bad "large snapshot exceeds Linux's per-argument limit"; fi
for ((i=0; i<45; i++)); do
  printf -v name 'new-path-%04d-%0100d.txt' "$i" "$i"
  printf 'new path\n' > "$deep_dir/$name"
done
"$SC/inspect_run" --id "$large_id" --workdir "$large_divergence_repo" > "$TMP/large-divergence-inspection.json"
assert_exit "large divergence inspection succeeds" 0 "$?"
assert_eq "large report names every new path" '45' "$(jq -r '.divergence.new_untracked_paths|length' "$TMP/large-divergence-inspection.json")"
if [ "$(wc -c < "$TMP/large-divergence-inspection.json")" -gt 131072 ]; then ok "large report exceeds Linux's per-argument limit"; else bad "large report exceeds Linux's per-argument limit"; fi
assert_eq "large report keeps the diverged state" 'diverged' "$(jq -r '.state' "$TMP/large-divergence-inspection.json")"
PANEL_REVIEW_KEEP_TMP=false "$SC/cleanup" --id "$large_id" --workdir "$large_divergence_repo"

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
invalid_id="$PREFIX-invalid name"; mkdir -p "$keeprepo/.panel-review/$invalid_id" "/tmp/$invalid_id"
printf '%s\n' "$invalid_id" > "$keeprepo/.panel-review/$invalid_id/.panel-run"
discard_output="$(env -u PANEL_REVIEW_KEEP_TMP "$SC/discard" --workdir "$keeprepo")"
assert_eq "discard prints one summary for valid or invalid marker names" \
  'Cleared .panel-review/ for this workdir.' "$discard_output"
assert_eq "discard removes an invalidly named marker" 'gone' "$([ -d "$keeprepo/.panel-review" ] && echo here || echo gone)"
assert_eq "discard leaves an unmappable /tmp path alone" 'kept' "$([ -d "/tmp/$invalid_id" ] && echo kept || echo gone)"
rm -rf -- "/tmp/$invalid_id"

section "reopen — archives the finished epoch, then resets for the next cycle"
# A finished run: i1 accepted (settled a prior round), i2 contested (the leftover).
# reopen must (a) snapshot the whole finished record into epochs/epoch-<prev>/ before
# the next cycle's round-N filenames clobber it, (b) reset the live index for a fresh
# debate, (c) wipe+recreate sweeps. Regression for the continue data-loss/round-restart
# investigation (issues-2026-07-11): night round-1 raws were overwritten with no .bak.
rid="$PREFIX-reopen1"; rm -rf "/tmp/$rid" "/tmp/$rid.md" "/tmp/$rid.md.bak"
mkdir -p "/tmp/$rid/raw" "/tmp/$rid/audit" "/tmp/$rid/sweeps/round-1"
cat > "/tmp/$rid/index.json" <<'JSON'
{"issues":[{"id":"i1","claim":"c","location":"f:1","category":"performance","severity":"medium","evidence_pro":[],"evidence_contra":[],"peer_reviewed":true,"fully_vetted":true,"detail_contested":false,"state":"accepted","rounds_debated":1},{"id":"i2","claim":"c","location":"f:2","category":"correctness","severity":"high","evidence_pro":[],"evidence_contra":[],"peer_reviewed":true,"fully_vetted":true,"detail_contested":false,"state":"contested","rounds_debated":2}],"round":2,"phase":"debate","committed_rounds":[1,2],"run_epoch":0,"evaluated_by":{"i1":["claude","codex","gemini"],"i2":["claude","codex","gemini"]}}
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
{"issues":[{"id":"i1","claim":"c","location":"f:1","category":"performance","severity":"medium","evidence_pro":[],"evidence_contra":[],"peer_reviewed":true,"fully_vetted":true,"detail_contested":false,"state":"accepted","rounds_debated":1}],"round":1,"phase":"debate","committed_rounds":[1],"run_epoch":0,"evaluated_by":{"i1":["claude","codex"]}}
JSON
"$SC/reopen" --id "$rid2" --category both >/dev/null 2>&1; assert_exit "reopen with nothing to reopen exits 3" 3 "$?"
assert_eq "no-match makes no archive"    'no' "$([ -d "/tmp/$rid2/epochs" ] && echo yes || echo no)"
assert_eq "no-match leaves index untouched" '1|0' "$(jq -r '"\(.round)|\(.run_epoch)"' "/tmp/$rid2/index.json")"
rm -rf "/tmp/$rid" "/tmp/$rid.md" "/tmp/$rid.md.bak" "/tmp/$rid2"

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
# Opt-in live checks. These call a real external CLI (network, auth, a little quota),
# so the default suite stays hermetic and offline; PANEL_REVIEW_LIVE=1 adds them.
if [ "${PANEL_REVIEW_LIVE:-0}" = 1 ]; then
  section "live — agy honors run_agy's model pins (PANEL_REVIEW_LIVE=1)"
  live_out="$("$here/live/agy_model_binding.sh" 2>&1)"; live_rc=$?
  case "$live_rc" in
    0) ok "agy model binding — $(printf '%s\n' "$live_out" | grep -c '^  PASS:') checks passed";;
    3) echo "  SKIP: $(printf '%s\n' "$live_out" | head -1)";;
    *) bad "agy model binding" "$(printf '%s\n' "$live_out" | grep -A2 '^  FAIL:' | head -12)";;
  esac
fi

# ---------------------------------------------------------------------------
echo
echo "================================"
echo "  PASS: $pass   FAIL: $fail"
echo "================================"
[ "$fail" -eq 0 ]
