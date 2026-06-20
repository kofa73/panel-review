# Optional Peer Seats Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Codex and Gemini seats symmetric optional peers — the review runs on Claude plus at least one peer — and give Panel Review its own auto-created Codex profile decoupled from upstream.

**Architecture:** Three small, independent changes: (1) relax `preflight` gating so the hard requirement is "≥1 peer present" and it reports both seats' availability; (2) `run_codex` defaults to its own `panel-review` profile, auto-copied from a shipped `assets/` template on first use; (3) a wording sweep so docs stop treating Codex as mandatory / Gemini as the only droppable seat. Runtime degradation already handles a down seat generically (the "≥2 engaged" rule), so no debate logic changes.

**Tech Stack:** Bash scripts (`skills/panel-review/scripts/`), Markdown skill/agent/README docs. No test framework — verification is via direct script invocation, exit-code/grep assertions, and a PATH-stubbed fake `codex`.

## Global Constraints

- Hard preflight requirements: `jq`, `git`, inside a git work tree, writable cwd, **and ≥1 peer seat** (`codex` CLI **or** `agy`). Neither peer → exit 1.
- "Peer present" means setup correctness (`command -v`), not operational liveness.
- Default Codex profile name: `panel-review` (NOT `peer-review`). Profile values: `model = "gpt-5.5"`, `model_reasoning_effort = "xhigh"`.
- The shipped default lives at `skills/panel-review/assets/default-panel-review.config.toml` (Agent Skills standard `assets/` subdir). `run_codex` copies it; it never overwrites an existing profile.
- `preflight` must remain read-only (writes no config files). Profile creation happens only in `run_codex`.
- Drop the `peer-review-summarizer` profile entirely — it is unused dead config.
- `install.sh` ships skill dirs wholesale; `assets/` deploys automatically. Keep `chmod +x` scoped to `scripts/*` only (no exec bit on the `.toml`).

---

### Task 1: Relax `preflight` gating and report both seats

**Files:**
- Modify: `skills/panel-review/scripts/preflight`

**Interfaces:**
- Consumes: nothing.
- Produces: a `preflight` whose machine-readable tail is two lines — `CODEX: yes|no` then `GEMINI: yes|no` — and which exits 1 only when core is unusable (missing jq/git/work-tree/writable-cwd, or **no** peer seat).

- [ ] **Step 1: Write the failing test**

Create `skills/panel-review/scripts/.preflight_test.sh` (temporary; deleted in Step 5):

```bash
#!/usr/bin/env bash
# Exercises preflight gating by shadowing codex/agy on PATH.
set -u
SC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fail=0
mk() { # mk <dir> <name...> : create empty stub execs named <name> in <dir>
  local d="$1"; shift; mkdir -p "$d"
  for n in "$@"; do printf '#!/usr/bin/env bash\nexit 0\n' > "$d/$n"; chmod +x "$d/$n"; done
}
# real PATH keeps jq/git; we only add/remove codex+agy via a front dir.
BASE="$(mktemp -d)"; mk "$BASE/both" codex agy; mk "$BASE/codex" codex
mk "$BASE/gem" agy;  mk "$BASE/none" # empty

run() { # run <frontdir> -> prints "exit=<code>" then preflight output
  ( PATH="$1:$PATH" "$SC/preflight" ) > /tmp/pf.out 2>&1; echo "exit=$?"; cat /tmp/pf.out
}
assert() { if eval "$2"; then echo "ok: $1"; else echo "FAIL: $1"; fail=1; fi; }

O="$(run "$BASE/both/both")"
assert "both: exit 0"        '[ "$(printf "%s" "$O" | grep -c "exit=0")" = 1 ]'
assert "both: CODEX yes"     'printf "%s" "$O" | grep -qx "CODEX: yes"'
assert "both: GEMINI yes"    'printf "%s" "$O" | grep -qx "GEMINI: yes"'

O="$(run "$BASE/codex/codex")"
assert "codex-only: exit 0"  '[ "$(printf "%s" "$O" | grep -c "exit=0")" = 1 ]'
assert "codex-only: GEM no"  'printf "%s" "$O" | grep -qx "GEMINI: no"'

O="$(run "$BASE/gem/gem")"
assert "gem-only: exit 0"    '[ "$(printf "%s" "$O" | grep -c "exit=0")" = 1 ]'
assert "gem-only: CODEX no"  'printf "%s" "$O" | grep -qx "CODEX: no"'

# none: PATH has only the empty dir + the system PATH MINUS codex/agy is hard to
# guarantee, so point PATH at ONLY the empty front dir plus coreutils via /usr/bin.
O="$( PATH="$BASE/none:/usr/bin:/bin" "$SC/preflight" 2>&1; echo "exit=$?" )"
assert "none: exit 1"        'printf "%s" "$O" | grep -q "exit=1"'
assert "none: no-peer error" 'printf "%s" "$O" | grep -qi "no peer seat"'

exit $fail
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash skills/panel-review/scripts/.preflight_test.sh`
Expected: FAIL lines (current preflight emits no `CODEX:` line and hard-fails when `codex` is absent), nonzero exit.

