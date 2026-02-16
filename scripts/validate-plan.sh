#!/usr/bin/env bash
set -euo pipefail

# validate-plan.sh — Validate plan.jsonl structure
#
# Checks: header keys, task keys, wave ordering, no circular deps,
# relative file paths. Uses jq for all JSON operations.
#
# Usage: validate-plan.sh <path-to-plan.jsonl>
# Output: JSON {valid:bool,errors:[]}
# Exit codes: 0 = valid plan, 1 = invalid plan or usage error

# --- jq dependency check ---
if ! command -v jq &>/dev/null; then
  echo '{"error":"jq is required but not installed. Install: brew install jq (macOS) / apt install jq (Linux)"}' >&2
  exit 1
fi

# --- Arg parsing ---
if [ $# -lt 1 ]; then
  echo "Usage: validate-plan.sh <path-to-plan.jsonl>" >&2
  exit 1
fi

PLAN_FILE="$1"

if [ ! -f "$PLAN_FILE" ]; then
  echo "Usage: validate-plan.sh <path-to-plan.jsonl>" >&2
  echo "Error: File not found: $PLAN_FILE" >&2
  exit 1
fi

# --- Global state (bash 3.2 compatible: indexed arrays only) ---
ERRORS=()
VALID=true

# --- Validation functions ---

validate_header() {
  local header
  header=$(head -1 "$PLAN_FILE") || true

  # Empty file check
  if [ -z "$header" ]; then
    ERRORS+=("Empty plan file")
    VALID=false
    return
  fi

  # Valid JSON check
  if ! echo "$header" | jq empty 2>/dev/null; then
    ERRORS+=("Line 1: invalid JSON")
    VALID=false
    return
  fi

  # Required keys with type checks
  local required_keys="p n t w d mh obj"
  for key in $required_keys; do
    local has_key
    has_key=$(echo "$header" | jq --arg k "$key" 'has($k)' 2>/dev/null) || true
    if [ "$has_key" != "true" ]; then
      ERRORS+=("Header missing required key: $key")
      VALID=false
      continue
    fi

    # Type checks
    case "$key" in
      p|n|t|obj)
        local is_string
        is_string=$(echo "$header" | jq --arg k "$key" '.[$k] | type == "string"' 2>/dev/null) || true
        if [ "$is_string" != "true" ]; then
          ERRORS+=("Header key $key: expected string")
          VALID=false
        fi
        ;;
      w)
        local is_number
        is_number=$(echo "$header" | jq '.w | type == "number"' 2>/dev/null) || true
        if [ "$is_number" != "true" ]; then
          ERRORS+=("Header key w: expected number")
          VALID=false
        fi
        ;;
      d)
        local is_array
        is_array=$(echo "$header" | jq '.d | type == "array"' 2>/dev/null) || true
        if [ "$is_array" != "true" ]; then
          ERRORS+=("Header key d: expected array")
          VALID=false
        fi
        ;;
      mh)
        local is_object
        is_object=$(echo "$header" | jq '.mh | type == "object"' 2>/dev/null) || true
        if [ "$is_object" != "true" ]; then
          ERRORS+=("Header key mh: expected object")
          VALID=false
        fi
        ;;
    esac
  done

  # Optional keys type checks (if present)
  local opt_check
  opt_check=$(echo "$header" | jq 'if has("xd") then (.xd | type == "array") else true end' 2>/dev/null) || true
  if [ "$opt_check" = "false" ]; then
    ERRORS+=("Header key xd: expected array")
    VALID=false
  fi

  opt_check=$(echo "$header" | jq 'if has("sk") then (.sk | type == "array") else true end' 2>/dev/null) || true
  if [ "$opt_check" = "false" ]; then
    ERRORS+=("Header key sk: expected array")
    VALID=false
  fi

  opt_check=$(echo "$header" | jq 'if has("fm") then (.fm | type == "array") else true end' 2>/dev/null) || true
  if [ "$opt_check" = "false" ]; then
    ERRORS+=("Header key fm: expected array")
    VALID=false
  fi

  opt_check=$(echo "$header" | jq 'if has("auto") then (.auto | type == "boolean") else true end' 2>/dev/null) || true
  if [ "$opt_check" = "false" ]; then
    ERRORS+=("Header key auto: expected boolean")
    VALID=false
  fi
}

