#!/usr/bin/env bash
# yolo-common.sh — Shared shell functions for YOLO scripts
#
# Source this file to get: require_jq, parse_named_args, json_output,
# run_with_timeout, acquire_lock, release_lock.
#
# Guard: source once only.

[ "${_YOLO_COMMON_LOADED:-}" = "1" ] && return 0
_YOLO_COMMON_LOADED=1

# --- require_jq ---
# Check jq is available, emit JSON error and exit 1 if not.
require_jq() {
  if ! command -v jq &>/dev/null; then
    echo '{"error":"jq is required but not installed"}' >&2
    exit 1
  fi
}

# --- parse_named_args ---
# Parse --key value pairs into associative array.
# Usage: declare -A ARGS; parse_named_args ARGS "$@"
# Supports: --flag value pairs. Unknown flags cause exit 1.
# Caller must declare the allowed keys in ARGS before calling
# (set them to "" as defaults). Unknown keys trigger usage error.
parse_named_args() {
  local -n _pna_map="$1"
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --*)
        local key="${1#--}"
        key="${key//-/_}"  # --phase-dir -> phase_dir
        if [[ $# -lt 2 ]]; then
          echo "Error: $1 requires a value" >&2
          return 1
        fi
        _pna_map["$key"]="$2"
        shift 2
        ;;
      *)
        echo "Error: unexpected argument: $1" >&2
        return 1
        ;;
    esac
  done
}

# --- json_output ---
# Wrapper around jq -n for structured JSON output.
# Usage: json_output --arg key val --argjson key val '{...}'
json_output() {
  jq -n "$@"
}

# --- run_with_timeout ---
# Run a command with a timeout in seconds. Returns 124 on timeout.
# Handles missing timeout command on macOS (uses gtimeout or bash fallback).
run_with_timeout() {
  local secs="$1"; shift
  if command -v timeout &>/dev/null; then
    timeout "$secs" "$@"
    return $?
  elif command -v gtimeout &>/dev/null; then
    gtimeout "$secs" "$@"
    return $?
  else
    "$@" &
    local cmd_pid=$!
    local elapsed=0
    while kill -0 "$cmd_pid" 2>/dev/null; do
      if [ "$elapsed" -ge "$secs" ]; then
        pkill -P "$cmd_pid" 2>/dev/null || true
        kill "$cmd_pid" 2>/dev/null || true
        wait "$cmd_pid" 2>/dev/null || true
        return 124
      fi
      sleep 1
      elapsed=$((elapsed + 1))
    done
    wait "$cmd_pid" 2>/dev/null
    return $?
  fi
}

# --- acquire_lock / release_lock ---
# File locking with flock (Linux) and mkdir fallback (macOS/POSIX).
# Usage:
#   LOCK_FILE="/path/to/.lock"      # for flock
#   LOCK_DIR="/path/to/.lock.d"     # for mkdir fallback
#   LOCK_TIMEOUT=10                  # seconds
#   acquire_lock
#   ... critical section ...
#   release_lock
#
# Requires LOCK_FILE, LOCK_DIR, LOCK_TIMEOUT to be set before calling.
# Exit 2 on lock timeout.

acquire_lock() {
  local lock_file="${LOCK_FILE:?LOCK_FILE must be set}"
  local lock_dir="${LOCK_DIR:?LOCK_DIR must be set}"
  local lock_timeout="${LOCK_TIMEOUT:-10}"

  if command -v flock >/dev/null 2>&1; then
    exec 9>"$lock_file"
    if ! flock -w "$lock_timeout" 9; then
      echo "ERROR: Lock timeout after ${lock_timeout}s on $lock_file" >&2
      exit 2
    fi
  else
    local attempts=0
    local max_attempts=$((lock_timeout * 10))
    while ! mkdir "$lock_dir" 2>/dev/null; do
      attempts=$((attempts + 1))
      if [ "$attempts" -ge "$max_attempts" ]; then
        echo "ERROR: Lock timeout after ${lock_timeout}s on $lock_dir" >&2
        exit 2
      fi
      sleep 0.1
    done
    trap 'rmdir "'"$lock_dir"'" 2>/dev/null || true' EXIT
  fi
}

release_lock() {
  local lock_dir="${LOCK_DIR:?LOCK_DIR must be set}"

  if command -v flock >/dev/null 2>&1; then
    exec 9>&-
  else
    rmdir "$lock_dir" 2>/dev/null || true
  fi
}
