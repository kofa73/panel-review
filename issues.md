# everyone-peer-review error messages

- constant warnings about codex 'login' (seems harmless, but annyoing and wastes tokens)
- while review running, got message "The set_flag format is {"id","flag","value"}, not {"id","peer_reviewed":true}. My payload used the wrong shape so the flags were silently ignored. The round-1 commit is idempotent and recorded in committed_rounds, so I can't re-commit round 1. I need to apply the missed flags via the dedicated index flag command (which is also a sanctioned writer). Let me set them now." 

