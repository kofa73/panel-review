#!/usr/bin/env bash
#
# Installer for the panel-review plugin.
#
# Copies the whole plugin tree (.claude-plugin/, skills/, agents/, scripts/,
# prompts/, assets/, CONTRACTS.md) into the user's Claude config dir as a single
# skills-directory plugin, loaded as panel-review@skills-dir. Commands are
# namespaced panel-review:<verb> (panel-review:start, :status, :resume,
# :continue, :result, :discard).
#
# It REMOVES the old pre-plugin layout this repo used to install (loose
# skills/agents, not a plugin) — both project- and user-level agents/
# definitions outrank a plugin agent of the same name (Claude Code
# sub-agents.md), so a stale copy at either scope would silently shadow the
# plugin's agents. Only the user-level copies are removed here; a
# project-level .claude/agents/panel-review-*.md is warned about, not
# touched (it isn't this installer's to delete).
#
# Target defaults to ~/.claude; override with CLAUDE_DIR=/path ./install.sh
set -euo pipefail

# Repo root = the directory this script lives in, so it works from any cwd.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"

SKILLS_DST="$CLAUDE_DIR/skills"
AGENTS_DST="$CLAUDE_DIR/agents"
PLUGIN_DST="$SKILLS_DST/panel-review"

echo "Installing the panel-review plugin into: $PLUGIN_DST"

# Remove the OLD pre-plugin layout first, so nothing stale is left beside (or
# shadowing) the new plugin tree. The old layout had panel-review,
# panel-review-for-agent, and panel-review-init as separate loose skill dirs,
# and the two agents at the top level of agents/.
for old_skill in panel-review-for-agent panel-review-init; do
  if [ -d "$SKILLS_DST/$old_skill" ]; then
    echo "  removing old loose skill: $SKILLS_DST/$old_skill"
    rm -rf -- "$SKILLS_DST/$old_skill"
  fi
done
for old_agent in panel-review-referee panel-review-claude-seat; do
  if [ -f "$AGENTS_DST/$old_agent.md" ]; then
    echo "  removing old top-level agent: $AGENTS_DST/$old_agent.md"
    rm -f -- "$AGENTS_DST/$old_agent.md"
  fi
done

# The old panel-review dir held a flat skill (SKILL.md at its root). The new
# plugin tree reuses the SAME name but as a plugin (.claude-plugin/ at its
# root, commands nested under skills/<verb>/). Wipe it before copying so no
# stale old SKILL.md or old scripts linger alongside the new tree.
rm -rf -- "$PLUGIN_DST"
mkdir -p "$PLUGIN_DST"

for part in .claude-plugin skills agents scripts prompts assets CONTRACTS.md; do
  if [ -e "$REPO/$part" ]; then
    cp -a "$REPO/$part" "$PLUGIN_DST/$part"
  fi
done

# Set exec bits on the copied script wrappers — a fresh git checkout may not
# carry them. _panel_common.sh is sourced, not run, so leave it non-exec.
SCRIPTS_DST="$PLUGIN_DST/scripts"
chmod +x "$SCRIPTS_DST"/*
chmod -x "$SCRIPTS_DST/_panel_common.sh"

# Shadow check: a project- or user-level agents/panel-review-*.md outranks
# the plugin's own agents of the same name (lowest priority), so either would
# silently take over. We already removed the user-level ones above; warn
# about anything left (re-created since, or a project-level copy in cwd).
shadow_found=0
for agent in panel-review-referee panel-review-claude-seat panel-review-cli-barrier; do
  if [ -f "$AGENTS_DST/$agent.md" ]; then
    echo "WARNING: $AGENTS_DST/$agent.md still exists and will shadow the plugin's $agent agent."
    shadow_found=1
  fi
  if [ -f "$PWD/.claude/agents/$agent.md" ]; then
    echo "WARNING: $PWD/.claude/agents/$agent.md exists and will shadow the plugin's $agent agent in this project."
    shadow_found=1
  fi
done
[ "$shadow_found" -eq 0 ] || echo "Remove the file(s) above so the plugin's agents aren't shadowed."

echo "Done. Loaded as panel-review@skills-dir; commands are panel-review:start/status/resume/continue/result/discard."
echo "/reload-plugins (or restart) to pick up the changes."
