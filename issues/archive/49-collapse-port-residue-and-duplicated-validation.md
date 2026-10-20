# Collapse the remaining jq transliteration, process chain, and duplicated validation

Priority: 49

Status: Completed

Source: Simplification panel (Opus §1.3, §1.5, §5 rows 5-8; Sol "Small removals"), 2026-08-16

Triage: ready-for-agent

## Problem

Five leftovers from the bash→Python port, in one theme: logic that exists twice, or crosses a
language boundary for no reason.

**1. `birth_index` is the last significant jq program.** 119 lines of bash wrapping a two-pass jq
program that re-implements the `valid_point` / `valid_location` predicates in jq, with a comment
saying they are *"identical to parse_block / index commit-sweep so a record birth_index emits always
passes `index put`"* — the file documents its own hand-synchronized duplicate schema. Ported to
Python it becomes roughly 70 lines importing `panel_common.valid_point`, `CATEGORIES` and
`SEVERITIES`, and stops being a second schema. Its tests are black-box (`tests/run_tests.sh`), so
they survive the port unchanged.

**2. A three-process, two-language fence scan.** `check_draft` (Python) spawns `parse_block`
(Python), which spawns `extract_block` (bash + awk) **twice** — for a scan that is about 15 lines of
Python. Each seat runs this several times per pass. Fold the fence scan into `panel_common.py`,
keeping `extract_block` as a thin CLI shim if it is still wanted on the command line. Missing-versus-
empty and duplicate-block behavior must be preserved exactly; that distinction drives parse exit
codes 0/4/5 and the referee's salvage decision.

**3. `parse_block` dead code.** `scripts/parse_block:41-45` is a no-op maze:

```python
if not diagnose and label:
    pass
else:
    label = ""
```

which means `if diagnose: label = ""`. And `parsed_whole` (lines 80, 103) is assigned and never read.

**4. `decide_degraded_round` port residue.** `scripts/decide_degraded_round:79-81`:

```python
source_str = json.dumps(source) if source is None else source
if source is None:
    source_str = "null"
```

`json.dumps(None)` is already `"null"`, so the first line's only reachable branch is immediately
overwritten. Nearby comments quote the spec as "matching the Bash".

**5. Stance-integrity validation implemented twice.** `decide_round` and `decide_degraded_round` each
implement unknown-`_source` detection, exactly-one-stance-per-open-issue, and engaged ⊆ configured,
with different message formatting. One shared helper in `panel_common.py` removes roughly 40
duplicated lines and the risk of the two drifting.

Lower priority, same theme: `jq_raw` / `jq_default` in `scripts/sweep` and `scripts/index` are
jq-emulation shims that make Python read as a transliteration. `jq_default` is
`x if x not in (None, False) else default` and deserves that name.

## Expected behavior

Items 1-5 done as separate commits, each with the existing tests green. Item 2 needs its own
characterization test for the missing/empty/duplicate cases before the move.

## Verification

- `./tests/run_tests.sh` and `scripts/check_contracts --root .` pass after each commit.
- `python3 -m unittest tests.python.test_parse_block -v` (and the draft/round modules) pass.
- One real review completes end to end after item 1 and after item 2.

## Non-goals

- Do not merge the modules behind the boundary into one file. `round`, `sweep`, `decide_round`,
  `merge_payload`, and `index` are separately tested for a reason; a monolith is not easier to reason
  about. This issue removes duplication, not module boundaries.
- Do not change `check_draft` into its own validator. It is deliberately a thin wrapper over
  `parse_block --diagnose` so there is no second schema.

## Resolution

Ported `birth_index` to Python and shared the issue/evidence predicates, moved fence scanning into
`panel_common.py` while retaining `extract_block` as a CLI shim, removed the parser's dead state, and
centralized stance-integrity checks without changing their diagnostics. Added characterization and
ownership tests, updated script documentation, and bumped the plugin to 1.0.40. The lower-priority
`jq_raw` / `jq_default` naming observation was not part of the five specified deliverables and remains
unchanged.
