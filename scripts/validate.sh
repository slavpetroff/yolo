#!/usr/bin/env bash
set -euo pipefail

# validate.sh -- Consolidated validator dispatcher
#
# Replaces: validate-plan.sh, validate-naming.sh, validate-config.sh,
#           validate-gates.sh, validate-deps.sh
# Thin wrappers remain: validate-summary.sh, validate-frontmatter.sh (hook-style)
# Untouched hooks: validate-commit.sh, validate-send-message.sh, validate-dept-spawn.sh
#
# Usage: validate.sh --type <type> [type-specific args...]
# Types: plan, summary, naming, config, gates, deps, frontmatter
# Output: JSON to stdout (type-specific schema)
# Exit codes: 0 = valid, 1 = invalid or usage error

# --- Source shared lib (graceful fallback) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/../lib/yolo-common.sh" ]; then
  # shellcheck source=../lib/yolo-common.sh
  source "$SCRIPT_DIR/../lib/yolo-common.sh"
fi

# --- jq dependency check ---
if ! command -v jq &>/dev/null; then
  echo '{"error":"jq is required but not installed. Install: brew install jq (macOS) / apt install jq (Linux)"}' >&2
  exit 1
fi

# --- Arg parsing: extract --type, pass remainder to handler ---
TYPE=""
ARGS=()

TYPE_SET=false
for arg in "$@"; do
  case "$arg" in
    --type)
      if [ "$TYPE_SET" = "false" ]; then
        : # next arg is the type value
      else
        ARGS+=("$arg")
      fi
      ;;
    --type=*)
      if [ "$TYPE_SET" = "false" ]; then
        TYPE="${arg#--type=}"
        TYPE_SET=true
      else
        ARGS+=("$arg")
      fi
      ;;
    *)
      if [ "$TYPE_SET" = "false" ] && [ "${prev_was_type:-}" = "true" ]; then
        TYPE="$arg"
        TYPE_SET=true
      else
        ARGS+=("$arg")
      fi
      ;;
  esac
  if [ "$arg" = "--type" ] && [ "$TYPE_SET" = "false" ]; then
    prev_was_type=true
  else
    prev_was_type=false
  fi
done

if [ -z "$TYPE" ]; then
  echo "Usage: validate.sh --type <plan|summary|naming|config|gates|deps|frontmatter> [args...]" >&2
  exit 1
fi

# ============================================================================
# PLAN VALIDATION
# ============================================================================