validate_tasks() {
  local line_num=1
  local line
  while IFS= read -r line; do
    line_num=$((line_num + 1))

    # Skip empty lines
    [ -z "$line" ] && continue

    # Valid JSON check
    if ! echo "$line" | jq empty 2>/dev/null; then
      ERRORS+=("Line $line_num: invalid JSON")
      VALID=false
      continue
    fi

    # Extract task id for error messages
    local task_id
    task_id=$(echo "$line" | jq -r '.id // "unknown"' 2>/dev/null) || task_id="unknown"

    # Required keys
    local required_task_keys="id tp a f v done"
    for key in $required_task_keys; do
      local has_key
      has_key=$(echo "$line" | jq --arg k "$key" 'has($k)' 2>/dev/null) || true
      if [ "$has_key" != "true" ]; then
        ERRORS+=("Task $task_id: missing required key: $key")
        VALID=false
      fi
    done

    # Validate id format: must match ^T[0-9]+$
    if echo "$line" | jq -e 'has("id")' >/dev/null 2>&1; then
      local id_valid
      id_valid=$(echo "$line" | jq '.id | test("^T[0-9]+$")' 2>/dev/null) || true
      if [ "$id_valid" = "false" ]; then
        ERRORS+=("Task $task_id: id must match ^T[0-9]+$ pattern")
        VALID=false
      fi
    fi

    # Check f array for absolute paths
    if echo "$line" | jq -e 'has("f")' >/dev/null 2>&1; then
      local abs_paths
      abs_paths=$(echo "$line" | jq -r '.f[]? | select(startswith("/"))' 2>/dev/null) || true
      if [ -n "$abs_paths" ]; then
        while IFS= read -r abs_path; do
          ERRORS+=("Task $task_id: absolute path in f: $abs_path")
          VALID=false
        done <<< "$abs_paths"
      fi
    fi
  done < <(tail -n +2 "$PLAN_FILE")
}

validate_waves() {
  local header
  header=$(head -1 "$PLAN_FILE") || true

  # Check if header is valid JSON first
  if ! echo "$header" | jq empty 2>/dev/null; then
    return
  fi

  local plan_wave
  plan_wave=$(echo "$header" | jq -r '.w // empty' 2>/dev/null) || true
  [ -z "$plan_wave" ] && return

  local plan_p plan_n
  plan_p=$(echo "$header" | jq -r '.p // empty' 2>/dev/null) || true
  plan_n=$(echo "$header" | jq -r '.n // empty' 2>/dev/null) || true

  # Get dependencies
  local deps
  deps=$(echo "$header" | jq -r '.d[]? // empty' 2>/dev/null) || true
  [ -z "$deps" ] && return

  local plan_dir
  plan_dir=$(dirname "$PLAN_FILE")

  while IFS= read -r dep; do
    [ -z "$dep" ] && continue

    # Skip self-reference (handled by validate_no_circular_deps)
    local plan_id="${plan_p}-${plan_n}"
    [ "$dep" = "$plan_id" ] && continue

    # Try to find the dep plan file in same directory
    local dep_file
    dep_file=$(ls "$plan_dir"/${dep}.plan.jsonl 2>/dev/null | head -1) || true
    if [ -n "$dep_file" ] && [ -f "$dep_file" ]; then
      local dep_wave
      dep_wave=$(head -1 "$dep_file" | jq -r '.w // empty' 2>/dev/null) || true
      if [ -n "$dep_wave" ] && [ "$dep_wave" -ge "$plan_wave" ] 2>/dev/null; then
        ERRORS+=("Plan depends on same-or-higher wave plan: $dep (wave $dep_wave >= $plan_wave)")
        VALID=false
      fi
    fi
  done <<< "$deps"
}

validate_no_circular_deps() {
  local header
  header=$(head -1 "$PLAN_FILE") || true

  # Check if header is valid JSON first
  if ! echo "$header" | jq empty 2>/dev/null; then
    return
  fi

  local plan_p plan_n
  plan_p=$(echo "$header" | jq -r '.p // empty' 2>/dev/null) || true
  plan_n=$(echo "$header" | jq -r '.n // empty' 2>/dev/null) || true
  [ -z "$plan_p" ] && return
  [ -z "$plan_n" ] && return

  local plan_id="${plan_p}-${plan_n}"

  # Check if plan ID appears in its own d array
  local self_dep
  self_dep=$(echo "$header" | jq --arg pid "$plan_id" '.d[]? | select(. == $pid)' 2>/dev/null) || true
  if [ -n "$self_dep" ]; then
    ERRORS+=("Circular dependency: plan depends on itself")
    VALID=false
  fi
}

# --- Main flow ---
validate_header
validate_tasks
validate_waves
validate_no_circular_deps

# --- Output ---
if [ ${#ERRORS[@]} -eq 0 ]; then
  jq -n '{"valid":true,"errors":[]}'
  exit 0
else
  printf '%s\n' "${ERRORS[@]}" | jq -R . | jq -s '{"valid":false,"errors":.}'
  exit 1
fi
