# Executable contract ownership

This index names the authoritative owner for each executable invariant. Consumers may explain why an
interface matters, but must reference its owner rather than restating its fields, transition rules,
or helper internals.

| Invariant | Authoritative owner | Consumers |
|---|---|---|
| Seat blocks, fields, stance values, normalization, and phase cardinality | `scripts/seat_contract.py` | `parse_block`, `write_seat_raw`, `sweep`, `decide_round`, and rendered prompts produced by `round` |
| Review phases and referee judgment points | `skills/panel-review-for-agent/references/protocol.md` | the bootstrap skill and referee agent load or reference the active phase |
| Mechanical issue transitions and state mutation | `scripts/decide_round`, `scripts/decide_degraded_round`, `scripts/merge_payload`, `scripts/index`, and `scripts/sweep` | the protocol invokes their interfaces and supplies only required judgment |
| CLI-seat execution and completion signal | `scripts/await_seats` and `agents/panel-review-cli-barrier.md` | `round` prepares the invocation; the protocol passes its paths and consumes `await_seats_rc` |
| Verdict persistence and delivery classification | `scripts/write_verdict_artifact`, `scripts/read_verdict_artifact`, and `scripts/index delivery-status` | the protocol invokes persistence; command skills consume validated delivery text |
| Claude-seat return statuses | `prompts/claude_delivery.tmpl` | the Claude-seat agent references the delivery contract; `hooks/enforce_agent_status_stub` gates the final response |
| Referee-to-command return statuses | `skills/panel-review-for-agent/SKILL.md` | the referee agent references this return contract; `hooks/enforce_agent_status_stub` gates the final response; command skills validate the artifact independently |
| Agent status-stub runtime gate | `hooks/hooks.json` and `hooks/enforce_agent_status_stub` | Claude Code invokes the hook for the Claude-seat and referee Agent types |
| Agent identity, context isolation, and role limits | the corresponding file under `agents/` | prompts and protocol instructions do not redefine agent identity |
| Public behavior and operator guidance | `README.md` | explanatory only; never used as machine validation |

`scripts/check_contracts` verifies the machine-readable seat contract, rendered prompt variants, and
the ownership rules whose earlier drift caused executable contradictions. Narrow source scans remain
only for forbidden legacy wording that would redirect a model to an obsolete interface.
