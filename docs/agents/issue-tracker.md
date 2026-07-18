# Issue tracker: Local Markdown

Issues for this repository live as Markdown files under `issues/`.
`issues/README.md` is the authoritative ordered index.

## Conventions

- One issue per `issues/<NN>-<slug>.md`.
- Numeric identifiers are stable. Use the next unused number for a new issue.
- Execution order is the row order in `issues/README.md`; it may differ from numeric order
  when a later issue has higher priority.
- Every issue has `Priority:`, `Status:`, and `Source:` fields near the top.
- Keep the issue file, its README row, and any corresponding `pending.md` handoff entry synchronized.
- `Status:` records the repository lifecycle: `Pending`, `Deferred`, `Optional`, `Closed`, or
  `Completed`.
- When triage assigns a canonical role, record it separately as `Triage:` using
  `docs/agents/triage-labels.md`.
- Append discussion that must remain with an issue under a `## Comments` heading.
- Feature specifications live under `issues/specs/<feature-slug>.md`. Tickets derived from a
  specification remain ordinary numbered issue files and link back to it with a `Spec:` field.

## When a skill says "publish to the issue tracker"

Create the next numbered issue file and add it to `issues/README.md` in the appropriate
execution-order position. Correctness and executable-contract work precede documentation and
optional work.

## When a skill says "fetch the relevant ticket"

Read the referenced numbered file. If only an issue number is provided, resolve it against
`issues/<NN>-*.md`.

## Wayfinding operations

Wayfinding efforts live under `issues/wayfinding/<effort>/`.

- Map: `issues/wayfinding/<effort>/map.md`.
- Child ticket: `issues/wayfinding/<effort>/issues/<NN>-<slug>.md`.
- Child tickets use `Type: research|prototype|grilling|task` and
  `Status: open|claimed|resolved`.
- Dependencies use `Blocked by: NN, NN`.
- The frontier is the first numbered open, unblocked, and unclaimed child ticket.
- Claim by setting `Status: claimed`.
- Resolve by adding an `## Answer`, setting `Status: resolved`, and recording the result in the
  map's Decisions-so-far section.
