#!/usr/bin/env bash
set -euo pipefail

# compile-context.sh <phase-number> <role> [phases-dir] [plan-path]
# Produces .ctx-{role}.toon in the phase directory with role-specific context.
# Roles: architect, lead, senior, dev, qa, qa-code, security, debugger, critic, tester, owner, integration-gate, analyze, po, questionary, roadmap
# Department roles: fe-architect, fe-lead, fe-senior, fe-dev, fe-tester, fe-qa, fe-qa-code
#                   ux-architect, ux-lead, ux-senior, ux-dev, ux-tester, ux-qa, ux-qa-code
# Exit 0 on success, exit 1 when phase directory not found.

# --- Parse --measure flag (must be first arg if present) ---
MEASURE=false
if [ "${1:-}" = "--measure" ]; then
  MEASURE=true
  shift
fi

if [ $# -lt 2 ]; then
  echo "Usage: compile-context.sh [--measure] <phase-number> <role> [phases-dir] [plan-path]" >&2
  exit 1
fi

PHASE="$1"
ROLE="$2"
PHASES_DIR="${3:-.yolo-planning/phases}"
PLANNING_DIR=$(dirname "$PHASES_DIR")
PLAN_PATH="${4:-}"

# --- Extract department and base role from role name ---
# fe-dev → DEPT=fe, BASE_ROLE=dev; ux-architect → DEPT=ux, BASE_ROLE=architect
# architect → DEPT=backend, BASE_ROLE=architect; owner → DEPT=shared, BASE_ROLE=owner
case "$ROLE" in
  fe-*) DEPT="fe"; BASE_ROLE="${ROLE#fe-}" ;;
  ux-*) DEPT="ux"; BASE_ROLE="${ROLE#ux-}" ;;
  owner|analyze|po|questionary|roadmap) DEPT="shared"; BASE_ROLE="$ROLE" ;;
  *) DEPT="backend"; BASE_ROLE="$ROLE" ;;
esac

# --- Resolve department-specific architecture file ---
get_arch_file() {
  case "$DEPT" in
    fe)      echo "$PHASE_DIR/fe-architecture.toon" ;;
    ux)      echo "$PHASE_DIR/ux-architecture.toon" ;;
    *)       echo "$PHASE_DIR/architecture.toon" ;;
  esac
}

# Strip leading zeros for ROADMAP matching (ROADMAP uses "Phase 2:", not "Phase 02:")
# OPTIMIZATION 3: Use arithmetic instead of sed for leading zero removal
PHASE_NUM=$(( 10#$PHASE ))

# --- Find phase directory ---
# OPTIMIZATION 1: Use ls glob instead of find for phase dir lookup
PHASE_DIR=$(command ls -d "$PHASES_DIR/${PHASE}-"*/ 2>/dev/null | head -1 || true)
PHASE_DIR=${PHASE_DIR%/}
if [ -z "$PHASE_DIR" ]; then
  echo "Phase ${PHASE} directory not found" >&2
  exit 1
fi

# --- SQLite DB (mandatory) ---
DB_PATH="${PLANNING_DIR}/yolo.db"
if [ ! -f "$DB_PATH" ]; then
  echo "ERROR: Database not found at $DB_PATH. Run init-db.sh first." >&2
  exit 1
fi

# Helper: execute read-only SQL query against yolo.db
# Usage: sql "SELECT ..." → stdout rows
sql() {
  sqlite3 -batch "$DB_PATH" <<EOSQL
.output /dev/null
PRAGMA journal_mode=WAL;
PRAGMA busy_timeout=5000;
.output stdout
.mode list
.separator ','
.headers off
$1
EOSQL
}

# Helper: format SQL output as TOON lines with prefix
# Usage: sql_toon "prefix" "SELECT col1,col2 FROM ..."
sql_toon() {
  local prefix="$1" query="$2"
  sql "$query" | while IFS= read -r row; do
    [ -n "$row" ] && echo "  ${prefix}${row}"
  done
}

# --- Extract phase metadata (SQL-only) ---
ROADMAP="$PLANNING_DIR/ROADMAP.md"

PHASE_GOAL="Not available"
PHASE_REQS="Not available"
PHASE_SUCCESS="Not available"

_db_goal=$(sql "SELECT objective FROM plans WHERE phase='$PHASE' LIMIT 1;" 2>/dev/null || true)
_db_reqs=$(sql "SELECT must_haves FROM plans WHERE phase='$PHASE' LIMIT 1;" 2>/dev/null || true)
if [ -n "$_db_goal" ] && [ "$_db_goal" != "" ]; then
  PHASE_GOAL="$_db_goal"
  if [ -n "$_db_reqs" ] && command -v jq &>/dev/null; then
    _reqs_parsed=$(echo "$_db_reqs" | jq -r '.tr // [] | join(", ")' 2>/dev/null || true)
    [ -n "$_reqs_parsed" ] && PHASE_REQS="$_reqs_parsed"
  fi
fi

# --- Build REQ grep pattern from comma-separated REQ IDs ---
REQ_PATTERN=""
if [ "$PHASE_REQS" != "Not available" ] && [ -n "$PHASE_REQS" ]; then
  REQ_PATTERN=$(echo "$PHASE_REQS" | tr ',' '\n' | sed 's/^ *//' | sed 's/ *$//' | paste -sd '|' -) || true
fi

# --- Helper: extract conventions (compact, tag-only if over budget) ---
get_conventions() {
  local compact="${1:-false}"
  if [ -f "$PLANNING_DIR/conventions.json" ] && command -v jq &>/dev/null; then
    if [ "$compact" = "true" ]; then
      jq -r '.conventions[] | "  \(.category)"' "$PLANNING_DIR/conventions.json" 2>/dev/null || true
    else
      jq -r '.conventions[] | "  \(.category),\(.rule)"' "$PLANNING_DIR/conventions.json" 2>/dev/null || true
    fi
  fi
}

# --- Helper: get research findings if available ---
get_research() {
  local _rows
  _rows=$(sql "SELECT q, finding FROM research WHERE phase='$PHASE' AND q != '' AND finding != '';" 2>/dev/null || true)
  if [ -n "$_rows" ]; then
    echo "research:"
    echo "$_rows" | while IFS=',' read -r _q _finding; do
      echo "  - $_q: $_finding"
    done
  fi
}

# --- Helper: get decisions from decisions.jsonl ---
get_decisions() {
  local _rows
  _rows=$(sql "SELECT agent, dec, reason FROM decisions WHERE phase='$PHASE' AND dec != '';" 2>/dev/null || true)
  if [ -n "$_rows" ]; then
    echo "decisions:"
    echo "$_rows" | while IFS=',' read -r _agent _dec _reason; do
      echo "  $_agent: $_dec ($_reason)"
    done
  fi
}

# --- Helper: get department conventions from generated or static TOON ---
get_dept_conventions() {
  # Map DEPT to generated TOON filename
  local DEPT_TOON_FILE
  case "$DEPT" in
    backend) DEPT_TOON_FILE="backend.toon" ;;
    fe)      DEPT_TOON_FILE="frontend.toon" ;;
    ux)      DEPT_TOON_FILE="uiux.toon" ;;
    shared)  return 0 ;;  # shared department has no generated conventions
  esac

  # Try generated path first (project-specific)
  local GENERATED_DEPT_TOON="$PLANNING_DIR/departments/$DEPT_TOON_FILE"
  if [ -f "$GENERATED_DEPT_TOON" ]; then
    cat "$GENERATED_DEPT_TOON"
    return 0
  fi

  # Fall back to static department TOON (extract conventions section only)
  local STATIC_DEPT_TOON
  case "$DEPT" in
    backend) STATIC_DEPT_TOON="references/departments/backend.toon" ;;
    fe)      STATIC_DEPT_TOON="references/departments/frontend.toon" ;;
    ux)      STATIC_DEPT_TOON="references/departments/uiux.toon" ;;
  esac
  if [ -f "${STATIC_DEPT_TOON:-}" ]; then
    awk '/^conventions:/,/^[a-z_]+:/{if(/^[a-z_]+:/ && !/^conventions:/) exit; print}' "$STATIC_DEPT_TOON"
    return 0
  fi

  # Neither exists — silent backward-compatible return
  return 0
}

