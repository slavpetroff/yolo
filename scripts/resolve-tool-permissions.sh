#!/usr/bin/env bash
# resolve-tool-permissions.sh — Resolve agent tool permissions per project type
# Merges base tools from agent YAML frontmatter with project-type overrides.
# Output consumed by compile-context.sh for soft enforcement (D4).
#
# Usage: resolve-tool-permissions.sh --role <role> --project-dir <path> [--config <tool-permissions.json>]
# Output: JSON {role, project_type, base_tools, tools, disallowed_tools}
# Exit: 0=success, 1=error
set -euo pipefail

# --- jq dependency check ---
if ! command -v jq &>/dev/null; then
  echo "Error: jq is required but not installed. Install: brew install jq (macOS) / apt install jq (Linux)" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Argument parsing ---
ROLE=""
PROJECT_DIR=""
CONFIG_FILE="$SCRIPT_DIR/../config/tool-permissions.json"

while [ $# -gt 0 ]; do
  case "$1" in
    --role)
      ROLE="$2"
      shift 2
      ;;
    --project-dir)
      PROJECT_DIR="$2"
      shift 2
      ;;
    --config)
      CONFIG_FILE="$2"
      shift 2
      ;;
    *)
      echo "Usage: resolve-tool-permissions.sh --role <role> --project-dir <path> [--config <tool-permissions.json>]" >&2
      exit 1
      ;;
  esac
done

if [ -z "$ROLE" ] || [ -z "$PROJECT_DIR" ]; then
  echo "Usage: resolve-tool-permissions.sh --role <role> --project-dir <path> [--config <tool-permissions.json>]" >&2
  exit 1
fi

# --- Department/base-role extraction ---
case "$ROLE" in
  fe-*)
    DEPT="fe"
    BASE_ROLE="${ROLE#fe-}"
    ;;
  ux-*)
    DEPT="ux"
    BASE_ROLE="${ROLE#ux-}"
    ;;
  owner)
    DEPT="shared"
    BASE_ROLE="owner"
    ;;
  *)
    DEPT="backend"
    BASE_ROLE="$ROLE"
    ;;
esac

# --- Step 1: Detect project type ---
DETECT_SCRIPT="$SCRIPT_DIR/detect-stack.sh"
if [ ! -f "$DETECT_SCRIPT" ]; then
  echo "Error: detect-stack.sh not found at $DETECT_SCRIPT" >&2
  exit 1
fi

PROJECT_TYPE=$(bash "$DETECT_SCRIPT" "$PROJECT_DIR" 2>/dev/null | jq -r '.project_type // "generic"') || PROJECT_TYPE="generic"
if [ -z "$PROJECT_TYPE" ] || [ "$PROJECT_TYPE" = "null" ]; then
  PROJECT_TYPE="generic"
fi

# --- Step 2: Read base tools from agent YAML frontmatter ---
AGENTS_DIR="$SCRIPT_DIR/../agents"
AGENT_FILE="$AGENTS_DIR/yolo-${ROLE}.md"

if [ ! -f "$AGENT_FILE" ]; then
  echo "Error: Agent file not found: yolo-${ROLE}.md" >&2
  exit 1
fi

BASE_TOOLS_CSV=$(grep '^tools:' "$AGENT_FILE" | sed 's/^tools: *//' | tr -d ' ')
BASE_DISALLOWED_CSV=$(grep '^disallowedTools:' "$AGENT_FILE" | sed 's/^disallowedTools: *//' | tr -d ' ')

# --- Step 3: Read overrides from tool-permissions.json ---
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Tool permissions config not found at $CONFIG_FILE" >&2
  exit 1
fi

# Check if the project type exists in config; fall back to generic if not
TYPE_EXISTS=$(jq -r --arg pt "$PROJECT_TYPE" '.types | has($pt)' "$CONFIG_FILE")
if [ "$TYPE_EXISTS" != "true" ]; then
  PROJECT_TYPE="generic"
fi

ADD_TOOLS=$(jq -r --arg pt "$PROJECT_TYPE" --arg role "$BASE_ROLE" \
  '.types[$pt][$role].add_tools // [] | join(",")' "$CONFIG_FILE")
REMOVE_TOOLS=$(jq -r --arg pt "$PROJECT_TYPE" --arg role "$BASE_ROLE" \
  '.types[$pt][$role].remove_tools // [] | join(",")' "$CONFIG_FILE")

# --- Step 4: Protected tools guard ---
PROTECTED="Bash,Read,Glob,Grep,Write,Edit"
if [ -n "$REMOVE_TOOLS" ]; then
  FILTERED_REMOVE=""
  IFS=',' read -ra remove_arr <<< "$REMOVE_TOOLS"
  for tool in "${remove_arr[@]}"; do
    [ -z "$tool" ] && continue
    # Check if tool is protected
    is_protected=false
    IFS=',' read -ra prot_arr <<< "$PROTECTED"
    for p in "${prot_arr[@]}"; do
      if [ "$tool" = "$p" ]; then
        is_protected=true
        break
      fi
    done
    if [ "$is_protected" = false ]; then
      if [ -n "$FILTERED_REMOVE" ]; then
        FILTERED_REMOVE="$FILTERED_REMOVE,$tool"
      else
        FILTERED_REMOVE="$tool"
      fi
    fi
  done
  REMOVE_TOOLS="$FILTERED_REMOVE"
fi

# --- Step 5: Merge and output JSON ---
jq -n \
  --arg role "$ROLE" \
  --arg project_type "$PROJECT_TYPE" \
  --arg base_tools "$BASE_TOOLS_CSV" \
  --arg add_tools "$ADD_TOOLS" \
  --arg remove_tools "$REMOVE_TOOLS" \
  --arg base_disallowed "$BASE_DISALLOWED_CSV" \
  '{
    role: $role,
    project_type: $project_type,
    base_tools: ($base_tools | split(",") | map(select(. != ""))),
    tools: (
      (($base_tools | split(",") | map(select(. != ""))) +
       ($add_tools | split(",") | map(select(. != "")))) |
      unique |
      . - ($remove_tools | split(",") | map(select(. != "")))
    ),
    disallowed_tools: (
      (($base_disallowed | split(",") | map(select(. != ""))) +
       ($remove_tools | split(",") | map(select(. != ""))) +
       ["EnterPlanMode", "ExitPlanMode"]) |
      unique
    )
  }'
