#!/usr/bin/env bash
# agy_model_binding.sh — LIVE check that agy actually runs the model run_agy pins.
#
# Not part of the hermetic suite: it invokes the real `agy`, needs a signed-in CLI
# and network, and spends a little quota (two tiny prompts, ~10-20s). Run it when
# you bump a pin, when a new agy version lands, or when a seat's findings look
# like they came from a different model than the one pinned.
#
# Usage:
#   tests/live/agy_model_binding.sh                     # check run_agy's two pins
#   tests/live/agy_model_binding.sh --model "Gemini 3.7 Flash (Medium)" [--model …]
#                                                       # check candidate labels instead
#   tests/live/agy_model_binding.sh --negative-control  # also show how this agy treats a bad pin
#   PANEL_REVIEW_LIVE=1 tests/run_tests.sh              # run it as part of the suite
#
# Exit: 0 all checks passed · 1 a check failed · 3 skipped (agy not installed)
#
# WHY this exists (see issues/archive/20-agy-model-pin-contract.md and issues/63):
#   How agy treats an unrecognized --model depends on the version. agy 1.1.10 silently
#   ran whatever ~/.gemini/antigravity-cli/settings.json has as `model` — a per-user
#   value the plugin cannot see — so a retired pin downgraded the seat with NO visible
#   failure. agy 1.1.13 and 1.4.2 hard-error at startup instead, so a retired pin takes
#   that attempt down. The offline suite can only check the pin's SHAPE; proving the pin
#   BINDS needs a real call, which is this script.
#
#   Effort needs no separate check: agy encodes it in the label ("… (High)"), and
#   these checks compare the whole propagated label, effort included.
#
# HOW the binding is observed: agy logs the model it resolved to
#   `Propagating selected model override to backend: label="…"`
# in ~/.gemini/antigravity-cli/log/cli-<timestamp>.log. That is an internal log line,
# not a documented interface — which is exactly why this lives in an on-demand test
# instead of inside run_agy, where a format change would break every review. Here, a
# missing line fails loudly as "the check is stale", never silently as "pin is fine".
# The exit code is checked BEFORE the logged label, on purpose: measured on agy 1.4.2, a
# REJECTED label still logs a propagation line naming the settings.json default before
# the startup error, so a failed call's log names a model that never ran.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
SC="$root/scripts"
LOG_DIR="${AGY_LOG_DIR:-$HOME/.gemini/antigravity-cli/log}"
PROMPT='Reply with exactly the word OK. Do not use any tools.'
PRINT_TIMEOUT="${AGY_CHECK_PRINT_TIMEOUT:-2m}"
WALL_TIMEOUT="${AGY_CHECK_WALL_TIMEOUT:-240}"
# A well-formed label that no agy version has offered: the negative control asks for
# it to demonstrate the silent-fallback hazard the pins are guarded against.
BOGUS_LABEL='Gemini 0.0 Nonexistent (High)'

pass=0; fail=0
ok()   { pass=$((pass+1)); echo "  PASS: $1"; }
bad()  { fail=$((fail+1)); echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "        $2"; return 0; }
note() { echo "  note: $1"; }
section() { echo; echo "## $1"; }

models=()
negative_control=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --model) [ "$#" -ge 2 ] || { echo "--model needs a label" >&2; exit 2; }; models+=("$2"); shift 2;;
    --negative-control) negative_control=1; shift;;
    -h|--help) sed -n '2,30p' "$0"; exit 0;;
    *) echo "unknown argument: $1" >&2; exit 2;;
  esac
done

command -v agy >/dev/null 2>&1 || { echo "SKIP: agy CLI not installed"; exit 3; }
[ -d "$LOG_DIR" ] || { echo "SKIP: agy log directory not found ($LOG_DIR)"; exit 3; }

TMP="$(mktemp -d /tmp/agy-bind.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

agy_pin() { sed -n "s/^$1=\"\(.*\)\"$/\1/p" "$SC/run_agy"; }
PRIMARY_PIN="$(agy_pin PRIMARY_MODEL)"
FALLBACK_PIN="$(agy_pin FALLBACK_MODEL)"

# Every label agy propagated to the backend since $1 (a marker file), one per line.
# Reads only logs modified after the marker, so a previous run's log cannot answer
# for this one. Blank output means agy logged nothing we recognize.
bound_labels() {
  local marker="$1" logs
  logs="$(find "$LOG_DIR" -maxdepth 1 -name 'cli-*.log' -newer "$marker" 2>/dev/null)"
  [ -n "$logs" ] || return 0
  # shellcheck disable=SC2086 # deliberate word splitting: one path per line, no spaces
  grep -h 'Propagating selected model override to backend: label="' $logs 2>/dev/null \
    | sed -n 's/.*label="\([^"]*\)".*/\1/p' | sort -u
}

