# Correct repository documentation

Priority: 6

Status: Completed

Source: former `pending.md` item 13, refreshed against the live tree on 2026-07-18

## Problem

The original ticket predates the implementation of issues 01–05, 13, and 14. Some of its named
inventory work has already landed, but later changes introduced or exposed other documentation
drift. The maintained repository documentation does not yet give one accurate account of the
current low-severity gate, salvage path, normal debate transaction, plugin components, test suite,
and tracked-tree trust boundary.

This is a documentation-correction task. It must describe the settled executable behavior without
creating another normative copy of contracts already owned by `CONTRACTS.md`,
`scripts/seat_contract.py`, the canonical protocol, or the transition scripts.

## Verified pre-implementation drift

### `AGENTS.md`

- The Python-script inventory already includes `round`, `write_seat_raw`, and
  `read_protocol_phase`, along with the other current Python entry points. That original requirement
  is complete and should not be repeated as pending work.
- The non-obvious-facts section still says `run_seat` performs a repair that overwrites the raw file.
  The live `run_seat` explicitly does not repair. CLI shape salvage is referee-owned; debate salvage
  is installed from the canonical `.salvaged` side file through `round salvage-debate`, while a
  failed Claude delivery is retried or dropped because `write_seat_raw` validates before install.
- The file repeats its issue-tracker, triage, and domain-doc navigation block at both the beginning
  and end.
- Its test guidance names only part of the executable-contract surface and omits the newer protocol,
  artifact, raw-writer, coarse-round, and status-hook seams.
- “The code under review is never modified” overstates what `repo_guard` provides. Seats have broad
  write/execute permissions; the behavioral rule forbids tracked-tree edits, and `repo_guard`
  detects and restores honest tracked drift after a pass. It is not preventive confinement and does
  not protect untracked files or the rest of the machine.

### `README.md`

- The user-facing low-severity description and the “only remaining `AskUserQuestion`” design note
  describe only the Round-0 gate. The canonical protocol reapplies the same stop decision after each
  committed debate round when all remaining open issues are low and `debate-low` is false.
- The component table calls `skills/panel-review-for-agent/SKILL.md` the full procedure. It is now a
  bootstrap/return-contract skill that lazily loads marked phases from
  `skills/panel-review-for-agent/references/protocol.md`. The table also omits that canonical protocol
  file and `agents/panel-review-cli-barrier.md`.
- The install inventory omits `CONTRACTS.md`, although `install.sh` copies it. The prompt inventory
  names `blind_pass.tmpl` and `debate.tmpl` but not the transport-only `claude_delivery.tmpl`.
- The wrapper/component inventory has no entry for the shared `_panel_common.sh` and
  `panel_common.py` libraries even though it presents itself as the maintainer-facing script map.
- “Read-only by construction” and repeated “never modified” wording conflict with the documented
  broad-permission/disposable-container trust model. The README must distinguish the seat instruction
  from the after-the-fact tracked-tree restore mechanism and its limits.
- The early graceful-degradation summary implies that the engaged set is always Claude plus a peer.
  The configured run starts with Claude plus at least one available peer, but engagement is per pass;
  any two seats may form the normal quorum, and a 0–1-seat pass follows the degraded terminal path.

### `CONTEXT.md`

- `Low-severity gate` is defined only as a decision after Round 0. It also applies after every
  committed debate round.
- `Finished review` is defined only as a run with no open issues. An explicitly finalized low-only
  gate is also finished even though its low issues remain open in the final artifact snapshot.
- The `Consensus` and `Quorum` definitions should be jointly explicit that unanimity among fewer than
  two engaged seats cannot settle an issue.

### `.claude/rules/scripts.md`

- The `merge_payload` entry still explains its error behavior in terms of the referee skill's former
  `> tmp && mv tmp payload` sequence. Issue 14 removed that normal-path sequence: `round commit
  --addendum` now owns validation, guarded merge, atomic payload installation, commit, and card
  regeneration.

### `tests/README.md`

- The detailed Python-suite inventory has no dedicated coverage entry for
  `test_agent_status_hook.py`, `test_check_draft.py`, `test_verdict_artifact.py`, or
  `test_write_seat_raw.py`.
- `test_round.py` is mentioned only as part of instruction rendering, omitting its coarse
  prepare/collect/salvage/commit, changed-panel resume, judgment-addendum, and failed-addendum
  transaction coverage.
- Existing summaries should be checked against every live `tests/python/test_*.py` module and the
  current bash sections rather than patched only for the four known omissions. In particular,
  document the artifact `delivery-status`/low-gate cases, the status-hook packaging checks, and the
  issue-14 normal-debate ownership regression.

