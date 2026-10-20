# Rejected simplification proposals from the 2026-08-16 panel

Priority: 54

Status: Closed

Source: Simplification panel (Opus, Sol, Gemini Pro, Gemini Flash), 2026-08-16 — recorded so the same
proposals are not re-derived and acted on at the next pass

Triage: wontfix

## Purpose

Four independent reports proposed simplifications. Issues 41-53 carry the ones that survived
evaluation. This file records the ones that did **not**, with the reason, because three of them are
the obvious-looking move that a fresh reader will propose again.

## Rejected

**1. Remove `repo_guard` and rely on `git reset --hard`.** (Gemini Pro §3.1)

`repo_guard verify --restore` runs after *every seat pass*, inside a run whose whole point is that
three unconstrained models touch the tree. A manual reset afterwards cannot tell which pass caused
the drift, and cannot report it in the verdict's Process notes. Seats have made honest tracked-tree
edits in real runs. Separately, issue 33 records a real defect in the restore path — that is a reason
to fix it, not to delete the guard.

**2. Remove the `SubagentStop` status-stub hook and regex the status out of the prose instead.**
(Gemini Pro §3.2, Gemini Flash §2.3)

Both reports argue that the on-disk file is authoritative, so the return text does not matter. It
does: the return text lands in the *referee's context*. Issue 13 records a real run where a seat
returned forbidden prose and raw content. The hook is documented as bounded conformance enforcement,
not a security boundary, which is the correct claim and the right target class under ADR-0005 —
honest model confusion. Keep it, and keep describing it as context hygiene.

**3. Unify `/tmp/<ID>/` and `<workdir>/.panel-review/<ID>/` into one directory.** (Gemini Flash §2.2)

The split is load-bearing in both directions. `/tmp/<ID>.md` is a *sibling* of the run directory
precisely so cleanup and discard cannot eat the verdict. Cards live under the workdir so a seat in a
constrained workspace can still read them. And issue 24 is moving state in the opposite direction —
seat scratch **out** of the workdir — because in-workdir state is searchable by other seats and
breaks blindness. Unifying into `.panel-review/` would re-create the exact leak issue 24 exists to
close.

**4. Rewrite the 38 scripts as one Python package.** (Gemini Flash §4.1)

The estimate ("60% reduction, ~3,500 lines removed") is not supported by anything in the report, and
the proposal misidentifies the problem. The reliability cost is model-visible procedural surface, not
process count — which is why issues 51 and 52 move *boundaries* rather than merging modules. A
rewrite would also discard the incident regressions that make the current suite worth having.

**5. Remove `check_contracts` and the Python suites because a hobby project can debug manually.**
(Gemini Pro §3.4, Gemini Flash §4.3)

Rejected outright. Issue 46 removes the checks that assert on English *wording*; the functional
suites and every incident regression stay. The two proposals are not the same thing and should not
be conflated.

**6. Replace the CLI barrier with a `bash wait` or a manual collection step.** (Gemini Pro §3.3)

Issue 15 measured what the referee-side wait cost: 279 wait polls, 432 model calls, ~52 M cache-read
tokens. A foreground Bash call cannot cover a 40-minute seat, and a referee-backgrounded Bash job
does not wake the referee — only an Agent return does. The 26 × 100 s loop looks wasteful and runs in
a tiny Sonnet context. Do not simplify `await_seats` back into per-seat dispatch either.

## Also do not simplify

Recorded from the same reports so a later pass does not undo them:

- `run_agy`'s stdin-with-no-bare-`--print` invocation and its exact display-label pins (issue 20).
- `run_codex --dangerously-bypass-approvals-and-sandbox` — see issue 47's non-goals for the one
  probe that could change this, and why documentation review alone cannot.
- `await_seats` running both CLI seats in one job.
- The `.out`-published-last completion marker and the fail-closed corrupt-checkpoint rule in `sweep`.
- `round0.attempts.json` and the frozen `round0.panel.json` — why a resume cannot destroy a completed
  blind pass.
- `write_seat_raw`'s validate-before-install, and `check_draft` as a thin wrapper over
  `parse_block --diagnose` with no second schema.
- `disable-model-invocation: true` on the four mutating skills and `user-invocable: false` on the
  preloaded bootstrap. These are **not** interchangeable: `disable-model-invocation` also blocks
  preloading a skill into a subagent, which would break the referee (issue 22 §4).
- The fresh non-fork Claude seat, and the installer's shadow warning for higher-precedence agent
  files.

## Two runtime facts worth recording once

Neither needs code. They belong in issue 22's record, or in `docs/agent-runtimes.md` when issue 53
creates it:

- **Subagent output scanning** (Claude Code 2.1.210+): the harness prepends a marker line to a
  subagent's final report when it mentions `bypassPermissions` / `--dangerously-skip-permissions`,
  and inserts backslashes into text imitating harness tags. Panel-review's fixed stubs cannot trigger
  it, and `hooks/enforce_agent_status_stub` reads `last_assistant_message` rather than the scanned
  report — but if a stub ever gains free text, this is where an exact-match gate would break in a way
  that is very hard to diagnose.
- **Model restriction falls back to the parent model** (2.1.223): both agent files pin `model: opus`;
  under an organization restriction the Claude seat silently runs the referee's model. Nothing to
  enforce from inside the plugin.
