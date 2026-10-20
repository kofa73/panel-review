# Executable contract ownership

This index names the authoritative owner for each executable invariant. Consumers may explain why an
interface matters, but must reference its owner rather than restating its fields, transition rules,
or helper internals.

| Invariant | Authoritative owner | Consumers |
|---|---|---|
| Seat blocks, fields, stance values, normalization, and phase cardinality | `scripts/seat_contract.py` | `parse_block`, `write_seat_raw`, `sweep`, `decide_round`, and rendered prompts produced by `round` |
| Shared Python issue/evidence predicates, fence extraction, and debate stance-integrity checks | `scripts/panel_common.py` | `birth_index`, `parse_block`, `extract_block`, `decide_round`, and `decide_degraded_round` |
| Review phases and referee judgment points | `skills/panel-review-for-agent/references/protocol.md` | the bootstrap skill and referee agent load or reference the active phase |
| Round-0 configured-panel/prompt freezing, attempt history, complete-seat checkpoint recovery, selective retry/resume dispatch, and final Process-note facts | `scripts/round prepare-round0`, `scripts/round collect-round0`, and `scripts/round verdict-input` | the referee protocol supplies current availability plus the explicit initial/`--retry`/`--resume` attempt kind, dispatches only returned non-null Agent inputs, and synthesizes from the returned attempt/final-status summary |
| Mechanical issue transitions and state mutation | `scripts/decide_round`, `scripts/decide_degraded_round`, `scripts/merge_payload`, `scripts/index`, and `scripts/sweep` | `scripts/round` invokes these internal interfaces; the normal debate protocol does not |
| Commit payload keys and merge-shape validation | `scripts/merge_payload` | `scripts/round` owns the transaction boundary; `scripts/check_contracts` probes rejection behavior and the protocol supplies only the referee's judgment addendum |
| Normal debate decision/addendum/commit transaction | `scripts/round commit` | the protocol supplies only the referee's judgment addendum; `round` owns validation, merge, atomic payload installation, sweep commit, and card regeneration |
| Review-profile validation, snapshot, metadata, and seat-facing reference | `scripts/stage_review_profile`, `scripts/init_run`, and `scripts/round` | command skills select only the source path; prompts consume the validated saved-profile reference |
| User config schema, selector resolution, new-run defaults, saved setting updates, and action-time cleanup policy | `scripts/user_config.py` | `init_run` resolves new runs; `set_limits` updates saved runs; `round` reads saved timeouts; `cleanup` and `discard` read current retention policy |
| Uncommitted-scope divergence snapshot and path diagnostics | `scripts/scope_diagnostics` | `scripts/init_run` records the baseline; `scripts/inspect_run`, `scripts/resume_check`, and `scripts/round` report current differences while retaining the hash gate |
| CLI-seat execution and completion signal | `scripts/await_seats` and `agents/panel-review-cli-barrier.md` | `round` prepares the invocation and clears the previous signal, so the barrier's sentinel is absent when it starts; the protocol passes its paths and consumes `await_seats_rc` |
| Referee-owned origin records | `scripts/write_card` | the protocol installs origin records atomically; card files go through `project_card` or `regen_cards` |
| Verdict persistence and delivery classification | `scripts/write_verdict_artifact`, `scripts/read_verdict_artifact`, and `scripts/index delivery-status` | the protocol invokes persistence; command skills consume validated delivery text |
| Claude-seat return statuses | `prompts/claude_delivery.tmpl` | the Claude-seat agent references the delivery contract; the hook validates `SubagentHandback` in auto mode and the final response in other modes |
| Referee-to-command return statuses | `skills/panel-review-for-agent/SKILL.md` | the referee agent references this return contract; the hook validates `SubagentHandback` in auto mode and the final response in other modes; command skills validate the artifact independently |
| Agent status-stub runtime gate | `hooks/hooks.json` and `hooks/enforce_agent_status_stub` | Claude Code invokes the hook on `SubagentHandback` and `SubagentStop`; the script scopes checks to the Claude-seat and referee Agent types, allows at most one invalid hand-back denial per subagent, and substitutes a fixed failure stub when further denial is unsafe |
| Agent identity, context isolation, and role limits | the corresponding file under `agents/` | prompts and protocol instructions do not redefine agent identity |
| Review-session startup mode, preflight, and marker notice | `bin/panel-review-session` | `install.sh` links the launcher for skills-directory installs; `README.md` documents direct use and the marketplace fallback |
| Public behavior and operator guidance | `README.md` | explanatory only; never used as machine validation |

`scripts/check_contracts` verifies the machine-readable seat contract, rendered prompt variants,
Round-0 retry/resume call shapes, Claude-specific block ownership, command dispatch shapes, inline
and fenced transaction ownership, status-stub boundaries, model-pin form, and session-launcher
ownership. Its checks cover structural and executable invariants.