- [ ] **Step 3: Rewrite `preflight`**

Replace the body of `skills/panel-review/scripts/preflight` (everything from the header comment's "Hard requirements" lines through the final `exit`) so it reads:

```bash
#!/usr/bin/env bash
# preflight — verify the panel-review environment.
#
# Hard requirements: jq, git, a git work tree, a writable cwd, and at least one
# PEER seat — the codex CLI or agy (Gemini). The Claude seat is the host and is
# always present; Codex and Gemini are interchangeable optional peers, so the
# review only needs Claude + one of them.
#
# Exit 1 if the core is unusable; exit 0 otherwise. Prints human-readable
# status. The final two lines are "CODEX: yes|no" and "GEMINI: yes|no" for
# scripted seat detection.
#
# Single source of truth for both the skill and /panel-review's prereq report —
# keep the checks here so the two can't drift. Writes no files (read-only):
# run_codex owns Codex-profile creation.
set -uo pipefail   # not -e: accumulate all failures before reporting

hard_fail=0

command -v jq    >/dev/null 2>&1 || { echo "ERROR: install jq"; hard_fail=1; }
command -v git   >/dev/null 2>&1 || { echo "ERROR: install git"; hard_fail=1; }

# At least one peer seat must be present.
have_codex=no;  command -v codex >/dev/null 2>&1 && have_codex=yes
have_gemini=no; command -v agy   >/dev/null 2>&1 && have_gemini=yes
if [ "$have_codex" = no ] && [ "$have_gemini" = no ]; then
  echo "ERROR: no peer seat available — install the codex CLI (npm i -g @openai/codex) or agy (Gemini)."
  hard_fail=1
fi

# Runtime needs a git work tree (diff resolution, .git/info/exclude) and a
# writable cwd (cards live in .panel-review/ under the repo root).
if command -v git >/dev/null 2>&1; then
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "ERROR: run from inside a git work tree"; hard_fail=1; }
fi
[ -w "." ] || { echo "ERROR: working directory is not writable (cards need .panel-review/ here)"; hard_fail=1; }

# Soft checks
if [ "$have_codex" = yes ]; then
  codex login --check >/dev/null 2>&1 || echo "WARNING: run 'codex login'"
else
  echo "NOTE: codex CLI not found — Codex seat unavailable (running without it)."
fi
if [ "$have_gemini" = no ]; then
  echo "NOTE: agy CLI not found — Gemini seat unavailable (running without it)."
fi

echo "CODEX: $have_codex"
echo "GEMINI: $have_gemini"

exit "$hard_fail"
```

Note what was removed: the hard `codex`/`jq`-profile checks pinned to Codex, the `~/.codex/peer-review.config.toml` hard requirement, and the summarizer soft-check.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash skills/panel-review/scripts/.preflight_test.sh`
Expected: all `ok:` lines, exit 0.
Also run a real check: `skills/panel-review/scripts/preflight; echo "rc=$?"` from inside this repo → ends with `CODEX: yes` / `GEMINI: yes` (or `no` matching your machine) and `rc=0`.

- [ ] **Step 5: Delete the test scratch file and commit**

```bash
rm skills/panel-review/scripts/.preflight_test.sh
git add skills/panel-review/scripts/preflight
git commit -m "preflight: require any one peer seat (codex or agy), report both"
```

---

### Task 2: `run_codex` owns an auto-created `panel-review` profile

**Files:**
- Create: `skills/panel-review/assets/default-panel-review.config.toml`
- Modify: `skills/panel-review/scripts/run_codex`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `run_codex` invokes `codex exec --profile panel-review --sandbox read-only`, having ensured `~/.codex/panel-review.config.toml` exists (copied from the shipped asset, never overwriting an existing file). Final assistant message on stdout; exit 127 if `codex` absent; exit 1 on codex failure. (Unchanged output contract.)

- [ ] **Step 1: Create the shipped default profile asset**

Create `skills/panel-review/assets/default-panel-review.config.toml`:

```toml
# Default Codex profile for the Panel Review Codex seat. Layered via
# `codex exec --profile panel-review`. Copied to ~/.codex/panel-review.config.toml
# by run_codex on first use; edit that copy to tune the model/effort for reviews.
# Separate from upstream agent-peer-review's peer-review profile on purpose.
model = "gpt-5.5"
model_reasoning_effort = "xhigh"
```

- [ ] **Step 2: Write the failing test**

Create `skills/panel-review/scripts/.run_codex_test.sh` (temporary; deleted in Step 6):

```bash
#!/usr/bin/env bash
# Drives run_codex with a fake `codex` on PATH so no real model is called.
set -u
SC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fail=0
assert() { if eval "$2"; then echo "ok: $1"; else echo "FAIL: $1"; fail=1; fi; }

# Fake codex: parse `-o <path>`, write a known message there, exit 0.
STUB="$(mktemp -d)"
cat > "$STUB/codex" <<'EOF'
#!/usr/bin/env bash
out=""
while [ $# -gt 0 ]; do case "$1" in -o) out="$2"; shift 2;; *) shift;; esac; done
[ -n "$out" ] && printf 'STUB_OK' > "$out"
exit 0
EOF
chmod +x "$STUB/codex"

PROFILE="$HOME/.codex/panel-review.config.toml"
# Back up any real profile so the test starts from "absent".
BK=""; if [ -f "$PROFILE" ]; then BK="$(mktemp)"; mv "$PROFILE" "$BK"; fi
restore() { rm -f "$PROFILE"; [ -n "$BK" ] && mv "$BK" "$PROFILE"; }
trap restore EXIT

# Case A: profile absent -> run_codex copies the template and runs.
OUT="$( printf 'hi' | PATH="$STUB:$PATH" "$SC/run_codex" )"
assert "A: stdout is stub message" '[ "$OUT" = "STUB_OK" ]'
assert "A: profile created"        '[ -f "$PROFILE" ]'
assert "A: matches shipped asset"  'diff -q "$PROFILE" "$SC/../assets/default-panel-review.config.toml" >/dev/null'

# Case B: existing (user-tuned) profile is NOT clobbered.
printf 'model = "custom"\n' > "$PROFILE"
printf 'hi' | PATH="$STUB:$PATH" "$SC/run_codex" >/dev/null
assert "B: existing profile untouched" 'grep -qx "model = \"custom\"" "$PROFILE"'

exit $fail
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bash skills/panel-review/scripts/.run_codex_test.sh`
Expected: FAIL — current `run_codex` uses `--profile peer-review` and never creates `~/.codex/panel-review.config.toml`, so "A: profile created" fails.

- [ ] **Step 4: Edit `run_codex`**

In `skills/panel-review/scripts/run_codex`, update the header comment block bullet about the profile and the `CODEX_PROFILE` example, and change the default + add the ensure-profile guard.

Change the profile comment lines (currently mentioning `peer-review` and `peer-review-summarizer`) to:

```bash
#  - --profile panel-review  (NEVER hardcode -m / a raw model; the profile owns
#                             model selection. Panel Review's profile is separate
#                             from upstream peer-review and is auto-created from
#                             assets/default-panel-review.config.toml on first use.
#                             Override only the profile name via CODEX_PROFILE.)
```

Change the default assignment:

```bash
PROFILE="${CODEX_PROFILE:-panel-review}"
```

Immediately after the `command -v codex ... exit 127` line, insert the ensure-profile guard:

```bash
# Ensure our own Codex profile exists (decoupled from upstream peer-review).
# Copy the shipped default on first use; never clobber an existing/tuned file.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE_FILE="$HOME/.codex/${PROFILE}.config.toml"
if [ ! -f "$PROFILE_FILE" ]; then
  template="$SCRIPT_DIR/../assets/default-${PROFILE}.config.toml"
  if [ -f "$template" ]; then
    mkdir -p "$HOME/.codex"
    cp "$template" "$PROFILE_FILE"
  fi
fi
```

(The `codex exec --profile "$PROFILE" ...` invocation below is unchanged.)

- [ ] **Step 5: Run test to verify it passes**

Run: `bash skills/panel-review/scripts/.run_codex_test.sh`
Expected: all `ok:` lines, exit 0.

- [ ] **Step 6: Delete the test scratch file and commit**

```bash
rm skills/panel-review/scripts/.run_codex_test.sh
git add skills/panel-review/assets/default-panel-review.config.toml skills/panel-review/scripts/run_codex
git commit -m "run_codex: own panel-review profile, auto-created from shipped asset"
```

---

### Task 3: Documentation wording sweep

**Files:**
- Modify: `README.md`
- Modify: `skills/panel-review-for-agent/SKILL.md`
- Modify: `agents/panel-review-referee.md`
- Modify: `skills/panel-review-init/SKILL.md`

**Interfaces:**
- Consumes: the behavior from Tasks 1–2 (≥1-peer rule, `CODEX:`/`GEMINI:` tail lines, `panel-review` profile auto-create).
- Produces: docs only; no code depends on this.

- [ ] **Step 1: README — graceful-degradation bullet**

Replace (README, "Three rules govern…" list):

```
- **Graceful degradation.** If Gemini is unavailable, the review runs 2-way (Claude + Codex) and
  says so. One dead seat never aborts the review.
```

with:

```
- **Graceful degradation.** Either peer seat — Codex or Gemini — may be missing or fail mid-review.
  The review runs with whatever seats engage (Claude plus at least one peer) and says which seat was
  down. One dead seat never aborts the review.
```

- [ ] **Step 2: README — preflight + run_codex table rows**

Replace the `preflight` row:

```
| `preflight` | Check codex / jq / git / work-tree / writable cwd / profiles; report whether `agy` (Gemini) is present |
```

with:

```
| `preflight` | Check jq / git / work-tree / writable cwd and that ≥1 peer seat (`codex` or `agy`) is present; emit `CODEX:` / `GEMINI:` availability |
```

Replace the `run_codex` row:

```
| `run_codex` | The **only** way to call the Codex seat — pins `--sandbox read-only`, defaults `--profile peer-review` |
```

with:

```
| `run_codex` | The **only** way to call the Codex seat — pins `--sandbox read-only`, defaults `--profile panel-review` (auto-creates the profile from a shipped default) |
```

- [ ] **Step 3: README — "Degrade gracefully" rule and the config-file rule**

Replace:

```
- **Degrade gracefully.** If `agy`/Gemini is missing or every Gemini call fails, the review runs
  2-way and says so.
```

with:

```
- **Degrade gracefully.** Any seat whose call fails (CLI missing, error exit, or no parseable block)
  is treated as down; with ≥2 seats still engaged the review continues and says so. Codex and Gemini
  are both optional peers — Claude plus at least one peer is the minimum to start.
```

Replace:

```
- **Never** create, edit, or delete `~/.codex/config.toml` or any `~/.codex/*.config.toml` — the
  Codex profiles are owned by `/codex-peer-review init`.
```

with:

```
- **Never** hand-create, edit, or delete `~/.codex/config.toml`. `run_codex` owns
  `~/.codex/panel-review.config.toml` (auto-created from a shipped default); leave it and any other
  `~/.codex/*.config.toml` profile to their tools.
```

- [ ] **Step 4: for-agent SKILL — script comments**

In `skills/panel-review-for-agent/SKILL.md`, replace the `preflight` comment line:

```
"$SC/preflight"                              # env check; last line "GEMINI: yes|no"; exit 1 = core unusable
```

with:

```
"$SC/preflight"                              # env check; tail "CODEX: yes|no"/"GEMINI: yes|no"; exit 1 = core unusable (needs jq, git, work-tree, ≥1 peer)
```

Replace the `run_codex` comment line:

```
"$SC/run_codex" < prompt > raw 2> err        # Codex seat (pins --profile peer-review, --sandbox read-only)
```

with:

```
"$SC/run_codex" < prompt > raw 2> err        # Codex seat (pins --profile panel-review, --sandbox read-only; auto-creates the profile)
```

- [ ] **Step 5: for-agent SKILL — "full panel" definition and non-negotiable**

Replace:

```
A "full panel" = all seats `preflight` reported available (Gemini may be absent → 2-way). An
```

with:

```
A "full panel" = every seat `preflight` reported available (either peer may be absent → run with the rest). An
```

Replace the Codex non-negotiable bullet:

```
- ✅ `run_codex` pins `--sandbox read-only` + `--profile peer-review` (never `-m`). **Never** create,
  edit, or delete `~/.codex/config.toml` or any `~/.codex/*.config.toml`.
```

with:

```
- ✅ `run_codex` pins `--sandbox read-only` + `--profile panel-review` (never `-m`); it auto-creates
  `~/.codex/panel-review.config.toml` from the shipped default. **Never** hand-create, edit, or delete
  `~/.codex/config.toml` or other `~/.codex/*.config.toml` profiles yourself.
```

- [ ] **Step 6: referee agent — mandatory-contract line**

In `agents/panel-review-referee.md`, replace:

```
  calls; `run_codex` profile/sandbox pinning; the `~/.codex/*.config.toml` ban; `index.json` written
  only via the `index`/`sweep` scripts; cards only via `project_card`/`regen_cards`; graceful
  2-way degrade). They live in `panel-review-for-agent`; do not restate or override them here.
```

with:

```
  calls; `run_codex` profile/sandbox pinning; the `~/.codex/config.toml` hand-edit ban — run_codex
  owns its own `panel-review.config.toml`; `index.json` written only via the `index`/`sweep` scripts;
  cards only via `project_card`/`regen_cards`; graceful degrade when any peer seat is down). They live
  in `panel-review-for-agent`; do not restate or override them here.
