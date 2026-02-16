#!/bin/bash
set -u
# Pre-compute all project state for implement.md and other commands.
# Output: key=value pairs on stdout, one per line. Exit 0 always.

PLANNING_DIR=".yolo-planning"

# --- jq availability ---
JQ_AVAILABLE=false
if command -v jq &>/dev/null; then
  JQ_AVAILABLE=true
fi
echo "jq_available=$JQ_AVAILABLE"

# --- Helper: print all default values ---
print_defaults() {
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
}

# --- Planning directory ---
# OPTIMIZATION 1: Early exit if planning dir missing
if [ ! -d "$PLANNING_DIR" ]; then
  echo "planning_dir_exists=false"
  print_defaults
  exit 0
fi
echo "planning_dir_exists=true"

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

# OPTIMIZATION 1 (continued): Early exit if phases dir missing or empty
if [ -d "$PHASES_DIR" ]; then
  # OPTIMIZATION 6: Bash array instead of mktemp for phase listing
  PHASE_DIRS=()
  while IFS= read -r d; do
    [ -n "$d" ] && PHASE_DIRS+=("$d")
  done <<< "$(command ls -d "$PHASES_DIR"/*/ 2>/dev/null | sort)"
  PHASE_COUNT=${#PHASE_DIRS[@]}

  if [ "$PHASE_COUNT" -eq 0 ]; then
    NEXT_PHASE_STATE="no_phases"
  else
    ALL_DONE=true
    for DIR in "${PHASE_DIRS[@]}"; do
      DIRNAME=$(basename "$DIR")
      # OPTIMIZATION 3: Parameter expansion instead of sed for phase number
      NUM=${DIRNAME%%-*}

      # OPTIMIZATION 2: Bash glob counting instead of find+wc+tr
      P_COUNT=0
      for f in "$DIR"/*.plan.jsonl "$DIR"/*-PLAN.md; do [ -f "$f" ] && P_COUNT=$((P_COUNT+1)); done
      S_COUNT=0
      for f in "$DIR"/*.summary.jsonl "$DIR"/*-SUMMARY.md; do [ -f "$f" ] && S_COUNT=$((S_COUNT+1)); done

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
  IFS='|' read -r CFG_EFFORT CFG_AUTONOMY CFG_AUTO_COMMIT CFG_VERIFICATION_TIER \
    CFG_AGENT_TEAMS CFG_MAX_TASKS CFG_CONTEXT_COMPILER CFG_SECURITY_AUDIT \
    CFG_APPROVAL_QA_FAIL CFG_APPROVAL_SECURITY_WARN <<< \
    "$(jq -r '[
      (.effort // "balanced"),
      (.autonomy // "standard"),
      (.auto_commit // true | tostring),
      (.verification_tier // "standard"),
      (.agent_teams // false | tostring),
      (.max_tasks_per_plan // 5 | tostring),
      (.context_compiler // true | tostring),
      (.security_audit // false | tostring),
      (.approval_gates.qa_fail // false | tostring),
      (.approval_gates.security_warn // false | tostring)
    ] | join("|")' "$CONFIG_FILE" 2>/dev/null)"
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

# --- State from state.json + execution state ---
# OPTIMIZATION 5: Batch state+exec jq reads into single call when possible
STATE_JSON="$PLANNING_DIR/state.json"
EXEC_STATE_FILE="$PLANNING_DIR/.execution-state.json"

if [ "$JQ_AVAILABLE" = true ] && [ -f "$STATE_JSON" ]; then
  if [ -f "$EXEC_STATE_FILE" ]; then
    # Both files exist: read in single jq call using --slurpfile
    IFS='|' read -r _ph _tt _st _step _pr _exec_st <<< \
      "$(jq -r --slurpfile exec "$EXEC_STATE_FILE" \
        '[(.ph // ""), (.tt // ""), (.st // ""), (.step // ""), (.pr // 0 | tostring), ($exec[0].status // "none")] | join("|")' "$STATE_JSON" 2>/dev/null)"
  else
    IFS='|' read -r _ph _tt _st _step _pr <<< \
      "$(jq -r '[(.ph // ""), (.tt // ""), (.st // ""), (.step // ""), (.pr // 0 | tostring)] | join("|")' "$STATE_JSON" 2>/dev/null)"
    _exec_st="none"
  fi
  echo "current_phase=${_ph:-}"
  echo "total_phases=${_tt:-}"
  echo "workflow_status=${_st:-}"
  echo "workflow_step=${_step:-}"
  echo "progress=${_pr:-0}"
  echo "execution_state=${_exec_st:-none}"
else
  echo "current_phase="
  echo "total_phases="
  echo "workflow_status="
  echo "workflow_step="
  echo "progress=0"
  # Execution state fallback (no jq or no state.json)
  EXEC_STATE="none"
  if [ -f "$EXEC_STATE_FILE" ]; then
    if [ "$JQ_AVAILABLE" = true ]; then
      EXEC_STATE=$(jq -r '.status // "none"' "$EXEC_STATE_FILE" 2>/dev/null)
    else
      EXEC_STATE=$(grep -o '"status"[[:space:]]*:[[:space:]]*"[^"]*"' "$EXEC_STATE_FILE" 2>/dev/null | head -1 | sed 's/.*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
      [ -z "$EXEC_STATE" ] && EXEC_STATE="none"
    fi
  fi
  echo "execution_state=$EXEC_STATE"
fi

exit 0
