#!/usr/bin/env bash
# resolve-agent-model.sh - Model resolution for YOLO agents
#
# Reads model_profile from config.json, loads preset from model-profiles.json,
# applies per-agent overrides, and returns the final model string.
#
# Usage: resolve-agent-model.sh <agent-name> <config-path> <profiles-path>
#   agent-name: Any agent key present in model-profiles.json (e.g., analyze, po, questionary, roadmap, lead, dev, fe-architect, ux-dev, owner, fe-security, ux-security, documenter, fe-documenter, ux-documenter)
#   config-path: path to .yolo-planning/config.json
#   profiles-path: path to config/model-profiles.json
#
# Returns: stdout = model string (opus|sonnet|haiku), exit 0
# Errors: stderr = error message, exit 1
#
# Integration pattern (from command files):
#   MODEL=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh lead .yolo-planning/config.json ${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json)
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

# Validate config file exists
if [ ! -f "$CONFIG_PATH" ]; then
  echo "Config not found at $CONFIG_PATH. Run /yolo:init first." >&2
  exit 1
fi

# Validate profiles file exists
if [ ! -f "$PROFILES_PATH" ]; then
  echo "Model profiles not found at $PROFILES_PATH. Plugin installation issue." >&2
  exit 1
fi

# Single jq call: read config + profiles, validate, resolve model with overrides
MODEL=$(jq -r --arg agent "$AGENT" --slurpfile profiles "$PROFILES_PATH" '
  (.model_profile // "balanced") as $profile |
  if ($profiles[0] | has($profile) | not) then
    "ERROR:invalid_profile:" + $profile
  elif ($profiles[0][$profile] | has($agent) | not) then
    "ERROR:unknown_agent:" + $agent + ":" + $profile
  else
    ($profiles[0][$profile][$agent]) as $base |
    (.model_overrides[$agent] // "") as $override |
    if ($override | length) > 0 then $override else $base end
  end
' "$CONFIG_PATH" 2>/dev/null)

# Handle errors and validate final model value
case "$MODEL" in
  ERROR:invalid_profile:*)
    PROFILE="${MODEL#ERROR:invalid_profile:}"
    echo "Invalid model_profile '$PROFILE'. Valid: quality, balanced, budget" >&2
    exit 1
    ;;
  ERROR:unknown_agent:*)
    IFS=: read -r _ _ AGENT_ERR PROFILE_ERR <<< "$MODEL"
    echo "Unknown agent '$AGENT_ERR' for profile '$PROFILE_ERR'. Check model-profiles.json for valid agents." >&2
    exit 1
    ;;
  opus|sonnet|haiku)
    echo "$MODEL"
    ;;
  *)
    echo "Invalid model '$MODEL' for $AGENT. Valid: opus, sonnet, haiku" >&2
    exit 1
    ;;
esac
