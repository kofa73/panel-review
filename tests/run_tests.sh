#!/usr/bin/env bash
# Regression suite for the panel-review debate pipeline (parse_block, decide_round,
# merge_payload, and the SKILL-level empty-stances guard idiom).
#
# Self-contained: fixtures live in tests/fixtures/ (captured real run data +
# synthetic cases built inline). No automated framework exists in this repo, so
# this is plain bash with a tiny assert harness.
#
# decide_round/index hardcode /tmp/<id>/ paths, so tests mint throwaway run ids
# under /tmp with a unique prefix and clean them up on exit.
#
# Usage: tests/run_tests.sh            # run all, exit nonzero if any fail
#        VERBOSE=1 tests/run_tests.sh  # also print each PASS
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
SC="$root/scripts"
FX="$here/fixtures"
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

# mkrun <suffix> : create /tmp/<PREFIX>-<suffix> with decide_round fixtures; echo the id
mkrun() {
  local id="$PREFIX-$1"; rm -rf "/tmp/$id"; mkdir -p "/tmp/$id"
  cp "$FX/decide_round/index.round0.json" "/tmp/$id/index.json"
  jq --slurpfile evaluated "$FX/decide_round/evaluated.round0.json" '.evaluated_by = $evaluated[0]' \
    "/tmp/$id/index.json" > "$TMP/index.$1.json"
  mv "$TMP/index.$1.json" "/tmp/$id/index.json"
  cp "$FX/decide_round/manifest.json"     "/tmp/$id/manifest.json"
  echo "$id"
}
states() { jq -c '[.issues[]|{id,state,sev:.severity,rd:.rounds_debated,pr:.peer_reviewed,fv:.fully_vetted,dc:.detail_contested}]' "/tmp/$1/index.json"; }

# ---------------------------------------------------------------------------
section "parse_block — normal-mode exit codes (real messy output)"
"$SC/parse_block" findings "$FX/parse_block/round0.codex.empty.txt"  codex  >/dev/null 2>&1; assert_exit "codex empty findings -> 0" 0 "$?"
"$SC/parse_block" findings "$FX/parse_block/round0.claude.flat.txt"  claude >/dev/null 2>&1; assert_exit "claude flat-shape -> 5 (malformed)" 5 "$?"
"$SC/parse_block" findings "$FX/parse_block/round0.gemini.timeout.txt" gemini >/dev/null 2>&1; assert_exit "gemini timeout (no block) -> 4" 4 "$?"

section "parse_block — stances parse byte-identical to stored output"
for s in codex gemini claude; do
  got="$("$SC/parse_block" stances "$FX/parse_block/round1.$s.stances.txt" "$s" 2>/dev/null)"
  exp="$(cat "$FX/parse_block/expected.$s.stances.json")"
  assert_eq "$s stances identical" "$exp" "$got"
done

section "parse_block --diagnose — pinpoints the failed constraint"
diag="$("$SC/parse_block" --diagnose findings "$FX/parse_block/round0.claude.flat.txt" 2>/dev/null)"
case "$diag" in *"no valid \`points[]\`"*) ok "flat shape -> 'no valid points[]'";; *) bad "flat shape diagnose" "got: $diag";; esac
# synthetic per-reason
mkf="$TMP/badf.txt"
cat > "$mkf" <<'EOF'
```findings
{"claim":"ok","location":"f.c:1","category":"correctness","severity":"high","points":[{"assertion":"x","location":"f.c:1"}]}
{"location":"f.c:2","category":"correctness","severity":"high","points":[{"assertion":"x","location":"f.c:2"}]}
{"claim":"x","location":"f.c:3","category":"bogus","severity":"high","points":[{"assertion":"x","location":"f.c:3"}]}
{"claim":"x","location":"f.c:4","category":"correctness","severity":"epic","points":[{"assertion":"x","location":"f.c:4"}]}
{"claim":"x","location":"f.c:5","category":"correctness","severity":"high","points":[{"impact":"no assertion"}]}
{not json}
```
EOF
d="$("$SC/parse_block" --diagnose findings "$mkf" 2>/dev/null)"
case "$d" in *"item 2: missing or non-string field \`claim\`"*) ok "diag: missing claim";; *) bad "diag missing claim";; esac
case "$d" in *"item 3: missing/invalid \`category\`"*)        ok "diag: bad category";; *) bad "diag bad category";; esac
case "$d" in *"item 4: missing/invalid \`severity\`"*)        ok "diag: bad severity";; *) bad "diag bad severity";; esac
case "$d" in *"item 5: no valid \`points[]\`"*)               ok "diag: empty points";; *) bad "diag empty points";; esac
case "$d" in *"item 6: not valid JSON"*)                      ok "diag: syntax error";; *) bad "diag syntax";; esac
"$SC/parse_block" --diagnose findings "$mkf" >/dev/null 2>&1; assert_exit "diagnose exit 5 when invalid present" 5 "$?"

