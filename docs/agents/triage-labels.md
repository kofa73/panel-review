# Triage Labels

The engineering skills use five canonical triage roles. Local Markdown issues record the selected
role in an optional `Triage:` field.

| Canonical role | Local value | Meaning |
|---|---|---|
| `needs-triage` | `needs-triage` | Maintainer needs to evaluate the issue |
| `needs-info` | `needs-info` | Waiting on the reporter for more information |
| `ready-for-agent` | `ready-for-agent` | Fully specified and ready for an autonomous agent |
| `ready-for-human` | `ready-for-human` | Requires human implementation or judgment |
| `wontfix` | `wontfix` | Will not be actioned |

When a skill mentions a triage role, use the corresponding value from this table. Do not replace
the issue's repository lifecycle `Status:` field.