# Run one agy call and report which model actually served it.
# $1 = label to request, $2 = "wrapper" to go through scripts/run_agy instead of agy.
# Echoes the bound label(s); returns the call's exit code.
dispatch() {
  local label="$1" mode="${2:-direct}" marker="$TMP/marker" out="$TMP/out" rc=0
  : > "$marker"; sleep 1   # 1s so `find -newer` cannot miss a same-second log write
  if [ "$mode" = wrapper ]; then
    printf '%s\n' "$PROMPT" | timeout "$WALL_TIMEOUT" "$SC/run_agy" > "$out" 2>"$TMP/err" || rc=$?
  else
    printf '%s\n' "$PROMPT" | timeout "$WALL_TIMEOUT" agy \
      --print-timeout="$PRINT_TIMEOUT" --model "$label" --dangerously-skip-permissions \
      > "$out" 2>"$TMP/err" || rc=$?
  fi
  bound_labels "$marker"
  return "$rc"
}

# Assert that requesting $1 (via mode $2) actually ran $1.
check_binds() {
  local want="$1" mode="${2:-direct}" got rc
  got="$(dispatch "$want" "$mode")"; rc=$?
  local label="'$want' binds exactly"
  [ "$mode" = wrapper ] && label="run_agy dispatches its primary pin '$want'"
  if [ "$rc" -ne 0 ]; then
    bad "$label" "the agy call exited $rc — check auth/network before trusting this result"
    return
  fi
  if [ -z "$got" ]; then
    bad "$label" "no 'Propagating selected model override' line in any log written by this call.
        This check is stale, not the pin: agy's log format or path changed. Re-derive it
        from a manual run before trusting any pass here."
    return
  fi
  if [ "$got" = "$want" ]; then ok "$label"; else
    bad "$label" "requested [$want] but agy ran [$(printf '%s' "$got" | tr '\n' ',')]"
  fi
}

section "pins exist in agy's own model listing (no quota)"
if agy models > "$TMP/models" 2>"$TMP/models.err"; then
  for pin in "$PRIMARY_PIN" "$FALLBACK_PIN"; do
    # The listing prints "<slug>\t<label>" (agy 1.1.13). Match the label field exactly
    # so a substring like "Gemini 3.7 Flash (High)" cannot pass on "… (Highest)".
    if cut -f2- "$TMP/models" | grep -Fxq -- "$pin"; then
      ok "agy models lists '$pin'"
    else
      bad "agy models lists '$pin'" "not offered by this agy version — the attempt will fail or run another model"
    fi
  done
else
  bad "agy models" "$(head -3 "$TMP/models.err")"
fi

if [ "${#models[@]}" -gt 0 ]; then
  section "candidate labels bind (ad-hoc --model)"
  for label in "${models[@]}"; do check_binds "$label"; done
else
  section "run_agy's primary pin binds end to end (through the wrapper)"
  # Goes through scripts/run_agy itself, so a quoting bug in the wrapper's argv —
  # the label contains spaces — fails here and not only in the offline argv test.
  check_binds "$PRIMARY_PIN" wrapper

  section "run_agy's fallback pin binds (direct: the wrapper reaches it only on a primary failure)"
  check_binds "$FALLBACK_PIN"
fi

if [ "$negative_control" = 1 ]; then
  section "negative control — what this agy does with an unknown label"
  got="$(dispatch "$BOGUS_LABEL")"; rc=$?
  if [ "$rc" -ne 0 ]; then
    note "agy exited $rc for '$BOGUS_LABEL' — this version REJECTS unknown models (as 1.1.13
        and 1.4.2 did), so a retired pin takes its attempt down rather than running another model."
  elif [ -n "$got" ] && [ "$got" != "$BOGUS_LABEL" ]; then
    note "confirmed: '$BOGUS_LABEL' silently ran [$(printf '%s' "$got" | tr '\n' ',')]
        (your settings.json default). This is the hazard the pins are checked against."
  else
    note "inconclusive: no usable propagation line for the bogus label"
  fi
fi

echo
echo "================================"
echo "  PASS: $pass   FAIL: $fail   (agy $(agy --version 2>/dev/null | head -1))"
echo "================================"
[ "$fail" -eq 0 ]
