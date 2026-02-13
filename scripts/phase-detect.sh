#!/bin/bash
set -u
# Pre-compute all project state for implement.md and other commands.
# Output: key=value pairs on stdout, one per line. Exit 0 always.

PLANNING_DIR=".vbw-planning"

# --- jq availability ---
JQ_AVAILABLE=false
if command -v jq &>/dev/null; then
  JQ_AVAILABLE=true
fi
echo "jq_available=$JQ_AVAILABLE"

# --- Planning directory ---
if [ -d "$PLANNING_DIR" ]; then
  echo "planning_dir_exists=true"
else
  echo "planning_dir_exists=false"
  echo "project_exists=false"
  echo "active_milestone=none"
  echo "phases_dir=none"
  echo "phase_count=0"
  echo "next_phase=none"
  echo "next_phase_slug=none"
  echo "next_phase_state=no_phases"
  echo "next_phase_plans=0"
  echo "next_phase_summaries=0"
  echo "config_effort=balanced"
  echo "config_autonomy=standard"
  echo "config_auto_commit=true"
  echo "config_verification_tier=standard"
  echo "config_agent_teams=false"
  echo "config_max_tasks_per_plan=5"
  echo "config_context_compiler=true"
  echo "config_security_audit=false"
  echo "config_approval_qa_fail=false"
  echo "config_approval_security_warn=false"
  echo "has_codebase_map=false"
  echo "brownfield=false"
  echo "execution_state=none"
  exit 0
fi

# --- Project existence ---
PROJECT_EXISTS=false
if [ -f "$PLANNING_DIR/PROJECT.md" ]; then
  if ! grep -q '{project-description}' "$PLANNING_DIR/PROJECT.md" 2>/dev/null; then
    PROJECT_EXISTS=true
  fi
fi
echo "project_exists=$PROJECT_EXISTS"

# --- Active milestone resolution ---
ACTIVE_MILESTONE="none"
ACTIVE_MILESTONE_ERROR=false
PHASES_DIR="$PLANNING_DIR/phases"

if [ -f "$PLANNING_DIR/ACTIVE" ]; then
  SLUG=$(cat "$PLANNING_DIR/ACTIVE" 2>/dev/null | tr -d '[:space:]')
  if [ -n "$SLUG" ]; then
    CANDIDATE="$PLANNING_DIR/milestones/$SLUG/phases"
    if [ -d "$CANDIDATE" ]; then
      ACTIVE_MILESTONE="$SLUG"
      PHASES_DIR="$CANDIDATE"
    else
      ACTIVE_MILESTONE_ERROR=true
      # Fall back to default phases dir
    fi
  fi
fi
echo "active_milestone=$ACTIVE_MILESTONE"
echo "active_milestone_error=$ACTIVE_MILESTONE_ERROR"
echo "phases_dir=$PHASES_DIR"

# --- Phase scanning ---
PHASE_COUNT=0
NEXT_PHASE="none"
NEXT_PHASE_SLUG="none"
NEXT_PHASE_STATE="no_phases"
NEXT_PHASE_PLANS=0
NEXT_PHASE_SUMMARIES=0