section "parse_block --diagnose — all-valid -> exit 0, no output"
"$SC/parse_block" --diagnose stances "$FX/parse_block/round1.codex.stances.txt" >/dev/null 2>&1; assert_exit "valid stances diagnose -> 0" 0 "$?"

# ---------------------------------------------------------------------------
section "decide_round — round 1 (finding-1 fix: i4 stays open, enum unconverged)"
id="$(mkrun r1)"
p="$("$SC/decide_round" --id "$id" --round 1 --configured "codex gemini claude" --engaged "codex gemini claude" \
      --stances "$FX/decide_round/stances.round1.json")"
assert_eq "bump = i1,i3,i4,i5,i6"        '["i1","i3","i4","i5","i6"]' "$(echo "$p"|jq -c '.bump')"
assert_eq "set_state accepted i1,i3,i5"  '["i1","i3","i5"]'            "$(echo "$p"|jq -c '[.set_state[]|select(.state=="accepted")|.id]')"
assert_eq "i4 NOT terminal (stays open)" 'false'                       "$(echo "$p"|jq -c 'any(.set_state[];.id=="i4")')"
assert_eq "no enum revise at r1"         'null'                        "$(echo "$p"|jq -c '.revise')"

section "decide_round — round 1 commits cleanly via index commit-sweep"
echo "$p" > "$TMP/p1.json"
"$SC/index" commit-sweep "$id" 1 0 < "$TMP/p1.json" >/dev/null 2>&1; assert_exit "commit round1 -> 0" 0 "$?"
assert_eq "after r1 i4 open"      'open'     "$(jq -r '.issues[]|select(.id=="i4")|.state' "/tmp/$id/index.json")"
assert_eq "after r1 i1 accepted" 'accepted' "$(jq -r '.issues[]|select(.id=="i1")|.state' "/tmp/$id/index.json")"
assert_eq "after r1 i6 open"      'open'     "$(jq -r '.issues[]|select(.id=="i6")|.state' "/tmp/$id/index.json")"
assert_eq "coverage is committed atomically" 'true' "$(jq -c '.evaluated_by.i1 == ["claude","codex","gemini"]' "/tmp/$id/index.json")"
# idempotent re-commit
"$SC/index" commit-sweep "$id" 1 0 < "$TMP/p1.json" >/dev/null 2>&1; assert_exit "re-commit round1 idempotent" 0 "$?"
assert_eq "no double-bump i1 rd=1" '1' "$(jq -r '.issues[]|select(.id=="i1")|.rounds_debated' "/tmp/$id/index.json")"

section "decide_round — round 2 (i4 unanimous low, i6 mixed at per-issue limit)"
cat > "$TMP/st2.json" <<'EOF'
{"id":"i4","stance":"support_with_revision","rationale":"low","revision":{"severity":"low"},"_source":"codex","fid":"codex-1"}
{"id":"i4","stance":"support_with_revision","rationale":"low","revision":{"severity":"low"},"_source":"gemini","fid":"gemini-1"}
{"id":"i4","stance":"support_with_revision","rationale":"low","revision":{"severity":"low"},"_source":"claude","fid":"claude-1"}
{"id":"i6","stance":"reject","rationale":"self-heals","_source":"codex","fid":"codex-2"}
{"id":"i6","stance":"support","rationale":"leak","_source":"gemini","fid":"gemini-2"}
{"id":"i6","stance":"support","rationale":"risk","_source":"claude","fid":"claude-2"}
EOF
p2="$("$SC/decide_round" --id "$id" --round 2 --configured "codex gemini claude" --engaged "codex gemini claude" --stances "$TMP/st2.json")"
echo "$p2" > "$TMP/p2.json"
"$SC/index" commit-sweep "$id" 2 0 < "$TMP/p2.json" >/dev/null 2>&1; assert_exit "commit round2 -> 0" 0 "$?"
assert_eq "i4 accepted sev=low rd=2" 'accepted|low|2' "$(jq -r '.issues[]|select(.id=="i4")|"\(.state)|\(.severity)|\(.rounds_debated)"' "/tmp/$id/index.json")"
assert_eq "i6 contested rd=2"        'contested|2'    "$(jq -r '.issues[]|select(.id=="i6")|"\(.state)|\(.rounds_debated)"' "/tmp/$id/index.json")"

