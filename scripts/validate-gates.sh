#!/usr/bin/env bash
set -euo pipefail

# validate-gates.sh — Validate verification gate artifacts per step
#
# Checks entry artifact existence per execute-protocol.md enforcement contract.
# Also checks skip status in .execution-state.json.
#
# Usage: validate-gates.sh --step <step_name> --phase-dir <path>
# Steps: critique, research, architecture, planning, design_review, test_authoring,
#        implementation, code_review, qa, security, signoff
# Output: JSON {gate:pass|fail,step:str,missing:[]}
# Exit codes: 0 = gate passes, 1 = gate fails or usage error

# --- jq dependency check ---
if ! command -v jq &>/dev/null; then
  echo '{"error":"jq is required but not installed. Install: brew install jq (macOS) / apt install jq (Linux)"}' >&2
  exit 1
fi

# --- Arg parsing ---
STEP=""
PHASE_DIR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --step) STEP="$2"; shift 2 ;;
    --phase-dir) PHASE_DIR="$2"; shift 2 ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

if [ -z "$STEP" ] || [ -z "$PHASE_DIR" ]; then
  echo "Usage: validate-gates.sh --step <step_name> --phase-dir <path>" >&2
  exit 1
fi

# --- State file ---
STATE_FILE="$PHASE_DIR/.execution-state.json"

# --- Helper functions ---

check_step_skipped() {
  local step_name="$1"
  if [ ! -f "$STATE_FILE" ]; then
    return 1
  fi
  local status
  status=$(jq -r --arg s "$step_name" '.steps[$s].status // ""' "$STATE_FILE" 2>/dev/null) || return 1
  if [ "$status" = "skipped" ]; then
    return 0
  fi
  return 1
}

check_artifact_exists() {
  local artifact_path="$1"
  if [ -f "$artifact_path" ] && [ -s "$artifact_path" ]; then
    return 0
  fi
  return 1
}

check_glob_exists() {
  local pattern="$1"
  local result
  result=$(ls $pattern 2>/dev/null | head -1) || true
  if [ -n "$result" ]; then
    return 0
  fi
  return 1
}

check_step_complete() {
  local step_name="$1"
  if [ ! -f "$STATE_FILE" ]; then
    return 1
  fi
  local status
  status=$(jq -r --arg s "$step_name" '.steps[$s].status // ""' "$STATE_FILE" 2>/dev/null) || return 1
  if [ "$status" = "complete" ]; then
    return 0
  fi
  return 1
}

# --- Global state ---
MISSING=()
GATE_RESULT="pass"