```

- [ ] **Step 7: init SKILL — preflight comment and profile-ownership note**

In `skills/panel-review-init/SKILL.md`, replace:

```
"$SC/preflight"   # core (codex/jq/profile) hard checks + summarizer/login/agy status; last line GEMINI: yes|no
```

with:

```
"$SC/preflight"   # hard: jq/git/work-tree/writable-cwd + ≥1 peer (codex or agy); soft: codex login; tail lines CODEX: yes|no / GEMINI: yes|no
```

Replace:

```
- The Codex profile files are owned by `/codex-peer-review init` — do **not** write them
  here; if `~/.codex/peer-review.config.toml` is missing, point the user there.
```

with:

```
- Panel Review owns its Codex profile `~/.codex/panel-review.config.toml`; `run_codex` auto-creates
  it from `skills/panel-review/assets/default-panel-review.config.toml` on first use — nothing to set
  up by hand. (Upstream `/codex-peer-review init` owns the separate `peer-review` profile; the two no
  longer share config.)
```

Replace:

```
- A missing `agy` is reported as `GEMINI: no`, not a failure — the review still runs 2-way.
```

with:

```
- A missing `agy` or `codex` is reported as `GEMINI: no` / `CODEX: no`, not a failure as long as one
  peer remains — the review runs with the seats present. Only zero peers is a hard failure.