### Current-looking historical material

- `example_self_review.md` presents a pre-artifact-delivery transcript as a current “example”: it
  uses the retired command shape, returns the verdict body through the main conversation, and
  describes obsolete sandbox and implementation behavior. Either replace it with a current actual
  example or label/move it unambiguously as a historical transcript. Do not mechanically rewrite a
  captured transcript and imply that the edited text was actual output.

## Required outcome

1. Correct `AGENTS.md`, remove its duplicated navigation block, and keep its script/test inventory
   synchronized with the live filesystem.
2. Correct the README's public gate behavior, trust-boundary wording, architecture/component map,
   installation inventory, and per-pass engagement description. Refer to executable owners instead
   of copying their schemas or transition tables.
3. Correct the three `CONTEXT.md` definitions above while keeping that file a glossary rather than a
   protocol manual.
4. Correct `.claude/rules/scripts.md` so its normal debate transaction description agrees with
   `CONTRACTS.md` and the live `round commit --addendum` path.
5. Bring `tests/README.md` up to date with every current Python test module and the actual bash-suite
   sections. Summaries may group closely related tests, but no module should be invisible and no
   summary should claim coverage the suite does not provide.
6. Resolve `example_self_review.md` as a current example or an explicitly historical artifact.
7. Recheck the changes delivered by issues 01–05, 13, and 14 across the maintained documentation;
   keep their accurate current text and correct only remaining contradictions or missing routing.

## Scope boundaries

- `docs/superpowers/`, `design-notes/`, completed issue records, and
  `issues/referee-context-cost-history.md` are historical/design evidence. Do not rewrite
  their past-tense claims to match current code. Their consolidation and archival treatment belongs
  to issue 07.
- Do not add behavior changes, new security controls, or compatibility aliases under this ticket.
- Do not turn README, `AGENTS.md`, or `CONTEXT.md` into another executable schema. Normative ownership
  remains in `CONTRACTS.md` and the owners it names.
- Do not add brittle source-phrase checks for ordinary descriptive inventories. Automated checks are
  appropriate only for repeated wording that could route an agent onto an obsolete executable path
  or materially misstate a contract.

## Verification

- Compare the documented script, hook, agent, prompt, and test inventories against `find`/`rg --files`
  output from the live tree.
- Check low-gate and finalization wording against `index gate-status`, `round commit`,
  `write_verdict_artifact --final`, `read_verdict_artifact --delivery`, the canonical `gate` phase,
  and their tests.
- Check salvage wording against `run_seat`, `round salvage-debate`, `write_seat_raw`, and the
  canonical `salvage`/`debate` phases.
- Check normal debate ownership against `CONTRACTS.md`, `round commit --addendum`, and the issue-14
  protocol/contract tests.
- Run `scripts/check_contracts --root .`, the documentation/contract-focused tests, the full
  `./tests/run_tests.sh` suite, and `git diff --check`.
- Review the final documentation diff for contradictions between README, `AGENTS.md`, `CONTEXT.md`,
  `CONTRACTS.md`, `.claude/rules/scripts.md`, and `tests/README.md`.

## Implementation

Completed 2026-07-18 as a documentation-only change:

- `AGENTS.md` now describes referee-owned CLI salvage, the tracked-tree restoration boundary, the
  current test surfaces, and the four participant roles without duplicating its navigation block.
- `README.md` now describes the low-severity gate after Round 0 and committed debate rounds, separates
  configured seats from per-pass engagement, accurately states the broad-permission trust boundary,
  and inventories the bootstrap, canonical protocol, CLI barrier, Claude delivery template,
  `CONTRACTS.md`, and shared script libraries.
- `CONTEXT.md` now defines quorum-qualified consensus, both low-gate decision points, and explicit
  low-gate finalization while remaining a concise glossary.
- `.claude/rules/scripts.md` now assigns the normal addendum merge and transaction to
  `round commit --addendum` rather than the retired referee-side temporary-file sequence.
- `tests/README.md` now names all 13 Python test modules and describes the current coarse-round,
  artifact-delivery, raw-writer, status-hook, and transaction-ownership coverage.
- `example_self_review.md` is explicitly labeled as a historical 2026-06-20 transcript rather than
  current operating documentation.

No runtime code, prompt contract, plugin manifest, marketplace metadata, or plugin version changed.

## Completed verification

- Live script, hook, agent, prompt, and test inventories were compared with the maintained docs; all
  13 `tests/python/test_*.py` modules are named in `tests/README.md`.
- `scripts/check_contracts --root .`: `instruction contracts: OK`.
- `./tests/run_tests.sh`: `PASS: 223`, `FAIL: 0`.
- `git diff --check`: passed.