# --- Gate check dispatch (case statement lookup table, bash 3.2 compatible) ---
case "$STEP" in
  critique)
    # Entry: Phase dir exists
    if [ ! -d "$PHASE_DIR" ]; then
      MISSING+=("Phase directory does not exist: $PHASE_DIR")
      GATE_RESULT="fail"
    fi
    ;;

  architecture)
    # Entry: critique.jsonl OR step 1 skipped
    if ! check_artifact_exists "$PHASE_DIR/critique.jsonl" && ! check_step_skipped "critique"; then
      MISSING+=("critique.jsonl")
      GATE_RESULT="fail"
    fi
    ;;

  planning)
    # Entry: architecture.toon OR step 2 skipped
    if ! check_artifact_exists "$PHASE_DIR/architecture.toon" && ! check_step_skipped "architecture"; then
      MISSING+=("architecture.toon")
      GATE_RESULT="fail"
    fi
    ;;

  design_review)
    # Entry: *.plan.jsonl exists
    if ! check_glob_exists "$PHASE_DIR/*.plan.jsonl"; then
      MISSING+=("*.plan.jsonl")
      GATE_RESULT="fail"
    fi
    ;;

  test_authoring)
    # Entry: enriched plan.jsonl with spec fields
    _gate_plans=$(ls "$PHASE_DIR"/*.plan.jsonl 2>/dev/null) || true
    if [ -z "$_gate_plans" ]; then
      MISSING+=("*.plan.jsonl")
      GATE_RESULT="fail"
    else
      while IFS= read -r plan_file; do
        [ -z "$plan_file" ] && continue
        # Check that tasks have spec fields
        _has_missing_spec=false
        while IFS= read -r task_line; do
          [ -z "$task_line" ] && continue
          _spec_check=$(echo "$task_line" | jq -e '.spec // empty' 2>/dev/null) || true
          if [ -z "$_spec_check" ]; then
            _has_missing_spec=true
            break
          fi
        done < <(tail -n +2 "$plan_file")
        if [ "$_has_missing_spec" = "true" ]; then
          MISSING+=("$(basename "$plan_file"): tasks missing spec field")
          GATE_RESULT="fail"
        fi
      done <<< "$_gate_plans"
    fi
    ;;

  implementation)
    # Entry: enriched plan.jsonl + test-plan.jsonl (if step 5 ran)
    _gate_plans=$(ls "$PHASE_DIR"/*.plan.jsonl 2>/dev/null) || true
    if [ -z "$_gate_plans" ]; then
      MISSING+=("*.plan.jsonl")
      GATE_RESULT="fail"
    else
      while IFS= read -r plan_file; do
        [ -z "$plan_file" ] && continue
        _has_missing_spec=false
        while IFS= read -r task_line; do
          [ -z "$task_line" ] && continue
          _spec_check=$(echo "$task_line" | jq -e '.spec // empty' 2>/dev/null) || true
          if [ -z "$_spec_check" ]; then
            _has_missing_spec=true
            break
          fi
        done < <(tail -n +2 "$plan_file")
        if [ "$_has_missing_spec" = "true" ]; then
          MISSING+=("$(basename "$plan_file"): tasks missing spec field")
          GATE_RESULT="fail"
        fi
      done <<< "$_gate_plans"
    fi
    # Check test-plan.jsonl if test_authoring step completed
    if check_step_complete "test_authoring"; then
      if ! check_artifact_exists "$PHASE_DIR/test-plan.jsonl"; then
        MISSING+=("test-plan.jsonl (test_authoring step completed)")
        GATE_RESULT="fail"
      fi
    fi
    ;;

  code_review)
    # Entry: summary.jsonl for each plan
    _gate_plans=$(ls "$PHASE_DIR"/*.plan.jsonl 2>/dev/null) || true
    if [ -z "$_gate_plans" ]; then
      MISSING+=("*.plan.jsonl")
      GATE_RESULT="fail"
    else
      while IFS= read -r plan_file; do
        [ -z "$plan_file" ] && continue
        _plan_header=$(head -1 "$plan_file") || true
        _plan_p=$(echo "$_plan_header" | jq -r '.p // ""' 2>/dev/null) || true
        _plan_n=$(echo "$_plan_header" | jq -r '.n // ""' 2>/dev/null) || true
        _plan_id="${_plan_p}-${_plan_n}"
        if ! check_artifact_exists "$PHASE_DIR/${_plan_id}.summary.jsonl"; then
          MISSING+=("${_plan_id}.summary.jsonl")
          GATE_RESULT="fail"
        fi
      done <<< "$_gate_plans"
    fi
    ;;

  qa)
    # Entry: code-review.jsonl with r:approve
    if ! check_artifact_exists "$PHASE_DIR/code-review.jsonl"; then
      MISSING+=("code-review.jsonl")
      GATE_RESULT="fail"
    else
      _review_result=$(head -1 "$PHASE_DIR/code-review.jsonl" | jq -r '.r // ""' 2>/dev/null) || true
      if [ "$_review_result" != "approve" ]; then
        MISSING+=("code-review.jsonl: r must be 'approve' (got '$_review_result')")
        GATE_RESULT="fail"
      fi
    fi
    ;;

  security)
    # Entry: verification.jsonl OR step 8 skipped
    if ! check_artifact_exists "$PHASE_DIR/verification.jsonl" && ! check_step_skipped "qa"; then
      MISSING+=("verification.jsonl")
      GATE_RESULT="fail"
    fi
    ;;

  signoff)
    # Entry: security-audit.jsonl OR step 9 skipped + code-review approved
    if ! check_artifact_exists "$PHASE_DIR/security-audit.jsonl" && ! check_step_skipped "security"; then
      MISSING+=("security-audit.jsonl")
      GATE_RESULT="fail"
    fi
    # Also check code-review approved
    if ! check_artifact_exists "$PHASE_DIR/code-review.jsonl"; then
      MISSING+=("code-review.jsonl")
      GATE_RESULT="fail"
    else
      _review_result=$(head -1 "$PHASE_DIR/code-review.jsonl" | jq -r '.r // ""' 2>/dev/null) || true
      if [ "$_review_result" != "approve" ]; then
        MISSING+=("code-review.jsonl: r must be 'approve' (got '$_review_result')")
        GATE_RESULT="fail"
      fi
    fi
    ;;

  post_task_qa)
    # Entry: .qa-gate-results.jsonl contains post-task result for specified task
    if check_artifact_exists "$PHASE_DIR/.qa-gate-results.jsonl"; then
      # Verify at least one post-task entry exists
      _has_post_task=$(jq -r 'select(.gl=="post-task")' "$PHASE_DIR/.qa-gate-results.jsonl" 2>/dev/null | head -1) || true
      if [ -z "$_has_post_task" ]; then
        MISSING+=("post-task gate results in .qa-gate-results.jsonl")
        GATE_RESULT="fail"
      fi
    elif ! check_step_skipped "post_task_qa"; then
      MISSING+=(".qa-gate-results.jsonl")
      GATE_RESULT="fail"
    fi
    ;;

  post_plan_qa)
    # Entry: .qa-gate-results.jsonl contains post-plan result
    if check_artifact_exists "$PHASE_DIR/.qa-gate-results.jsonl"; then
      _has_post_plan=$(jq -r 'select(.gl=="post-plan")' "$PHASE_DIR/.qa-gate-results.jsonl" 2>/dev/null | head -1) || true
      if [ -z "$_has_post_plan" ]; then
        MISSING+=("post-plan gate results in .qa-gate-results.jsonl")
        GATE_RESULT="fail"
      fi
    elif ! check_step_skipped "post_plan_qa"; then
      MISSING+=(".qa-gate-results.jsonl")
      GATE_RESULT="fail"
    fi
    ;;

  research)
    # Entry: research.jsonl OR step skipped
    if ! check_artifact_exists "$PHASE_DIR/research.jsonl" && ! check_step_skipped "research"; then
      MISSING+=("research.jsonl")
      GATE_RESULT="fail"
    fi
    ;;

  *)
    echo "ERROR: Unknown step: $STEP" >&2
    exit 1
    ;;
esac

# --- Output ---
if [ "$GATE_RESULT" = "pass" ]; then
  jq -n --arg s "$STEP" '{"gate":"pass","step":$s,"missing":[]}'
  exit 0
else
  printf '%s\n' "${MISSING[@]}" | jq -R . | jq -s --arg g "fail" --arg s "$STEP" '{"gate":$g,"step":$s,"missing":.}'
  exit 1
fi
