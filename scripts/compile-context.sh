#!/usr/bin/env bash
set -euo pipefail

# compile-context.sh <phase-number> <role> [phases-dir] [plan-path]
# Produces .ctx-{role}.toon in the phase directory with role-specific context.
# Roles: architect, lead, senior, dev, qa, qa-code, security, debugger, critic, tester, owner
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
PLANNING_DIR=".yolo-planning"
PLAN_PATH="${4:-}"

# --- Extract department and base role from role name ---
# fe-dev → DEPT=fe, BASE_ROLE=dev; ux-architect → DEPT=ux, BASE_ROLE=architect
# architect → DEPT=backend, BASE_ROLE=architect; owner → DEPT=shared, BASE_ROLE=owner
case "$ROLE" in
  fe-*) DEPT="fe"; BASE_ROLE="${ROLE#fe-}" ;;
  ux-*) DEPT="ux"; BASE_ROLE="${ROLE#ux-}" ;;
  owner) DEPT="shared"; BASE_ROLE="owner" ;;
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

# --- Extract phase metadata from ROADMAP.md ---
ROADMAP="$PLANNING_DIR/ROADMAP.md"

PHASE_GOAL="Not available"
PHASE_REQS="Not available"
PHASE_SUCCESS="Not available"

# OPTIMIZATION 2: Single awk for ROADMAP extraction (replaces 1 sed + 3 grep + 3 sed = 7 subprocesses)
if [ -f "$ROADMAP" ]; then
  IFS=$'\t' read -r PHASE_GOAL PHASE_REQS PHASE_SUCCESS <<< "$(awk -v pn="$PHASE_NUM" '
    BEGIN { g="Not available"; r="Not available"; s="Not available" }
    /^## Phase / {
      if (found) exit
      if ($0 ~ "^## Phase " pn ":") found=1
      next
    }
    found && /^\*\*Goal:\*\*/ { gsub(/\*\*Goal:\*\* */, ""); g=$0 }
    found && /^\*\*Reqs:\*\*/ { gsub(/\*\*Reqs:\*\* */, ""); r=$0 }
    found && /^\*\*Success/ { gsub(/\*\*Success.*:\*\* */, ""); s=$0 }
    END { printf "%s\t%s\t%s", g, r, s }
  ' "$ROADMAP" 2>/dev/null)" || true
  : "${PHASE_GOAL:=Not available}"
  : "${PHASE_REQS:=Not available}"
  : "${PHASE_SUCCESS:=Not available}"
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
  local research_file="$PHASE_DIR/research.jsonl"
  if [ -f "$research_file" ]; then
    echo "research:"
    jq -r 'select((.q // .query // empty) != "" and (.finding // empty) != "") | "  - \(.q // .query): \(.finding)"' "$research_file" 2>/dev/null || true
  fi
}

