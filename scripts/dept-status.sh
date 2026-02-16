#!/usr/bin/env bash
set -euo pipefail

# dept-status.sh — Atomic read/write of per-department status files
#
# Manages .dept-status-{dept}.json files with flock locking (mkdir fallback).
# Each department gets its own status file tracking progress through phases.
#
# Usage:
#   dept-status.sh --dept <name> --phase-dir <path> --action read
#   dept-status.sh --dept <name> --phase-dir <path> --action write --status <val> --step <val>
#
# Write options: --error <msg>, --plans-complete <N>, --plans-total <N>
# Exit codes: 0=success, 1=missing file or invalid args, 2=lock timeout

LOCK_TIMEOUT=10  # seconds

# --- Arg parsing ---
DEPT="" PHASE_DIR="" ACTION="" STATUS="" STEP="" ERROR="" PLANS_COMPLETE=0 PLANS_TOTAL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dept) DEPT="$2"; shift 2 ;;
    --phase-dir) PHASE_DIR="$2"; shift 2 ;;
    --action) ACTION="$2"; shift 2 ;;
    --status) STATUS="$2"; shift 2 ;;
    --step) STEP="$2"; shift 2 ;;
    --error) ERROR="$2"; shift 2 ;;
    --plans-complete) PLANS_COMPLETE="$2"; shift 2 ;;
    --plans-total) PLANS_TOTAL="$2"; shift 2 ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

# --- Validation ---
if [ -z "$DEPT" ] || [ -z "$PHASE_DIR" ] || [ -z "$ACTION" ]; then
  echo "Usage: dept-status.sh --dept <name> --phase-dir <path> --action <read|write> [--status <val>] [--step <val>]" >&2
  exit 1
fi

if [ "$ACTION" != "read" ] && [ "$ACTION" != "write" ]; then
  echo "ERROR: --action must be read or write" >&2
  exit 1
fi

if [ "$ACTION" = "write" ] && [ -z "$STATUS" ]; then
  echo "ERROR: --status required for write action" >&2
  exit 1
fi

if [ "$ACTION" = "write" ] && [ -z "$STEP" ]; then
  echo "ERROR: --step required for write action" >&2
  exit 1
fi

# --- File paths ---
STATUS_FILE="$PHASE_DIR/.dept-status-${DEPT}.json"
LOCK_FILE="$PHASE_DIR/.dept-lock-${DEPT}"
LOCK_DIR="$PHASE_DIR/.dept-lock-${DEPT}.d"

# --- Locking mechanism ---
acquire_lock() {
  if command -v flock >/dev/null 2>&1; then
    exec 9>"$LOCK_FILE"
    if ! flock -w "$LOCK_TIMEOUT" 9; then
      echo "ERROR: Lock timeout after ${LOCK_TIMEOUT}s on $LOCK_FILE" >&2
      exit 2
    fi
  else
    # mkdir fallback (atomic on all POSIX systems)
    local attempts=0
    local max_attempts=$((LOCK_TIMEOUT * 10))  # 100ms intervals
    while ! mkdir "$LOCK_DIR" 2>/dev/null; do
      attempts=$((attempts + 1))
      if [ "$attempts" -ge "$max_attempts" ]; then
        echo "ERROR: Lock timeout after ${LOCK_TIMEOUT}s on $LOCK_DIR" >&2
        exit 2
      fi
      sleep 0.1
    done
    trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT
  fi
}

release_lock() {
  if command -v flock >/dev/null 2>&1; then
    exec 9>&-
  else
    rmdir "$LOCK_DIR" 2>/dev/null || true
  fi
}

# --- Read action ---
if [ "$ACTION" = "read" ]; then
  if [ ! -f "$STATUS_FILE" ]; then
    echo "ERROR: Status file not found: $STATUS_FILE" >&2
    exit 1
  fi
  cat "$STATUS_FILE"
  exit 0
fi

# --- Write action ---
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
acquire_lock

# Determine started_at: preserve from existing file, or set to NOW
STARTED_AT="$NOW"
if [ -f "$STATUS_FILE" ]; then
  EXISTING_STARTED=$(jq -r '.started_at // ""' "$STATUS_FILE" 2>/dev/null) || true
  if [ -n "$EXISTING_STARTED" ] && [ "$EXISTING_STARTED" != "null" ]; then
    STARTED_AT="$EXISTING_STARTED"
  fi
fi

# Write status JSON atomically (write to temp, then mv)
TEMP_FILE="${STATUS_FILE}.tmp.$$"
jq -n \
  --arg dept "$DEPT" \
  --arg status "$STATUS" \
  --arg step "$STEP" \
  --arg started_at "$STARTED_AT" \
  --arg updated_at "$NOW" \
  --argjson plans_complete "$PLANS_COMPLETE" \
  --argjson plans_total "$PLANS_TOTAL" \
  --arg error "$ERROR" \
  '{dept:$dept,status:$status,step:$step,started_at:$started_at,updated_at:$updated_at,plans_complete:$plans_complete,plans_total:$plans_total,error:$error}' \
  > "$TEMP_FILE"
mv "$TEMP_FILE" "$STATUS_FILE"

release_lock
exit 0
