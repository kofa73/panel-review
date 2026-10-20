# Evaluate new agy CLI capabilities for the Gemini seat

Priority: 23

Status: Optional

Source: external CLI update review (agy 1.1.6 → 1.1.10), 2026-08-05

Triage: ready-for-human

## Problem

agy gained four flags since `run_agy`'s contract was written. None is required, two are plausible
robustness wins against failure modes this repository has already hit, and one should be explicitly
declined so it is not adopted later "for safety". Recording the evaluation prevents the same
analysis being redone at the next CLI update.

## Candidates

### `--disable-slash-commands` — cheap hardening, probably adopt

agy 1.1.9 made print mode expand slash commands *and skills* found in the prompt, with this flag to
opt out. 1.1.9 also widened recognition to commands separated from their arguments by a newline or
tab.

Panel-review feeds its prompt on stdin and every template starts with plain prose, so today's
exposure is low. It is not zero: the prompt carries a diff and card text the plugin does not control,
and the failure would be silent — an expanded command changes what the seat reviews without changing
what the referee thinks it sent.

Open question before adopting: confirm that stdin-fed prompts (no `--print`) go through the same
expansion path as `-p`. If they do not, the flag is a no-op and can still be passed as insurance
against that changing.

### `--add-dir <dir>` — test before adopting

`AGENTS.md` records that agy runs tools inside its own managed sandbox and *guesses* the repository
root each run, which `cd` cannot influence; the mitigation is an absolute path anchor plus an
explicit "set the tool `cwd`" directive in the prompt. `--add-dir` adds a directory to the workspace
and is a mechanical anchor rather than a prompt instruction.

Verified 2026-08-05 (agy 1.1.10, small prompt, existing prompt anchor only): the seat reported `pwd`
= the workdir and ran `git status --short` and `git diff --stat HEAD~1` successfully, so the current
mitigation works at that prompt size. The known drift case was a very large prompt.

Test to run before adopting: a deliberately large prompt with and without `--add-dir`, checking
whether the flag changes the sandbox's root guess. Adopt only if it does — an inert flag in a
wrapper that documents every flag's reason is worse than none.

### `--output-format json` + `--json-schema` — recommend against

Structured output would attack the known prose-not-JSONL failure directly. It is still the wrong
trade here: all three seats deliver the same fenced-block contract to `parse_block`, and making one
seat's transport different adds an envelope-unwrapping step, a second parse path, and a second place
for `seat_contract.py`'s schema to drift. The existing mitigations (lean prompts, salient contract,
`check_draft`, referee salvage) address the same failure without splitting the contract.

Reconsider only if prose-without-fence recurs after prompt-size control.

### `--sandbox` — decline, and say why

agy now exposes an opt-in sandbox with terminal restrictions. Panel-review deliberately runs the
seat unconstrained (`--dangerously-skip-permissions`) because safety rests on the disposable
container plus `repo_guard`, and because a sandboxed seat cannot run the tools the review asks for —
the same lesson `run_codex` already records. Worth one line in the `run_agy` header so it is not
added later as an apparent improvement.

Related, no action: agy 1.1.10 made `.git` read-only inside its terminal sandbox. Verified above
that read-only git commands still work; only a write-touching command (`stash`, `worktree`, `gc`)
would fail, and no prompt asks a seat for one.

## Expected outcome

A decision recorded per candidate, and for each adopted flag a `run_agy` header entry explaining why
it is there — matching the existing convention that every flag in that wrapper carries its rationale.

## Verification

- Any adopted flag is exercised by one real review with the Gemini seat engaged.
- `--add-dir` is adopted only with the large-prompt comparison recorded in this file.
- `scripts/check_contracts --root .` and `./tests/run_tests.sh` pass.

## Non-goals

- Do not change the Gemini seat's output contract or `parse_block`'s interface.
- Do not adopt `--effort` (see issue 20).
- Do not add flags whose effect has not been observed on this machine.

## Comments