section "decide_round — enum at ceiling -> accepted + detail_contested (no adopt)"
id="$(mkrun ceil)"
pc="$("$SC/decide_round" --id "$id" --round 4 --configured "codex gemini claude" --engaged "codex gemini claude" --stances "$FX/decide_round/stances.round1.json")"
assert_eq "i4 accepted at ceiling"        'accepted' "$(echo "$pc"|jq -r '.set_state[]|select(.id=="i4")|.state')"
assert_eq "i4 detail_contested set"       '1'        "$(echo "$pc"|jq -c '[.set_flag[]|select(.id=="i4" and .flag=="detail_contested")]|length')"
assert_eq "still no enum revise"          'null'     "$(echo "$pc"|jq -c '.revise')"

section "decide_round — true unanimity adopts enum"
id="$(mkrun unan)"
grep -v '"id":"i4"' "$FX/decide_round/stances.round1.json" > "$TMP/unan.json"
cat >> "$TMP/unan.json" <<'EOF'
{"id":"i4","stance":"support_with_revision","rationale":"low","revision":{"severity":"low"},"_source":"codex","fid":"c"}
{"id":"i4","stance":"support_with_revision","rationale":"low","revision":{"severity":"low"},"_source":"gemini","fid":"g"}
{"id":"i4","stance":"support_with_revision","rationale":"low","revision":{"severity":"low"},"_source":"claude","fid":"l"}
EOF
pu="$("$SC/decide_round" --id "$id" --round 1 --configured "codex gemini claude" --engaged "codex gemini claude" --stances "$TMP/unan.json")"
assert_eq "i4 accepted + revise sev=low" 'accepted|low' "$(echo "$pu"|jq -r '"\(.set_state[]|select(.id=="i4")|.state)|\(.revise[]|select(.id=="i4")|.fields.severity)"')"

section "decide_round — split support/reject cannot adopt one seat's revision"
id="$(mkrun split-revision)"
cat > "/tmp/$id/index.json" <<'EOF'
{"issues":[{"id":"i1","claim":"c","location":"a.c:1","category":"correctness","severity":"high","evidence_pro":[{"location":"a.c:1","assertion":"x"}],"evidence_contra":[],"peer_reviewed":false,"fully_vetted":false,"detail_contested":false,"state":"open","rounds_debated":0,"card_rev":0}],"round":0,"phase":"debate","committed_rounds":[],"run_epoch":0}
EOF
cat > "$TMP/split-revision.json" <<'EOF'
{"id":"i1","stance":"support_with_revision","rationale":"severity is low","revision":{"severity":"low"},"_source":"codex","fid":"c"}
{"id":"i1","stance":"reject","rationale":"the claim is not established","_source":"claude","fid":"l"}
EOF
ps="$($SC/decide_round --id "$id" --round 1 --configured "codex claude" --engaged "codex claude" --stances "$TMP/split-revision.json")"
assert_eq "split vote leaves issue open" 'null' "$(echo "$ps" | jq -c '.set_state')"
assert_eq "split vote does not revise severity" 'null' "$(echo "$ps" | jq -c '.revise')"

# ---------------------------------------------------------------------------
section "decide_round — integrity gate (finding 2)"
id="$(mkrun gate)"
# duplicate
cp "$FX/decide_round/stances.round1.json" "$TMP/dup.json"
echo '{"id":"i6","stance":"reject","rationale":"dup","_source":"codex","fid":"x"}' >> "$TMP/dup.json"
"$SC/decide_round" --id "$id" --round 1 --configured "codex gemini claude" --engaged "codex gemini claude" --stances "$TMP/dup.json" >/dev/null 2>&1; assert_exit "duplicate stance -> exit 3" 3 "$?"
# missing
grep -v '"id":"i5".*"_source":"claude"' "$FX/decide_round/stances.round1.json" > "$TMP/miss.json"
"$SC/decide_round" --id "$id" --round 1 --configured "codex gemini claude" --engaged "codex gemini claude" --stances "$TMP/miss.json" >/dev/null 2>&1; assert_exit "missing stance -> exit 3" 3 "$?"
# unknown _source
cp "$FX/decide_round/stances.round1.json" "$TMP/unk.json"
echo '{"id":"i1","stance":"support","rationale":"x","_source":"mistral","fid":"m"}' >> "$TMP/unk.json"
"$SC/decide_round" --id "$id" --round 1 --configured "codex gemini claude" --engaged "codex gemini claude" --stances "$TMP/unk.json" >/dev/null 2>&1; assert_exit "unknown _source -> exit 3" 3 "$?"

