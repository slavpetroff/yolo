#!/usr/bin/env bash
set -euo pipefail

# validate-naming.sh — Validate artifact naming conventions
#
# Checks: plan headers (p/n/t fields), task keys, summary keys,
# reqs keys, legacy key detection, file name consistency.
# Uses jq for all JSON operations.
#
# Usage: validate-naming.sh <file-or-dir> [--scope=active|all] [--type=plan|summary|reqs] [--turbo]
# Output: JSON {valid:bool,errors:[],warnings:[]}
# Exit codes: 0 = valid naming, 1 = naming violation or usage error

# --- jq dependency check ---
if ! command -v jq &>/dev/null; then
  echo '{"error":"jq is required but not installed. Install: brew install jq (macOS) / apt install jq (Linux)"}' >&2
  exit 1
fi

# --- Arg parsing ---
if [ $# -lt 1 ]; then
  echo "Usage: validate-naming.sh <file-or-dir> [--scope=active|all] [--type=plan|summary|reqs] [--turbo]" >&2
  exit 1
fi

TARGET=""
SCOPE="active"
TURBO=false
TYPE_OVERRIDE=""

for arg in "$@"; do
  case "$arg" in
    --scope=*) SCOPE="${arg#--scope=}";;
    --type=*) TYPE_OVERRIDE="${arg#--type=}";;
    --turbo) TURBO=true;;
    *) TARGET="$arg";;
  esac
done

if [ -z "$TARGET" ]; then
  echo "Usage: validate-naming.sh <file-or-dir> [--scope=active|all] [--type=plan|summary|reqs] [--turbo]" >&2
  exit 1
fi

# --- Global state ---
ERRORS=()
WARNINGS=()
VALID=true

# --- Helpers ---
add_error() { ERRORS+=("$1"); VALID=false; }
add_warning() { WARNINGS+=("$1"); }

# --- detect_type function ---
detect_type() {
  local file="$1"
  if [ -n "$TYPE_OVERRIDE" ]; then
    echo "$TYPE_OVERRIDE"
    return
  fi
  local bn
  bn="$(basename "$file")"
  case "$bn" in
    *.plan.jsonl) echo "plan";;
    *.summary.jsonl) echo "summary";;
    reqs.jsonl) echo "reqs";;
    critique.jsonl) echo "critique";;
    decisions.jsonl) echo "decisions";;
    code-review.jsonl) echo "code-review";;
    *) echo "unknown";;
  esac
}

