#!/usr/bin/env bash
set -euo pipefail

# git-commit-serialized.sh -- Serialized git commit wrapper for parallel Dev agents.
# Uses flock(1) for exclusive locking on .git/yolo-commit.lock.
# Falls back to mkdir-based advisory lock if flock is unavailable.
# Usage: git-commit-serialized.sh [git commit args]
# Example: git-commit-serialized.sh -m "feat(01-01): add auth"
# Caller must stage files BEFORE calling this script.
# Outputs commit hash on stdout. Exit 0 on success, 1 on failure.

LOCK_FILE=".git/yolo-commit.lock"
MAX_RETRIES=5
BASE_DELAY_MS=200

# --- Lock strategy detection ---

has_flock() {
  command -v flock &>/dev/null
}

# --- flock-based locking ---

acquire_lock_flock() {
  exec 200>"$LOCK_FILE" && flock -n 200
  return $?
}

# --- mkdir-based locking (fallback) ---

acquire_lock_mkdir() {
  mkdir "${LOCK_FILE}.d" 2>/dev/null
  return $?
}

release_lock_mkdir() {
  rmdir "${LOCK_FILE}.d" 2>/dev/null || true
}

# --- Sleep in milliseconds ---

sleep_ms() {
  local ms="$1"
  # Try awk first (most portable), then bc, then python3
  if command -v awk &>/dev/null; then
    sleep "$(awk "BEGIN {printf \"%.3f\", $ms/1000}")"
  elif command -v bc &>/dev/null; then
    sleep "$(echo "scale=3; $ms/1000" | bc)"
  elif command -v python3 &>/dev/null; then
    sleep "$(python3 -c "print(f'{$ms/1000:.3f}')")"
  else
    # Fallback: round up to nearest second
    sleep $(( (ms + 999) / 1000 ))
  fi
}

# --- Main logic ---

USE_FLOCK=false
if has_flock; then
  USE_FLOCK=true
fi

# mkdir fallback: set trap for cleanup
if [ "$USE_FLOCK" = false ]; then
  trap 'rmdir "${LOCK_FILE}.d" 2>/dev/null || true' EXIT
fi

for i in $(seq 0 $((MAX_RETRIES - 1))); do
  # Attempt to acquire lock
  lock_acquired=false
  if [ "$USE_FLOCK" = true ]; then
    if acquire_lock_flock; then
      lock_acquired=true
    fi
  else
    if acquire_lock_mkdir; then
      lock_acquired=true
    fi
  fi

  if [ "$lock_acquired" = true ]; then
    # Run git commit with all passed arguments (suppress output so only hash goes to stdout)
    commit_exit=0
    git commit "$@" >/dev/null 2>&1 || commit_exit=$?

    if [ "$commit_exit" -eq 0 ]; then
      # Capture commit hash
      commit_hash=$(git rev-parse --short HEAD)

      # Release lock (mkdir mode only; flock releases on fd close)
      if [ "$USE_FLOCK" = false ]; then
        release_lock_mkdir
      fi

      echo "$commit_hash"
      exit 0
    else
      # Commit failed (e.g., nothing staged) -- release lock and exit with error
      if [ "$USE_FLOCK" = false ]; then
        release_lock_mkdir
      fi
      exit "$commit_exit"
    fi
  fi

  # Lock not acquired -- backoff and retry
  delay=$((BASE_DELAY_MS * (1 << i)))
  sleep_ms "$delay"
done

# All retries exhausted
echo "ERROR: Could not acquire commit lock after $MAX_RETRIES retries (total wait ~6.2s). Escalate to Senior as a blocker." >&2
exit 1
