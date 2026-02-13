#!/usr/bin/env bash
# resolve-agent-model.sh - Model resolution for VBW agents
#
# Reads model_profile from config.json, loads preset from model-profiles.json,
# applies per-agent overrides, and returns the final model string.
#
# Usage: resolve-agent-model.sh <agent-name> <config-path> <profiles-path>
#   agent-name: lead|dev|qa|qa-code|scout|debugger|architect|senior|security
#   config-path: path to .vbw-planning/config.json
#   profiles-path: path to config/model-profiles.json
#
# Returns: stdout = model string (opus|sonnet|haiku), exit 0
# Errors: stderr = error message, exit 1
#
# Integration pattern (from command files):
#   MODEL=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh lead .vbw-planning/config.json ${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json)
#   if [ $? -ne 0 ]; then echo "Model resolution failed"; exit 1; fi
#   # Pass to Task tool: model: "${MODEL}"

set -euo pipefail

# Argument parsing
if [ $# -ne 3 ]; then
  echo "Usage: resolve-agent-model.sh <agent-name> <config-path> <profiles-path>" >&2
  exit 1
fi

AGENT="$1"
CONFIG_PATH="$2"
PROFILES_PATH="$3"

# Validate agent name
case "$AGENT" in
  lead|dev|qa|qa-code|scout|debugger|architect|senior|security)
    # Valid agent
    ;;
  *)
    echo "Invalid agent name '$AGENT'. Valid: lead, dev, qa, qa-code, scout, debugger, architect, senior, security" >&2
    exit 1
    ;;
esac

# Validate config file exists
if [ ! -f "$CONFIG_PATH" ]; then
  echo "Config not found at $CONFIG_PATH. Run /vbw:init first." >&2
  exit 1
fi

# Validate profiles file exists
if [ ! -f "$PROFILES_PATH" ]; then
  echo "Model profiles not found at $PROFILES_PATH. Plugin installation issue." >&2
  exit 1
fi

# Read model_profile from config.json (default to "balanced")
PROFILE=$(jq -r '.model_profile // "balanced"' "$CONFIG_PATH")

# Validate profile exists in model-profiles.json
if ! jq -e ".$PROFILE" "$PROFILES_PATH" >/dev/null 2>&1; then
  echo "Invalid model_profile '$PROFILE'. Valid: quality, balanced, budget" >&2
  exit 1
fi

# Get model from preset for the agent (--arg avoids jq interpreting hyphens as operators)
MODEL=$(jq -r --arg p "$PROFILE" --arg a "$AGENT" '.[$p][$a]' "$PROFILES_PATH")

# Check for per-agent override in config.json model_overrides
OVERRIDE=$(jq -r --arg a "$AGENT" '.model_overrides[$a] // ""' "$CONFIG_PATH")
if [ -n "$OVERRIDE" ]; then
  MODEL="$OVERRIDE"
fi

# Validate final model value
case "$MODEL" in
  opus|sonnet|haiku)
    echo "$MODEL"
    ;;
  *)
    echo "Invalid model '$MODEL' for $AGENT. Valid: opus, sonnet, haiku" >&2
    exit 1
    ;;
esac
