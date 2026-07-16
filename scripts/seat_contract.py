#!/usr/bin/env python3
"""Authoritative seat-output contract for prompt rendering and runtime validation."""

import argparse
import json
import re

from panel_common import CATEGORIES, SEVERITIES, valid_location, valid_point


STANCE_VALUES = ("support", "reject")
PHASES = {
    "round0": {
        "required_blocks": ("findings",),
        "cardinality": {"findings": "zero_or_more"},
    },
    "debate": {
        "required_blocks": ("stances", "new_findings"),
        "cardinality": {
            "stances": "one_per_card",
            "new_findings": "zero_or_more",
        },
    },
}

FINDING_EXAMPLE = {
    "claim": "<one-sentence statement of the defect>",
    "location": "src/foo.py:42",
    "severity": "high",
    "category": "correctness",
    "points": [
        {
            "location": "src/foo.py:42",
            "assertion": "<one concise technical fact>",
            "precondition": "<optional: when it triggers>",
            "impact": "<optional>",
        }
    ],
}

STANCE_EXAMPLE = {
    "id": "i1",
    "stance": "support",
    "rationale": "<optional technical reason for a revision>",
    "revision": {
        "severity": "high",
        "location": "src/foo.py:42",
        "category": "correctness",
        "claim": "<optional corrected one-sentence claim>",
    },
    "new_evidence": {
        "location": "src/foo.py:42",
        "assertion": "<optional one new technical fact>",
        "precondition": "<optional>",
        "impact": "<optional>",
    },
}


def compact_json(value):
    return json.dumps(value, separators=(",", ":"), ensure_ascii=False)


def ok_object(obj):
    return isinstance(obj, dict)


def ok_claim(obj):
    return isinstance(obj.get("claim"), str)


def ok_location(obj):
    return "location" in obj and valid_location(obj["location"])


def ok_category(obj):
    return isinstance(obj.get("category"), str) and obj.get("category") in CATEGORIES


def ok_severity(obj):
    return isinstance(obj.get("severity"), str) and obj.get("severity") in SEVERITIES


def normalize_points(obj):
    points = obj.get("points", [])
    if isinstance(points, list):
        return [point for point in points if valid_point(point)]
    if valid_point(points):
        return [points]
    return []


def ok_points(obj):
    return len(normalize_points(obj)) > 0


def ok_id(obj):
    return isinstance(obj.get("id"), str)


def ok_stance(obj):
    return isinstance(obj.get("stance"), str) and obj.get("stance") in STANCE_VALUES


def ok_reject_rationale(obj):
    return obj.get("stance") != "reject" or (
        isinstance(obj.get("rationale"), str) and bool(obj["rationale"].strip())
    )


def diag_findings(obj):
    if not ok_object(obj):
        return "not a JSON object"
    if not ok_claim(obj):
        return "missing or non-string field `claim`"
    if not ok_location(obj):
        return 'missing/invalid `location` (a non-empty "file:line" string, or an array of such)'
    if not ok_category(obj):
        return "missing/invalid `category` (one of: security, correctness, performance, maintainability, style)"
    if not ok_severity(obj):
        return "missing/invalid `severity` (one of: critical, high, medium, low, style)"
    if not ok_points(obj):
        return "no valid `points[]`: every finding needs a non-empty points array; each point needs a string `assertion` and a valid `location` (do not put precondition/impact at the top level)"
    return "valid"


def valid_findings(obj):
    if ok_object(obj) and ok_claim(obj) and ok_location(obj) and ok_category(obj) and ok_severity(obj):
        points = normalize_points(obj)
        if points:
            obj["points"] = points
            return True, obj
    return False, None


def diag_stances(obj):
    if not ok_object(obj):
        return "not a JSON object"
    if not ok_id(obj):
        return "missing or non-string field `id`"
    if not ok_stance(obj):
        return f"missing/invalid `stance` (one of: {', '.join(STANCE_VALUES)})"
    if not ok_reject_rationale(obj):
        return "reject requires non-empty `rationale` counter-evidence"
    return "valid"


def valid_stances(obj):
    if not (ok_object(obj) and ok_id(obj) and ok_stance(obj) and ok_reject_rationale(obj)):
        return False, None

    if obj["stance"] == "reject":
        obj.pop("revision", None)
    elif "revision" in obj:
        revision = obj["revision"]
        if isinstance(revision, dict):
            normalized = {}
            for key, value in revision.items():
                if key not in {"category", "severity", "claim", "location"}:
                    continue
                if key == "category" and not (isinstance(value, str) and value in CATEGORIES):
                    continue
                if key == "severity" and not (isinstance(value, str) and value in SEVERITIES):
                    continue
                if key == "claim" and not isinstance(value, str):
                    continue
                if key == "location" and not valid_location(value):
                    continue
                normalized[key] = value
            if normalized:
                obj["revision"] = normalized
            else:
                del obj["revision"]
        else:
            del obj["revision"]

    for key in ("new_evidence", "evidence"):
        if key in obj and not (isinstance(obj[key], dict) and valid_point(obj[key])):
            del obj[key]

    return True, obj


