#!/usr/bin/env bash
#
# Installer for the panel-review skill suite.
# Copies the three skills (with their prompts/ and scripts/) and the two agents
# into the user's Claude config dir.
#
# It does NOT remove anything. The previous everyone-peer-review* skills and
# agents stay in the target — delete those yourself after installing.
#
# Target defaults to ~/.claude; override with CLAUDE_DIR=/path ./install.sh
set -euo pipefail

# Repo root = the directory this script lives in, so it works from any cwd.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"

SKILLS_DST="$CLAUDE_DIR/skills"
AGENTS_DST="$CLAUDE_DIR/agents"

SKILLS=(
  panel-review
  panel-review-for-agent
  panel-review-init
)
AGENTS=(
  panel-review-referee
  panel-review-claude-seat
)

echo "Installing panel-review into: $CLAUDE_DIR"
mkdir -p "$SKILLS_DST" "$AGENTS_DST"

# Skills: copy each directory wholesale.
for skill in "${SKILLS[@]}"; do
  echo "  skill: $skill"
  dst="$SKILLS_DST/$skill"
  mkdir -p "$dst"
  cp -a "$REPO/skills/$skill/." "$dst/"
done

# Set exec bits on the copied script wrappers — a fresh git checkout may not
# carry them. _panel_common.sh is sourced, not run, so leave it non-exec.
SCRIPTS_DST="$SKILLS_DST/panel-review/scripts"
chmod +x "$SCRIPTS_DST"/*
chmod -x "$SCRIPTS_DST/_panel_common.sh"

# Agents.
for agent in "${AGENTS[@]}"; do
  echo "  agent: $agent"
  cp -a "$REPO/agents/$agent.md" "$AGENTS_DST/$agent.md"
done

echo "Done."
echo "/reload-plugins (or restart) to pick up the changes."
