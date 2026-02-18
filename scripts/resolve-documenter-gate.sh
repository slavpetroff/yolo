#!/usr/bin/env bash
# resolve-documenter-gate.sh — Determine whether Documenter agent should spawn
#
# Reads documenter config value and compares against trigger context.
# Default: on_request (spawn only when user explicitly asks).
#
# Usage: resolve-documenter-gate.sh --config <path> --trigger <phase|on_request>
#
# Output: JSON {"spawn":true|false,"reason":"..."}
# Exit 0 when spawn=true, exit 1 when spawn=false

set -u

CONFIG_PATH=""
TRIGGER=""

# Parse flags
while [ $# -gt 0 ]; do
  case "$1" in
    --config)
      CONFIG_PATH="$2"
      shift 2
      ;;
    --trigger)
      TRIGGER="$2"
      shift 2
      ;;
    *)
      echo "Usage: resolve-documenter-gate.sh --config <path> --trigger <phase|on_request>" >&2
      exit 1
      ;;
  esac
done

# Validate required flags
if [ -z "$CONFIG_PATH" ] || [ -z "$TRIGGER" ]; then
  echo "Usage: resolve-documenter-gate.sh --config <path> --trigger <phase|on_request>" >&2
  exit 1
fi

# Validate trigger value
if [ "$TRIGGER" != "phase" ] && [ "$TRIGGER" != "on_request" ]; then
  echo '{"spawn":false,"reason":"invalid trigger: must be phase or on_request"}'
  exit 1
fi

# jq dependency check — fail-closed (do not spawn if we cannot read config)
if ! command -v jq &>/dev/null; then
  echo '{"spawn":false,"reason":"jq not available, cannot read config"}'
  exit 1
fi

# Read documenter value from config, default to on_request
DOCUMENTER="on_request"
if [ -f "$CONFIG_PATH" ]; then
  val=$(jq -r '.documenter // "on_request"' "$CONFIG_PATH" 2>/dev/null) || val="on_request"
  if [ "$val" != "null" ] && [ -n "$val" ]; then
    DOCUMENTER="$val"
  fi
fi

# Gate logic
case "$DOCUMENTER" in
  never)
    echo '{"spawn":false,"reason":"documenter config is never"}'
    exit 1
    ;;
  always)
    echo '{"spawn":true,"reason":"documenter config is always"}'
    exit 0
    ;;
  on_request)
    if [ "$TRIGGER" = "on_request" ]; then
      echo '{"spawn":true,"reason":"documenter is on_request and user requested documentation"}'
      exit 0
    else
      echo '{"spawn":false,"reason":"documenter is on_request but trigger is phase (not explicitly requested)"}'
      exit 1
    fi
    ;;
  *)
    echo "{\"spawn\":false,\"reason\":\"unknown documenter value: $DOCUMENTER\"}"
    exit 1
    ;;
esac