# --- Helper: get per-role reference package path (D3/D6) ---
# Returns the path to references/packages/{BASE_ROLE}.toon if it exists.
# Backward compatible: returns 1 when packages/ dir absent (D6).
get_reference_package() {
  local PACKAGE_PATH="references/packages/${BASE_ROLE}.toon"
  if [ -f "$PACKAGE_PATH" ]; then
    echo "$PACKAGE_PATH"
    return 0
  fi
  return 1
}

# --- Helper: get tool restrictions from resolve-tool-permissions.sh (D4) ---
# Emits tool_restrictions section when disallowed_tools exist for this role/project.
# Silently returns 0 when resolve-tool-permissions.sh is absent (pre-phase-3).
get_tool_restrictions() {
  local RESOLVE_SCRIPT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")" && pwd)/..}/scripts/resolve-tool-permissions.sh"
  if [ -x "$RESOLVE_SCRIPT" ]; then
    local TOOL_JSON
    TOOL_JSON=$(bash "$RESOLVE_SCRIPT" --role "$ROLE" --project-dir "." 2>/dev/null) || return 0
    local DISALLOWED
    DISALLOWED=$(echo "$TOOL_JSON" | jq -r '.disallowed_tools // [] | join(", ")' 2>/dev/null) || return 0
    if [ -n "$DISALLOWED" ]; then
      echo "tool_restrictions:"
      echo "  Do NOT use: $DISALLOWED"
    fi
  fi
  return 0
}

# --- Helper: get architecture summary ---
get_architecture() {
  local arch_file="$PHASE_DIR/architecture.toon"
  if [ -f "$arch_file" ]; then
    # Extract goal and tech_decisions lines (first 20 lines max)
    head -20 "$arch_file"
  fi
}

# --- Helper: get requirements ---
get_requirements() {
  if [ -n "$REQ_PATTERN" ]; then
    local _mh
    _mh=$(sql "SELECT must_haves FROM plans WHERE phase='$PHASE' LIMIT 1;" 2>/dev/null || true)
    if [ -n "$_mh" ] && command -v jq &>/dev/null; then
      local _reqs
      _reqs=$(echo "$_mh" | jq -r '.tr // [] | .[] | "  \(.)"' 2>/dev/null || true)
      if [ -n "$_reqs" ]; then
        echo "reqs:"
        echo "$_reqs"
      fi
    fi
  fi
}

# --- Helper: get manifest config for a role (data-driven context scoping) ---
# Reads config/context-manifest.json when present and returns role entry via jq.
# Returns empty (triggers fallback to hardcoded case blocks) when manifest absent.
MANIFEST_PATH="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")" && pwd)/..}/config/context-manifest.json"
MANIFEST_AVAILABLE=false
if [ -f "$MANIFEST_PATH" ] && command -v jq &>/dev/null; then
  MANIFEST_AVAILABLE=true
fi

get_manifest_config() {
  local role="$1"
  local field="$2"  # files, artifacts, fields, budget, includes
  if [ "$MANIFEST_AVAILABLE" = true ]; then
    jq -r --arg r "$role" --arg f "$field" '.roles[$r][$f] // empty' "$MANIFEST_PATH" 2>/dev/null || true
  fi
}

get_manifest_budget() {
  local role="$1"
  if [ "$MANIFEST_AVAILABLE" = true ]; then
    local budget
    budget=$(jq -r --arg r "$role" '.roles[$r].budget // empty' "$MANIFEST_PATH" 2>/dev/null) || true
    if [ -n "$budget" ] && [ "$budget" != "null" ]; then
      echo "$budget"
      return 0
    fi
  fi
  return 1
}

get_manifest_artifacts() {
  local role="$1"
  if [ "$MANIFEST_AVAILABLE" = true ]; then
    jq -r --arg r "$role" '.roles[$r].artifacts // [] | .[]' "$MANIFEST_PATH" 2>/dev/null || true
  fi
}

get_manifest_files() {
  local role="$1"
  if [ "$MANIFEST_AVAILABLE" = true ]; then
    jq -r --arg r "$role" '.roles[$r].files // [] | .[]' "$MANIFEST_PATH" 2>/dev/null || true
  fi
}

get_manifest_field_filter() {
  local role="$1"
  local artifact_type="$2"
  if [ "$MANIFEST_AVAILABLE" = true ]; then
    jq -r --arg r "$role" --arg t "$artifact_type" '.roles[$r].fields[$t] // [] | .[]' "$MANIFEST_PATH" 2>/dev/null || true
  fi
}

