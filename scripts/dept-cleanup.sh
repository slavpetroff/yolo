#!/usr/bin/env bash
set -euo pipefail

# dept-cleanup.sh — Remove YOLO coordination files from phase directory
#
# Safely removes only coordination artifacts (.dept-status-*, .handoff-*,
# .dept-lock-*, .phase-orchestration.json) after completion or failure.
# Never removes user artifacts (plan, summary, toon, md files).
#
# Usage: dept-cleanup.sh --phase-dir <path> --reason <complete|failure|timeout>
# Exit codes: 0=always (cleanup is best-effort)

# --- Arg parsing ---
PHASE_DIR="" REASON=""
while [ $# -gt 0 ]; do
  case "$1" in
    --phase-dir) PHASE_DIR="$2"; shift 2 ;;
    --reason) REASON="$2"; shift 2 ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

# --- Validation ---
if [ -z "$PHASE_DIR" ] || [ -z "$REASON" ]; then
  echo "Usage: dept-cleanup.sh --phase-dir <path> --reason <complete|failure|timeout>" >&2
  exit 1
fi

case "$REASON" in
  complete|failure|timeout) ;;
  *) echo "ERROR: --reason must be complete, failure, or timeout" >&2; exit 1 ;;
esac

if [ ! -d "$PHASE_DIR" ]; then
  echo "WARNING: Phase dir does not exist: $PHASE_DIR" >&2
  exit 0
fi

# --- Cleanup patterns (explicit allowlist of coordination file patterns) ---
PATTERNS=(
  ".dept-status-*.json"
  ".handoff-*"
  ".dept-lock-*"
  ".dept-lock-*.d"
  ".phase-orchestration.json"
)

# --- Cleanup logic ---
REMOVED=()
for pattern in "${PATTERNS[@]}"; do
  for file in "$PHASE_DIR"/$pattern; do
    if [ -f "$file" ]; then
      rm -f "$file"
      REMOVED+=("$(basename "$file")")
    elif [ -d "$file" ]; then
      rmdir "$file" 2>/dev/null || true
      REMOVED+=("$(basename "$file")")
    fi
  done
done

# --- Output ---
if [ ${#REMOVED[@]} -gt 0 ]; then
  echo "Cleaned up ${#REMOVED[@]} coordination files (reason: $REASON):"
  for f in "${REMOVED[@]}"; do
    echo "  removed: $f"
  done
else
  echo "No coordination files to clean up in $PHASE_DIR"
fi
