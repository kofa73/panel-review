# Clarifications

Notes captured while walking through the everyone-peer-review flow. To be folded into the README later.

- **"Limits"** (as in "parse scope + limits") = the two debate-round caps:
  - `issue-rounds` — per-issue debate threshold (default 2): how many sweeps a single issue is debated before it's forced terminal.
  - `max-rounds` — global ceiling (default 4): total debate sweeps for the whole run.
  Both are validated as positive integers with `issue-rounds <= max-rounds`. They bound the debate loop so it always terminates.

- **`resolve_diff`** — turns the scope into the actual diff text to review. For the three git-backed scopes it returns: code changed since `base=BRANCH`, the contents of `commit=SHA`, or the current `uncommitted` changes (staged + unstaged + new files). For a free-text `question` scope there's no diff — it returns empty.

## TODO (rewrites for the README)

- Write proper per-file descriptions for the state/data files, each with a concrete **example** that explains its structure and content in plain language. Files to cover include at least: `manifest.json`, `index.json` (and one issue record), a blind card (`issue-<id>.md`), a round payload (`payload.<round>.json`), a seat's `findings`/`stances` block, and the marker file (`.epr-run`). (User will run a real 3-way review to collect actual samples to use here.)

- Document the diff/hash procedure readably. The README currently only has a one-line table entry for `diff_hash`; the actual flow — **resolve the scope into the diff, hash that diff, store the hash in the manifest, then recompute and compare it on resume to detect that the code changed** — is never written out as a step. Add it as prose or a clear step list. Avoid arrow-chain shorthand that mixes scripts, data, and shell variables on one line. (Hash algorithm is an implementation detail — leave it out of the user guide.)