# --- Helper: emit rolling summaries for prior plans ---
# When compiling context for plan NN-MM, includes only summary.jsonl for plans < NN-MM.
# This caps context growth as phase plan count increases.
get_rolling_summaries() {
  if [ -z "$PLAN_PATH" ] || [ ! -f "$PLAN_PATH" ]; then
    return 0
  fi
  local current_plan
  current_plan=$(basename "$PLAN_PATH" .plan.jsonl)

  local _current_num="${current_plan##*-}"  # e.g. "01-03" -> "03"
  local _rows
  _rows=$(sql "SELECT p.plan_num, s.status, s.fm
    FROM summaries s JOIN plans p ON s.plan_id = p.rowid
    WHERE p.phase='$PHASE' AND p.plan_num < '$_current_num'
    ORDER BY p.plan_num;" 2>/dev/null || true)
  if [ -n "$_rows" ]; then
    echo "prior_plans:"
    echo "$_rows" | while IFS=',' read -r _pn _st _fm; do
      echo "  $PHASE-$_pn: s=$_st fm=$_fm"
    done
  fi
}

# --- Helper: emit error recovery context from gaps.jsonl ---
# When gaps.jsonl has open entries with retry_context, includes error details
# so the retry agent knows what failed and why.
get_error_recovery() {
  local _rows
  _rows=$(sql "SELECT id, res FROM gaps WHERE phase='$PHASE' AND st='open' AND res != '' AND res IS NOT NULL;" 2>/dev/null || true)
  if [ -n "$_rows" ]; then
    echo "error_recovery:"
    echo "$_rows" | while IFS=',' read -r _id _ctx; do
      echo "  $_id: $_ctx"
    done
  fi
}

# --- Helper: emit all plan summaries (for QA/QA-code phase-wide review) ---
# Unlike get_rolling_summaries which skips the current plan, this includes all.
get_all_plan_summaries() {
  local _rows
  _rows=$(sql "SELECT p.plan_num, s.status, s.fm
    FROM summaries s JOIN plans p ON s.plan_id = p.rowid
    WHERE p.phase='$PHASE'
    ORDER BY p.plan_num;" 2>/dev/null || true)
  if [ -n "$_rows" ]; then
    echo "plan_summaries:"
    echo "$_rows" | while IFS=',' read -r _pn _st _fm; do
      echo "  $PHASE-$_pn: s=$_st fm=$_fm"
    done
  fi
}

# --- Token budget per role (chars/4 ≈ tokens) ---
# Uses BASE_ROLE for department agents (fe-dev → dev budget, ux-architect → architect budget)
# Reads from manifest when available, falls through to hardcoded case block otherwise.
get_budget() {
  # Manifest-first: use manifest budget when available
  if get_manifest_budget "$1" 2>/dev/null; then
    return 0
  fi
  # Fallback: hardcoded case statement
  case "$1" in
    architect|fe-architect|ux-architect)  echo 5000 ;;
    lead|fe-lead|ux-lead)                 echo 3000 ;;
    senior|fe-senior|ux-senior)           echo 4000 ;;
    dev|fe-dev|ux-dev)                    echo 2000 ;;
    qa|fe-qa|ux-qa)                       echo 2000 ;;
    qa-code|fe-qa-code|ux-qa-code)        echo 3000 ;;
    security|fe-security)                 echo 3000 ;;
    ux-security)                          echo 2000 ;;
    scout)                                echo 1000 ;;
    debugger)                             echo 3000 ;;
    critic)                               echo 4000 ;;
    tester|fe-tester|ux-tester)           echo 3000 ;;
    owner)                                echo 3000 ;;
    documenter|fe-documenter|ux-documenter) echo 2000 ;;
    analyze)                              echo 2000 ;;
    po)                                   echo 3000 ;;
    questionary)                          echo 2000 ;;
    roadmap)                              echo 3000 ;;
    *)                                    echo 3000 ;;
  esac
}

# OPTIMIZATION 5: Single-pass awk truncation (replaces 3 sed/awk passes + 4 wc calls)
enforce_budget() {
  local file="$1"
  local budget="$2"

  # Quick check: if file is within budget, skip entirely
  local chars
  chars=$(( $(wc -c < "$file") ))
  local tokens=$(( chars / 4 ))
  [ "$tokens" -le "$budget" ] && return 0

  # Single awk pass that applies increasingly aggressive truncation
  local budget_chars=$(( budget * 4 ))
  local tmp="${file}.trunc.$$"
  awk -v budget_chars="$budget_chars" '
    BEGIN { bytes=0; level=0; in_reqs=0 }
    {
      line = $0
      len = length(line) + 1

      # Check if we need to escalate truncation level
      if (bytes + len > budget_chars && level == 0) level = 1
      if (bytes + len > budget_chars * 1.2 && level == 1) level = 2
      if (bytes + len > budget_chars * 1.4 && level == 2) level = 3

      # Track reqs section
      if (line ~ /^reqs:/) in_reqs = 1
      else if (line ~ /^[^ ]/ && line !~ /^$/) in_reqs = 0

      # Level 1: conventions tag-only (drop rule text after comma for convention lines)
      if (level >= 1 && !in_reqs && line ~ /^  [a-z_-]+,/) {
        sub(/,.*/, "", line)
      }

      # Level 2: requirements ID-only (drop title after comma for REQ lines)
      if (level >= 2 && in_reqs && line ~ /^  REQ-[0-9]+,/) {
        sub(/,.*/, "", line)
      }

      # Level 3: headings-only (drop indented content)
      if (level >= 3 && line ~ /^  / && line !~ /^$/) next

      bytes += length(line) + 1
      print line
    }
  ' "$file" > "$tmp" 2>/dev/null && mv "$tmp" "$file" || rm -f "$tmp"
}

BUDGET=$(get_budget "$ROLE")

# --- Resolve filter-agent-context.sh path (D10: graceful degradation) ---
FILTER_SCRIPT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")" && pwd)/..}/scripts/filter-agent-context.sh"
FILTER_AVAILABLE=false; [ -x "$FILTER_SCRIPT" ] && FILTER_AVAILABLE=true

ARCH_FILE=$(get_arch_file)

# OPTIMIZATION 6: Cache file existence flags (avoid repeated stat syscalls)
ARCH_EXISTS=false; [ -f "$ARCH_FILE" ] && ARCH_EXISTS=true
DECISIONS_EXISTS=true
HAS_CODEBASE=false; [ -d "$PLANNING_DIR/codebase" ] && HAS_CODEBASE=true
DEPT_CONVENTIONS_AVAILABLE=false
if [ -f "$PLANNING_DIR/departments/${DEPT_TOON_FILE:-}" ] || [ "$DEPT" != "shared" ]; then
  DEPT_CONVENTIONS_AVAILABLE=true
fi

# --- Department-aware header (adds department tag to context) ---
emit_header() {
  echo "phase: $PHASE"
  echo "goal: $PHASE_GOAL"
  if [ "$DEPT" != "backend" ]; then
    echo "department: $DEPT"
  fi
}

