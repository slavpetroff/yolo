#!/usr/bin/env bash
set -euo pipefail

# dept-gate.sh — Check handoff gate conditions with polling and timeout
#
# Validates department handoff gates by checking sentinel files and artifact
# integrity. Supports polling mode for waiting and --no-poll for single checks.
#
# Usage: dept-gate.sh --gate <name> --phase-dir <path> [--timeout <secs>] [--poll-interval <secs>] [--no-poll]
# Gates: ux-complete, api-contract, all-depts
# Exit codes: 0=gate satisfied, 1=timeout or gate not met

# --- Arg parsing ---
GATE="" PHASE_DIR="" TIMEOUT=1800 POLL_INTERVAL=0.5 NO_POLL=false
while [ $# -gt 0 ]; do
  case "$1" in
    --gate) GATE="$2"; shift 2 ;;
    --phase-dir) PHASE_DIR="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --poll-interval) POLL_INTERVAL="$2"; shift 2 ;;
    --no-poll) NO_POLL=true; shift ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

# --- Validation ---
if [ -z "$GATE" ] || [ -z "$PHASE_DIR" ]; then
  echo "Usage: dept-gate.sh --gate <name> --phase-dir <path> [--timeout <secs>] [--poll-interval <secs>] [--no-poll]" >&2
  exit 1
fi

case "$GATE" in
  ux-complete|api-contract|all-depts) ;;
  *) echo "ERROR: Unknown gate: $GATE" >&2; exit 1 ;;
esac

# --- Gate check functions ---

check_ux_complete() {
  # 1. Sentinel file must exist
  [ -f "$PHASE_DIR/.handoff-ux-complete" ] || return 1
  # 2. design-handoff.jsonl must exist and have valid JSON on line 1
  [ -f "$PHASE_DIR/design-handoff.jsonl" ] || return 1
  jq empty "$PHASE_DIR/design-handoff.jsonl" 2>/dev/null || return 1
  # 3. design-tokens.jsonl must exist
  [ -f "$PHASE_DIR/design-tokens.jsonl" ] || return 1
  # 4. component-specs.jsonl must exist and have valid JSON on line 1
  [ -f "$PHASE_DIR/component-specs.jsonl" ] || return 1
  jq empty "$PHASE_DIR/component-specs.jsonl" 2>/dev/null || return 1
  return 0
}

check_api_contract() {
  local contracts="$PHASE_DIR/api-contracts.jsonl"
  [ -f "$contracts" ] || return 1
  # Must have at least one line with status=agreed
  local found=false
  while IFS= read -r line; do
    local st
    st=$(echo "$line" | jq -r '.status // ""' 2>/dev/null) || continue
    if [ "$st" = "agreed" ]; then
      found=true
      break
    fi
  done < "$contracts"
  [ "$found" = true ] && return 0 || return 1
}

check_all_depts() {
  # Find all .dept-status-*.json files
  local status_files
  status_files=$(ls "$PHASE_DIR"/.dept-status-*.json 2>/dev/null) || return 1
  [ -z "$status_files" ] && return 1
  # Every status file must have status=complete
  while IFS= read -r sf; do
    local st
    st=$(jq -r '.status // ""' "$sf" 2>/dev/null) || return 1
    [ "$st" = "complete" ] || return 1
  done <<< "$status_files"
  # At least one summary.jsonl must exist in phase dir
  local summaries
  summaries=$(ls "$PHASE_DIR"/*.summary.jsonl 2>/dev/null | head -1) || true
  [ -n "$summaries" ] || return 1
  return 0
}

# --- Polling loop ---
START_TIME=$(date +%s)
while true; do
  # Check gate condition using function dispatch
  # Convert hyphens to underscores: ux-complete -> check_ux_complete
  if "check_${GATE//-/_}"; then
    exit 0  # Gate satisfied
  fi

  # If --no-poll, single check mode
  if [ "$NO_POLL" = true ]; then
    exit 1  # Gate not satisfied, no polling
  fi

  # Check timeout
  ELAPSED=$(( $(date +%s) - START_TIME ))
  if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
    echo "TIMEOUT: Gate '$GATE' not satisfied after ${TIMEOUT}s" >&2
    exit 1
  fi

  sleep "$POLL_INTERVAL"
done
