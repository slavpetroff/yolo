#!/bin/bash
# DEPRECATED: This script forwards to the native Rust dispatcher where possible.
# Unmigrated scripts still execute as bash. Remove in v3.0.
#
# hook-wrapper.sh — Universal YOLO hook wrapper (DXP-01)
#
# Wraps every YOLO hook with error logging and graceful degradation.
# No hook failure can ever break a session.
#
# Usage: hook-wrapper.sh <script-name.sh> [extra-args...]

SCRIPT="$1"; shift
[ -z "$SCRIPT" ] && exit 0

# --- Map migrated scripts to native Rust dispatcher events ---
# These scripts have been fully migrated to the Rust dispatcher.
# Forward to `yolo hook <event>` instead of executing bash scripts.
_rust_event=""
case "$SCRIPT" in
  security-filter.sh)       _rust_event="pre-tool-use" ;;
  validate-summary.sh)      _rust_event="post-tool-use" ;;
  skill-hook-dispatch.sh)   _rust_event="post-tool-use" ;;
  agent-start.sh)           _rust_event="subagent-start" ;;
  agent-stop.sh)            _rust_event="subagent-stop" ;;
  agent-health.sh)
    case "${1:-}" in
      start)   _rust_event="subagent-start" ;;
      stop)    _rust_event="subagent-stop" ;;
      idle)    _rust_event="teammate-idle" ;;
      cleanup) _rust_event="stop" ;;
    esac
    ;;
  compaction-instructions.sh) _rust_event="pre-compact" ;;
  post-compact.sh)            _rust_event="session-start" ;;
  map-staleness.sh)           _rust_event="session-start" ;;
  prompt-preflight.sh)        _rust_event="user-prompt-submit" ;;
  session-stop.sh)            _rust_event="stop" ;;
  notification-log.sh)        _rust_event="notification" ;;
  blocker-notify.sh)          _rust_event="task-completed" ;;
esac

if [ -n "$_rust_event" ]; then
  if command -v yolo &>/dev/null; then
    # Log deprecation warning (once per session, via marker)
    if [ -d ".yolo-planning" ]; then
      _marker=".yolo-planning/.deprecated-hook-warning"
      if [ ! -f "$_marker" ]; then
        LOG=".yolo-planning/.hook-errors.log"
        TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%s")
        printf '[%s] DEPRECATED: hook-wrapper.sh invoked for %s — use yolo hook %s directly\n' "$TS" "$SCRIPT" "$_rust_event" >> "$LOG" 2>/dev/null
        touch "$_marker" 2>/dev/null
      fi
    fi
    # Forward stdin to native Rust dispatcher
    exec yolo hook "$_rust_event"
  fi
  # yolo binary not found — fall through to bash execution
fi

# --- SIGHUP trap for terminal force-close ---
cleanup_on_sighup() {
  PLANNING_DIR=".yolo-planning"
  if [ ! -d "$PLANNING_DIR" ]; then
    exit 1
  fi

  # shellcheck source=resolve-claude-dir.sh
  . "$(dirname "$0")/resolve-claude-dir.sh" 2>/dev/null || true
  CACHE="${CLAUDE_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}/plugins/cache/yolo-marketplace/yolo"
  TRACKER=$(ls -1 "$CACHE"/*/scripts/agent-pid-tracker.sh 2>/dev/null \
    | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1)

  if [ -z "$TRACKER" ] || [ ! -f "$TRACKER" ]; then
    exit 1
  fi

  LOG="$PLANNING_DIR/.hook-errors.log"
  TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%s")
  echo "[$TS] SIGHUP received, cleaning up agent PIDs" >> "$LOG" 2>/dev/null || true

  PIDS=$(bash "$TRACKER" list 2>/dev/null || true)
  if [ -n "$PIDS" ]; then
    for pid in $PIDS; do
      kill -TERM "$pid" 2>/dev/null || true
    done
    sleep 3
    for pid in $PIDS; do
      if kill -0 "$pid" 2>/dev/null; then
        kill -KILL "$pid" 2>/dev/null || true
      fi
    done
  fi

  exit 1
}

trap cleanup_on_sighup SIGHUP

YOLO_DEBUG="${YOLO_DEBUG:-0}"

# Resolve from plugin cache (version-sorted, latest wins)
# shellcheck source=resolve-claude-dir.sh
. "$(dirname "$0")/resolve-claude-dir.sh"
CACHE="$CLAUDE_DIR/plugins/cache/yolo-marketplace/yolo"
TARGET=$(ls -1 "$CACHE"/*/scripts/"$SCRIPT" 2>/dev/null \
  | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1)

# Fallback to CLAUDE_PLUGIN_ROOT for --plugin-dir installs (local dev)
if [ -z "$TARGET" ] || [ ! -f "$TARGET" ]; then
  TARGET="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/scripts/$SCRIPT}"
fi
[ -z "$TARGET" ] || [ ! -f "$TARGET" ] && exit 0

[ "$YOLO_DEBUG" = "1" ] && echo "[YOLO DEBUG] hook-wrapper: $SCRIPT → $TARGET" >&2

# Execute — stdin flows through to the target script
bash "$TARGET" "$@"
RC=$?
[ "$YOLO_DEBUG" = "1" ] && [ "$RC" -ne 0 ] && echo "[YOLO DEBUG] hook-wrapper: $SCRIPT exit=$RC" >&2
[ "$RC" -eq 0 ] && exit 0

# Exit 2 = intentional block (PreToolUse/UserPromptSubmit) — pass through
[ "$RC" -eq 2 ] && exit 2

# --- Failure: log and exit 0 ---
if [ -d ".yolo-planning" ]; then
  LOG=".yolo-planning/.hook-errors.log"
  TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%s")
  printf '%s %s exit=%d\n' "$TS" "$SCRIPT" "$RC" >> "$LOG" 2>/dev/null
  if [ -f "$LOG" ]; then
    LC=$(wc -l < "$LOG" 2>/dev/null | tr -d ' ')
    [ "${LC:-0}" -gt 50 ] && { tail -30 "$LOG" > "${LOG}.tmp" && mv "${LOG}.tmp" "$LOG"; } 2>/dev/null
  fi
fi

exit 0