### 2026-09-05 — flag surface to triage on agy 1.1.27

The recorded baseline is 1.1.18; installed is 1.1.27. `agy --help` on 1.1.27 shows these flags,
which need a recorded decision each in the table above (some may predate 1.1.18 and already have
one — check before re-analysing):

| Flag | Why it might matter here |
|---|---|
| `--disable-slash-commands` | Would make the seat prompt immune to accidental leading-command expansion — and would break `issues/60`. The two must be decided together; `issues/61` owns the question. |
| `--json-schema <schema>` | "Enforce structured output". The seat contract is exactly a structured-output contract enforced today by prose plus `parse_block`. If this binds, it is the strongest available answer to the prose-not-JSONL failure mode recorded in `AGENTS.md`. Highest-value candidate in this list. |
| `--output-format json` / `stream-json` | Would give a machine-readable envelope instead of raw stdout, and (1.1.27) carries `denied_actions`. Changes what `run_seat` and the fence scan parse; see `issues/61`. |
| `--input-format stream-json` | Not needed — the panel sends one prompt per pass. |
| `--mode accept-edits\|plan` | `plan` is a read-only-ish posture that may suit a reviewer seat better than `--dangerously-skip-permissions`. Measure whether a plan-mode seat can still run its read tools. |
| `--sandbox` | "Run in a sandbox with terminal restrictions enabled". Reconcile with the no-security-theatre rule: this is a real host control, not a seat-cooperative one, so it is admissible — but it may block the seat's tool use. |
| `--add-dir` | Could scope what the seat can reach. Note the trust model: seats are unconstrained by design, so treat this as convenience, not a control. |
| `--agent`, `--effort` | `--effort` remains ruled out by `issues/20` (effort rides in the model label). `--agent` would let the seat run under a named agent definition instead of a long inline prompt. |

Also new in the unreviewed range and worth noting even though they are not flags: an **embedded
`ripgrep`** replaces whatever the machine provides (1.1.21), so seat search behavior no longer
varies with the container's tooling; and **`always-proceed` now auto-approves MCP tool calls**
(1.1.21), which is the mode the tilth MCP server runs under.

### 2026-10-19 — flag surface on agy 1.4.2

New or changed since the 1.1.27 table above:

| Flag / behavior | Version | Why it might matter here |
|---|---|---|
| `--mode auto` | 1.3.5 | Auto mode: approves edits and "safe" commands, and a separate agent reviews commands that would leave the terminal sandbox. It adds a second model deciding what the seat may run, the same objection as Codex's `--approve-for-me` in `issues/28`. Expected decision: decline. |
| `--effort low\|medium\|high\|xhigh\|max` | 1.2.11 | Still ruled out while the label form is the pin contract (`issues/20`). Combined with 1.3.4 (`--model` takes a base name), it is a possible second contract. Decide in `issues/63`, not here. |
| `--json-schema` | 1.2.14 | Now rejects plain text, bare type names, missing files and a non-object root at startup with exit 1. That makes a bad schema fail loudly, which helps if this candidate is ever adopted. |
| `--log-file` | in 1.4.2 `--help` | Per-run CLI log path. Makes the model-binding line attributable to one attempt. Candidate mechanism for `issues/63` item 4. |

Not flags, but they change what the seat runs with:

- **1.2.7** retired the legacy `find_by_name`, `grep_search` and `list_dir` tools from the default
  toolset. The panel's prompts do not name them (checked 2026-10-19).
- **1.2.16** loads `skills.json`, `rules.json` and other manifests from every `.agents/` directory
  between the working directory and the project root, and 1.2.10 made directory entries non-recursive.
  The reviewed repository's own agy customizations reach the Gemini seat. This is the same family as
  `issues/47` (the reviewed repository configures the seat that reviews it). It is not new, but it
  now covers more files.
- **1.1.28** changed the default permission for fetching URLs to "ask". Under
  `--dangerously-skip-permissions` there is no prompt, but if a fetch is ever denied, see
  `issues/61` item 1.