section "decide_round — dropped (empty) seat: decides on remainder, withholds fully_vetted"
id="$(mkrun drop)"
# only i1 open issue, gemini omitted (empty stances) -> engaged = codex,claude
cat > "/tmp/$id/index.json" <<'EOF'
{"issues":[{"id":"i1","claim":"c","location":"a.c:1","category":"correctness","severity":"high","evidence_pro":[{"location":"a.c:1","assertion":"x"}],"evidence_contra":[],"peer_reviewed":false,"fully_vetted":false,"detail_contested":false,"state":"open","rounds_debated":0,"card_rev":0}],"round":0,"phase":"debate","committed_rounds":[],"run_epoch":0}
EOF
cat > "$TMP/drop.json" <<'EOF'
{"id":"i1","stance":"support","rationale":"y","_source":"codex","fid":"c"}
{"id":"i1","stance":"support","rationale":"y","_source":"claude","fid":"l"}
EOF
pd="$("$SC/decide_round" --id "$id" --round 1 --configured "codex gemini claude" --engaged "codex claude" --stances "$TMP/drop.json")"
assert_eq "i1 accepted by 2 engaged"   'accepted' "$(echo "$pd"|jq -r '.set_state[]|select(.id=="i1")|.state')"
assert_eq "fully_vetted withheld"      '0'        "$(echo "$pd"|jq -c '[.set_flag[]|select(.flag=="fully_vetted")]|length')"

# ---------------------------------------------------------------------------
section "merge_payload — set_state replace + revise field-merge (finding 3)"
cat > "$TMP/base.json" <<'EOF'
{"bump":["i4"],"set_state":[{"id":"i4","state":"accepted"}],
 "set_flag":[{"id":"i4","flag":"peer_reviewed","value":true},{"id":"i4","flag":"fully_vetted","value":true}],
 "revise":[{"id":"i4","fields":{"severity":"low"}}],
 "add_evidence":[{"id":"i4","side":"contra","point":{"location":"analysis","assertion":"base"}}]}
EOF
cat > "$TMP/add.json" <<'EOF'
{"set_state":[{"id":"i4","state":"open"}],
 "revise":[{"id":"i4","fields":{"claim":"synth claim"}}],
 "add_issues":[{"id":"i7","claim":"new","location":"y.c:2","category":"correctness","severity":"low","evidence_pro":[{"location":"y.c:2","assertion":"z"}],"evidence_contra":[],"peer_reviewed":false,"fully_vetted":false,"detail_contested":false,"state":"open","rounds_debated":0,"card_rev":0}]}
EOF
m="$("$SC/merge_payload" "$TMP/base.json" < "$TMP/add.json")"
assert_eq "set_state single, addendum wins (open)" '[{"id":"i4","state":"open"}]' "$(echo "$m"|jq -c '.set_state')"
assert_eq "revise single, fields merged"           '{"severity":"low","claim":"synth claim"}' "$(echo "$m"|jq -c '.revise[]|select(.id=="i4")|.fields')"
assert_eq "no dup ids in set_state/revise"         'true' "$(echo "$m"|jq -c '(.set_state|map(.id)|(unique|length)==length) and (.revise|map(.id)|(unique|length)==length)')"
# commits cleanly
id="$(mkrun merge)"
echo "$m" > "$TMP/m.json"
"$SC/index" commit-sweep "$id" 1 0 < "$TMP/m.json" >/dev/null 2>&1; assert_exit "merged payload commits -> 0" 0 "$?"
assert_eq "i4 reopened with merged severity" 'open|low' "$(jq -r '.issues[]|select(.id=="i4")|"\(.state)|\(.severity)"' "/tmp/$id/index.json")"
assert_eq "i7 added"                         'open'     "$(jq -r '.issues[]|select(.id=="i7")|.state' "/tmp/$id/index.json")"

