#!/usr/bin/env bash
set -u

# log-event.sh <event-type> <phase> [plan] [key=value ...]
# Appends a structured event to .vbw-planning/.events/event-log.jsonl
# Event types: phase_start, phase_end, plan_start, plan_end,
#              agent_spawn, agent_shutdown, error, checkpoint
# Exit 0 always — event logging must never block execution.

if [ $# -lt 2 ]; then
  exit 0
fi

PLANNING_DIR=".vbw-planning"
CONFIG_PATH="${PLANNING_DIR}/config.json"

# Check feature flag
if [ -f "$CONFIG_PATH" ] && command -v jq &>/dev/null; then
  ENABLED=$(jq -r '.v3_event_log // false' "$CONFIG_PATH" 2>/dev/null || echo "false")
  [ "$ENABLED" != "true" ] && exit 0
fi

EVENT_TYPE="$1"
PHASE="$2"
shift 2

PLAN=""
DATA_PAIRS=""

# Parse remaining args: first non-key=value arg is plan number
for arg in "$@"; do
  case "$arg" in
    *=*)
      KEY=$(echo "$arg" | cut -d'=' -f1)
      VALUE=$(echo "$arg" | cut -d'=' -f2-)
      if [ -n "$DATA_PAIRS" ]; then
        DATA_PAIRS="${DATA_PAIRS},\"${KEY}\":\"${VALUE}\""
      else
        DATA_PAIRS="\"${KEY}\":\"${VALUE}\""
      fi
      ;;
    *)
      if [ -z "$PLAN" ]; then
        PLAN="$arg"
      fi
      ;;
  esac
done

EVENTS_DIR="${PLANNING_DIR}/.events"
EVENTS_FILE="${EVENTS_DIR}/event-log.jsonl"

mkdir -p "$EVENTS_DIR" 2>/dev/null || exit 0

TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "unknown")

PLAN_FIELD=""
if [ -n "$PLAN" ]; then
  PLAN_FIELD=",\"plan\":${PLAN}"
fi

DATA_FIELD=""
if [ -n "$DATA_PAIRS" ]; then
  DATA_FIELD=",\"data\":{${DATA_PAIRS}}"
fi

echo "{\"ts\":\"${TS}\",\"event\":\"${EVENT_TYPE}\",\"phase\":${PHASE}${PLAN_FIELD}${DATA_FIELD}}" >> "$EVENTS_FILE" 2>/dev/null || true
