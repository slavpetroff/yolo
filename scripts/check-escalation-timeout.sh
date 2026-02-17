#!/usr/bin/env bash
set -euo pipefail

# check-escalation-timeout.sh -- Detect stale pending escalations
#
# Reads .execution-state.json escalations array. Compares each pending
# escalation's last_escalated_at against escalation.timeout_seconds from config.
#
# Usage: check-escalation-timeout.sh --phase-dir <path> [--config <path>]
# Output: JSON {timed_out:[...], active:[...], resolved:N}
# Exit codes: 0 = no timeouts, 1 = timed-out escalations found

# --- jq dependency check ---
if ! command -v jq &>/dev/null; then
  echo '{"error":"jq is required but not installed. Install: brew install jq (macOS) / apt install jq (Linux)"}' >&2
  exit 1
fi

# --- Arg parsing ---
PHASE_DIR=""
CONFIG_FILE="config/defaults.json"

while [ $# -gt 0 ]; do
  case "$1" in
    --phase-dir) PHASE_DIR="$2"; shift 2 ;;
    --config) CONFIG_FILE="$2"; shift 2 ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

if [ -z "$PHASE_DIR" ]; then
  echo "Usage: check-escalation-timeout.sh --phase-dir <path> [--config <path>]" >&2
  exit 1
fi

# --- State file ---
STATE_FILE="$PHASE_DIR/.execution-state.json"

# If file does not exist or has no 'escalations' key, output empty result
if [ ! -f "$STATE_FILE" ]; then
  echo '{"timed_out":[],"active":[],"resolved":0}'
  exit 0
fi

HAS_ESCALATIONS=$(jq -e '.escalations' "$STATE_FILE" 2>/dev/null) || true
if [ -z "$HAS_ESCALATIONS" ] || [ "$HAS_ESCALATIONS" = "null" ]; then
  echo '{"timed_out":[],"active":[],"resolved":0}'
  exit 0
fi

# --- Read timeout from config ---
if [ -f "$CONFIG_FILE" ]; then
  TIMEOUT=$(jq -r '.escalation.timeout_seconds // 300' "$CONFIG_FILE")
else
  TIMEOUT=300
fi

# --- Portable ISO date to epoch helper ---
parse_iso_to_epoch() {
  local iso="$1"
  # Try GNU date first (Linux) -- handles Z suffix natively
  date -d "$iso" +%s 2>/dev/null && return 0
  # Try BSD date (macOS) -- force UTC via TZ env to handle Z suffix
  TZ=UTC date -jf "%Y-%m-%dT%H:%M:%SZ" "$iso" +%s 2>/dev/null && return 0
  TZ=UTC date -jf "%Y-%m-%dT%H:%M:%S" "${iso%%Z}" +%s 2>/dev/null && return 0
  # Fallback: return 0 (epoch start -- will always trigger timeout)
  echo 0
}

# --- Get current timestamp ---
NOW=$(date +%s)

# --- Process escalations with jq ---
# Extract pending, resolved counts
RESOLVED=$(jq '[.escalations[] | select(.status == "resolved")] | length' "$STATE_FILE")
PENDING_JSON=$(jq -c '[.escalations[] | select(.status == "pending")]' "$STATE_FILE")

# Build timed_out and active arrays
TIMED_OUT="[]"
ACTIVE="[]"

# Iterate over pending escalations
PENDING_COUNT=$(echo "$PENDING_JSON" | jq 'length')
for ((i = 0; i < PENDING_COUNT; i++)); do
  ENTRY=$(echo "$PENDING_JSON" | jq -c ".[$i]")
  ESC_ID=$(echo "$ENTRY" | jq -r '.id // "unknown"')
  ESC_TASK=$(echo "$ENTRY" | jq -r '.task // "unknown"')
  LAST_AT=$(echo "$ENTRY" | jq -r '.last_escalated_at // ""')

  if [ -z "$LAST_AT" ]; then
    ELAPSED=$((NOW))
  else
    EPOCH=$(parse_iso_to_epoch "$LAST_AT")
    ELAPSED=$((NOW - EPOCH))
  fi

  if [ "$ELAPSED" -gt "$TIMEOUT" ]; then
    TIMED_OUT=$(echo "$TIMED_OUT" | jq -c \
      --arg id "$ESC_ID" \
      --arg task "$ESC_TASK" \
      --argjson elapsed "$ELAPSED" \
      '. + [{"id":$id,"task":$task,"elapsed_seconds":$elapsed,"recommended_action":"Auto-escalate to next level"}]')
  else
    ACTIVE=$(echo "$ACTIVE" | jq -c \
      --arg id "$ESC_ID" \
      --arg task "$ESC_TASK" \
      --argjson elapsed "$ELAPSED" \
      '. + [{"id":$id,"task":$task,"elapsed_seconds":$elapsed}]')
  fi
done

# --- Output final JSON ---
jq -n \
  --argjson timed_out "$TIMED_OUT" \
  --argjson active "$ACTIVE" \
  --argjson resolved "$RESOLVED" \
  '{"timed_out":$timed_out,"active":$active,"resolved":$resolved}'

# --- Exit code ---
TIMED_OUT_COUNT=$(echo "$TIMED_OUT" | jq 'length')
if [ "$TIMED_OUT_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
