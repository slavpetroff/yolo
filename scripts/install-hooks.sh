#!/bin/bash
set -euo pipefail
# Install YOLO-managed git hooks. Idempotent -- safe to run repeatedly.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Determine the user's project root, NOT the plugin root.
# When called from a hook, $PWD is the project. When called manually, use git.
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || ROOT=""

# Exit silently if not inside a git repo
if [ -z "$ROOT" ] || [ ! -d "$ROOT/.git" ]; then
  exit 0
fi

# Ensure hooks directory exists
mkdir -p "$ROOT/.git/hooks"

# --- pre-push hook ---
HOOK_PATH="$ROOT/.git/hooks/pre-push"

# Create a standalone hook script that uses git rev-parse (not relative paths)
# so it works regardless of where the plugin is cached.
HOOK_CONTENT='#!/usr/bin/env bash
set -euo pipefail
# YOLO pre-push hook — delegates to the latest cached plugin script.
# Installed by YOLO install-hooks.sh. Remove with: rm .git/hooks/pre-push
SCRIPT=$(command ls -1 "$HOME"/.claude/plugins/cache/yolo-marketplace/yolo/*/scripts/pre-push-hook.sh 2>/dev/null | sort -V | tail -1) || true
if [ -n "$SCRIPT" ] && [ -f "$SCRIPT" ]; then
  exec bash "$SCRIPT" "$@"
fi
# Plugin not cached — skip silently
exit 0'

if [ -f "$HOOK_PATH" ]; then
  # Check if this is a YOLO-managed hook (symlink to old target or contains our marker)
  if [ -L "$HOOK_PATH" ]; then
    CURRENT_TARGET=$(readlink "$HOOK_PATH")
    if echo "$CURRENT_TARGET" | grep -q "pre-push-hook.sh"; then
      # Old symlink-style YOLO hook — upgrade to standalone script
      echo "$HOOK_CONTENT" > "$HOOK_PATH"
      chmod +x "$HOOK_PATH"
      echo "Upgraded pre-push hook to standalone script" >&2
    else
      echo "pre-push hook exists but is not managed by YOLO -- skipping" >&2
    fi
  elif grep -q "YOLO pre-push hook" "$HOOK_PATH" 2>/dev/null; then
    echo "pre-push hook already installed" >&2
  else
    echo "pre-push hook exists but is not managed by YOLO -- skipping" >&2
  fi
else
  echo "$HOOK_CONTENT" > "$HOOK_PATH"
  chmod +x "$HOOK_PATH"
  echo "Installed pre-push hook" >&2
fi