section "merge_payload — contrast: hand-appending IS rejected by commit-sweep"
id="$(mkrun append)"
jq -s '{set_state:(.[0].set_state+.[1].set_state),revise:(.[0].revise+.[1].revise)}' "$TMP/base.json" "$TMP/add.json" > "$TMP/app.json"
"$SC/index" commit-sweep "$id" 1 0 < "$TMP/app.json" >/dev/null 2>&1; assert_exit "appended (dup set_state) -> rejected" 1 "$?"

# ---------------------------------------------------------------------------
section "SKILL idiom — empty-but-present stances guard (record only if non-empty)"
printf '```stances\n```\n' > "$TMP/empty.txt"
if "$SC/parse_block" stances "$TMP/empty.txt" gemini > "$TMP/st.out" 2>/dev/null && [ -s "$TMP/st.out" ]; then r=recorded; else r=skipped; fi
assert_eq "empty stances block -> skipped (not recorded)" 'skipped' "$r"
printf '```stances\n{"id":"i1","stance":"support","rationale":"ok"}\n```\n' > "$TMP/real.txt"
if "$SC/parse_block" stances "$TMP/real.txt" gemini > "$TMP/st.out" 2>/dev/null && [ -s "$TMP/st.out" ]; then r=recorded; else r=skipped; fi
assert_eq "real stances block -> recorded" 'recorded' "$r"

section "SKILL idiom — partial batch is not checkpointed"
printf 'i1\ni2\n' > "$TMP/expected.ids"
cat > "$TMP/partial.txt" <<'EOF'
```stances
{"id":"i1","stance":"support","rationale":"ok"}
{"id":42,"stance":"support"}
```
EOF
parsed="$TMP/partial.json"; parsed_ids="$TMP/partial.ids"
if "$SC/parse_block" stances "$TMP/partial.txt" gemini > "$parsed" 2>/dev/null && [ -s "$parsed" ] \
   && jq -r '.id' "$parsed" | sort > "$parsed_ids" \
   && [ "$(wc -l < "$parsed")" -eq "$(wc -l < "$TMP/expected.ids")" ] \
   && cmp -s "$TMP/expected.ids" "$parsed_ids"; then r=recorded; else r=skipped; fi
assert_eq "partial batch -> skipped (not checkpointed)" 'skipped' "$r"

# ---------------------------------------------------------------------------
section "decide_degraded_round — terminal degraded outcomes and coverage"
id="$(mkrun degraded)"
cat > "/tmp/$id/index.json" <<'EOF'
{"issues":[{"id":"old","claim":"c","location":"a:1","category":"correctness","severity":"high","evidence_pro":[{"location":"a:1","assertion":"x"}],"evidence_contra":[],"peer_reviewed":true,"fully_vetted":false,"detail_contested":false,"state":"open","rounds_debated":1,"card_rev":0},{"id":"new","claim":"c","location":"b:1","category":"correctness","severity":"high","evidence_pro":[{"location":"b:1","assertion":"x"}],"evidence_contra":[],"peer_reviewed":false,"fully_vetted":false,"detail_contested":false,"state":"open","rounds_debated":0,"card_rev":0}],"round":0,"phase":"debate","committed_rounds":[],"run_epoch":0,"evaluated_by":{"old":["codex","claude"],"new":["codex"]}}
EOF
cat > "$TMP/degraded.json" <<'EOF'
{"id":"old","stance":"support","_source":"gemini"}
{"id":"new","stance":"reject","_source":"gemini"}
EOF
dp="$("$SC/decide_degraded_round" --id "$id" --round 1 --configured "codex claude gemini" --engaged gemini --stances "$TMP/degraded.json")"
echo "$dp" > "$TMP/degraded.payload.json"
assert_eq "lone seat makes prior peer pass contested" 'contested' "$(echo "$dp" | jq -r '.set_state[]|select(.id=="old")|.state')"
assert_eq "lone seat makes never-peer issue unresolved" 'unresolved' "$(echo "$dp" | jq -r '.set_state[]|select(.id=="new")|.state')"
assert_eq "lone seat only sets fully_vetted after peer coverage" 'old' "$(echo "$dp" | jq -r '.set_flag[]?.id')"
"$SC/index" commit-sweep "$id" 1 0 < "$TMP/degraded.payload.json" >/dev/null 2>&1; assert_exit "degraded payload commits" 0 "$?"
assert_eq "degraded coverage persisted with state" 'true' "$(jq -c '.evaluated_by.old == ["claude","codex","gemini"] and (.issues[]|select(.id=="old")|.fully_vetted)' "/tmp/$id/index.json")"
printf '' > "$TMP/no-stances.json"
id="$(mkrun degraded-zero)"
dz="$("$SC/decide_degraded_round" --id "$id" --round 1 --configured "codex claude" --engaged '' --stances "$TMP/no-stances.json")"
assert_eq "zero-seat round is unresolved" 'true' "$(echo "$dz" | jq -c '(.set_state|map(.state)|unique)==["unresolved"]')"
"$SC/decide_degraded_round" --id "$id" --round 1 --configured "codex claude" --engaged "codex claude" --stances "$TMP/no-stances.json" >/dev/null 2>&1; assert_exit "degraded rejects two seats" 2 "$?"

