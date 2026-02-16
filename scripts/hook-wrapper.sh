#!/bin/bash
# hook-wrapper.sh — Universal YOLO hook wrapper (DXP-01)
#
# Wraps every YOLO hook with error logging and graceful degradation.
#
# Usage: hook-wrapper.sh <script-name.sh> [extra-args...]
#
# - Resolves the target script from the YOLO plugin cache (cached in /tmp)
# - Passes through stdin (hook JSON context) and extra arguments
# - Target script stdout (JSON) flows through to Claude Code
# - Exit 0: allow (PreToolUse JSON deny decisions also use exit 0 with JSON stdout)
# - Exit 2: block (passed through — used by Notification qa-gate, PostToolUse task-verify, etc.)
# - Other non-zero: script error — logged and converted to exit 0 (graceful degradation)
# - Logs errors to .yolo-planning/.hook-errors.log

SCRIPT="$1"; shift
[ -z "$SCRIPT" ] && exit 0

# Resolve from plugin cache (version-sorted, latest wins) — cached per-user
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CACHE="$CLAUDE_DIR/plugins/cache/yolo-marketplace/yolo"
_YOLO_DIR="/tmp/yolo-vdir-$(id -u)"

if [ -f "$_YOLO_DIR" ]; then
  VDIR=$(<"$_YOLO_DIR")  # bash-native read, no subshell fork
  # Invalidate if plugin cache dir was modified (new version installed)
  [ "$CACHE" -nt "$_YOLO_DIR" ] 2>/dev/null && VDIR=""
fi
if [ -z "${VDIR:-}" ]; then
  VDIR=$(command ls -1d "$CACHE"/*/ 2>/dev/null | sort -V | tail -1)
  VDIR="${VDIR%/}"
  [ -n "$VDIR" ] && printf '%s' "$VDIR" > "$_YOLO_DIR" 2>/dev/null
fi
TARGET="${VDIR:-}/scripts/$SCRIPT"
[ -f "$TARGET" ] || exit 0

# Execute — stdin and stdout flow through to the target script / Claude Code
bash "$TARGET" "$@"
RC=$?
[ "$RC" -eq 0 ] && exit 0

# Exit 2 = intentional block decision (pass through to Claude Code)
[ "$RC" -eq 2 ] && exit 2

# --- Other non-zero: unexpected script error — log and exit 0 (graceful degradation) ---
if [ -d ".yolo-planning" ]; then
  LOG=".yolo-planning/.hook-errors.log"
  TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%s")
  printf '%s %s exit=%d\n' "$TS" "$SCRIPT" "$RC" >> "$LOG" 2>/dev/null
  # Trim to last 50 entries to prevent unbounded growth
  if [ -f "$LOG" ]; then
    LC=$(( $(wc -l < "$LOG" 2>/dev/null) ))
    [ "${LC:-0}" -gt 50 ] && { tail -30 "$LOG" > "${LOG}.tmp" && mv "${LOG}.tmp" "$LOG"; } 2>/dev/null
  fi
fi

exit 0