if [ -d "$PHASES_DIR" ]; then
  # Collect phase directories in sorted order
  PHASE_DIRS=$(ls -d "$PHASES_DIR"/*/ 2>/dev/null | sort)

  for DIR in $PHASE_DIRS; do
    PHASE_COUNT=$((PHASE_COUNT + 1))
  done

  if [ "$PHASE_COUNT" -eq 0 ]; then
    NEXT_PHASE_STATE="no_phases"
  else
    ALL_DONE=true
    for DIR in $PHASE_DIRS; do
      DIRNAME=$(basename "$DIR")
      # Extract numeric prefix (e.g., "01" from "01-context-diet")
      NUM=$(echo "$DIRNAME" | sed 's/^\([0-9]*\).*/\1/')

      # Count plan and summary files (JSONL format or legacy PLAN.md)
      P_COUNT=$(ls "$DIR"*.plan.jsonl "$DIR"*-PLAN.md 2>/dev/null | wc -l | tr -d ' ')
      S_COUNT=$(ls "$DIR"*.summary.jsonl "$DIR"*-SUMMARY.md 2>/dev/null | wc -l | tr -d ' ')

      if [ "$P_COUNT" -eq 0 ]; then
        # Needs plan and execute
        if [ "$NEXT_PHASE" = "none" ]; then
          NEXT_PHASE="$NUM"
          NEXT_PHASE_SLUG="$DIRNAME"
          NEXT_PHASE_STATE="needs_plan_and_execute"
          NEXT_PHASE_PLANS="$P_COUNT"
          NEXT_PHASE_SUMMARIES="$S_COUNT"
        fi
        ALL_DONE=false
        break
      elif [ "$S_COUNT" -lt "$P_COUNT" ]; then
        # Has plans but not all have summaries — needs execute
        if [ "$NEXT_PHASE" = "none" ]; then
          NEXT_PHASE="$NUM"
          NEXT_PHASE_SLUG="$DIRNAME"
          NEXT_PHASE_STATE="needs_execute"
          NEXT_PHASE_PLANS="$P_COUNT"
          NEXT_PHASE_SUMMARIES="$S_COUNT"
        fi
        ALL_DONE=false
        break
      fi
      # This phase is complete, continue scanning
    done

    if [ "$ALL_DONE" = true ] && [ "$NEXT_PHASE" = "none" ]; then
      NEXT_PHASE_STATE="all_done"
    fi
  fi
fi

echo "phase_count=$PHASE_COUNT"
echo "next_phase=$NEXT_PHASE"
echo "next_phase_slug=$NEXT_PHASE_SLUG"
echo "next_phase_state=$NEXT_PHASE_STATE"
echo "next_phase_plans=$NEXT_PHASE_PLANS"
echo "next_phase_summaries=$NEXT_PHASE_SUMMARIES"

# --- Config values ---
CONFIG_FILE="$PLANNING_DIR/config.json"

# Defaults (from config/defaults.json)
CFG_EFFORT="balanced"
CFG_AUTONOMY="standard"
CFG_AUTO_COMMIT="true"
CFG_VERIFICATION_TIER="standard"
CFG_AGENT_TEAMS="false"
CFG_MAX_TASKS="5"
CFG_COMPACTION="130000"
CFG_CONTEXT_COMPILER="true"
CFG_SECURITY_AUDIT="false"
CFG_APPROVAL_QA_FAIL="false"
CFG_APPROVAL_SECURITY_WARN="false"

if [ "$JQ_AVAILABLE" = true ] && [ -f "$CONFIG_FILE" ]; then
  CFG_EFFORT=$(jq -r '.effort // "balanced"' "$CONFIG_FILE" 2>/dev/null)
  CFG_AUTONOMY=$(jq -r '.autonomy // "standard"' "$CONFIG_FILE" 2>/dev/null)
  CFG_AUTO_COMMIT=$(jq -r '.auto_commit // true' "$CONFIG_FILE" 2>/dev/null)
  CFG_VERIFICATION_TIER=$(jq -r '.verification_tier // "standard"' "$CONFIG_FILE" 2>/dev/null)
  CFG_AGENT_TEAMS=$(jq -r '.agent_teams // false' "$CONFIG_FILE" 2>/dev/null)
  CFG_MAX_TASKS=$(jq -r '.max_tasks_per_plan // 5' "$CONFIG_FILE" 2>/dev/null)
  CFG_CONTEXT_COMPILER=$(jq -r '.context_compiler // true' "$CONFIG_FILE" 2>/dev/null)
  CFG_SECURITY_AUDIT=$(jq -r '.security_audit // false' "$CONFIG_FILE" 2>/dev/null)
  CFG_APPROVAL_QA_FAIL=$(jq -r '.approval_gates.qa_fail // false' "$CONFIG_FILE" 2>/dev/null)
  CFG_APPROVAL_SECURITY_WARN=$(jq -r '.approval_gates.security_warn // false' "$CONFIG_FILE" 2>/dev/null)
fi

echo "config_effort=$CFG_EFFORT"
echo "config_autonomy=$CFG_AUTONOMY"
echo "config_auto_commit=$CFG_AUTO_COMMIT"
echo "config_verification_tier=$CFG_VERIFICATION_TIER"
echo "config_agent_teams=$CFG_AGENT_TEAMS"
echo "config_max_tasks_per_plan=$CFG_MAX_TASKS"
echo "config_context_compiler=$CFG_CONTEXT_COMPILER"
echo "config_security_audit=$CFG_SECURITY_AUDIT"
echo "config_approval_qa_fail=$CFG_APPROVAL_QA_FAIL"
echo "config_approval_security_warn=$CFG_APPROVAL_SECURITY_WARN"

# --- Codebase map status ---
if [ -f "$PLANNING_DIR/codebase/META.md" ]; then
  echo "has_codebase_map=true"
else
  echo "has_codebase_map=false"
fi

# --- Brownfield detection ---
BROWNFIELD=false
if git ls-files --error-unmatch . 2>/dev/null | head -1 | grep -q .; then
  BROWNFIELD=true
fi
echo "brownfield=$BROWNFIELD"

# --- State from state.json ---
STATE_JSON="$PLANNING_DIR/state.json"
if [ -f "$STATE_JSON" ] && [ "$JQ_AVAILABLE" = true ]; then
  echo "current_phase=$(jq -r '.ph // ""' "$STATE_JSON" 2>/dev/null)"
  echo "total_phases=$(jq -r '.tt // ""' "$STATE_JSON" 2>/dev/null)"
  echo "workflow_status=$(jq -r '.st // ""' "$STATE_JSON" 2>/dev/null)"
  echo "workflow_step=$(jq -r '.step // ""' "$STATE_JSON" 2>/dev/null)"
  echo "progress=$(jq -r '.pr // 0' "$STATE_JSON" 2>/dev/null)"
else
  echo "current_phase="
  echo "total_phases="
  echo "workflow_status="
  echo "workflow_step="
  echo "progress=0"
fi

# --- Execution state ---
EXEC_STATE_FILE="$PLANNING_DIR/.execution-state.json"
EXEC_STATE="none"
if [ -f "$EXEC_STATE_FILE" ]; then
  if [ "$JQ_AVAILABLE" = true ]; then
    EXEC_STATE=$(jq -r '.status // "none"' "$EXEC_STATE_FILE" 2>/dev/null)
  else
    # Fallback: grep for status field
    EXEC_STATE=$(grep -o '"status"[[:space:]]*:[[:space:]]*"[^"]*"' "$EXEC_STATE_FILE" 2>/dev/null | head -1 | sed 's/.*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    if [ -z "$EXEC_STATE" ]; then
      EXEC_STATE="none"
    fi
  fi
fi
echo "execution_state=$EXEC_STATE"

exit 0