section "sweep — script-owned batch checkpointing and recovery plan"
id="$(mkrun sweep)"
"$SC/sweep" begin "$id" 1 0 >/dev/null
cat > "$TMP/batch-plan.json" <<'EOF'
{"batches":[{"seat":"codex","batch":"b1","expected_ids":["i1","i2"]},{"seat":"claude","batch":"b1","expected_ids":["i1","i2"]}]}
EOF
printf 'i1\ni2\n' > "$TMP/batch.ids"
"$SC/sweep" plan "$id" 1 0 "$TMP/batch-plan.json" >/dev/null; assert_exit "batch plan accepted" 0 "$?"
assert_eq "missing raw is classified" '{"status":"missing"}' "$("$SC/sweep" ingest-batch "$id" 1 0 codex b1 "$TMP/batch.ids" "$TMP/not-there.txt")"
printf '```stances\n```\n' > "$TMP/empty-batch.txt"
assert_eq "empty batch is classified" '{"status":"empty"}' "$("$SC/sweep" ingest-batch "$id" 1 0 codex b1 "$TMP/batch.ids" "$TMP/empty-batch.txt")"
printf '```stances\nnot-json\n```\n' > "$TMP/malformed-batch.txt"
assert_eq "malformed batch is classified" '{"status":"malformed"}' "$("$SC/sweep" ingest-batch "$id" 1 0 codex b1 "$TMP/batch.ids" "$TMP/malformed-batch.txt")"
partial_status="$("$SC/sweep" ingest-batch "$id" 1 0 codex b1 "$TMP/batch.ids" "$TMP/partial.txt")"
assert_eq "partial batch is not checkpointed by sweep" '{"status":"partial"}' "$partial_status"
"$SC/sweep" has "$id" 1 codex b1 >/dev/null 2>&1; assert_exit "partial batch has no cache" 1 "$?"
cat > "$TMP/duplicate-batch.txt" <<'EOF'
```stances
{"id":"i1","stance":"support"}
{"id":"i1","stance":"reject"}
```
EOF
assert_eq "duplicate ID batch is classified" '{"status":"wrong_ids"}' "$("$SC/sweep" ingest-batch "$id" 1 0 codex b1 "$TMP/batch.ids" "$TMP/duplicate-batch.txt")"
cat > "$TMP/wrong-id-batch.txt" <<'EOF'
```stances
{"id":"i1","stance":"support"}
{"id":"i3","stance":"reject"}
```
EOF
assert_eq "wrong ID batch is classified" '{"status":"wrong_ids"}' "$("$SC/sweep" ingest-batch "$id" 1 0 codex b1 "$TMP/batch.ids" "$TMP/wrong-id-batch.txt")"
cat > "$TMP/complete.txt" <<'EOF'
```stances
{"id":"i1","stance":"support"}
{"id":"i2","stance":"reject"}
```
EOF
complete_status="$("$SC/sweep" ingest-batch "$id" 1 0 codex b1 "$TMP/batch.ids" "$TMP/complete.txt")"
assert_eq "complete batch is checkpointed by sweep" '{"status":"complete"}' "$complete_status"
rp="$("$SC/sweep" resume-plan "$id")"
assert_eq "resume plan reports complete and missing batches" 'complete|missing' "$(echo "$rp" | jq -r '.batches[]|.status' | paste -sd'|' -)"
"$SC/sweep" drop-seat "$id" 1 codex >/dev/null
assert_eq "dropped seat is excluded from resume" 'dropped' "$("$SC/sweep" resume-plan "$id" | jq -r '.batches[]|select(.seat=="codex")|.status')"
"$SC/sweep" ingest-batch "$id" 1 0 codex b1 "$TMP/batch.ids" "$TMP/complete.txt" >/dev/null 2>&1; assert_exit "dropped seat cannot be re-ingested" 1 "$?"