validate_plan() {
  if [ ${#ARGS[@]} -lt 1 ]; then
    echo "Usage: validate.sh --type plan <path-to-plan.jsonl>" >&2
    exit 1
  fi

  local PLAN_FILE="${ARGS[0]}"

  if [ ! -f "$PLAN_FILE" ]; then
    echo "Usage: validate.sh --type plan <path-to-plan.jsonl>" >&2
    echo "Error: File not found: $PLAN_FILE" >&2
    exit 1
  fi

  local ERRORS=()
  local VALID=true

  # --- Header validation ---
  local header
  header=$(head -1 "$PLAN_FILE") || true

  if [ -z "$header" ]; then
    ERRORS+=("Empty plan file")
    VALID=false
  elif ! echo "$header" | jq empty 2>/dev/null; then
    ERRORS+=("Line 1: invalid JSON")
    VALID=false
  else
    local required_keys="p n t w d mh obj"
    for key in $required_keys; do
      local has_key
      has_key=$(echo "$header" | jq --arg k "$key" 'has($k)' 2>/dev/null) || true
      if [ "$has_key" != "true" ]; then
        ERRORS+=("Header missing required key: $key")
        VALID=false
        continue
      fi

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

    # Optional keys type checks
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
  fi

  # --- Task validation ---
  local line_num=1
  local line
  while IFS= read -r line; do
    line_num=$((line_num + 1))
    [ -z "$line" ] && continue

    if ! echo "$line" | jq empty 2>/dev/null; then
      ERRORS+=("Line $line_num: invalid JSON")
      VALID=false
      continue
    fi

    local task_id
    task_id=$(echo "$line" | jq -r '.id // "unknown"' 2>/dev/null) || task_id="unknown"

    local required_task_keys="id tp a f v done"
    for key in $required_task_keys; do
      local has_key
      has_key=$(echo "$line" | jq --arg k "$key" 'has($k)' 2>/dev/null) || true
      if [ "$has_key" != "true" ]; then
        ERRORS+=("Task $task_id: missing required key: $key")
        VALID=false
      fi
    done

    # Validate id format
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

  # --- Wave ordering validation ---
  if [ -n "$header" ] && echo "$header" | jq empty 2>/dev/null; then
    local plan_wave
    plan_wave=$(echo "$header" | jq -r '.w // empty' 2>/dev/null) || true

    if [ -n "$plan_wave" ]; then
      local plan_p plan_n
      plan_p=$(echo "$header" | jq -r '.p // empty' 2>/dev/null) || true
      plan_n=$(echo "$header" | jq -r '.n // empty' 2>/dev/null) || true

      local deps
      deps=$(echo "$header" | jq -r '.d[]? // empty' 2>/dev/null) || true

      if [ -n "$deps" ]; then
        local plan_dir
        plan_dir=$(dirname "$PLAN_FILE")

        while IFS= read -r dep; do
          [ -z "$dep" ] && continue
          local plan_id="${plan_p}-${plan_n}"
          [ "$dep" = "$plan_id" ] && continue

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
      fi

      # Circular dep check
      local plan_id="${plan_p}-${plan_n}"
      if [ -n "$plan_p" ] && [ -n "$plan_n" ]; then
        local self_dep
        self_dep=$(echo "$header" | jq --arg pid "$plan_id" '.d[]? | select(. == $pid)' 2>/dev/null) || true
        if [ -n "$self_dep" ]; then
          ERRORS+=("Circular dependency: plan depends on itself")
          VALID=false
        fi
      fi
    fi
  fi

  # --- Cross-call naming validation ---
  if [ -x "$SCRIPT_DIR/validate.sh" ]; then
    local naming_result
    naming_result=$(bash "$SCRIPT_DIR/validate.sh" --type naming "${ARGS[0]}" --type=plan 2>/dev/null) || true

    local naming_valid
    naming_valid=$(echo "$naming_result" | jq -r 'if has("valid") then .valid else true end' 2>/dev/null) || true

    if [ "$naming_valid" = "false" ]; then
      local naming_errors
      naming_errors=$(echo "$naming_result" | jq -r '.errors[]?' 2>/dev/null) || true
      if [ -n "$naming_errors" ]; then
        while IFS= read -r err; do
          [ -z "$err" ] && continue
          ERRORS+=("Naming: $err")
          VALID=false
        done <<< "$naming_errors"
      fi
    fi
  fi

  # --- Output ---
  if [ ${#ERRORS[@]} -eq 0 ]; then
    jq -n '{"valid":true,"errors":[]}'
    exit 0
  else
    printf '%s\n' "${ERRORS[@]}" | jq -R . | jq -s '{"valid":false,"errors":.}'
    exit 1
  fi
}

# ============================================================================
# NAMING VALIDATION
# ============================================================================

validate_naming() {
  local TARGET=""
  local SCOPE="active"
  local TURBO=false
  local TYPE_OVERRIDE=""

  for arg in "${ARGS[@]}"; do
    case "$arg" in
      --scope=*) SCOPE="${arg#--scope=}";;
      --type=*) TYPE_OVERRIDE="${arg#--type=}";;
      --turbo) TURBO=true;;
      *) TARGET="$arg";;
    esac
  done

  if [ -z "$TARGET" ]; then
    echo "Usage: validate.sh --type naming <file-or-dir> [--scope=active|all] [--type=plan|summary|reqs] [--turbo]" >&2
    exit 1
  fi

  local ERRORS=()
  local WARNINGS=()
  local VALID=true

  _naming_add_error() { ERRORS+=("$1"); VALID=false; }
  _naming_add_warning() { WARNINGS+=("$1"); }

  _naming_detect_type() {
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

  _naming_validate_plan() {
    local file="$1"
    local header
    header=$(head -1 "$file") || true

    if [ -z "$header" ]; then
      _naming_add_error "$file: empty plan file"
      return
    fi

    if ! echo "$header" | jq empty 2>/dev/null; then
      _naming_add_error "$file: invalid JSON in header"
      return
    fi

    # p field: phase-only, zero-padded
    local p_val
    p_val=$(echo "$header" | jq -r '.p // empty') || true
    if [ -n "$p_val" ]; then
      if [[ "$p_val" == *-* ]]; then
        _naming_add_error "Header p field is compound '$p_val' -- must be phase-only (e.g. '01')"
      elif ! [[ "$p_val" =~ ^[0-9]{2}$ ]]; then
        _naming_add_error "Header p field '$p_val' is not valid -- must be zero-padded number (e.g. '01')"
      fi
    fi

    # n field: plan-only, zero-padded
    local n_val
    n_val=$(echo "$header" | jq -r '.n // empty') || true
    if [ -n "$n_val" ]; then
      if ! [[ "$n_val" =~ ^[0-9]{2}$ ]]; then
        _naming_add_error "Header n field '$n_val' is not a plan number -- must be zero-padded number (e.g. '03')"
      fi
    fi

    # t field: must be title string, not a number
    local t_val
    t_val=$(echo "$header" | jq -r '.t // empty') || true
    if [ -n "$t_val" ] && [[ "$t_val" =~ ^[0-9]+$ ]]; then
      _naming_add_error "Header t field is a number '$t_val' -- must be title string"
    fi

    # Turbo detection
    local auto_turbo=false
    local eff_val
    eff_val=$(echo "$header" | jq -r '.eff // empty') || true
    local has_mh
    has_mh=$(echo "$header" | jq 'has("mh")') || true
    if [ "$eff_val" = "turbo" ] || [ "$has_mh" != "true" ]; then
      auto_turbo=true
    fi

    if [ "$TURBO" = "false" ] && [ "$auto_turbo" = "false" ]; then
      local mh_type
      mh_type=$(echo "$header" | jq -r '.mh | type' 2>/dev/null) || true
      if [ "$mh_type" != "object" ]; then
        _naming_add_error "Header mh field must be an object"
      fi
    fi

    # File name vs header consistency
    local bn
    bn="$(basename "$file")"
    local name_part="${bn%.plan.jsonl}"
    if [[ "$name_part" =~ ^[0-9]{2}-[0-9]{2}$ ]]; then
      local file_nn="${name_part%%-*}"
      local file_mm="${name_part#*-}"
      if [ -n "$p_val" ] && [ "$file_nn" != "$p_val" ]; then
        _naming_add_error "File name $bn does not match header p='$p_val' n='$n_val'"
      elif [ -n "$n_val" ] && [ "$file_mm" != "$n_val" ]; then
        _naming_add_error "File name $bn does not match header p='$p_val' n='$n_val'"
      fi
    fi

    # Task lines
    local task_line
    while IFS= read -r task_line; do
      [ -z "$task_line" ] && continue

      if ! echo "$task_line" | jq empty 2>/dev/null; then
        _naming_add_error "Task line: invalid JSON"
        continue
      fi

      local task_id
      task_id=$(echo "$task_line" | jq -r '.id // "unknown"') || task_id="unknown"

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
          _naming_add_error "Task $task_id: missing required key: $key"
        fi
      done

      # Legacy key detection
      local has_legacy_n has_a
      has_legacy_n=$(echo "$task_line" | jq 'has("n")') || true
      has_a=$(echo "$task_line" | jq 'has("a")') || true
      if [ "$has_legacy_n" = "true" ] && [ "$has_a" != "true" ]; then
        _naming_add_error "Task $task_id: uses legacy key 'n' instead of 'a'"
      fi

      local has_legacy_ac has_v
      has_legacy_ac=$(echo "$task_line" | jq 'has("ac")') || true
      has_v=$(echo "$task_line" | jq 'has("v")') || true
      if [ "$has_legacy_ac" = "true" ] && [ "$has_v" != "true" ]; then
        _naming_add_error "Task $task_id: uses legacy key 'ac' instead of 'v'"
      fi

      # Check no absolute paths in f
      if echo "$task_line" | jq -e 'has("f")' >/dev/null 2>&1; then
        local abs_paths
        abs_paths=$(echo "$task_line" | jq -r '.f[]? | select(startswith("/"))' 2>/dev/null) || true
        if [ -n "$abs_paths" ]; then
          while IFS= read -r abs_path; do
            _naming_add_error "Task $task_id: absolute path in f: $abs_path"
          done <<< "$abs_paths"
        fi
      fi
    done < <(tail -n +2 "$file")
  }

  _naming_validate_summary() {
    local file="$1"
    local content
    content=$(cat "$file") || true

    if ! echo "$content" | jq empty 2>/dev/null; then
      _naming_add_error "$file: invalid JSON"
      return
    fi

    # Required keys check (12 keys)
    local required_keys="p n t s dt tc tt ch fm dv built tst"
    for key in $required_keys; do
      local has_key
      has_key=$(echo "$content" | jq --arg k "$key" 'has($k)') || true
      if [ "$has_key" != "true" ]; then
        _naming_add_error "Summary $file: missing required key: $key"
      fi
    done

    # Legacy key detection
    local has_commits has_tasks has_dev has_sum
    has_commits=$(echo "$content" | jq 'has("commits")') || true
    has_tasks=$(echo "$content" | jq 'has("tasks")') || true
    has_dev=$(echo "$content" | jq 'has("dev")') || true
    has_sum=$(echo "$content" | jq 'has("sum")') || true

    if [ "$has_commits" = "true" ]; then
      _naming_add_error "Summary uses legacy key 'commits' -- use 'ch' (commit hashes)"
    fi
    if [ "$has_tasks" = "true" ]; then
      _naming_add_error "Summary uses legacy key 'tasks' -- use 'tc' (tasks completed)"
    fi
    if [ "$has_dev" = "true" ]; then
      _naming_add_error "Summary uses legacy key 'dev' -- use 'dv' (deviations)"
    fi
    if [ "$has_sum" = "true" ]; then
      _naming_add_error "Summary uses legacy key 'sum' -- not canonical (remove)"
    fi

    # p field format validation
    local p_val
    p_val=$(echo "$content" | jq -r '.p // empty') || true
    if [ -n "$p_val" ]; then
      if [[ "$p_val" == *-* ]]; then
        _naming_add_error "Summary p field is compound '$p_val' -- must be phase-only (e.g. '01')"
      elif ! [[ "$p_val" =~ ^[0-9]{2}$ ]]; then
        _naming_add_error "Summary p field '$p_val' is not valid -- must be zero-padded number (e.g. '01')"
      fi
    fi

    # n field format validation
    local n_val
    n_val=$(echo "$content" | jq -r '.n // empty') || true
    if [ -n "$n_val" ]; then
      if ! [[ "$n_val" =~ ^[0-9]{2}$ ]]; then
        _naming_add_error "Summary n field '$n_val' is not a plan number -- must be zero-padded number"
      fi
    fi

    # Enum validation for s field
    local s_val
    s_val=$(echo "$content" | jq -r '.s // empty') || true
    if [ -n "$s_val" ]; then
      case "$s_val" in
        complete|partial|failed) ;;
        *) _naming_add_error "Summary s field '$s_val' not valid -- must be complete|partial|failed";;
      esac
    fi

    # Enum validation for tst field
    local tst_val
    tst_val=$(echo "$content" | jq -r '.tst // empty') || true
    if [ -n "$tst_val" ]; then
      case "$tst_val" in
        red_green|green_only|no_tests) ;;
        *) _naming_add_error "Summary tst field '$tst_val' not valid -- must be red_green|green_only|no_tests";;
      esac
    fi

    # File name consistency
    local bn
    bn="$(basename "$file")"
    local name_part="${bn%.summary.jsonl}"
    if [[ "$name_part" =~ ^[0-9]{2}-[0-9]{2}$ ]]; then
      local file_nn="${name_part%%-*}"
      local file_mm="${name_part#*-}"
      if [ -n "$p_val" ] && [ "$file_nn" != "$p_val" ]; then
        _naming_add_error "Summary file name $bn does not match header p='$p_val' n='$n_val'"
      elif [ -n "$n_val" ] && [ "$file_mm" != "$n_val" ]; then
        _naming_add_error "Summary file name $bn does not match header p='$p_val' n='$n_val'"
      fi
    fi

    # Multi-line check (warning, not error)
    local line_count
    line_count=$(wc -l < "$file" | tr -d ' ')
    if [ "$line_count" -gt 1 ]; then
      _naming_add_warning "Summary $file has $line_count lines -- canonical is single-line JSONL"
    fi
  }

  _naming_validate_reqs() {
    local file="$1"
    local line_num=0
    local line

    while IFS= read -r line; do
      line_num=$((line_num + 1))
      [ -z "$line" ] && continue

      if ! echo "$line" | jq empty 2>/dev/null; then
        _naming_add_error "Reqs line $line_num: invalid JSON"
        continue
      fi

      local req_id
      req_id=$(echo "$line" | jq -r '.id // "unknown"') || req_id="unknown"

      local required_keys="id t pri"
      for key in $required_keys; do
        local has_key
        has_key=$(echo "$line" | jq --arg k "$key" 'has($k)') || true
        if [ "$has_key" != "true" ]; then
          _naming_add_error "Reqs $req_id: missing required key: $key"
        fi
      done

      # Legacy key detection
      local has_p has_pri
      has_p=$(echo "$line" | jq 'has("p")') || true
      has_pri=$(echo "$line" | jq 'has("pri")') || true
      if [ "$has_p" = "true" ] && [ "$has_pri" != "true" ]; then
        _naming_add_error "Reqs $req_id: uses legacy key 'p' -- use 'pri'"
      fi

      local has_d has_ac
      has_d=$(echo "$line" | jq 'has("d")') || true
      has_ac=$(echo "$line" | jq 'has("ac")') || true
      if [ "$has_d" = "true" ] && [ "$has_ac" != "true" ]; then
        _naming_add_error "Reqs $req_id: uses legacy key 'd' -- use 'ac'"
      fi

      # Valid enums
      local pri_val
      pri_val=$(echo "$line" | jq -r '.pri // empty') || true
      if [ -n "$pri_val" ]; then
        case "$pri_val" in
          must|should|nice) ;;
          *) _naming_add_error "Reqs $req_id: pri field '$pri_val' not valid -- must be must|should|nice";;
        esac
      fi

      local st_val
      st_val=$(echo "$line" | jq -r '.st // empty') || true
      if [ -n "$st_val" ]; then
        case "$st_val" in
          open|done) ;;
          *) _naming_add_error "Reqs $req_id: st field '$st_val' not valid -- must be open|done";;
        esac
      fi
    done < "$file"
  }

  _naming_scan_directory() {
    local dir="$1"
    local files=()

    while IFS= read -r f; do
      files+=("$f")
    done < <(find "$dir" -maxdepth 2 \( -name '*.plan.jsonl' -o -name '*.summary.jsonl' -o -name 'reqs.jsonl' \) 2>/dev/null | sort)

    for f in "${files[@]}"; do
      local ftype
      ftype=$(_naming_detect_type "$f")
      case "$ftype" in
        plan) _naming_validate_plan "$f";;
        summary) _naming_validate_summary "$f";;
        reqs) _naming_validate_reqs "$f";;
        *) _naming_add_warning "Unknown artifact type for $f";;
      esac
    done

    # scope=all: scan milestones too (warnings only)
    if [ "$SCOPE" = "all" ]; then
      local milestones_dir=""
      if [ -d "$dir/../../../milestones" ]; then
        milestones_dir="$dir/../../../milestones"
      elif [ -d "$dir/../../milestones" ]; then
        milestones_dir="$dir/../../milestones"
      elif [ -d "$dir/milestones" ]; then
        milestones_dir="$dir/milestones"
      fi

      if [ -n "$milestones_dir" ] && [ -d "$milestones_dir" ]; then
        local saved_errors=("${ERRORS[@]+"${ERRORS[@]}"}")
        local saved_valid="$VALID"
        ERRORS=()
        VALID=true

        while IFS= read -r f; do
          local ftype
          ftype=$(_naming_detect_type "$f")
          case "$ftype" in
            plan) _naming_validate_plan "$f";;
            summary) _naming_validate_summary "$f";;
            reqs) _naming_validate_reqs "$f";;
            *) ;;
          esac
        done < <(find "$milestones_dir" \( -name '*.plan.jsonl' -o -name '*.summary.jsonl' -o -name 'reqs.jsonl' \) 2>/dev/null | sort)

        for err in "${ERRORS[@]+"${ERRORS[@]}"}"; do
          [ -z "$err" ] && continue
          _naming_add_warning "Milestone: $err"
        done

        ERRORS=("${saved_errors[@]+"${saved_errors[@]}"}")
        VALID="$saved_valid"
      fi
    fi
  }

  # --- Main naming flow ---
  if [ -f "$TARGET" ]; then
    local local_type
    local_type=$(_naming_detect_type "$TARGET")
    case "$local_type" in
      plan) _naming_validate_plan "$TARGET";;
      summary) _naming_validate_summary "$TARGET";;
      reqs) _naming_validate_reqs "$TARGET";;
      *) _naming_add_warning "Unknown artifact type for $TARGET";;
    esac
  elif [ -d "$TARGET" ]; then
    _naming_scan_directory "$TARGET"
  else
    echo "Error: $TARGET is not a file or directory" >&2
    exit 1
  fi

  # --- Output ---
  local warnings_json
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
}

