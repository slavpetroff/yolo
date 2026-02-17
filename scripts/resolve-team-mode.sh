#!/usr/bin/env bash
set -euo pipefail

# resolve-team-mode.sh -- Team mode resolution for spawn strategy
# Reads team_mode from config, validates requirements, outputs effective mode.
# Called by go.md to determine Task tool vs Teammate API spawning.
#
# Usage: bash scripts/resolve-team-mode.sh [config_path]
# Output: Key-value pairs:
#   team_mode=task|teammate|auto
#   fallback_notice=true|false
#   auto_detected=true|false (3rd line, only when input team_mode=auto)
#
# team_mode=task: spawn agents via Task tool (default, proven)
# team_mode=teammate: spawn agents via Teammate API (experimental)
# team_mode=auto: detect optimal mode from environment (env var + config)
# fallback_notice=true: teammate was requested but unavailable, fell back to task

CONFIG="${1:-.yolo-planning/config.json}"

if [ ! -f "$CONFIG" ]; then
  echo "team_mode=task"
  echo "fallback_notice=false"
  exit 0
fi

IFS='|' read -r TEAM_MODE AGENT_TEAMS <<< "$(jq -r '[(.team_mode // "task"), (if .agent_teams == null then true else .agent_teams end | tostring)] | join("|")' "$CONFIG")"

FALLBACK_NOTICE="false"

# Auto mode: detect optimal team_mode from environment
if [ "$TEAM_MODE" = "auto" ]; then
  AUTO_INPUT=true
  # Check preconditions for teammate mode
  if [ "$AGENT_TEAMS" = "true" ] && [ -n "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-}" ]; then
    TEAM_MODE="teammate"
  else
    TEAM_MODE="task"
    FALLBACK_NOTICE="true"
  fi
else
  AUTO_INPUT=false
fi

# Validation: agent_teams must be enabled for teammate mode
if [ "$TEAM_MODE" = "teammate" ] && [ "$AGENT_TEAMS" != "true" ]; then
  TEAM_MODE="task"
  FALLBACK_NOTICE="true"
fi

# Validation: env var must be set for teammate mode
if [ "$TEAM_MODE" = "teammate" ]; then
  if [ -z "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-}" ]; then
    TEAM_MODE="task"
    FALLBACK_NOTICE="true"
  fi
fi

echo "team_mode=$TEAM_MODE"
echo "fallback_notice=$FALLBACK_NOTICE"
if [ "$AUTO_INPUT" = true ]; then
  if [ "$TEAM_MODE" = "teammate" ]; then
    echo "auto_detected=true"
  else
    echo "auto_detected=false"
  fi
fi