# --- Role-specific TOON output (uses BASE_ROLE for routing, ROLE for filename) ---
case "$BASE_ROLE" in
  architect)
    {
      emit_header
      echo ""
      get_requirements
      get_research
      echo ""
      # Include codebase mapping summaries if available
      if [ "$HAS_CODEBASE" = true ]; then
        echo "codebase:"
        for base in INDEX ARCHITECTURE PATTERNS CONCERNS; do
          if [ -f "$PLANNING_DIR/codebase/${base}.md" ]; then
            echo "  @$PLANNING_DIR/codebase/${base}.md"
          fi
        done
      fi
      echo ""
      # For FE architect: include UX handoff if available
      if [ "$DEPT" = "fe" ] && [ -f "$PHASE_DIR/design-handoff.jsonl" ]; then
        echo "design_handoff: @$PHASE_DIR/design-handoff.jsonl"
        echo ""
      fi
      echo "success_criteria: $PHASE_SUCCESS"
      REF_PKG=$(get_reference_package) && { echo ''; echo "reference_package: @${REF_PKG}"; }
      get_tool_restrictions
    } > "${PHASE_DIR}/.ctx-${ROLE}.toon"
    ;;

  lead)
    {
      emit_header
      echo ""
      # Architecture summary if available (department-specific)
      if [ "$ARCH_EXISTS" = true ]; then
        echo "architecture:"
        head -5 "$ARCH_FILE" | sed 's/^/  /'
        echo ""
      fi
      get_requirements
      echo ""
      # Decisions from decisions.jsonl (preferred) or STATE.md (fallback)
      if [ "$DECISIONS_EXISTS" = true ]; then
        get_decisions
      elif [ -f "$PLANNING_DIR/STATE.md" ]; then
        DECISIONS=$(sed -n '/^## Key Decisions/,/^## [A-Z]/p' "$PLANNING_DIR/STATE.md" 2>/dev/null | sed '$d' | tail -n +2) || true
        if [ -n "${DECISIONS:-}" ]; then
          echo "decisions:"
          echo "$DECISIONS" | head -5 | sed 's/^/  /'
        fi
      fi
      echo ""
      # For FE lead: include UX handoff and API contracts
      if [ "$DEPT" = "fe" ]; then
        if [ -f "$PHASE_DIR/design-handoff.jsonl" ]; then
          echo "design_handoff: @$PHASE_DIR/design-handoff.jsonl"
        fi
        if [ -f "$PHASE_DIR/api-contracts.jsonl" ]; then
          echo "api_contracts: @$PHASE_DIR/api-contracts.jsonl"
        fi
        echo ""
      fi
      # Test results summary (GREEN phase metrics)
      _tr_rows=$(sql "SELECT plan, ps, fl, dept FROM test_results WHERE phase='$PHASE';" 2>/dev/null || true)
      if [ -n "$_tr_rows" ]; then
        echo ""
        echo "test_results:"
        echo "$_tr_rows" | while IFS=',' read -r _plan _ps _fl _dept; do
          echo "  $_plan: ps=$_ps fl=$_fl dept=$_dept"
        done
      fi
      echo "success_criteria: $PHASE_SUCCESS"
      REF_PKG=$(get_reference_package) && { echo ''; echo "reference_package: @${REF_PKG}"; }
      get_tool_restrictions
    } > "${PHASE_DIR}/.ctx-${ROLE}.toon"
    ;;

  senior)
    {
      emit_header
      echo ""
      # Rolling summaries for prior plans (T-1: cap context growth)
      get_rolling_summaries
      # Error recovery context (CG-4: inject prior failure details on retry)
      get_error_recovery
      # Full architecture context (department-specific)
      if [ "$ARCH_EXISTS" = true ]; then
        echo "architecture:"
        sed 's/^/  /' "$ARCH_FILE"
        echo ""
      fi
      get_requirements
      echo ""
      # Codebase patterns for spec enrichment
      if [ -f "$PLANNING_DIR/codebase/PATTERNS.md" ]; then
        echo "patterns: @$PLANNING_DIR/codebase/PATTERNS.md"
      fi
      echo ""
      # For FE senior: include design tokens and component specs
      if [ "$DEPT" = "fe" ]; then
        if [ -f "$PHASE_DIR/design-tokens.jsonl" ]; then
          echo "design_tokens: @$PHASE_DIR/design-tokens.jsonl"
        fi
        if [ -f "$PHASE_DIR/component-specs.jsonl" ]; then
          echo "component_specs: @$PHASE_DIR/component-specs.jsonl"
        fi
        echo ""
      fi
      # Dev suggestions from summaries (for code review consumption)
      _sg_rows=$(sql "SELECT s.suggestions FROM summaries s JOIN plans p ON s.plan_id = p.rowid WHERE p.phase='$PHASE' AND s.suggestions IS NOT NULL AND s.suggestions != '' AND s.suggestions != 'null';" 2>/dev/null || true)
      if [ -n "$_sg_rows" ]; then
        echo ""
        echo "suggestions:"
        echo "$_sg_rows" | while IFS= read -r _sg_json; do
          echo "$_sg_json" | jq -r '.[]' 2>/dev/null | while IFS= read -r sg_item; do
            echo "  - $sg_item"
          done
        done
      fi
      echo ""
      # Conventions for code review
      CONVENTIONS=$(get_conventions)
      if [ -n "$CONVENTIONS" ]; then
        CONV_COUNT=$(echo "$CONVENTIONS" | wc -l | tr -d ' ')
        echo "conventions[${CONV_COUNT}]{category,rule}:"
        echo "$CONVENTIONS"
      fi
      # Department-specific conventions (generated or static fallback)
      DEPT_CONV=$(get_dept_conventions)
      if [ -n "$DEPT_CONV" ]; then
        echo ''
        echo 'dept_conventions:'
        echo "$DEPT_CONV" | sed 's/^/  /'
      fi
      REF_PKG=$(get_reference_package) && { echo ''; echo "reference_package: @${REF_PKG}"; }
      get_tool_restrictions
    } > "${PHASE_DIR}/.ctx-${ROLE}.toon"
    ;;

  dev)
    {
      emit_header
      echo ""
      # Rolling summaries for prior plans (T-1: cap context growth)
      get_rolling_summaries
      # Error recovery context (CG-4: inject prior failure details on retry)
      get_error_recovery
      # Plan tasks with specs (the Dev's primary input)
      if [ -n "$PLAN_PATH" ] && [ -f "$PLAN_PATH" ]; then
        # Extract tasks from plan.jsonl (skip header line)
        TASK_COUNT=$(tail -n +2 "$PLAN_PATH" | wc -l | tr -d ' ')
        echo "tasks[${TASK_COUNT}]{id,action,files,done,spec}:"
        if [ "$FILTER_AVAILABLE" = true ]; then
          bash "$FILTER_SCRIPT" --role "$BASE_ROLE" --artifact "$PLAN_PATH" --type plan 2>/dev/null | \
            jq -r 'select((.id // empty) != "") | "  \(.id),\(.a // ""),\(.f // [] | join(";")),\(.done // ""),\(.spec // "")"' 2>/dev/null || true
        else
          # Fallback: inline jq (pre-filter behavior)
          tail -n +2 "$PLAN_PATH" | jq -r 'select((.id // empty) != "") | "  \(.id),\(.a // ""),\(.f // [] | join(";")),\(.done // ""),\(.spec // "")"' 2>/dev/null || true
        fi
      fi
      echo ""
      # For FE dev: include design tokens reference
      if [ "$DEPT" = "fe" ] && [ -f "$PHASE_DIR/design-tokens.jsonl" ]; then
        echo "design_tokens: @$PHASE_DIR/design-tokens.jsonl"
        echo ""
      fi
      # Conventions (compact)
      CONVENTIONS=$(get_conventions true)
      if [ -n "$CONVENTIONS" ]; then
        CONV_COUNT=$(echo "$CONVENTIONS" | wc -l | tr -d ' ')
        echo "conventions[${CONV_COUNT}]{category,rule}:"
        echo "$CONVENTIONS"
      fi
      # Department-specific conventions (generated or static fallback)
      DEPT_CONV=$(get_dept_conventions)
      if [ -n "$DEPT_CONV" ]; then
        echo ''
        echo 'dept_conventions:'
        echo "$DEPT_CONV" | sed 's/^/  /'
      fi
      echo ""
      # Skill bundling (from plan frontmatter)
      if [ -n "$PLAN_PATH" ] && [ -f "$PLAN_PATH" ]; then
        SKILLS=$(head -1 "$PLAN_PATH" | jq -r '.sk // [] | .[]' 2>/dev/null || true)
        if [ -n "$SKILLS" ]; then
          echo "skills:"
          while IFS= read -r skill; do
            SKILL_FILE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/${skill}/SKILL.md"
            if [ -f "$SKILL_FILE" ]; then
              echo "  ${skill}: @${SKILL_FILE}"
            fi
          done <<< "$SKILLS"
        fi
      fi
      REF_PKG=$(get_reference_package) && { echo ''; echo "reference_package: @${REF_PKG}"; }
      get_tool_restrictions
    } > "${PHASE_DIR}/.ctx-${ROLE}.toon"
    ;;

  qa)
    {
      emit_header
      echo ""
      # Rolling summaries for all plans (QA reviews phase-wide)
      get_all_plan_summaries
      echo "success_criteria: $PHASE_SUCCESS"
      echo ""
      # Test results as primary QA input
      _tr_rows=$(sql "SELECT plan, ps, fl, dept FROM test_results WHERE phase='$PHASE';" 2>/dev/null || true)
      if [ -n "$_tr_rows" ]; then
        echo "test_results:"
        echo "$_tr_rows" | while IFS=',' read -r _plan _ps _fl _dept; do
          echo "  $_plan: ps=$_ps fl=$_fl dept=$_dept"
        done
        echo ""
      fi
      # Plan header context (must-haves and objective)
      if [ -n "$PLAN_PATH" ] && [ -f "$PLAN_PATH" ]; then
        echo "plan_context:"
        if [ "$FILTER_AVAILABLE" = true ]; then
          bash "$FILTER_SCRIPT" --role "$BASE_ROLE" --artifact "$PLAN_PATH" --type plan 2>/dev/null | \
            jq -r '"  obj: \(.obj // "")"' 2>/dev/null || true
          bash "$FILTER_SCRIPT" --role "$BASE_ROLE" --artifact "$PLAN_PATH" --type plan 2>/dev/null | \
            jq -r '.mh.tr // [] | .[] | "  must_have: \(.)"' 2>/dev/null || true
        else
          # Fallback: extract mh,obj from header inline
          head -1 "$PLAN_PATH" | jq -r '"  obj: \(.obj // "")"' 2>/dev/null || true
          head -1 "$PLAN_PATH" | jq -r '.mh.tr // [] | .[] | "  must_have: \(.)"' 2>/dev/null || true
        fi
        echo ""
      fi
      get_requirements
      echo ""
      # For FE QA: include design compliance context
      if [ "$DEPT" = "fe" ]; then
        if [ -f "$PHASE_DIR/component-specs.jsonl" ]; then
          echo "component_specs: @$PHASE_DIR/component-specs.jsonl"
        fi
        echo ""
      fi
      # Conventions to check
      CONVENTIONS=$(get_conventions)
      if [ -n "$CONVENTIONS" ]; then
        CONV_COUNT=$(echo "$CONVENTIONS" | wc -l | tr -d ' ')
        echo "conventions[${CONV_COUNT}]{category,rule}:"
        echo "$CONVENTIONS"
      fi
      # Escalation summary (open/resolved counts)
      _esc_open=$(sql "SELECT COUNT(*) FROM escalation WHERE phase='$PHASE' AND st='open';" 2>/dev/null || echo 0)
      _esc_resolved=$(sql "SELECT COUNT(*) FROM escalation WHERE phase='$PHASE' AND st='resolved';" 2>/dev/null || echo 0)
      if [ "$(( _esc_open + _esc_resolved ))" -gt 0 ] 2>/dev/null; then
        echo ""
        echo "escalations: open=$_esc_open resolved=$_esc_resolved"
      fi
      REF_PKG=$(get_reference_package) && { echo ''; echo "reference_package: @${REF_PKG}"; }
      get_tool_restrictions
    } > "${PHASE_DIR}/.ctx-${ROLE}.toon"
    ;;

  qa-code)
    {
      emit_header
      echo ""
      # Rolling summaries for all plans (QA-code reviews phase-wide)
      get_all_plan_summaries
      # Files modified (from DB summaries)
      echo "files_to_check:"
      sql "SELECT s.fm FROM summaries s JOIN plans p ON s.plan_id = p.rowid WHERE p.phase='$PHASE' AND s.fm IS NOT NULL AND s.fm != '' AND s.fm != 'null';" 2>/dev/null | while IFS= read -r _fm_json; do
        echo "$_fm_json" | jq -r '.[]' 2>/dev/null | while IFS= read -r f; do
          echo "  $f"
        done
      done || true
      echo ""
      # Conventions for pattern checking
      CONVENTIONS=$(get_conventions)
      if [ -n "$CONVENTIONS" ]; then
        CONV_COUNT=$(echo "$CONVENTIONS" | wc -l | tr -d ' ')
        echo "conventions[${CONV_COUNT}]{category,rule}:"
        echo "$CONVENTIONS"
      fi
      # Department-specific conventions (generated or static fallback)
      DEPT_CONV=$(get_dept_conventions)
      if [ -n "$DEPT_CONV" ]; then
        echo ''
        echo 'dept_conventions:'
        echo "$DEPT_CONV" | sed 's/^/  /'
      fi
      get_research
      REF_PKG=$(get_reference_package) && { echo ''; echo "reference_package: @${REF_PKG}"; }
      get_tool_restrictions
    } > "${PHASE_DIR}/.ctx-${ROLE}.toon"
    ;;

  tester)
    {
      emit_header
      echo ""
      # Enriched plan tasks with test specs (the Tester's primary input)
      if [ -n "$PLAN_PATH" ] && [ -f "$PLAN_PATH" ]; then
        TASK_COUNT=$(tail -n +2 "$PLAN_PATH" | wc -l | tr -d ' ')
        echo "tasks[${TASK_COUNT}]{id,action,files,done,spec,test_spec}:"
        if [ "$FILTER_AVAILABLE" = true ]; then
          bash "$FILTER_SCRIPT" --role "$BASE_ROLE" --artifact "$PLAN_PATH" --type plan 2>/dev/null | \
            jq -r 'select((.id // empty) != "") | "  \(.id),\(.a // ""),\(.f // [] | join(";")),\(.done // ""),\(.spec // ""),\(.ts // "")"' 2>/dev/null || true
        else
          tail -n +2 "$PLAN_PATH" | jq -r 'select((.id // empty) != "") | "  \(.id),\(.a // ""),\(.f // [] | join(";")),\(.done // ""),\(.spec // ""),\(.ts // "")"' 2>/dev/null || true
        fi
      fi
      echo ""
      # Codebase patterns for test conventions
      if [ -f "$PLANNING_DIR/codebase/PATTERNS.md" ]; then
        echo "patterns: @$PLANNING_DIR/codebase/PATTERNS.md"
      fi
      echo ""
      # Conventions for test structure
      CONVENTIONS=$(get_conventions)
      if [ -n "$CONVENTIONS" ]; then
        CONV_COUNT=$(echo "$CONVENTIONS" | wc -l | tr -d ' ')
        echo "conventions[${CONV_COUNT}]{category,rule}:"
        echo "$CONVENTIONS"
      fi
      # Department-specific conventions (generated or static fallback)
      DEPT_CONV=$(get_dept_conventions)
      if [ -n "$DEPT_CONV" ]; then
        echo ''
        echo 'dept_conventions:'
        echo "$DEPT_CONV" | sed 's/^/  /'
      fi
      REF_PKG=$(get_reference_package) && { echo ''; echo "reference_package: @${REF_PKG}"; }
      get_tool_restrictions
    } > "${PHASE_DIR}/.ctx-${ROLE}.toon"
    ;;

  owner)
    {
      emit_header
      echo ""
      get_requirements
      echo "success_criteria: $PHASE_SUCCESS"
      echo ""
      # Department results if available
      echo "departments:"
      for dept_result in "$PHASE_DIR"/*department-result*.jsonl; do
        if [ -f "$dept_result" ]; then
          jq -r '"  \(.dept // ""): \(.r // "")"' "$dept_result" 2>/dev/null || true
        fi
      done
      # Cross-department overview
      if [ -f "$PHASE_DIR/design-handoff.jsonl" ]; then
        echo "design_handoff: @$PHASE_DIR/design-handoff.jsonl"
      fi
      if [ -f "$PHASE_DIR/api-contracts.jsonl" ]; then
        echo "api_contracts: @$PHASE_DIR/api-contracts.jsonl"
      fi
      REF_PKG=$(get_reference_package) && { echo ''; echo "reference_package: @${REF_PKG}"; }
      get_tool_restrictions
    } > "${PHASE_DIR}/.ctx-${ROLE}.toon"
    ;;

  integration-gate)
    {
      emit_header
      echo ""
      echo "success_criteria: $PHASE_SUCCESS"
      echo ""
      # Department completion status
      echo "department_results:"
      for dept_status in "$PHASE_DIR"/.dept-status-*.json; do
        if [ -f "$dept_status" ]; then
          DEPT_NAME=$(basename "$dept_status" | sed 's/.dept-status-//;s/.json//')
          DEPT_ST=$(jq -r '.status // "unknown"' "$dept_status" 2>/dev/null || echo "unknown")
          echo "  $DEPT_NAME: $DEPT_ST"
        fi
      done
      echo ""
      # Test results per department
      _tr_rows=$(sql "SELECT plan, dept, tc, ps, fl FROM test_results WHERE phase='$PHASE';" 2>/dev/null || true)
      if [ -n "$_tr_rows" ]; then
        echo "test_results:"
        echo "$_tr_rows" | while IFS=',' read -r _plan _dept _tc _ps _fl; do
          echo "  $_plan: dept=$_dept phase=$PHASE tc=$_tc ps=$_ps fl=$_fl"
        done
        echo ""
      fi
      # API contracts (cross-dept, if exists)
      if [ -f "$PHASE_DIR/api-contracts.jsonl" ]; then
        echo "api_contracts:"
        jq -r '"  \(.endpoint // ""): status=\(.status // "")"' "$PHASE_DIR/api-contracts.jsonl" 2>/dev/null || true
        echo ""
      fi
      # Design handoff (cross-dept, if exists)
      if [ -f "$PHASE_DIR/design-handoff.jsonl" ]; then
        echo "design_handoff:"
        jq -r '"  \(.component // ""): status=\(.status // "")"' "$PHASE_DIR/design-handoff.jsonl" 2>/dev/null || true
        echo ""
      fi
      # Summary fm/tst fields for implementation evidence
      echo "summaries:"
      sql "SELECT p.plan_num, s.status, s.test_status, s.fm FROM summaries s JOIN plans p ON s.plan_id = p.rowid WHERE p.phase='$PHASE' ORDER BY p.plan_num;" 2>/dev/null | while IFS=',' read -r _pn _st _tst _fm; do
        echo "  $PHASE-$_pn: s=$_st tst=${_tst:-n/a} fm=$_fm"
      done || true
      echo ""
      # Handoff sentinels
      echo "handoff_sentinels:"
      for sentinel in "$PHASE_DIR"/.handoff-*-complete; do
        if [ -f "$sentinel" ]; then
          echo "  $(basename "$sentinel")"
        fi
      done
      REF_PKG=$(get_reference_package) && { echo ''; echo "reference_package: @${REF_PKG}"; }
      get_tool_restrictions
    } > "${PHASE_DIR}/.ctx-${ROLE}.toon"
    ;;

  security)
    {
      emit_header
      echo ""
      # Files modified (from summary.jsonl files or DB)
      echo "files_to_audit:"
      sql "SELECT s.fm FROM summaries s JOIN plans p ON s.plan_id = p.rowid WHERE p.phase='$PHASE' AND s.fm IS NOT NULL AND s.fm != '' AND s.fm != 'null';" 2>/dev/null | while IFS= read -r _fm_json; do
        echo "$_fm_json" | jq -r '.[]' 2>/dev/null | while IFS= read -r f; do
          echo "  $f"
        done
      done || true
      echo ""
      # Dependency manifests
      echo "dependency_files:"
      for manifest in package.json requirements.txt go.mod Cargo.toml pyproject.toml; do
        if [ -f "$manifest" ]; then
          echo "  $manifest"
        fi
      done
      REF_PKG=$(get_reference_package) && { echo ''; echo "reference_package: @${REF_PKG}"; }
      get_tool_restrictions
    } > "${PHASE_DIR}/.ctx-${ROLE}.toon"
    ;;

  debugger)
    {
      emit_header
      get_research
      echo ""
      # Recent changes for context
      echo "recent_commits:"
      git log --oneline -10 2>/dev/null | while IFS= read -r line; do
        echo "  $line"
      done || true
      echo ""
      # Gaps if any exist
      _gap_rows=$(sql "SELECT sev, \"desc\" FROM gaps WHERE phase='$PHASE' AND \"desc\" != '';" 2>/dev/null || true)
      if [ -n "$_gap_rows" ]; then
        echo "known_gaps:"
        echo "$_gap_rows" | while IFS=',' read -r _sev _desc; do
          echo "  $_sev: $_desc"
        done
      fi
      REF_PKG=$(get_reference_package) && { echo ''; echo "reference_package: @${REF_PKG}"; }
      get_tool_restrictions
    } > "${PHASE_DIR}/.ctx-${ROLE}.toon"
    ;;

  critic)
    {
      emit_header
      echo ""
      get_requirements
      get_research
      echo ""
      # Include codebase mapping summaries if available
      if [ "$HAS_CODEBASE" = true ]; then
        echo "codebase:"
        for base in INDEX ARCHITECTURE PATTERNS CONCERNS; do
          if [ -f "$PLANNING_DIR/codebase/${base}.md" ]; then
            echo "  @$PLANNING_DIR/codebase/${base}.md"
          fi
        done
      fi
      echo ""
      # Project context for gap analysis
      if [ -f "$PLANNING_DIR/PROJECT.md" ]; then
        echo "project: @$PLANNING_DIR/PROJECT.md"
      fi
      echo ""
      echo "success_criteria: $PHASE_SUCCESS"
      REF_PKG=$(get_reference_package) && { echo ''; echo "reference_package: @${REF_PKG}"; }
      get_tool_restrictions
    } > "${PHASE_DIR}/.ctx-${ROLE}.toon"
    ;;

  scout)
    {
      emit_header
      echo ""
      get_requirements
      echo ""
      _crit_rows=$(sql "SELECT id, q FROM critique WHERE phase='$PHASE' AND (sev='critical' OR sev='major') AND q != '';" 2>/dev/null || true)
      if [ -n "$_crit_rows" ]; then
        echo "research_directives:"
        echo "$_crit_rows" | while IFS=',' read -r _id _q; do
          echo "  $_id: $_q"
        done
      fi
      echo ""
      if [ "$HAS_CODEBASE" = true ]; then
        echo "codebase:"
        for base in INDEX ARCHITECTURE PATTERNS; do
          if [ -f "$PLANNING_DIR/codebase/${base}.md" ]; then
            echo "  @$PLANNING_DIR/codebase/${base}.md"
          fi
        done
      fi
      # On-demand research request context (ra = requesting agent)
      if [ -f "$PHASE_DIR/research.jsonl" ]; then
        RA_CONTEXT=$(jq -r 'select(.ra != null and .ra != "") | "  \(.ra): \(.q // "")"' "$PHASE_DIR/research.jsonl" 2>/dev/null || true)
        if [ -n "$RA_CONTEXT" ]; then
          echo ""
          echo "requesting_agents:"
          echo "$RA_CONTEXT"
        fi
      fi
      REF_PKG=$(get_reference_package) && { echo ''; echo "reference_package: @${REF_PKG}"; }
      get_tool_restrictions
    } > "${PHASE_DIR}/.ctx-${ROLE}.toon"
    ;;

  documenter)
    {
      emit_header
      echo ""
      # Files documented (from summary.jsonl fm field)
      echo "files_to_document:"
      for summary in "$PHASE_DIR"/*.summary.jsonl; do
        if [ -f "$summary" ]; then
          # Use inline jq directly (filter-agent-context.sh may not know documenter yet)
          jq -r '.fm // [] | .[]' "$summary" 2>/dev/null | while IFS= read -r f; do
            echo "  $f"
          done
        fi
      done
      echo ""
      # Code review highlights
      if [ -f "$PHASE_DIR/code-review.jsonl" ]; then
        echo "code_review_highlights:"
        jq -r 'select((.sev // "") == "critical" or (.sev // "") == "major") | "  \(.file // ""): \(.issue // "")"' "$PHASE_DIR/code-review.jsonl" 2>/dev/null || true
        echo ""
      fi
      # Conventions for documentation standards
      CONVENTIONS=$(get_conventions)
      if [ -n "$CONVENTIONS" ]; then
        CONV_COUNT=$(echo "$CONVENTIONS" | wc -l | tr -d ' ')
        echo "conventions[${CONV_COUNT}]{category,rule}:"
        echo "$CONVENTIONS"
      fi
      # Department-specific conventions
      DEPT_CONV=$(get_dept_conventions)
      if [ -n "$DEPT_CONV" ]; then
        echo ''
        echo 'dept_conventions:'
        echo "$DEPT_CONV" | sed 's/^/  /'
      fi
      REF_PKG=$(get_reference_package) && { echo ''; echo "reference_package: @${REF_PKG}"; }
      get_tool_restrictions
    } > "${PHASE_DIR}/.ctx-${ROLE}.toon"
    ;;

  analyze)
    {
      emit_header
      echo ""
      # Codebase mapping for complexity classification
      if [ "$HAS_CODEBASE" = true ]; then
        echo "codebase:"
        for base in ARCHITECTURE INDEX; do
          if [ -f "$PLANNING_DIR/codebase/${base}.md" ]; then
            echo "  @$PLANNING_DIR/codebase/${base}.md"
          fi
        done
      fi
      REF_PKG=$(get_reference_package) && { echo ''; echo "reference_package: @${REF_PKG}"; }
      get_tool_restrictions
    } > "${PHASE_DIR}/.ctx-${ROLE}.toon"
    ;;

  po)
    {
      emit_header
      echo ""
      get_requirements
      echo ""
      # REQUIREMENTS.md for vision alignment
      if [ -f "$PLANNING_DIR/REQUIREMENTS.md" ]; then
        echo "requirements_doc: @$PLANNING_DIR/REQUIREMENTS.md"
      fi
      # ROADMAP.md for phase context
      if [ -f "$ROADMAP" ]; then
        echo "roadmap: @$ROADMAP"
      fi
      echo ""
      # Prior phase summaries for scope context
      echo "prior_summaries:"
      for summary in "$PHASE_DIR"/*.summary.jsonl; do
        if [ -f "$summary" ]; then
          jq -r '"  \(.p // "")-\(.n // ""): s=\(.s // "")"' "$summary" 2>/dev/null || true
        fi
      done
      echo ""
      # Codebase mapping for completeness checks
      if [ "$HAS_CODEBASE" = true ]; then
        echo "codebase:"
        for base in ARCHITECTURE INDEX; do
          if [ -f "$PLANNING_DIR/codebase/${base}.md" ]; then
            echo "  @$PLANNING_DIR/codebase/${base}.md"
          fi
        done
      fi
      echo ""
      echo "success_criteria: $PHASE_SUCCESS"
      REF_PKG=$(get_reference_package) && { echo ''; echo "reference_package: @${REF_PKG}"; }
      get_tool_restrictions
    } > "${PHASE_DIR}/.ctx-${ROLE}.toon"
    ;;

  questionary)
    {
      emit_header
      echo ""
      get_requirements
      echo ""
      # REQUIREMENTS.md for scope cross-reference
      if [ -f "$PLANNING_DIR/REQUIREMENTS.md" ]; then
        echo "requirements_doc: @$PLANNING_DIR/REQUIREMENTS.md"
      fi
      # Research findings for domain context
      get_research
      echo ""
      # Codebase mapping for implied requirements detection
      if [ "$HAS_CODEBASE" = true ]; then
        echo "codebase:"
        for base in ARCHITECTURE INDEX PATTERNS; do
          if [ -f "$PLANNING_DIR/codebase/${base}.md" ]; then
            echo "  @$PLANNING_DIR/codebase/${base}.md"
          fi
        done
      fi
      REF_PKG=$(get_reference_package) && { echo ''; echo "reference_package: @${REF_PKG}"; }
      get_tool_restrictions
    } > "${PHASE_DIR}/.ctx-${ROLE}.toon"
    ;;

  roadmap)
    {
      emit_header
      echo ""
      get_requirements
      echo ""
      # ROADMAP.md for existing roadmap state
      if [ -f "$ROADMAP" ]; then
        echo "roadmap: @$ROADMAP"
      fi
      # REQUIREMENTS.md for full requirement details
      if [ -f "$PLANNING_DIR/REQUIREMENTS.md" ]; then
        echo "requirements_doc: @$PLANNING_DIR/REQUIREMENTS.md"
      fi
      echo ""
      # Codebase deps for dependency analysis
      if [ "$HAS_CODEBASE" = true ]; then
        echo "codebase:"
        for base in ARCHITECTURE INDEX PATTERNS CONCERNS; do
          if [ -f "$PLANNING_DIR/codebase/${base}.md" ]; then
            echo "  @$PLANNING_DIR/codebase/${base}.md"
          fi
        done
      fi
      echo ""
      echo "success_criteria: $PHASE_SUCCESS"
      REF_PKG=$(get_reference_package) && { echo ''; echo "reference_package: @${REF_PKG}"; }
      get_tool_restrictions
    } > "${PHASE_DIR}/.ctx-${ROLE}.toon"
    ;;

  *)
    echo "Unknown role: $ROLE (base: $BASE_ROLE). Valid base roles: architect, lead, senior, dev, qa, qa-code, security, debugger, critic, tester, owner, scout, documenter, integration-gate, analyze, po, questionary, roadmap" >&2
    exit 1
    ;;
esac

# --- Enforce token budget ---
OUTPUT_FILE="${PHASE_DIR}/.ctx-${ROLE}.toon"
if [ -f "$OUTPUT_FILE" ]; then
  enforce_budget "$OUTPUT_FILE" "$BUDGET"
fi

# --- Trim-to-budget (targeted section removal when --measure active) ---
TRIMMED=false
if [ "$MEASURE" = true ] && [ -f "$OUTPUT_FILE" ]; then
  BUDGET_CHARS=$(( BUDGET * 4 ))
  CURRENT_CHARS=$(wc -c < "$OUTPUT_FILE" | tr -d ' ')

  if [ "$CURRENT_CHARS" -gt "$BUDGET_CHARS" ]; then
    # Pass 1: Remove optional sections (prior_plans, dept_conventions, suggestions)
    local_tmp="${OUTPUT_FILE}.trim1.$$"
    awk '
      /^prior_plans:/     { skip=1; next }
      /^dept_conventions:/ { skip=1; next }
      /^suggestions:/     { skip=1; next }
      /^[a-z_]+:/         { skip=0 }
      !skip { print }
    ' "$OUTPUT_FILE" > "$local_tmp" 2>/dev/null && mv "$local_tmp" "$OUTPUT_FILE" || rm -f "$local_tmp"
    CURRENT_CHARS=$(wc -c < "$OUTPUT_FILE" | tr -d ' ')
    TRIMMED=true
  fi

  if [ "$CURRENT_CHARS" -gt "$BUDGET_CHARS" ]; then
    # Pass 2: Truncate artifact JSONL references to last 5 lines per section
    local_tmp="${OUTPUT_FILE}.trim2.$$"
    awk -v max=5 '
      /^  / && in_section { buf[++count] = $0; next }
      /^[a-z_]+.*:/ {
        if (in_section && count > 0) {
          start = (count > max) ? count - max + 1 : 1
          for (i = start; i <= count; i++) print buf[i]
        }
        in_section = 1; count = 0; delete buf
        print; next
      }
      {
        if (in_section && count > 0) {
          start = (count > max) ? count - max + 1 : 1
          for (i = start; i <= count; i++) print buf[i]
        }
        in_section = 0; count = 0; delete buf
        print
      }
      END {
        if (in_section && count > 0) {
          start = (count > max) ? count - max + 1 : 1
          for (i = start; i <= count; i++) print buf[i]
        }
      }
    ' "$OUTPUT_FILE" > "$local_tmp" 2>/dev/null && mv "$local_tmp" "$OUTPUT_FILE" || rm -f "$local_tmp"
    CURRENT_CHARS=$(wc -c < "$OUTPUT_FILE" | tr -d ' ')
    TRIMMED=true
  fi

  if [ "$CURRENT_CHARS" -gt "$BUDGET_CHARS" ]; then
    # Pass 3: Remove codebase references
    local_tmp="${OUTPUT_FILE}.trim3.$$"
    awk '
      /^codebase:/        { skip=1; next }
      /^[a-z_]+:/         { skip=0 }
      !skip { print }
    ' "$OUTPUT_FILE" > "$local_tmp" 2>/dev/null && mv "$local_tmp" "$OUTPUT_FILE" || rm -f "$local_tmp"
    TRIMMED=true
  fi
fi

# --- Token reduction measurement (D9: char/4 approximation) ---
if [ "$MEASURE" = true ] && [ -f "$OUTPUT_FILE" ]; then
  FILTERED_CHARS=$(wc -c < "$OUTPUT_FILE" | tr -d ' ')
  FILTERED_TOKENS=$(( FILTERED_CHARS / 4 ))

  # Approximate unfiltered size from raw artifact file sizes (plan + summaries)
  UNFILTERED_CHARS=0
  if [ -n "$PLAN_PATH" ] && [ -f "$PLAN_PATH" ]; then
    PLAN_CHARS=$(wc -c < "$PLAN_PATH" | tr -d ' ')
    UNFILTERED_CHARS=$(( UNFILTERED_CHARS + PLAN_CHARS ))
  fi
  for summary in "$PHASE_DIR"/*.summary.jsonl; do
    if [ -f "$summary" ]; then
      SUMMARY_CHARS=$(wc -c < "$summary" | tr -d ' ')
      UNFILTERED_CHARS=$(( UNFILTERED_CHARS + SUMMARY_CHARS ))
    fi
  done
  # If no artifact data, use filtered as unfiltered (no reduction)
  if [ "$UNFILTERED_CHARS" -eq 0 ]; then
    UNFILTERED_CHARS="$FILTERED_CHARS"
  fi
  UNFILTERED_TOKENS=$(( UNFILTERED_CHARS / 4 ))

  if [ "$UNFILTERED_TOKENS" -gt 0 ]; then
    REDUCTION_PCT=$(( (UNFILTERED_TOKENS - FILTERED_TOKENS) * 100 / UNFILTERED_TOKENS ))
  else
    REDUCTION_PCT=0
  fi

  # Output measurement JSON to stderr (stdout has the file path)
  echo "{\"role\":\"$ROLE\",\"budget\":$BUDGET,\"filtered_tokens\":$FILTERED_TOKENS,\"unfiltered_tokens\":$UNFILTERED_TOKENS,\"reduction_pct\":$REDUCTION_PCT,\"trimmed\":$TRIMMED,\"note\":\"char/4 approx\"}" >&2
fi

echo "$OUTPUT_FILE"