# ============================================================================
# CONFIG VALIDATION
# ============================================================================

validate_config() {
  if [ ${#ARGS[@]} -lt 1 ]; then
    echo "Usage: validate.sh --type config <config-path> [<defaults-path>]" >&2
    exit 1
  fi

  local CONFIG_PATH="${ARGS[0]}"

  if [ ! -f "$CONFIG_PATH" ]; then
    echo "Usage: validate.sh --type config <config-path> [<defaults-path>]" >&2
    echo "Error: File not found: $CONFIG_PATH" >&2
    exit 1
  fi

  if ! jq -e '.' "$CONFIG_PATH" >/dev/null 2>&1; then
    printf '%s\n' "Config file is not valid JSON" | jq -R . | jq -s '{"valid":false,"errors":.}'
    exit 1
  fi

  local ERRORS=()

  # --- qa_gates section ---
  local has_qa_gates
  has_qa_gates=$(jq 'has("qa_gates")' "$CONFIG_PATH")
  if [ "$has_qa_gates" = "true" ]; then
    local is_object
    is_object=$(jq -r '.qa_gates | type' "$CONFIG_PATH")
    if [ "$is_object" != "object" ]; then
      ERRORS+=("qa_gates must be an object, got $is_object")
    else
      if jq -e '.qa_gates | has("post_task")' "$CONFIG_PATH" >/dev/null 2>&1; then
        local pt_type
        pt_type=$(jq -r '.qa_gates.post_task | type' "$CONFIG_PATH")
        if [ "$pt_type" != "boolean" ]; then
          ERRORS+=("qa_gates.post_task must be boolean, got $pt_type")
        fi
      fi

      if jq -e '.qa_gates | has("post_plan")' "$CONFIG_PATH" >/dev/null 2>&1; then
        local pp_type
        pp_type=$(jq -r '.qa_gates.post_plan | type' "$CONFIG_PATH")
        if [ "$pp_type" != "boolean" ]; then
          ERRORS+=("qa_gates.post_plan must be boolean, got $pp_type")
        fi
      fi

      if jq -e '.qa_gates | has("post_phase")' "$CONFIG_PATH" >/dev/null 2>&1; then
        local pph_type
        pph_type=$(jq -r '.qa_gates.post_phase | type' "$CONFIG_PATH")
        if [ "$pph_type" != "boolean" ]; then
          ERRORS+=("qa_gates.post_phase must be boolean, got $pph_type")
        fi
      fi

      if jq -e '.qa_gates | has("timeout_seconds")' "$CONFIG_PATH" >/dev/null 2>&1; then
        local ts_valid
        ts_valid=$(jq '.qa_gates.timeout_seconds | (type == "number") and (. > 0)' "$CONFIG_PATH")
        if [ "$ts_valid" != "true" ]; then
          ERRORS+=("qa_gates.timeout_seconds must be a positive number")
        fi
      fi

      if jq -e '.qa_gates | has("failure_threshold")' "$CONFIG_PATH" >/dev/null 2>&1; then
        local ft_valid
        ft_valid=$(jq '.qa_gates.failure_threshold | (type == "string") and test("^(critical|major|minor)$")' "$CONFIG_PATH")
        if [ "$ft_valid" != "true" ]; then
          ERRORS+=("qa_gates.failure_threshold must be one of: critical, major, minor")
        fi
      fi
    fi
  fi

  # --- integration_gate section ---
  local has_integration_gate
  has_integration_gate=$(jq 'has("integration_gate")' "$CONFIG_PATH")
  if [ "$has_integration_gate" = "true" ]; then
    local ig_type
    ig_type=$(jq -r '.integration_gate | type' "$CONFIG_PATH")
    if [ "$ig_type" != "object" ]; then
      ERRORS+=("integration_gate must be an object, got $ig_type")
    else
      if jq -e '.integration_gate | has("enabled")' "$CONFIG_PATH" >/dev/null 2>&1; then
        local ig_enabled_type
        ig_enabled_type=$(jq -r '.integration_gate.enabled | type' "$CONFIG_PATH")
        if [ "$ig_enabled_type" != "boolean" ]; then
          ERRORS+=("integration_gate.enabled must be boolean, got $ig_enabled_type")
        fi
      fi

      if jq -e '.integration_gate | has("timeout_seconds")' "$CONFIG_PATH" >/dev/null 2>&1; then
        local ig_ts_valid
        ig_ts_valid=$(jq '.integration_gate.timeout_seconds | (type == "number") and (. >= 60) and (. <= 3600)' "$CONFIG_PATH")
        if [ "$ig_ts_valid" != "true" ]; then
          ERRORS+=("integration_gate.timeout_seconds must be a number between 60 and 3600")
        fi
      fi

      if jq -e '.integration_gate | has("checks")' "$CONFIG_PATH" >/dev/null 2>&1; then
        local ig_checks_type
        ig_checks_type=$(jq -r '.integration_gate.checks | type' "$CONFIG_PATH")
        if [ "$ig_checks_type" != "object" ]; then
          ERRORS+=("integration_gate.checks must be an object, got $ig_checks_type")
        else
          local ig_checks_valid
          ig_checks_valid=$(jq '[.integration_gate.checks | to_entries[] | .value | type == "boolean"] | all' "$CONFIG_PATH")
          if [ "$ig_checks_valid" != "true" ]; then
            ERRORS+=("integration_gate.checks values must all be booleans")
          fi
        fi
      fi

      if jq -e '.integration_gate | has("retry_on_fail")' "$CONFIG_PATH" >/dev/null 2>&1; then
        local ig_retry_type
        ig_retry_type=$(jq -r '.integration_gate.retry_on_fail | type' "$CONFIG_PATH")
        if [ "$ig_retry_type" != "boolean" ]; then
          ERRORS+=("integration_gate.retry_on_fail must be boolean, got $ig_retry_type")
        fi
      fi
    fi
  fi

  # --- po.default_rejection ---
  if jq -e '.po | has("default_rejection")' "$CONFIG_PATH" >/dev/null 2>&1; then
    local po_dr_valid
    po_dr_valid=$(jq '.po.default_rejection | (type == "string") and test("^(patch|major)$")' "$CONFIG_PATH")
    if [ "$po_dr_valid" != "true" ]; then
      ERRORS+=("po.default_rejection must be one of: patch, major")
    fi
  fi

  # --- delivery section ---
  local has_delivery
  has_delivery=$(jq 'has("delivery")' "$CONFIG_PATH")
  if [ "$has_delivery" = "true" ]; then
    local del_type
    del_type=$(jq -r '.delivery | type' "$CONFIG_PATH")
    if [ "$del_type" != "object" ]; then
      ERRORS+=("delivery must be an object, got $del_type")
    else
      if jq -e '.delivery | has("mode")' "$CONFIG_PATH" >/dev/null 2>&1; then
        local del_mode_valid
        del_mode_valid=$(jq '.delivery.mode | (type == "string") and test("^(auto|manual)$")' "$CONFIG_PATH")
        if [ "$del_mode_valid" != "true" ]; then
          ERRORS+=("delivery.mode must be one of: auto, manual")
        fi
      fi

      if jq -e '.delivery | has("present_to_user")' "$CONFIG_PATH" >/dev/null 2>&1; then
        local del_ptu_type
        del_ptu_type=$(jq -r '.delivery.present_to_user | type' "$CONFIG_PATH")
        if [ "$del_ptu_type" != "boolean" ]; then
          ERRORS+=("delivery.present_to_user must be boolean, got $del_ptu_type")
        fi
      fi
    fi
  fi

  # --- complexity_routing section ---
  local has_complexity_routing
  has_complexity_routing=$(jq 'has("complexity_routing")' "$CONFIG_PATH")
  if [ "$has_complexity_routing" = "true" ]; then
    local cr_type
    cr_type=$(jq -r '.complexity_routing | type' "$CONFIG_PATH")
    if [ "$cr_type" != "object" ]; then
      ERRORS+=("complexity_routing must be an object, got $cr_type")
    else
      if jq -e '.complexity_routing | has("enabled")' "$CONFIG_PATH" >/dev/null 2>&1; then
        local cr_enabled_type
        cr_enabled_type=$(jq -r '.complexity_routing.enabled | type' "$CONFIG_PATH")
        if [ "$cr_enabled_type" != "boolean" ]; then
          ERRORS+=("complexity_routing.enabled must be boolean, got $cr_enabled_type")
        fi
      fi

      if jq -e '.complexity_routing | has("trivial_confidence_threshold")' "$CONFIG_PATH" >/dev/null 2>&1; then
        local cr_trivial_valid
        cr_trivial_valid=$(jq '.complexity_routing.trivial_confidence_threshold | (type == "number") and (. >= 0.0) and (. <= 1.0)' "$CONFIG_PATH")
        if [ "$cr_trivial_valid" != "true" ]; then
          ERRORS+=("complexity_routing.trivial_confidence_threshold must be a number between 0.0 and 1.0")
        fi
      fi

      if jq -e '.complexity_routing | has("medium_confidence_threshold")' "$CONFIG_PATH" >/dev/null 2>&1; then
        local cr_medium_valid
        cr_medium_valid=$(jq '.complexity_routing.medium_confidence_threshold | (type == "number") and (. >= 0.0) and (. <= 1.0)' "$CONFIG_PATH")
        if [ "$cr_medium_valid" != "true" ]; then
          ERRORS+=("complexity_routing.medium_confidence_threshold must be a number between 0.0 and 1.0")
        fi
      fi

      if jq -e '.complexity_routing | has("trivial_confidence_threshold") and has("medium_confidence_threshold")' "$CONFIG_PATH" >/dev/null 2>&1; then
        local cr_order_valid
        cr_order_valid=$(jq '.complexity_routing.trivial_confidence_threshold > .complexity_routing.medium_confidence_threshold' "$CONFIG_PATH")
        if [ "$cr_order_valid" != "true" ]; then
          ERRORS+=("complexity_routing.trivial_confidence_threshold must be greater than medium_confidence_threshold")
        fi
      fi

      if jq -e '.complexity_routing | has("fallback_path")' "$CONFIG_PATH" >/dev/null 2>&1; then
        local cr_fp_valid
        cr_fp_valid=$(jq '.complexity_routing.fallback_path | (type == "string") and test("^(trivial|medium|high)$")' "$CONFIG_PATH")
        if [ "$cr_fp_valid" != "true" ]; then
          ERRORS+=("complexity_routing.fallback_path must be one of: trivial, medium, high")
        fi
      fi

      if jq -e '.complexity_routing | has("force_analyze_model")' "$CONFIG_PATH" >/dev/null 2>&1; then
        local cr_fam_valid
        cr_fam_valid=$(jq '.complexity_routing.force_analyze_model | (type == "string") and test("^(opus|sonnet|haiku)$")' "$CONFIG_PATH")
        if [ "$cr_fam_valid" != "true" ]; then
          ERRORS+=("complexity_routing.force_analyze_model must be one of: opus, sonnet, haiku")
        fi
      fi

      if jq -e '.complexity_routing | has("max_trivial_files")' "$CONFIG_PATH" >/dev/null 2>&1; then
        local cr_mtf_valid
        cr_mtf_valid=$(jq '.complexity_routing.max_trivial_files | (type == "number") and (. > 0) and (. == floor)' "$CONFIG_PATH")
        if [ "$cr_mtf_valid" != "true" ]; then
          ERRORS+=("complexity_routing.max_trivial_files must be a positive integer")
        fi
      fi

      if jq -e '.complexity_routing | has("max_medium_tasks")' "$CONFIG_PATH" >/dev/null 2>&1; then
        local cr_mmt_valid
        cr_mmt_valid=$(jq '.complexity_routing.max_medium_tasks | (type == "number") and (. > 0) and (. == floor)' "$CONFIG_PATH")
        if [ "$cr_mmt_valid" != "true" ]; then
          ERRORS+=("complexity_routing.max_medium_tasks must be a positive integer")
        fi
      fi
    fi
  fi

  # --- Output ---
  if [ ${#ERRORS[@]} -eq 0 ]; then
    jq -n '{"valid":true,"errors":[]}'
    exit 0
  else
    printf '%s\n' "${ERRORS[@]}" | jq -R . | jq -s '{"valid":false,"errors":.}'
    exit 1
  fi
}

# ============================================================================
# GATES VALIDATION
# ============================================================================

validate_gates() {
  local STEP=""
  local PHASE_DIR=""

  local i=0
  while [ $i -lt ${#ARGS[@]} ]; do
    case "${ARGS[$i]}" in
      --step) STEP="${ARGS[$((i+1))]}"; i=$((i+2)) ;;
      --phase-dir) PHASE_DIR="${ARGS[$((i+1))]}"; i=$((i+2)) ;;
      *) echo "Unknown flag: ${ARGS[$i]}" >&2; exit 1 ;;
    esac
  done

  if [ -z "$STEP" ] || [ -z "$PHASE_DIR" ]; then
    echo "Usage: validate.sh --type gates --step <step_name> --phase-dir <path>" >&2
    exit 1
  fi

  local STATE_FILE="$PHASE_DIR/.execution-state.json"

  _gates_check_step_skipped() {
    local step_name="$1"
    if [ ! -f "$STATE_FILE" ]; then
      return 1
    fi
    local status
    status=$(jq -r --arg s "$step_name" '.steps[$s].status // ""' "$STATE_FILE" 2>/dev/null) || return 1
    [ "$status" = "skipped" ]
  }

  _gates_check_artifact_exists() {
    local artifact_path="$1"
    [ -f "$artifact_path" ] && [ -s "$artifact_path" ]
  }

  _gates_check_glob_exists() {
    local pattern="$1"
    local result
    result=$(ls $pattern 2>/dev/null | head -1) || true
    [ -n "$result" ]
  }

  _gates_check_step_complete() {
    local step_name="$1"
    if [ ! -f "$STATE_FILE" ]; then
      return 1
    fi
    local status
    status=$(jq -r --arg s "$step_name" '.steps[$s].status // ""' "$STATE_FILE" 2>/dev/null) || return 1
    [ "$status" = "complete" ]
  }

  local MISSING=()
  local GATE_RESULT="pass"

  case "$STEP" in
    critique)
      if [ ! -d "$PHASE_DIR" ]; then
        MISSING+=("Phase directory does not exist: $PHASE_DIR")
        GATE_RESULT="fail"
      fi
      ;;

    architecture)
      if ! _gates_check_artifact_exists "$PHASE_DIR/critique.jsonl" && ! _gates_check_step_skipped "critique"; then
        MISSING+=("critique.jsonl")
        GATE_RESULT="fail"
      fi
      ;;

    planning)
      if ! _gates_check_artifact_exists "$PHASE_DIR/architecture.toon" && ! _gates_check_step_skipped "architecture"; then
        MISSING+=("architecture.toon")
        GATE_RESULT="fail"
      fi
      ;;

    design_review)
      if ! _gates_check_glob_exists "$PHASE_DIR/*.plan.jsonl"; then
        MISSING+=("*.plan.jsonl")
        GATE_RESULT="fail"
      fi
      ;;

    test_authoring)
      local _gate_plans
      _gate_plans=$(ls "$PHASE_DIR"/*.plan.jsonl 2>/dev/null) || true
      if [ -z "$_gate_plans" ]; then
        MISSING+=("*.plan.jsonl")
        GATE_RESULT="fail"
      else
        while IFS= read -r plan_file; do
          [ -z "$plan_file" ] && continue
          local _has_missing_spec=false
          while IFS= read -r task_line; do
            [ -z "$task_line" ] && continue
            local _spec_check
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
      local _gate_plans
      _gate_plans=$(ls "$PHASE_DIR"/*.plan.jsonl 2>/dev/null) || true
      if [ -z "$_gate_plans" ]; then
        MISSING+=("*.plan.jsonl")
        GATE_RESULT="fail"
      else
        while IFS= read -r plan_file; do
          [ -z "$plan_file" ] && continue
          local _has_missing_spec=false
          while IFS= read -r task_line; do
            [ -z "$task_line" ] && continue
            local _spec_check
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
      if _gates_check_step_complete "test_authoring"; then
        if ! _gates_check_artifact_exists "$PHASE_DIR/test-plan.jsonl"; then
          MISSING+=("test-plan.jsonl (test_authoring step completed)")
          GATE_RESULT="fail"
        fi
      fi
      ;;

    code_review)
      local _gate_plans
      _gate_plans=$(ls "$PHASE_DIR"/*.plan.jsonl 2>/dev/null) || true
      if [ -z "$_gate_plans" ]; then
        MISSING+=("*.plan.jsonl")
        GATE_RESULT="fail"
      else
        while IFS= read -r plan_file; do
          [ -z "$plan_file" ] && continue
          local _plan_header
          _plan_header=$(head -1 "$plan_file") || true
          local _plan_p _plan_n
          _plan_p=$(echo "$_plan_header" | jq -r '.p // ""' 2>/dev/null) || true
          _plan_n=$(echo "$_plan_header" | jq -r '.n // ""' 2>/dev/null) || true
          local _plan_id="${_plan_p}-${_plan_n}"
          if ! _gates_check_artifact_exists "$PHASE_DIR/${_plan_id}.summary.jsonl"; then
            MISSING+=("${_plan_id}.summary.jsonl")
            GATE_RESULT="fail"
          fi
        done <<< "$_gate_plans"
      fi
      ;;

    qa)
      if ! _gates_check_artifact_exists "$PHASE_DIR/code-review.jsonl"; then
        MISSING+=("code-review.jsonl")
        GATE_RESULT="fail"
      else
        local _review_result
        _review_result=$(head -1 "$PHASE_DIR/code-review.jsonl" | jq -r '.r // ""' 2>/dev/null) || true
        if [ "$_review_result" != "approve" ]; then
          MISSING+=("code-review.jsonl: r must be 'approve' (got '$_review_result')")
          GATE_RESULT="fail"
        fi
      fi
      ;;

    security)
      if ! _gates_check_artifact_exists "$PHASE_DIR/verification.jsonl" && ! _gates_check_step_skipped "qa"; then
        MISSING+=("verification.jsonl")
        GATE_RESULT="fail"
      fi
      ;;

    signoff)
      if ! _gates_check_artifact_exists "$PHASE_DIR/security-audit.jsonl" && ! _gates_check_step_skipped "security"; then
        MISSING+=("security-audit.jsonl")
        GATE_RESULT="fail"
      fi
      if ! _gates_check_artifact_exists "$PHASE_DIR/code-review.jsonl"; then
        MISSING+=("code-review.jsonl")
        GATE_RESULT="fail"
      else
        local _review_result
        _review_result=$(head -1 "$PHASE_DIR/code-review.jsonl" | jq -r '.r // ""' 2>/dev/null) || true
        if [ "$_review_result" != "approve" ]; then
          MISSING+=("code-review.jsonl: r must be 'approve' (got '$_review_result')")
          GATE_RESULT="fail"
        fi
      fi
      ;;

    post_task_qa)
      if _gates_check_artifact_exists "$PHASE_DIR/.qa-gate-results.jsonl"; then
        local _has_post_task
        _has_post_task=$(jq -r 'select(.gl=="post-task")' "$PHASE_DIR/.qa-gate-results.jsonl" 2>/dev/null | head -1) || true
        if [ -z "$_has_post_task" ]; then
          MISSING+=("post-task gate results in .qa-gate-results.jsonl")
          GATE_RESULT="fail"
        fi
      elif ! _gates_check_step_skipped "post_task_qa"; then
        MISSING+=(".qa-gate-results.jsonl")
        GATE_RESULT="fail"
      fi
      ;;

    post_plan_qa)
      if _gates_check_artifact_exists "$PHASE_DIR/.qa-gate-results.jsonl"; then
        local _has_post_plan
        _has_post_plan=$(jq -r 'select(.gl=="post-plan")' "$PHASE_DIR/.qa-gate-results.jsonl" 2>/dev/null | head -1) || true
        if [ -z "$_has_post_plan" ]; then
          MISSING+=("post-plan gate results in .qa-gate-results.jsonl")
          GATE_RESULT="fail"
        fi
      elif ! _gates_check_step_skipped "post_plan_qa"; then
        MISSING+=(".qa-gate-results.jsonl")
        GATE_RESULT="fail"
      fi
      ;;

    research)
      if ! _gates_check_artifact_exists "$PHASE_DIR/research.jsonl" && ! _gates_check_step_skipped "research"; then
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
}

# ============================================================================
# DEPS VALIDATION
# ============================================================================

validate_deps() {
  local ROADMAP_JSON=""

  local i=0
  while [ $i -lt ${#ARGS[@]} ]; do
    case "${ARGS[$i]}" in
      --roadmap-json)
        ROADMAP_JSON="${ARGS[$((i+1))]}"
        i=$((i+2))
        ;;
      *)
        echo "Usage: validate.sh --type deps --roadmap-json <path>" >&2
        exit 1
        ;;
    esac
  done

  if [ -z "$ROADMAP_JSON" ]; then
    echo "Error: --roadmap-json is required" >&2
    exit 1
  fi

  if [ ! -f "$ROADMAP_JSON" ]; then
    echo "Error: roadmap file not found: $ROADMAP_JSON" >&2
    exit 1
  fi

  if ! jq -e '.' "$ROADMAP_JSON" >/dev/null 2>&1; then
    jq -n '{"valid":false,"errors":["Roadmap file is not valid JSON"],"warnings":[]}'
    exit 1
  fi

  local HAS_PHASES
  HAS_PHASES=$(jq 'has("phases") and (.phases | type == "array")' "$ROADMAP_JSON")
  if [ "$HAS_PHASES" != "true" ]; then
    jq -n '{"valid":false,"errors":["Missing or invalid phases array"],"warnings":[]}'
    exit 1
  fi

  local PHASE_COUNT
  PHASE_COUNT=$(jq '.phases | length' "$ROADMAP_JSON")
  if [ "$PHASE_COUNT" -eq 0 ]; then
    jq -n '{"valid":false,"errors":["Phases array is empty"],"warnings":[]}'
    exit 1
  fi

  local ALL_IDS
  ALL_IDS=$(jq -r '.phases[].id' "$ROADMAP_JSON")

  local ERRORS=()
  local WARNINGS=()

  # Check 1: All referenced dependency IDs exist
  while IFS= read -r line; do
    if [ -n "$line" ]; then
      local PHASE_ID
      PHASE_ID=$(echo "$line" | jq -r '.id')
      local DEPS
      DEPS=$(echo "$line" | jq -r '.depends_on // [] | .[]')
      for dep in $DEPS; do
        if ! echo "$ALL_IDS" | grep -qx "$dep"; then
          ERRORS+=("Phase '$PHASE_ID' depends on '$dep' which does not exist in phases array")
        fi
      done
    fi
  done < <(jq -c '.phases[]' "$ROADMAP_JSON")

  # Check 2: No circular dependencies (Kahn's algorithm via jq)
  local TOPO_RESULT
  TOPO_RESULT=$(jq -r '
    [.phases[].id] as $all_ids |
    .phases as $phases |
    (reduce $phases[] as $p ({};
      ($p.depends_on // []) as $deps |
      reduce ($deps[] | select(. as $d | $all_ids | index($d))) as $d (.;
        .[$p.id] = ((.[$p.id] // 0) + 1)
      )
    )) as $in_degree |
    {
      queue: [$all_ids[] | select(($in_degree[.] // 0) == 0)],
      sorted: [],
      deg: $in_degree
    } |
    until(.queue | length == 0;
      .queue[0] as $n |
      {
        queue: .queue[1:],
        sorted: (.sorted + [$n]),
        deg: .deg
      } |
      ([$phases[] | select((.depends_on // []) | index($n)) | .id]) as $neighbors |
      reduce $neighbors[] as $nb (.;
        .deg[$nb] = ((.deg[$nb] // 1) - 1) |
        if .deg[$nb] == 0 then .queue += [$nb] else . end
      )
    ) |
    .sorted as $sorted_list |
    if ($sorted_list | length) == ($all_ids | length) then
      "OK"
    else
      "CYCLE:" + ([$all_ids[] | select(. as $id | $sorted_list | index($id) | not)] | join(","))
    end
  ' "$ROADMAP_JSON" 2>/dev/null || echo "TOPO_ERROR")

  if [ "${TOPO_RESULT%%:*}" = "CYCLE" ]; then
    local CYCLE_NODES="${TOPO_RESULT#CYCLE:}"
    ERRORS+=("Circular dependency detected involving phases: $CYCLE_NODES")
  elif [ "$TOPO_RESULT" = "TOPO_ERROR" ]; then
    ERRORS+=("Failed to perform topological sort on dependency graph")
  fi

  # Check 3: Orphan phases
  while IFS= read -r line; do
    if [ -n "$line" ]; then
      local PHASE_ID
      PHASE_ID=$(echo "$line" | jq -r '.id')
      local HAS_DEPS
      HAS_DEPS=$(echo "$line" | jq '(.depends_on // []) | length > 0')
      local IS_DEPENDED_ON
      IS_DEPENDED_ON=$(jq --arg pid "$PHASE_ID" '[.phases[] | .depends_on // [] | index($pid)] | any(. != null)' "$ROADMAP_JSON")
      if [ "$HAS_DEPS" = "false" ] && [ "$IS_DEPENDED_ON" = "false" ] && [ "$PHASE_COUNT" -gt 1 ]; then
        WARNINGS+=("Phase '$PHASE_ID' is orphaned (no dependencies and nothing depends on it)")
      fi
    fi
  done < <(jq -c '.phases[]' "$ROADMAP_JSON")

  # Check 4: Critical path phases connected
  local CRITICAL_COUNT
  CRITICAL_COUNT=$(jq '[.phases[] | select(.critical == true)] | length' "$ROADMAP_JSON")
  if [ "$CRITICAL_COUNT" -gt 1 ]; then
    local CRITICAL_IDS
    CRITICAL_IDS=$(jq -r '[.phases[] | select(.critical == true) | .id] | join(" ")' "$ROADMAP_JSON")
    for cid in $CRITICAL_IDS; do
      local HAS_CRITICAL_LINK
      HAS_CRITICAL_LINK=$(jq --arg pid "$cid" '
        (.phases[] | select(.id == $pid) | .depends_on // []) as $deps |
        [.phases[] | select(.critical == true) | .id] as $critical_ids |
        ([$deps[] | select(. as $d | $critical_ids | index($d))] | length > 0) or
        ([.phases[] | select(.critical == true) | .depends_on // [] | index($pid)] | any(. != null))
      ' "$ROADMAP_JSON")
      if [ "$HAS_CRITICAL_LINK" = "false" ]; then
        WARNINGS+=("Critical phase '$cid' is not connected to other critical phases in the dependency graph")
      fi
    done
  fi

  # --- Output ---
  if [ ${#ERRORS[@]} -eq 0 ]; then
    if [ ${#WARNINGS[@]} -eq 0 ]; then
      jq -n '{"valid":true,"errors":[],"warnings":[]}'
    else
      printf '%s\n' "${WARNINGS[@]}" | jq -R . | jq -s '{valid: true, errors: [], warnings: .}'
    fi
    exit 0
  else
    local ERRORS_JSON
    ERRORS_JSON=$(printf '%s\n' "${ERRORS[@]}" | jq -R . | jq -s '.')
    if [ ${#WARNINGS[@]} -eq 0 ]; then
      echo "$ERRORS_JSON" | jq '{valid: false, errors: ., warnings: []}'
    else
      local WARNINGS_JSON
      WARNINGS_JSON=$(printf '%s\n' "${WARNINGS[@]}" | jq -R . | jq -s '.')
      jq -n --argjson errors "$ERRORS_JSON" --argjson warnings "$WARNINGS_JSON" \
        '{valid: false, errors: $errors, warnings: $warnings}'
    fi
    exit 1
  fi
}

# ============================================================================
# SUMMARY VALIDATION (hook-style, reads stdin)
# ============================================================================

validate_summary() {
  local INPUT
  INPUT=$(cat)

  # Fast exit for non-summary files
  case "$INPUT" in
    *.summary.jsonl*|*SUMMARY.md*) ;;
    *) exit 0 ;;
  esac

  local FILE_PATH
  FILE_PATH=$(jq -r '.tool_input.file_path // .tool_input.command // ""' <<< "$INPUT")

  local IS_JSONL=false IS_MD=false
  case "$FILE_PATH" in
    *.yolo-planning/*.summary.jsonl) IS_JSONL=true ;;
    *.yolo-planning/*SUMMARY.md) IS_MD=true ;;
  esac

  [ "$IS_JSONL" != true ] && [ "$IS_MD" != true ] && exit 0
  [ -f "$FILE_PATH" ] || exit 0

  local MISSING=""

  if [ "$IS_JSONL" = true ]; then
    if command -v jq >/dev/null 2>&1; then
      MISSING=$(jq -r '[
        (if has("p") then empty else "Missing '\''p'\'' (phase) field. " end),
        (if has("s") then empty else "Missing '\''s'\'' (status) field. " end),
        (if has("fm") then empty else "Missing '\''fm'\'' (files_modified) field. " end),
        (if has("sg") then (if (.sg | type == "array" and all(type == "string" and length > 0)) then empty else "Field '\''sg'\'' must be an array of non-empty strings. " end) else empty end)
      ] | join("")' "$FILE_PATH" 2>/dev/null)
    fi
  else
    if ! head -1 "$FILE_PATH" | grep -q '^---$'; then
      MISSING="Missing YAML frontmatter. "
    fi
    if ! grep -q "## What Was Built" "$FILE_PATH"; then
      MISSING="${MISSING}Missing '## What Was Built'. "
    fi
    if ! grep -q "## Files Modified" "$FILE_PATH"; then
      MISSING="${MISSING}Missing '## Files Modified'. "
    fi
  fi

  if [ -n "$MISSING" ]; then
    jq -n --arg msg "$MISSING" '{
      "hookSpecificOutput": {
        "additionalContext": ("SUMMARY validation: " + $msg)
      }
    }'
  fi

  exit 0
}

# ============================================================================
# FRONTMATTER VALIDATION (hook-style, reads stdin)
# ============================================================================

validate_frontmatter() {
  local INPUT
  INPUT=$(cat 2>/dev/null) || exit 0
  [ -z "$INPUT" ] && exit 0
  local FILE_PATH
  FILE_PATH=$(jq -r '.tool_input.file_path // ""' <<< "$INPUT" 2>/dev/null) || exit 0

  # Only check .md files
  case "$FILE_PATH" in
    *.md) ;;
    *) exit 0 ;;
  esac

  [ ! -f "$FILE_PATH" ] && exit 0
  local HEAD
  HEAD=$(head -1 "$FILE_PATH" 2>/dev/null)
  [ "$HEAD" != "---" ] && exit 0

  local WARNING
  WARNING=$(awk '
    BEGIN { in_fm=0; found_desc=0; desc_val=""; has_continuation=0 }
    NR==1 && $0=="---" { in_fm=1; next }
    in_fm && $0=="---" { in_fm=0; next }
    !in_fm { next }
    /^description:/ {
      found_desc=1
      sub(/^description:[[:space:]]*/, "")
      desc_val=$0
      next
    }
    found_desc==1 && /^[[:space:]]/ { has_continuation=1; next }
    found_desc==1 && !/^[[:space:]]/ { found_desc=2 }
    END {
      if (!found_desc) print "ok"
      else if (desc_val ~ /^[|>]/) print "multiline_indicator"
      else if (desc_val == "" && has_continuation) print "multiline_empty"
      else if (desc_val == "" && !has_continuation) print "empty"
      else if (has_continuation) print "multiline_continuation"
      else print "ok"
    }
  ' "$FILE_PATH" 2>/dev/null)

  case "$WARNING" in
    multiline_indicator|multiline_empty|multiline_continuation)
      jq -n --arg file "$FILE_PATH" '{
        "hookSpecificOutput": {
          "additionalContext": ("Frontmatter warning: description field in " + $file + " must be a single line. Multi-line descriptions break plugin command/skill discovery. Fix: collapse to one line.")
        }
      }'
      ;;
    empty)
      jq -n --arg file "$FILE_PATH" '{
        "hookSpecificOutput": {
          "additionalContext": ("Frontmatter warning: description field in " + $file + " is empty. Empty descriptions break plugin command/skill discovery. Fix: add a single-line description.")
        }
      }'
      ;;
    ok|*) ;;
  esac

  exit 0
}

# ============================================================================
# DISPATCHER
# ============================================================================

case "$TYPE" in
  plan) validate_plan ;;
  naming) validate_naming ;;
  config) validate_config ;;
  gates) validate_gates ;;
  deps) validate_deps ;;
  summary) validate_summary ;;
  frontmatter) validate_frontmatter ;;
  *)
    echo "Unknown validation type: $TYPE" >&2
    echo "Valid types: plan, summary, naming, config, gates, deps, frontmatter" >&2
    exit 1
    ;;
esac
