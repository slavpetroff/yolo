#!/usr/bin/env bash
set -euo pipefail

# resolve-research-request.sh -- Route research requests to Scout
#
# Parses a research_request JSON payload, classifies as blocking or
# informational, validates config limits, and appends an entry to
# research.jsonl with ra/rt fields populated.
#
# Usage: resolve-research-request.sh --phase-dir <path> --request-json <json|file> [--config <path>]
# Output: JSON {status:'dispatching'|'queued', request_type:string, ...}
# Exit codes: 0 = success, 1 = validation error

# --- jq dependency check ---
if ! command -v jq &>/dev/null; then
  echo '{"error":"jq is required but not installed. Install: brew install jq (macOS) / apt install jq (Linux)"}' >&2
  exit 1
fi

# --- Arg parsing ---
PHASE_DIR=""
REQUEST_JSON=""
CONFIG_FILE="config/defaults.json"

while [ $# -gt 0 ]; do
  case "$1" in
    --phase-dir) PHASE_DIR="$2"; shift 2 ;;
    --request-json) REQUEST_JSON="$2"; shift 2 ;;
    --config) CONFIG_FILE="$2"; shift 2 ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

if [ -z "$PHASE_DIR" ] || [ -z "$REQUEST_JSON" ]; then
  echo "Usage: resolve-research-request.sh --phase-dir <path> --request-json <json|file> [--config <path>]" >&2
  exit 1
fi

# --- Parse request JSON (string or file path) ---
if [ -f "$REQUEST_JSON" ]; then
  REQ=$(jq -c '.' "$REQUEST_JSON")
else
  REQ=$(echo "$REQUEST_JSON" | jq -c '.' 2>/dev/null) || {
    echo '{"error":"Invalid JSON in --request-json"}' >&2
    exit 1
  }
fi

# --- Extract fields ---
REQUEST_TYPE=$(echo "$REQ" | jq -r '.request_type // "informational"')
FROM=$(echo "$REQ" | jq -r '.from // "unknown"')
QUERY=$(echo "$REQ" | jq -r '.query // ""')
CONTEXT=$(echo "$REQ" | jq -r '.context // ""')
PRIORITY=$(echo "$REQ" | jq -r '.priority // "medium"')
TASK_REF=$(echo "$REQ" | jq -r '.task // ""')
PLAN_ID=$(echo "$REQ" | jq -r '.plan_id // ""')

# --- Validate required fields ---
if [ -z "$QUERY" ]; then
  echo '{"error":"Missing required field: query"}' >&2
  exit 1
fi

# --- Read config ---
BLOCKING_TIMEOUT=120
MAX_CONCURRENT_SCOUTS=4

if [ -f "$CONFIG_FILE" ]; then
  BLOCKING_TIMEOUT=$(jq -r '.research_requests.blocking_timeout_seconds // 120' "$CONFIG_FILE")
  MAX_CONCURRENT_SCOUTS=$(jq -r '.research_requests.max_concurrent_scouts // 4' "$CONFIG_FILE")
fi

# --- Route by request_type ---
DT=$(date -u +"%Y-%m-%d")

if [ "$REQUEST_TYPE" = "blocking" ]; then
  # Blocking: orchestrator spawns Scout synchronously and waits
  jq -n \
    --arg status "dispatching" \
    --arg request_type "blocking" \
    --argjson timeout "$BLOCKING_TIMEOUT" \
    --arg from "$FROM" \
    --arg query "$QUERY" \
    --arg priority "$PRIORITY" \
    --argjson max_scouts "$MAX_CONCURRENT_SCOUTS" \
    '{"status":$status,"request_type":$request_type,"timeout":$timeout,"from":$from,"query":$query,"priority":$priority,"max_concurrent_scouts":$max_scouts}'
else
  # Informational: orchestrator queues Scout spawn for after current task
  jq -n \
    --arg status "queued" \
    --arg request_type "informational" \
    --arg from "$FROM" \
    --arg query "$QUERY" \
    --arg priority "$PRIORITY" \
    --argjson max_scouts "$MAX_CONCURRENT_SCOUTS" \
    '{"status":$status,"request_type":$request_type,"from":$from,"query":$query,"priority":$priority,"max_concurrent_scouts":$max_scouts}'
fi

# --- Append entry to research.jsonl ---
RESEARCH_FILE="$PHASE_DIR/research.jsonl"

ENTRY=$(jq -n \
  --arg q "$QUERY" \
  --arg src "pending" \
  --arg finding "" \
  --arg conf "" \
  --arg dt "$DT" \
  --arg rel "$CONTEXT" \
  --arg ra "$FROM" \
  --arg rt "$REQUEST_TYPE" \
  --arg priority "$PRIORITY" \
  '{"q":$q,"src":$src,"finding":$finding,"conf":$conf,"dt":$dt,"rel":$rel,"ra":$ra,"rt":$rt,"priority":$priority}')

echo "$ENTRY" >> "$RESEARCH_FILE"

exit 0