# --- validate_plan_naming function ---
validate_plan_naming() {
  local file="$1"
  local header
  header=$(head -1 "$file") || true

  # Empty file check
  if [ -z "$header" ]; then
    add_error "$file: empty plan file"
    return
  fi

  # Valid JSON check
  if ! echo "$header" | jq empty 2>/dev/null; then
    add_error "$file: invalid JSON in header"
    return
  fi

  # (1) p field: phase-only, zero-padded
  local p_val
  p_val=$(echo "$header" | jq -r '.p // empty') || true
  if [ -n "$p_val" ]; then
    if [[ "$p_val" == *-* ]]; then
      add_error "Header p field is compound '$p_val' -- must be phase-only (e.g. '01')"
    elif ! [[ "$p_val" =~ ^[0-9]{2}$ ]]; then
      add_error "Header p field '$p_val' is not valid -- must be zero-padded number (e.g. '01')"
    fi
  fi

  # (2) n field: plan-only, zero-padded
  local n_val
  n_val=$(echo "$header" | jq -r '.n // empty') || true
  if [ -n "$n_val" ]; then
    if ! [[ "$n_val" =~ ^[0-9]{2}$ ]]; then
      add_error "Header n field '$n_val' is not a plan number -- must be zero-padded number (e.g. '03')"
    fi
  fi

  # (3) t field: must be title string, not a number
  local t_val
  t_val=$(echo "$header" | jq -r '.t // empty') || true
  if [ -n "$t_val" ] && [[ "$t_val" =~ ^[0-9]+$ ]]; then
    add_error "Header t field is a number '$t_val' -- must be title string"
  fi

  # (4) Turbo detection
  local auto_turbo=false
  local eff_val
  eff_val=$(echo "$header" | jq -r '.eff // empty') || true
  local has_mh
  has_mh=$(echo "$header" | jq 'has("mh")') || true
  if [ "$eff_val" = "turbo" ] || [ "$has_mh" != "true" ]; then
    auto_turbo=true
  fi

  if [ "$TURBO" = "false" ] && [ "$auto_turbo" = "false" ]; then
    # Verify mh key exists and is object
    local mh_type
    mh_type=$(echo "$header" | jq -r '.mh | type' 2>/dev/null) || true
    if [ "$mh_type" != "object" ]; then
      add_error "Header mh field must be an object"
    fi
  fi

  # (5) File name vs header consistency
  local bn
  bn="$(basename "$file")"
  local name_part="${bn%.plan.jsonl}"
  if [[ "$name_part" == *-* ]]; then
    local file_nn="${name_part%%-*}"
    local file_mm="${name_part#*-}"
    if [ -n "$p_val" ] && [ "$file_nn" != "$p_val" ]; then
      add_error "File name $bn does not match header p='$p_val' n='$n_val'"
    elif [ -n "$n_val" ] && [ "$file_mm" != "$n_val" ]; then
      add_error "File name $bn does not match header p='$p_val' n='$n_val'"
    fi
  fi

  # (6) Task lines
  local task_line
  while IFS= read -r task_line; do
    [ -z "$task_line" ] && continue

    if ! echo "$task_line" | jq empty 2>/dev/null; then
      add_error "Task line: invalid JSON"
      continue
    fi

    local task_id
    task_id=$(echo "$task_line" | jq -r '.id // "unknown"') || task_id="unknown"

    # Required keys based on turbo mode
    local required_keys
    if [ "$TURBO" = "true" ] || [ "$auto_turbo" = "true" ]; then
      required_keys="id a f v done"
    else
      required_keys="id tp a f v done"
    fi

    for key in $required_keys; do
      local has_key
      has_key=$(echo "$task_line" | jq --arg k "$key" 'has($k)') || true
      if [ "$has_key" != "true" ]; then
        add_error "Task $task_id: missing required key: $key"
      fi
    done

    # Legacy key detection
    local has_legacy_n has_a
    has_legacy_n=$(echo "$task_line" | jq 'has("n")') || true
    has_a=$(echo "$task_line" | jq 'has("a")') || true
    if [ "$has_legacy_n" = "true" ] && [ "$has_a" != "true" ]; then
      add_error "Task $task_id: uses legacy key 'n' instead of 'a'"
    fi

    local has_legacy_ac has_v
    has_legacy_ac=$(echo "$task_line" | jq 'has("ac")') || true
    has_v=$(echo "$task_line" | jq 'has("v")') || true
    if [ "$has_legacy_ac" = "true" ] && [ "$has_v" != "true" ]; then
      add_error "Task $task_id: uses legacy key 'ac' instead of 'v'"
    fi

    # Check no absolute paths in f
    if echo "$task_line" | jq -e 'has("f")' >/dev/null 2>&1; then
      local abs_paths
      abs_paths=$(echo "$task_line" | jq -r '.f[]? | select(startswith("/"))' 2>/dev/null) || true
      if [ -n "$abs_paths" ]; then
        while IFS= read -r abs_path; do
          add_error "Task $task_id: absolute path in f: $abs_path"
        done <<< "$abs_paths"
      fi
    fi
  done < <(tail -n +2 "$file")
}

