#!/usr/bin/env bash
#
# Installer for the panel-review plugin.
#
# Copies the whole plugin tree (.claude-plugin/, skills/, agents/, scripts/,
# hooks/, prompts/, profiles/, assets/, CONTRACTS.md) into the user's Claude config dir as a single
# skills-directory plugin, loaded as panel-review@skills-dir. Commands are
# namespaced panel-review:<verb> (panel-review:start, :status, :resume,
# :continue, :result, :discard).
#
# It replaces its plugin destination and leaves other skill and agent
# directories alone. Project- and user-level agent files can shadow plugin
# agents, so the installer warns about those files instead of deleting them.
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

# Replace the plugin destination so files from an earlier plugin version do not
# linger beside the current tree.
rm -rf -- "$PLUGIN_DST"
mkdir -p "$PLUGIN_DST"

for part in .claude-plugin skills agents scripts hooks prompts profiles assets bin CONTRACTS.md; do
  if [ -e "$REPO/$part" ]; then
    cp -a "$REPO/$part" "$PLUGIN_DST/$part"
  fi
done

# Set exec bits on the copied script wrappers — a fresh git checkout may not
# carry them. _panel_common.sh is sourced, not run, so leave it non-exec.
SCRIPTS_DST="$PLUGIN_DST/scripts"
chmod +x "$SCRIPTS_DST"/*
chmod -x "$SCRIPTS_DST/_panel_common.sh"
chmod +x "$PLUGIN_DST/hooks/enforce_agent_status_stub"
chmod +x "$PLUGIN_DST/bin/panel-review-session"

if [ "${PANEL_REVIEW_INSTALL_LAUNCHER:-1}" = 0 ]; then
  echo "Skipped the panel-review-session PATH link (PANEL_REVIEW_INSTALL_LAUNCHER=0)."
else
  launcher_bin_dir="${PANEL_REVIEW_BIN_DIR:-$HOME/.local/bin}"
  launcher_link="$launcher_bin_dir/panel-review-session"
  plugin_dst_abs="$(cd "$PLUGIN_DST" && pwd -P)"
  launcher_target="$plugin_dst_abs/bin/panel-review-session"

  mkdir -p "$launcher_bin_dir"
  if [ -L "$launcher_link" ] && [ "$(readlink "$launcher_link")" = "$launcher_target" ]; then
    echo "Already linked: $launcher_link -> $launcher_target"
  elif [ -e "$launcher_link" ] || [ -L "$launcher_link" ]; then
    echo "WARNING: $launcher_link already exists; the panel-review-session link was not installed."
  else
    ln -s "$launcher_target" "$launcher_link"
    echo "Linked: $launcher_link -> $launcher_target"
  fi

  case ":$PATH:" in
    *":$launcher_bin_dir:"*) ;;
    *) echo "NOTE: $launcher_bin_dir is not on PATH; run $launcher_link directly or add the directory to PATH." ;;
  esac
fi

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
