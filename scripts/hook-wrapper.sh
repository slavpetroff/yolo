#!/bin/bash
# DEPRECATED: This script forwards to native Rust dispatcher. Remove in v3.0.
#
# hook-wrapper.sh — Backward-compatible forwarding stub.
# All hooks are now handled natively by the Rust dispatcher at $HOME/.cargo/bin/yolo.
# This stub exists only for graceful migration of any external callers.
#
# Usage: hook-wrapper.sh <script-name.sh> [extra-args...]

SCRIPT="$1"; shift
[ -z "$SCRIPT" ] && exit 0

# --- Log deprecation warning ---
PLANNING_DIR=".yolo-planning"
if [ -d "$PLANNING_DIR" ]; then
  LOG="$PLANNING_DIR/.hook-errors.log"
  TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%s")
  printf '%s DEPRECATED hook-wrapper.sh called with: %s (use yolo hook <event> instead)\n' "$TS" "$SCRIPT" >> "$LOG" 2>/dev/null || true
  # Trim log to last 50 entries
  if [ -f "$LOG" ]; then
    LC=$(wc -l < "$LOG" 2>/dev/null | tr -d ' ')
    [ "${LC:-0}" -gt 50 ] && { tail -30 "$LOG" > "${LOG}.tmp" && mv "${LOG}.tmp" "$LOG"; } 2>/dev/null
  fi
fi

# --- Map script name to dispatcher event ---
EVENT=""
case "$SCRIPT" in
  security-filter.sh)         EVENT="PreToolUse" ;;
  bash-guard.sh)              EVENT="PreToolUse" ;;
  file-guard.sh)              EVENT="PreToolUse" ;;
  validate-summary.sh)        EVENT="PostToolUse" ;;
  validate-frontmatter.sh)    EVENT="PostToolUse" ;;
  validate-commit.sh)         EVENT="PostToolUse" ;;
  state-updater.sh)           EVENT="PostToolUse" ;;
  skill-hook-dispatch.sh)     EVENT="${1:-PostToolUse}"; shift 2>/dev/null || true ;;
  agent-start.sh)             EVENT="SubagentStart" ;;
  agent-stop.sh)              EVENT="SubagentStop" ;;
  agent-health.sh)
    case "${1:-}" in
      start)   EVENT="SubagentStart" ;;
      stop)    EVENT="SubagentStop" ;;
      idle)    EVENT="TeammateIdle" ;;
      cleanup) EVENT="Stop" ;;
      *)       EVENT="SubagentStart" ;;
    esac ;;
  qa-gate.sh)                 EVENT="TeammateIdle" ;;
  task-verify.sh)             EVENT="TaskCompleted" ;;
  blocker-notify.sh)          EVENT="TaskCompleted" ;;
  session-start.sh)           EVENT="SessionStart" ;;
  map-staleness.sh)           EVENT="SessionStart" ;;
  post-compact.sh)            EVENT="SessionStart" ;;
  compaction-instructions.sh) EVENT="PreCompact" ;;
  prompt-preflight.sh)        EVENT="UserPromptSubmit" ;;
  session-stop.sh)            EVENT="Stop" ;;
  notification-log.sh)        EVENT="Notification" ;;
  *)
    # Unknown script — cannot forward, exit gracefully
    exit 0 ;;
esac

# --- Forward to native Rust dispatcher, piping stdin ---
YOLO_BIN="${HOME}/.cargo/bin/yolo"
if [ -x "$YOLO_BIN" ]; then
  exec "$YOLO_BIN" hook "$EVENT"
fi

# Fallback: try yolo from PATH
if command -v yolo >/dev/null 2>&1; then
  exec yolo hook "$EVENT"
fi

# No yolo binary found — exit gracefully
exit 0
