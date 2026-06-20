# everyone-peer-review error messages

- constant warnings about codex 'login' (seems harmless, but annyoing and wastes tokens)
- while review running, got message "The set_flag format is {"id","flag","value"}, not {"id","peer_reviewed":true}. My payload used the wrong shape so the flags were silently ignored. The round-1 commit is idempotent and recorded in committed_rounds, so I can't re-commit round 1. I need to apply the missed flags via the dedicated index flag command (which is also a sanctioned writer). Let me set them now." 
- need a "--continue" flag to allow continuing with unresolved and contested (--continue continues both, --continue unresolved only the latter). new round to start with same limits as main, but counters (per-item and global) start fresh
- should document why we put stuff under /tmp/<ID> (.panel-review/<ID>/issue-<id>.md is mentioned: it's intended to be read by workspace-locked agents - wording should change from "so Codex's read-only sandbox can read them" to more future-proof, other agents may come, and read-only is not the important aspect here, it's visibility)
- no need to actively edit .git/info/exclude: just add .panel-review once, if not there
- the early quit should be applied for all rounds: if only low items remain, the process can stop, no point in burning tokens