section "index gate-status — pure low-only predicate"
id="$(mkrun gate-status)"
assert_eq "mixed open severities are not low-only" '{"open":5,"low_only":false}' "$("$SC/index" gate-status "$id")"
jq '(.issues[] | select(.state=="open")) |= (.severity="low")' "/tmp/$id/index.json" > "$TMP/low-index.json"
"$SC/index" put "$id" < "$TMP/low-index.json" >/dev/null
assert_eq "all low open issues are low-only" '{"open":5,"low_only":true}' "$("$SC/index" gate-status "$id")"
jq '(.issues[] | select(.state=="open")) |= (.state="accepted" | .peer_reviewed=true)' "/tmp/$id/index.json" > "$TMP/no-open-index.json"
"$SC/index" put "$id" < "$TMP/no-open-index.json" >/dev/null
assert_eq "no open issues are not low-only" '{"open":0,"low_only":false}' "$("$SC/index" gate-status "$id")"

# ---------------------------------------------------------------------------
section "decide_round — blindness gate (F2): seat identity / tally in promoted text -> exit 5"
id="$(mkrun blind)"
# single open issue, 2 engaged seats -> integrity gate passes, blindness gate reached
cat > "/tmp/$id/index.json" <<'EOF'
{"issues":[{"id":"i1","claim":"c","location":"a.c:1","category":"correctness","severity":"high","evidence_pro":[{"location":"a.c:1","assertion":"x"}],"evidence_contra":[],"peer_reviewed":false,"fully_vetted":false,"detail_contested":false,"state":"open","rounds_debated":0,"card_rev":0}],"round":0,"phase":"debate","committed_rounds":[],"run_epoch":0}
EOF
# (a) tally phrase in rationale
cat > "$TMP/blind.json" <<'EOF'
{"id":"i1","stance":"reject","rationale":"all three seats agree this is a non-issue","_source":"codex","fid":"c"}
{"id":"i1","stance":"support","rationale":"the off-by-one drops the last element","_source":"claude","fid":"l"}
EOF
"$SC/decide_round" --id "$id" --round 1 --configured "codex gemini claude" --engaged "codex claude" --stances "$TMP/blind.json" > "$TMP/blind.out" 2>/dev/null; assert_exit "tally rationale -> exit 5" 5 "$?"
assert_eq "blind round emits NO payload" '' "$(cat "$TMP/blind.out")"
# (b) seat name in new_evidence.assertion
cat > "$TMP/blind2.json" <<'EOF'
{"id":"i1","stance":"support","rationale":"the loop bound is wrong","new_evidence":{"location":"a.c:2","assertion":"Gemini missed the off-by-one here"},"_source":"codex","fid":"c"}
{"id":"i1","stance":"support","rationale":"confirmed, the index overruns","_source":"claude","fid":"l"}
EOF
"$SC/decide_round" --id "$id" --round 1 --configured "codex gemini claude" --engaged "codex claude" --stances "$TMP/blind2.json" >/dev/null 2>&1; assert_exit "seat name in new_evidence -> exit 5" 5 "$?"
# (c) seat name in an array-valued new_evidence.location
cat > "$TMP/blind3.json" <<'EOF'
{"id":"i1","stance":"support","rationale":"the loop bound is wrong","new_evidence":{"location":["a.c:2","Claude identified this path"],"assertion":"the loop stops early"},"_source":"codex","fid":"c"}
{"id":"i1","stance":"support","rationale":"confirmed, the index overruns","_source":"claude","fid":"l"}
EOF
"$SC/decide_round" --id "$id" --round 1 --configured "codex gemini claude" --engaged "codex claude" --stances "$TMP/blind3.json" >/dev/null 2>&1; assert_exit "seat name in array location -> exit 5" 5 "$?"
# (d) precondition and impact are scanned independently
cat > "$TMP/blind4.json" <<'EOF'
{"id":"i1","stance":"support","rationale":"the loop bound is wrong","new_evidence":{"location":"a.c:2","assertion":"the loop stops early","precondition":"Claude enables this mode"},"_source":"codex","fid":"c"}
{"id":"i1","stance":"support","rationale":"confirmed, the index overruns","_source":"claude","fid":"l"}
EOF
"$SC/decide_round" --id "$id" --round 1 --configured "codex gemini claude" --engaged "codex claude" --stances "$TMP/blind4.json" >/dev/null 2>&1; assert_exit "seat name in precondition -> exit 5" 5 "$?"
cat > "$TMP/blind5.json" <<'EOF'
{"id":"i1","stance":"support","rationale":"the loop bound is wrong","new_evidence":{"location":"a.c:2","assertion":"the loop stops early","impact":"all three reviewers observe the failure"},"_source":"codex","fid":"c"}
{"id":"i1","stance":"support","rationale":"confirmed, the index overruns","_source":"claude","fid":"l"}
EOF
"$SC/decide_round" --id "$id" --round 1 --configured "codex gemini claude" --engaged "codex claude" --stances "$TMP/blind5.json" >/dev/null 2>&1; assert_exit "tally in impact -> exit 5" 5 "$?"
# (e) clean control: technical-only text -> proceeds (exit 0, real payload)
cat > "$TMP/clean.json" <<'EOF'
{"id":"i1","stance":"support","rationale":"the off-by-one drops the last element","_source":"codex","fid":"c"}
{"id":"i1","stance":"support","rationale":"confirmed, the loop bound is wrong","_source":"claude","fid":"l"}
EOF
"$SC/decide_round" --id "$id" --round 1 --configured "codex gemini claude" --engaged "codex claude" --stances "$TMP/clean.json" > "$TMP/clean.out" 2>/dev/null; assert_exit "clean stances -> exit 0" 0 "$?"
assert_eq "clean round emits a payload"  'object'   "$(jq -r 'type' "$TMP/clean.out" 2>/dev/null)"
assert_eq "clean round accepts i1"       'accepted' "$(jq -r '.set_state[]|select(.id=="i1")|.state' "$TMP/clean.out" 2>/dev/null)"