# --- validate_summary_naming function ---
validate_summary_naming() {
  local file="$1"
  local content
  content=$(cat "$file") || true

  # Valid JSON check
  if ! echo "$content" | jq empty 2>/dev/null; then
    add_error "$file: invalid JSON"
    return
  fi

  # (1) Required keys check (12 keys)
  local required_keys="p n t s dt tc tt ch fm dv built tst"
  for key in $required_keys; do
    local has_key
    has_key=$(echo "$content" | jq --arg k "$key" 'has($k)') || true
    if [ "$has_key" != "true" ]; then
      add_error "Summary $file: missing required key: $key"
    fi
  done

  # (2) Legacy key detection
  local has_commits has_tasks has_dev has_sum
  has_commits=$(echo "$content" | jq 'has("commits")') || true
  has_tasks=$(echo "$content" | jq 'has("tasks")') || true
  has_dev=$(echo "$content" | jq 'has("dev")') || true
  has_sum=$(echo "$content" | jq 'has("sum")') || true

  if [ "$has_commits" = "true" ]; then
    add_error "Summary uses legacy key 'commits' -- use 'ch' (commit hashes)"
  fi
  if [ "$has_tasks" = "true" ]; then
    add_error "Summary uses legacy key 'tasks' -- use 'tc' (tasks completed)"
  fi
  if [ "$has_dev" = "true" ]; then
    add_error "Summary uses legacy key 'dev' -- use 'dv' (deviations)"
  fi
  if [ "$has_sum" = "true" ]; then
    add_error "Summary uses legacy key 'sum' -- not canonical (remove)"
  fi

  # (3) p field format validation
  local p_val
  p_val=$(echo "$content" | jq -r '.p // empty') || true
  if [ -n "$p_val" ]; then
    if [[ "$p_val" == *-* ]]; then
      add_error "Summary p field is compound '$p_val' -- must be phase-only (e.g. '01')"
    elif ! [[ "$p_val" =~ ^[0-9]{2}$ ]]; then
      add_error "Summary p field '$p_val' is not valid -- must be zero-padded number (e.g. '01')"
    fi
  fi

  # (4) n field format validation
  local n_val
  n_val=$(echo "$content" | jq -r '.n // empty') || true
  if [ -n "$n_val" ]; then
    if ! [[ "$n_val" =~ ^[0-9]{2}$ ]]; then
      add_error "Summary n field '$n_val' is not a plan number -- must be zero-padded number"
    fi
  fi

  # (5) Enum validation for s field
  local s_val
  s_val=$(echo "$content" | jq -r '.s // empty') || true
  if [ -n "$s_val" ]; then
    case "$s_val" in
      complete|partial|failed) ;;
      *) add_error "Summary s field '$s_val' not valid -- must be complete|partial|failed";;
    esac
  fi

  # (6) Enum validation for tst field
  local tst_val
  tst_val=$(echo "$content" | jq -r '.tst // empty') || true
  if [ -n "$tst_val" ]; then
    case "$tst_val" in
      red_green|green_only|no_tests) ;;
      *) add_error "Summary tst field '$tst_val' not valid -- must be red_green|green_only|no_tests";;
    esac
  fi

  # (7) File name consistency
  local bn
  bn="$(basename "$file")"
  local name_part="${bn%.summary.jsonl}"
  if [[ "$name_part" == *-* ]]; then
    local file_nn="${name_part%%-*}"
    local file_mm="${name_part#*-}"
    if [ -n "$p_val" ] && [ "$file_nn" != "$p_val" ]; then
      add_error "Summary file name $bn does not match header p='$p_val' n='$n_val'"
    elif [ -n "$n_val" ] && [ "$file_mm" != "$n_val" ]; then
      add_error "Summary file name $bn does not match header p='$p_val' n='$n_val'"
    fi
  fi

  # (8) Multi-line check (warning, not error)
  local line_count
  line_count=$(wc -l < "$file" | tr -d ' ')
  if [ "$line_count" -gt 1 ]; then
    add_warning "Summary $file has $line_count lines -- canonical is single-line JSONL"
  fi
}

# --- validate_reqs_naming function ---
validate_reqs_naming() {
  local file="$1"
  local line_num=0
  local line

  while IFS= read -r line; do
    line_num=$((line_num + 1))
    [ -z "$line" ] && continue

    if ! echo "$line" | jq empty 2>/dev/null; then
      add_error "Reqs line $line_num: invalid JSON"
      continue
    fi

    local req_id
    req_id=$(echo "$line" | jq -r '.id // "unknown"') || req_id="unknown"

    # (1) Required keys
    local required_keys="id t pri"
    for key in $required_keys; do
      local has_key
      has_key=$(echo "$line" | jq --arg k "$key" 'has($k)') || true
      if [ "$has_key" != "true" ]; then
        add_error "Reqs $req_id: missing required key: $key"
      fi
    done

    # (2) Legacy key detection
    local has_p has_pri
    has_p=$(echo "$line" | jq 'has("p")') || true
    has_pri=$(echo "$line" | jq 'has("pri")') || true
    if [ "$has_p" = "true" ] && [ "$has_pri" != "true" ]; then
      add_error "Reqs $req_id: uses legacy key 'p' -- use 'pri'"
    fi

    local has_d has_ac
    has_d=$(echo "$line" | jq 'has("d")') || true
    has_ac=$(echo "$line" | jq 'has("ac")') || true
    if [ "$has_d" = "true" ] && [ "$has_ac" != "true" ]; then
      add_error "Reqs $req_id: uses legacy key 'd' -- use 'ac'"
    fi

    # (3) Valid enums
    local pri_val
    pri_val=$(echo "$line" | jq -r '.pri // empty') || true
    if [ -n "$pri_val" ]; then
      case "$pri_val" in
        must|should|nice) ;;
        *) add_error "Reqs $req_id: pri field '$pri_val' not valid -- must be must|should|nice";;
      esac
    fi

    local st_val
    st_val=$(echo "$line" | jq -r '.st // empty') || true
    if [ -n "$st_val" ]; then
      case "$st_val" in
        open|done) ;;
        *) add_error "Reqs $req_id: st field '$st_val' not valid -- must be open|done";;
      esac
    fi
  done < "$file"
}

