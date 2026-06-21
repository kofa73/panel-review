#!/usr/bin/env bash
# _panel_common.sh — shared helpers, sourced by the persistence scripts.
# Not executable on its own. Keeps ID validation and atomic-write in one place
# (a wrong ID would let an rm -rf escape its namespace, so validate everywhere).

# A run ID is our own minted token: letters, digits, dot, dash, underscore only.
# Reject anything else BEFORE it reaches a filesystem path.
panel_valid_id() {
  case "$1" in
    ''|*[!A-Za-z0-9._-]*) return 1 ;;
    .|..) return 1 ;;
    *) return 0 ;;
  esac
}

panel_require_id() {
  panel_valid_id "${1-}" || { echo "panel: invalid run id: '${1-}'" >&2; exit 2; }
}

# Atomic-ish write: content on stdin -> dest. Rotates an existing dest to
# dest.bak first (best-effort fallback), writes a temp in the SAME dir (so the
# final mv is a same-filesystem rename = atomic), fsyncs, then renames over dest.
# No missing-file window: dest holds the old bytes until the rename flips it.
panel_atomic_write() {
  local dest="$1" dir tmp
  dir="$(dirname "$dest")"
  [ -d "$dir" ] || mkdir -p "$dir"
  if [ -e "$dest" ]; then cp -p "$dest" "$dest.bak" 2>/dev/null || true; fi
  tmp="$(mktemp "$dir/.panel.XXXXXX")"
  cat > "$tmp"
  dd if=/dev/null of="$tmp" conv=notrunc,fsync 2>/dev/null # durability before the rename
  mv -f "$tmp" "$dest"
}

# .git/info/exclude entry add/remove (never touches tracked .gitignore).
# Resolve the exclude path via git, not "$workdir/.git/info/exclude": in a git
# worktree or submodule `.git` is a FILE pointing elsewhere, so the hardcoded
# path is wrong and the exclude silently never gets written.
_panel_exclude_path() {
  local workdir="$1" p
  git -C "$workdir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  p="$(git -C "$workdir" rev-parse --git-path info/exclude 2>/dev/null)" || return 1
  [ -n "$p" ] || return 1
  case "$p" in /*) printf '%s\n' "$p";; *) printf '%s/%s\n' "$workdir" "$p";; esac
}
panel_git_exclude_add() {
  local workdir="$1" line="$2" ex
  ex="$(_panel_exclude_path "$workdir")" || return 0
  mkdir -p "$(dirname "$ex")"
  touch "$ex"
  grep -qxF "$line" "$ex" 2>/dev/null || printf '%s\n' "$line" >> "$ex"
}
panel_git_exclude_del() {
  local workdir="$1" line="$2" ex rc
  ex="$(_panel_exclude_path "$workdir")" || return 0
  [ -f "$ex" ] || return 0
  # grep exits 1 when NO lines remain (we filtered out the only entry) — that is
  # a valid empty result, not an error. Treat exit 0 and 1 as success; only a
  # real grep error (>=2) aborts the rewrite. (|| guards set -e.)
  grep -vxF "$line" "$ex" > "$ex.tmp" 2>/dev/null && rc=0 || rc=$?
  if [ "$rc" -le 1 ]; then mv -f "$ex.tmp" "$ex"; else rm -f "$ex.tmp"; fi
}