# --- Helper: get decisions from decisions.jsonl ---
get_decisions() {
  local decisions_file="$PHASE_DIR/decisions.jsonl"
  if [ -f "$decisions_file" ]; then
    echo "decisions:"
    jq -r 'select((.dec // empty) != "") | "  \(.agent // ""): \(.dec) (\(.reason // ""))"' "$decisions_file" 2>/dev/null || true
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
# OPTIMIZATION 4: Batch requirements jq (single jq call instead of N*2 per-line calls)
get_requirements() {
  if [ -n "$REQ_PATTERN" ]; then
    if [ -f "$PLANNING_DIR/reqs.jsonl" ]; then
      echo "reqs:"
      grep -E "($REQ_PATTERN)" "$PLANNING_DIR/reqs.jsonl" 2>/dev/null | \
        jq -r 'select((.id // empty) != "") | "  \(.id),\(.t // .title // "")"' 2>/dev/null || true
    elif [ -f "$PLANNING_DIR/REQUIREMENTS.md" ]; then
      echo "reqs:"
      grep -E "($REQ_PATTERN)" "$PLANNING_DIR/REQUIREMENTS.md" 2>/dev/null | head -10 | while IFS= read -r line; do
        echo "  $line"
      done
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
DECISIONS_EXISTS=false; [ -f "$PHASE_DIR/decisions.jsonl" ] && DECISIONS_EXISTS=true
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
      echo "success_criteria: $PHASE_SUCCESS"
      REF_PKG=$(get_reference_package) && { echo ''; echo "reference_package: @${REF_PKG}"; }
      get_tool_restrictions
    } > "${PHASE_DIR}/.ctx-${ROLE}.toon"
    ;;

  senior)
    {
      emit_header
      echo ""
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
      echo "success_criteria: $PHASE_SUCCESS"
      echo ""
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
      REF_PKG=$(get_reference_package) && { echo ''; echo "reference_package: @${REF_PKG}"; }
      get_tool_restrictions
    } > "${PHASE_DIR}/.ctx-${ROLE}.toon"
    ;;

  qa-code)
    {
      emit_header
      echo ""
      # Files modified (from summary.jsonl files in phase dir)
      echo "files_to_check:"
      for summary in "$PHASE_DIR"/*.summary.jsonl; do
        if [ -f "$summary" ]; then
          if [ "$FILTER_AVAILABLE" = true ]; then
            bash "$FILTER_SCRIPT" --role "$BASE_ROLE" --artifact "$summary" --type summary 2>/dev/null | \
              jq -r '.fm // [] | .[]' 2>/dev/null | while IFS= read -r f; do
                echo "  $f"
              done
          else
            jq -r '.fm // [] | .[]' "$summary" 2>/dev/null | while IFS= read -r f; do
              echo "  $f"
            done
          fi
        fi
      done
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

  security)
    {
      emit_header
      echo ""
      # Files modified (from summary.jsonl files)
      echo "files_to_audit:"
      for summary in "$PHASE_DIR"/*.summary.jsonl; do
        if [ -f "$summary" ]; then
          if [ "$FILTER_AVAILABLE" = true ]; then
            bash "$FILTER_SCRIPT" --role "$BASE_ROLE" --artifact "$summary" --type summary 2>/dev/null | \
              jq -r '.fm // [] | .[]' 2>/dev/null | while IFS= read -r f; do
                echo "  $f"
              done
          else
            jq -r '.fm // [] | .[]' "$summary" 2>/dev/null | while IFS= read -r f; do
              echo "  $f"
            done
          fi
        fi
      done
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
      done
      echo ""
      # Gaps if any exist
      if [ -f "$PHASE_DIR/gaps.jsonl" ]; then
        echo "known_gaps:"
        jq -r 'select((.desc // empty) != "") | "  \(.sev // ""): \(.desc)"' "$PHASE_DIR/gaps.jsonl" 2>/dev/null || true
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
      if [ -f "$PHASE_DIR/critique.jsonl" ]; then
        echo "research_directives:"
        jq -r 'select(.sev == "critical" or .sev == "major") | "  \(.id // ""): \(.q // .desc // "")"' "$PHASE_DIR/critique.jsonl" 2>/dev/null || true
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

  *)
    echo "Unknown role: $ROLE (base: $BASE_ROLE). Valid base roles: architect, lead, senior, dev, qa, qa-code, security, debugger, critic, tester, owner, scout, documenter" >&2
    exit 1
    ;;
esac

# --- Enforce token budget ---
OUTPUT_FILE="${PHASE_DIR}/.ctx-${ROLE}.toon"
if [ -f "$OUTPUT_FILE" ]; then
  enforce_budget "$OUTPUT_FILE" "$BUDGET"
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
  echo "{\"role\":\"$ROLE\",\"filtered_chars\":$FILTERED_CHARS,\"unfiltered_chars\":$UNFILTERED_CHARS,\"reduction_pct\":$REDUCTION_PCT,\"note\":\"char/4 approx\"}" >&2
fi

echo "$OUTPUT_FILE"