# --- Scope-aware directory scanning ---
scan_directory() {
  local dir="$1"
  local files=()
  local is_milestone=false

  # Collect files from the target directory
  while IFS= read -r f; do
    files+=("$f")
  done < <(find "$dir" -maxdepth 2 \( -name '*.plan.jsonl' -o -name '*.summary.jsonl' -o -name 'reqs.jsonl' \) 2>/dev/null | sort)

  # Validate each file
  for f in "${files[@]}"; do
    local ftype
    ftype=$(detect_type "$f")
    case "$ftype" in
      plan) validate_plan_naming "$f";;
      summary) validate_summary_naming "$f";;
      reqs) validate_reqs_naming "$f";;
      *) add_warning "Unknown artifact type for $f";;
    esac
  done

  # If scope=all AND milestones directory exists, scan those too (warnings only)
  if [ "$SCOPE" = "all" ]; then
    local milestones_dir
    # Try to find .yolo-planning/milestones relative to the target
    milestones_dir=""
    if [ -d "$dir/../../../milestones" ]; then
      milestones_dir="$dir/../../../milestones"
    elif [ -d "$dir/../../milestones" ]; then
      milestones_dir="$dir/../../milestones"
    elif [ -d "$dir/milestones" ]; then
      milestones_dir="$dir/milestones"
    fi

    if [ -n "$milestones_dir" ] && [ -d "$milestones_dir" ]; then
      # Save current errors/valid state
      local saved_errors=("${ERRORS[@]+"${ERRORS[@]}"}")
      local saved_valid="$VALID"
      ERRORS=()
      VALID=true

      while IFS= read -r f; do
        local ftype
        ftype=$(detect_type "$f")
        case "$ftype" in
          plan) validate_plan_naming "$f";;
          summary) validate_summary_naming "$f";;
          reqs) validate_reqs_naming "$f";;
          *) ;;
        esac
      done < <(find "$milestones_dir" \( -name '*.plan.jsonl' -o -name '*.summary.jsonl' -o -name 'reqs.jsonl' \) 2>/dev/null | sort)

      # Convert milestone errors to warnings (C3: non-blocking)
      for err in "${ERRORS[@]+"${ERRORS[@]}"}"; do
        [ -z "$err" ] && continue
        add_warning "Milestone: $err"
      done

      # Restore original errors/valid state
      ERRORS=("${saved_errors[@]+"${saved_errors[@]}"}")
      VALID="$saved_valid"
    fi
  fi
}

# --- Main flow ---
if [ -f "$TARGET" ]; then
  local_type=$(detect_type "$TARGET")
  case "$local_type" in
    plan) validate_plan_naming "$TARGET";;
    summary) validate_summary_naming "$TARGET";;
    reqs) validate_reqs_naming "$TARGET";;
    *) add_warning "Unknown artifact type for $TARGET";;
  esac
elif [ -d "$TARGET" ]; then
  scan_directory "$TARGET"
else
  echo "Error: $TARGET is not a file or directory" >&2
  exit 1
fi

# --- Output (JSON) ---
if [ ${#WARNINGS[@]} -eq 0 ]; then
  warnings_json='[]'
else
  warnings_json=$(printf '%s\n' "${WARNINGS[@]}" | jq -R . | jq -s .)
fi

if [ ${#ERRORS[@]} -eq 0 ]; then
  jq -n --argjson w "$warnings_json" '{"valid":true,"errors":[],"warnings":$w}'
  exit 0
else
  printf '%s\n' "${ERRORS[@]}" | jq -R . | jq -s --argjson w "$warnings_json" '{"valid":false,"errors":.,"warnings":$w}'
  exit 1
fi