```

- [ ] **Step 8: Verify the sweep and commit**

Run these greps; each must print nothing (old phrasings gone):

```bash
grep -rn "2-way (Claude + Codex)\|--profile peer-review\|owned by \`/codex-peer-review init\`\|runs 2-way" README.md skills/panel-review-for-agent/SKILL.md skills/panel-review-init/SKILL.md agents/panel-review-referee.md
grep -rn "peer-review-summarizer" skills/ agents/ README.md
```

Expected: no output from either (the only legitimate remaining `peer-review` mentions are the upstream-decoupling notes you just wrote, which say "peer-review profile" — confirm by reading them).

Then commit:

```bash
git add README.md skills/panel-review-for-agent/SKILL.md skills/panel-review-init/SKILL.md agents/panel-review-referee.md
git commit -m "docs: symmetric optional peers; panel-review profile; CODEX/GEMINI status"
```

---

## Notes for the implementer

- The `~/.codex/panel-review.config.toml` created during Task 2's test is restored/cleaned by the test's `trap`. If you ran a real review in between, your machine may have a genuine one — that's fine, the test backs it up and restores it.
- Do not touch the debate/consensus scripts (`index`, `sweep`, `parse_block`, etc.). A down Codex seat already flows through `parse_block` exit 4 → "≥2 engaged" degradation; no logic change is needed there.
- Line numbers in this plan may have drifted; anchor edits on the quoted old text, not the line number.
