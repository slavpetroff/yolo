#!/bin/bash
set -u
# SubagentStart hook: Regenerate department agent .md from template + overlay
# before the agent spawns, ensuring it always uses current template content.
#
# Parses agent name from hook input, checks if it's one of the 27 department
# agents (9 roles x 3 depts), extracts role + dept, and calls generate-agent.sh.
#
# Non-department agents (owner, critic, scout, etc.) are silently skipped.
# Errors are swallowed — exit 0 always (graceful degradation per DXP-01).
#
# Reads YOLO_AGENT_MODE env var (set by go.md) to pass --mode to generate-agent.sh
# for per-step token savings via mode filtering.

INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

# Extract agent name from hook input (agent-start.sh uses agent_type, validate-dept-spawn.sh uses agent_name)
AGENT_NAME=$(jq -r '.agent_type // .agent_name // .tool_input.name // ""' <<< "$INPUT" 2>/dev/null) || true
[ -z "$AGENT_NAME" ] && exit 0

# --- Identify department agents and extract role + dept ---
# Department agents follow: yolo-{prefix}{role}
# Backend: yolo-{role} (no prefix)
# Frontend: yolo-fe-{role}
# UI/UX: yolo-ux-{role}

VALID_ROLES="architect lead senior dev tester qa qa-code security documenter"
ROLE=""
DEPT=""

case "$AGENT_NAME" in
  yolo-fe-*)
    ROLE="${AGENT_NAME#yolo-fe-}"
    DEPT="frontend"
    ;;
  yolo-ux-*)
    ROLE="${AGENT_NAME#yolo-ux-}"
    DEPT="uiux"
    ;;
  yolo-*)
    ROLE="${AGENT_NAME#yolo-}"
    DEPT="backend"
    ;;
  *)
    exit 0  # Not a yolo agent
    ;;
esac

# Validate role is one of the 9 department roles (skip non-dept agents like owner, critic, scout)
VALID=false
for r in $VALID_ROLES; do
  if [ "$r" = "$ROLE" ]; then
    VALID=true
    break
  fi
done
[ "$VALID" != "true" ] && exit 0

# --- Locate generate-agent.sh ---
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
GENERATE="$SCRIPT_DIR/generate-agent.sh"
[ ! -f "$GENERATE" ] && exit 0

# --- Build flags ---
FLAGS=(--role "$ROLE" --dept "$DEPT")

# Pass --mode if YOLO_AGENT_MODE is set (go.md sets this per workflow step)
if [ -n "${YOLO_AGENT_MODE:-}" ]; then
  FLAGS+=(--mode "$YOLO_AGENT_MODE")
fi

# --- Generate (swallow errors) ---
bash "$GENERATE" "${FLAGS[@]}" >/dev/null 2>&1 || true

exit 0