def diag_default(obj):
    return "valid" if ok_object(obj) else "not a JSON object"


def valid_default(obj):
    return (True, obj) if ok_object(obj) else (False, None)


def get_rules(tag):
    if tag in ("findings", "new_findings"):
        return valid_findings, diag_findings
    if tag == "stances":
        return valid_stances, diag_stances
    return valid_default, diag_default


def response_problem(raw, phase):
    """Return a parse status/message when a complete response violates block cardinality."""
    if phase not in PHASES:
        raise ValueError(f"unknown seat-contract phase: {phase}")
    expected = PHASES[phase]["required_blocks"]
    known = {tag for value in PHASES.values() for tag in value["required_blocks"]}
    counts = {
        tag: len(re.findall(rf"(?m)^```{re.escape(tag)}[ \t\r]*$", raw))
        for tag in known
    }
    for tag in expected:
        if counts[tag] == 0:
            return 4, f"expected exactly one `{tag}` block, got 0"
        if counts[tag] != 1:
            return 5, f"expected exactly one `{tag}` block, got {counts[tag]}"
    for tag in sorted(known - set(expected)):
        if counts[tag]:
            return 5, f"unexpected `{tag}` block for {phase} response"
    return None


def render_contract(phase, panel_size, check_command):
    """Render the complete seat-facing block contract for one review phase."""
    if phase not in PHASES:
        raise ValueError(f"unknown seat-contract phase: {phase}")
    if panel_size not in (2, 3):
        raise ValueError("panel size must be 2 or 3")

    context = (
        f"The configured panel has {panel_size} reviewer seats, including you. "
        "Seats work independently and never receive origins or stance tallies."
    )
    if phase == "round0":
        return f"""You are performing an independent code review. {context}
You will not see another seat's findings until after this pass. Be neutral, objective, brief,
simple but accurate. Accuracy wins over simplicity. No praise or sycophancy; voice concerns and
point out mistakes.

## Output format (STRICT JSON — malformed lines are discarded)

Emit exactly one fenced block tagged `findings`, JSONL, with zero or more candidate issues. Each
line is one candidate issue in exactly this shape (`severity` is one of
critical|high|medium|low|style; `category` is one of
security|correctness|performance|maintainability|style):

```findings
{compact_json(FINDING_EXAMPLE)}
```

`points` is the evidence FOR the issue, one located fact each. If you find no issues, emit an empty
`findings` block. After the block, write 2-3 sentences on overall quality and your confidence.

## Validate before you emit

A malformed finding is silently dropped downstream. Write the JSONL planned for the fence to a
scratch file and run `{check_command}` with that file path appended. Exit status 0 means every item
is valid. Fix every reported item before emitting. An empty draft is valid when you found nothing.
"""

    return f"""You are continuing a blind peer review in the debate phase. {context}
Be neutral, objective, brief. Ground every stance in the actual code; do not invent.

## Stance output (STRICT JSON — malformed lines are discarded)

Emit exactly one fenced block tagged `stances`, JSONL, with exactly one stance per card, in this
shape (`stance` is one of {'|'.join(STANCE_VALUES)}):

```stances
{compact_json(STANCE_EXAMPLE)}
```

- support — the evidence establishes that the issue exists. A support may include a `revision` when
  severity/location/category/claim needs adjustment; omit fields you do not change. Without a
  revision, support endorses the current field values. Its `rationale` is optional.
- reject — the evidence does not establish the issue. Omit `revision`; `rationale` is required and
  must state the counter-evidence.

`new_evidence` is optional and carries one new located fact for this issue.

Blindness applies to every field: state only technical facts. Never mention another reviewer, the
number or identity of reviewers, agreement, consensus, unanimity, majority, or model/tool names.

## New findings (ALWAYS emit this block)

Emit exactly one fenced `new_findings` block after `stances`, using the same finding contract as
Round 0:

```new_findings
{compact_json(FINDING_EXAMPLE)}
```

A new finding must be a genuinely new defect, not a variation of a card or a confirmation. This
block is required-emptyable: use `[]` or leave it empty when there is no new issue.

## Validate before you emit

A malformed item is silently dropped downstream. Validate the stances JSONL by running
`{check_command}` with the draft path appended. Validate new findings by replacing `stances` in that
command with `new_findings`. Exit status 0 means every item is valid; fix all reported items before
emitting.
"""


def main(argv=None):
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    render = subparsers.add_parser("render")
    render.add_argument("phase", choices=tuple(PHASES))
    render.add_argument("--panel-size", type=int, choices=(2, 3), required=True)
    render.add_argument("--check-command", required=True)
    args = parser.parse_args(argv)
    print(render_contract(args.phase, args.panel_size, args.check_command), end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
