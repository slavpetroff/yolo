#!/bin/bash
set -u
# skill-hook-dispatch.sh — Runtime skill-hook dispatcher
# Reads config.json skill_hooks and invokes matching skill scripts
# Fail-open design: exit 0 on any error, never block legitimate work

EVENT_TYPE="${1:-}"
[ -z "$EVENT_TYPE" ] && exit 0

INPUT=$(cat 2>/dev/null) || exit 0
[ -z "$INPUT" ] && exit 0

TOOL_NAME=$(jq -r '.tool_name // ""' <<< "$INPUT" 2>/dev/null) || exit 0
[ -z "$TOOL_NAME" ] && exit 0

# Cached config path resolution (like vdir cache in hook-wrapper.sh)
_CFG_CACHE="/tmp/yolo-cfgpath-$(id -u)"
CONFIG_PATH=""
if [ -f "$_CFG_CACHE" ]; then
  CONFIG_PATH=$(<"$_CFG_CACHE")
  [ -f "$CONFIG_PATH" ] || CONFIG_PATH=""  # validate cache
fi
if [ -z "$CONFIG_PATH" ]; then
  # Walk up from PWD
  _dir="$PWD"
  while [ "$_dir" != "/" ]; do
    if [ -f "$_dir/.yolo-planning/config.json" ]; then
      CONFIG_PATH="$_dir/.yolo-planning/config.json"
      printf '%s' "$CONFIG_PATH" > "$_CFG_CACHE" 2>/dev/null
      break
    fi
    _dir=$(dirname "$_dir")
  done
fi
[ -z "$CONFIG_PATH" ] && exit 0

# Single jq: filter skill_hooks to matching event+tool, output skill names
MATCHES=$(jq -r --arg evt "$EVENT_TYPE" --arg tool "$TOOL_NAME" '
  .skill_hooks // {} | to_entries[] |
  select(.value.event == $evt) |
  select(.value.tools | split("|") | any(. == $tool)) |
  .key
' "$CONFIG_PATH" 2>/dev/null) || exit 0
[ -z "$MATCHES" ] && exit 0

while IFS= read -r SKILL_NAME; do
  SCRIPT=$(command ls -1 "$HOME"/.claude/plugins/cache/yolo-marketplace/yolo/*/scripts/"${SKILL_NAME}-hook.sh" 2>/dev/null | sort -V | tail -1)
  [ -f "$SCRIPT" ] && echo "$INPUT" | bash "$SCRIPT" 2>/dev/null || true
done <<< "$MATCHES"

exit 0