section "index state — enum validation (issues-curated #8)"
id="$(mkrun istate)"
"$SC/index" state "$id" i1 bogus >/dev/null 2>&1;     assert_exit "index state bogus -> exit 2" 2 "$?"
"$SC/index" state "$id" i1 contested >/dev/null 2>&1; assert_exit "index state contested -> ok" 0 "$?"
assert_eq "i1 now contested" 'contested' "$(jq -r '.issues[]|select(.id=="i1")|.state' "/tmp/$id/index.json")"

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
assert_file_contains "CLAUDE.md uses general constrained-seat wording" 'constrained/sandboxed workspace' "$root/CLAUDE.md"

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
mkdir -p "$keeprepo/.panel-review/$id"; echo "$id" > "$keeprepo/.panel-review/$id/.panel-run"
"$SC/cleanup" --id "$id" --workdir "$keeprepo" 2>/dev/null
assert_eq "default cleanup removes /tmp/<id>"       'gone'    "$([ -d "/tmp/$id" ] && echo kept || echo gone)"
id="$PREFIX-keep2"; rm -rf "/tmp/$id"; mkdir -p "/tmp/$id"; echo '{}' > "/tmp/$id/manifest.json"
mkdir -p "$keeprepo/.panel-review/$id"; echo "$id" > "$keeprepo/.panel-review/$id/.panel-run"
PANEL_REVIEW_KEEP_TMP=true "$SC/discard" --workdir "$keeprepo" >/dev/null
assert_eq "KEEP_TMP discard preserves /tmp/<id>"    'kept'    "$([ -d "/tmp/$id" ] && echo kept || echo gone)"
assert_eq "KEEP_TMP discard still clears .panel-review" 'gone' "$([ -d "$keeprepo/.panel-review" ] && echo here || echo gone)"
rm -rf "/tmp/$id"

section "protocol references the new deterministic helpers"
assert_file_contains "protocol uses birth_index"          'birth_index' "$root/skills/panel-review-for-agent/SKILL.md"
assert_file_contains "protocol uses run_seat"             'run_seat'    "$root/skills/panel-review-for-agent/SKILL.md"
assert_file_contains "protocol uses resolve_instructions" 'resolve_instructions' "$root/skills/panel-review-for-agent/SKILL.md"

# ---------------------------------------------------------------------------
echo
echo "================================"
echo "  PASS: $pass   FAIL: $fail"
echo "================================"
[ "$fail" -eq 0 ]
