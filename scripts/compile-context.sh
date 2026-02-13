#!/usr/bin/env bash
set -euo pipefail

# compile-context.sh <phase-number> <role> [phases-dir] [plan-path]
# Produces .ctx-{role}.toon in the phase directory with role-specific context.
# Roles: architect, lead, senior, dev, qa, qa-code, security, debugger, critic, tester, owner
# Department roles: fe-architect, fe-lead, fe-senior, fe-dev, fe-tester, fe-qa, fe-qa-code
#                   ux-architect, ux-lead, ux-senior, ux-dev, ux-tester, ux-qa, ux-qa-code
# Exit 0 on success, exit 1 when phase directory not found.

if [ $# -lt 2 ]; then
  echo "Usage: compile-context.sh <phase-number> <role> [phases-dir] [plan-path]" >&2
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
PHASE_NUM=$(echo "$PHASE" | sed 's/^0*//')
if [ -z "$PHASE_NUM" ]; then PHASE_NUM="0"; fi

# --- Find phase directory ---
PHASE_DIR=$(find "$PHASES_DIR" -maxdepth 1 -type d -name "${PHASE}-*" 2>/dev/null | head -1)
if [ -z "$PHASE_DIR" ]; then
  echo "Phase ${PHASE} directory not found" >&2
  exit 1
fi

# --- Extract phase metadata from ROADMAP.md ---
ROADMAP="$PLANNING_DIR/ROADMAP.md"

PHASE_GOAL="Not available"
PHASE_REQS="Not available"
PHASE_SUCCESS="Not available"

if [ -f "$ROADMAP" ]; then
  PHASE_SECTION=$(sed -n "/^## Phase ${PHASE_NUM}:/,/^## Phase [0-9]/p" "$ROADMAP" 2>/dev/null | sed '$d') || true
  if [ -n "${PHASE_SECTION:-}" ]; then
    PHASE_GOAL=$(echo "$PHASE_SECTION" | grep '^\*\*Goal:\*\*' 2>/dev/null | sed 's/\*\*Goal:\*\* *//' ) || PHASE_GOAL="Not available"
    PHASE_REQS=$(echo "$PHASE_SECTION" | grep '^\*\*Reqs:\*\*' 2>/dev/null | sed 's/\*\*Reqs:\*\* *//' ) || PHASE_REQS="Not available"
    PHASE_SUCCESS=$(echo "$PHASE_SECTION" | grep '^\*\*Success' 2>/dev/null | sed 's/\*\*Success.*:\*\* *//' ) || PHASE_SUCCESS="Not available"
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
      jq -r '.conventions[] | "  \(.tag),\(.rule)"' "$PLANNING_DIR/conventions.json" 2>/dev/null || true
    else
      jq -r '.conventions[] | "  \(.tag),\(.rule)"' "$PLANNING_DIR/conventions.json" 2>/dev/null || true
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
    if [ -f "$PLANNING_DIR/reqs.jsonl" ]; then
      echo "reqs:"
      grep -E "($REQ_PATTERN)" "$PLANNING_DIR/reqs.jsonl" 2>/dev/null | while IFS= read -r line; do
        local id; id=$(echo "$line" | jq -r '.id // empty' 2>/dev/null) || true
        local title; title=$(echo "$line" | jq -r '.t // .title // empty' 2>/dev/null) || true
        if [ -n "$id" ]; then
          echo "  $id,$title"
        fi
      done
    elif [ -f "$PLANNING_DIR/REQUIREMENTS.md" ]; then
      echo "reqs:"
      grep -E "($REQ_PATTERN)" "$PLANNING_DIR/REQUIREMENTS.md" 2>/dev/null | head -10 | while IFS= read -r line; do
        echo "  $line"
      done
    fi
  fi
}

# --- Token budget per role (chars/4 ≈ tokens) ---
# Uses BASE_ROLE for department agents (fe-dev → dev budget, ux-architect → architect budget)
get_budget() {
  case "$1" in
    architect|fe-architect|ux-architect)  echo 5000 ;;
    lead|fe-lead|ux-lead)                 echo 3000 ;;
    senior|fe-senior|ux-senior)           echo 4000 ;;
    dev|fe-dev|ux-dev)                    echo 2000 ;;
    qa|fe-qa|ux-qa)                       echo 2000 ;;
    qa-code|fe-qa-code|ux-qa-code)        echo 3000 ;;
    security)                             echo 3000 ;;
    scout)                                echo 1000 ;;
    debugger)                             echo 3000 ;;
    critic)                               echo 4000 ;;
    tester|fe-tester|ux-tester)           echo 3000 ;;
    owner)                                echo 3000 ;;
    *)                                    echo 3000 ;;
  esac
}

estimate_tokens() {
  local file="$1"
  local chars
  chars=$(( $(wc -c < "$file") ))
  echo $(( chars / 4 ))
}

# Truncation step 1: conventions tag-only (drop rule text after comma)
truncate_conventions_tag_only() {
  local file="$1"
  local tmp="${file}.trunc.$$"
  sed 's/^\(  [a-z_-]*\),.*/\1/' "$file" > "$tmp" 2>/dev/null && mv "$tmp" "$file" || rm -f "$tmp"
}

# Truncation step 2: requirements ID-only (drop title after comma)
truncate_reqs_id_only() {
  local file="$1"
  local tmp="${file}.trunc.$$"
  # Lines under "reqs:" section: "  REQ-NN,title" → "  REQ-NN"
  sed '/^reqs:/,/^[^ ]/{s/^\(  REQ-[0-9]*\),.*/\1/;}' "$file" > "$tmp" 2>/dev/null && mv "$tmp" "$file" || rm -f "$tmp"
}

# Truncation step 3: drop prose content, keep section headings
truncate_headings_only() {
  local file="$1"
  local tmp="${file}.trunc.$$"
  # Keep lines that are section headers (no leading space) or metadata, drop indented content
  awk '/^[^ ]/ || /^$/ { print }' "$file" > "$tmp" 2>/dev/null && mv "$tmp" "$file" || rm -f "$tmp"
}

enforce_budget() {
  local file="$1"
  local budget="$2"
  local tokens

  tokens=$(estimate_tokens "$file")
  [ "$tokens" -le "$budget" ] && return 0

  # Step 1: conventions tag-only
  truncate_conventions_tag_only "$file"
  tokens=$(estimate_tokens "$file")
  [ "$tokens" -le "$budget" ] && return 0

  # Step 2: requirements ID-only
  truncate_reqs_id_only "$file"
  tokens=$(estimate_tokens "$file")
  [ "$tokens" -le "$budget" ] && return 0

  # Step 3: headings-only
  truncate_headings_only "$file"
}

BUDGET=$(get_budget "$ROLE")
ARCH_FILE=$(get_arch_file)

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
      echo ""
      get_research
      echo ""
      # Include codebase mapping summaries if available
      if [ -d "$PLANNING_DIR/codebase" ]; then
        echo "codebase:"
        for f in index.jsonl architecture.jsonl patterns.jsonl concerns.jsonl; do
          if [ -f "$PLANNING_DIR/codebase/$f" ]; then
            echo "  @$PLANNING_DIR/codebase/$f"
          fi
        done
      fi
      echo ""
      # For FE architect: include UX handoff if available
      if [ "$DEPT" = "fe" ] && [ -f "$PHASE_DIR/design-handoff.jsonl" ]; then
        echo "design_handoff: @$PHASE_DIR/design-handoff.jsonl"
      fi
      echo ""
      echo "success_criteria: $PHASE_SUCCESS"
    } > "${PHASE_DIR}/.ctx-${ROLE}.toon"
    ;;

  lead)
    {
      emit_header
      echo ""
      # Architecture summary if available (department-specific)
      if [ -f "$ARCH_FILE" ]; then
        echo "architecture:"
        head -5 "$ARCH_FILE" | sed 's/^/  /'
      fi
      echo ""
      get_requirements
      echo ""
      # Decisions from decisions.jsonl (preferred) or STATE.md (fallback)
      if [ -f "$PHASE_DIR/decisions.jsonl" ]; then
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
      fi
      echo ""
      echo "success_criteria: $PHASE_SUCCESS"
    } > "${PHASE_DIR}/.ctx-${ROLE}.toon"
    ;;

  senior)
    {
      emit_header
      echo ""
      # Full architecture context (department-specific)
      if [ -f "$ARCH_FILE" ]; then
        echo "architecture:"
        sed 's/^/  /' "$ARCH_FILE"
      fi
      echo ""
      get_requirements
      echo ""
      # Codebase patterns for spec enrichment
      if [ -f "$PLANNING_DIR/codebase/patterns.jsonl" ]; then
        echo "patterns: @$PLANNING_DIR/codebase/patterns.jsonl"
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
      fi
      echo ""
      # Conventions for code review
      CONVENTIONS=$(get_conventions)
      if [ -n "$CONVENTIONS" ]; then
        CONV_COUNT=$(echo "$CONVENTIONS" | wc -l | tr -d ' ')
        echo "conventions[${CONV_COUNT}]{tag,rule}:"
        echo "$CONVENTIONS"
      fi
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
        tail -n +2 "$PLAN_PATH" | jq -r 'select((.id // empty) != "") | "  \(.id),\(.a // ""),\(.f // [] | join(";")),\(.done // ""),\(.spec // "")"' 2>/dev/null || true
      fi
      echo ""
      # For FE dev: include design tokens reference
      if [ "$DEPT" = "fe" ] && [ -f "$PHASE_DIR/design-tokens.jsonl" ]; then
        echo "design_tokens: @$PHASE_DIR/design-tokens.jsonl"
      fi
      echo ""
      # Conventions (compact)
      CONVENTIONS=$(get_conventions true)
      if [ -n "$CONVENTIONS" ]; then
        CONV_COUNT=$(echo "$CONVENTIONS" | wc -l | tr -d ' ')
        echo "conventions[${CONV_COUNT}]{tag,rule}:"
        echo "$CONVENTIONS"
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
    } > "${PHASE_DIR}/.ctx-${ROLE}.toon"
    ;;

  qa)
    {
      emit_header
      echo ""
      echo "success_criteria: $PHASE_SUCCESS"
      echo ""
      get_requirements
      echo ""
      # For FE QA: include design compliance context
      if [ "$DEPT" = "fe" ]; then
        if [ -f "$PHASE_DIR/component-specs.jsonl" ]; then
          echo "component_specs: @$PHASE_DIR/component-specs.jsonl"
        fi
      fi
      echo ""
      # Conventions to check
      CONVENTIONS=$(get_conventions)
      if [ -n "$CONVENTIONS" ]; then
        CONV_COUNT=$(echo "$CONVENTIONS" | wc -l | tr -d ' ')
        echo "conventions[${CONV_COUNT}]{tag,rule}:"
        echo "$CONVENTIONS"
      fi
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
          jq -r '.fm // [] | .[]' "$summary" 2>/dev/null | while IFS= read -r f; do
            echo "  $f"
          done
        fi
      done
      echo ""
      # Conventions for pattern checking
      CONVENTIONS=$(get_conventions)
      if [ -n "$CONVENTIONS" ]; then
        CONV_COUNT=$(echo "$CONVENTIONS" | wc -l | tr -d ' ')
        echo "conventions[${CONV_COUNT}]{tag,rule}:"
        echo "$CONVENTIONS"
      fi
      echo ""
      get_research
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
        tail -n +2 "$PLAN_PATH" | jq -r 'select((.id // empty) != "") | "  \(.id),\(.a // ""),\(.f // [] | join(";")),\(.done // ""),\(.spec // ""),\(.ts // "")"' 2>/dev/null || true
      fi
      echo ""
      # Codebase patterns for test conventions
      if [ -f "$PLANNING_DIR/codebase/patterns.jsonl" ]; then
        echo "patterns: @$PLANNING_DIR/codebase/patterns.jsonl"
      fi
      echo ""
      # Conventions for test structure
      CONVENTIONS=$(get_conventions)
      if [ -n "$CONVENTIONS" ]; then
        CONV_COUNT=$(echo "$CONVENTIONS" | wc -l | tr -d ' ')
        echo "conventions[${CONV_COUNT}]{tag,rule}:"
        echo "$CONVENTIONS"
      fi
    } > "${PHASE_DIR}/.ctx-${ROLE}.toon"
    ;;

  owner)
    {
      emit_header
      echo ""
      get_requirements
      echo ""
      echo "success_criteria: $PHASE_SUCCESS"
      echo ""
      # Department results if available
      echo "departments:"
      for dept_result in "$PHASE_DIR"/*department-result*.jsonl; do
        if [ -f "$dept_result" ]; then
          jq -r '"  \(.dept // ""): \(.r // "")"' "$dept_result" 2>/dev/null || true
        fi
      done
      echo ""
      # Cross-department overview
      if [ -f "$PHASE_DIR/design-handoff.jsonl" ]; then
        echo "design_handoff: @$PHASE_DIR/design-handoff.jsonl"
      fi
      if [ -f "$PHASE_DIR/api-contracts.jsonl" ]; then
        echo "api_contracts: @$PHASE_DIR/api-contracts.jsonl"
      fi
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
          jq -r '.fm // [] | .[]' "$summary" 2>/dev/null | while IFS= read -r f; do
            echo "  $f"
          done
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
    } > "${PHASE_DIR}/.ctx-${ROLE}.toon"
    ;;

  debugger)
    {
      emit_header
      echo ""
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
    } > "${PHASE_DIR}/.ctx-${ROLE}.toon"
    ;;

  critic)
    {
      emit_header
      echo ""
      get_requirements
      echo ""
      get_research
      echo ""
      # Include codebase mapping summaries if available
      if [ -d "$PLANNING_DIR/codebase" ]; then
        echo "codebase:"
        for f in index.jsonl architecture.jsonl patterns.jsonl concerns.jsonl; do
          if [ -f "$PLANNING_DIR/codebase/$f" ]; then
            echo "  @$PLANNING_DIR/codebase/$f"
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
    } > "${PHASE_DIR}/.ctx-${ROLE}.toon"
    ;;

  scout)
    {
      emit_header
      echo ""
      get_requirements
    } > "${PHASE_DIR}/.ctx-${ROLE}.toon"
    ;;

  *)
    echo "Unknown role: $ROLE (base: $BASE_ROLE). Valid base roles: architect, lead, senior, dev, qa, qa-code, security, debugger, critic, tester, owner, scout" >&2
    exit 1
    ;;
esac

# --- Enforce token budget ---
OUTPUT_FILE="${PHASE_DIR}/.ctx-${ROLE}.toon"
if [ -f "$OUTPUT_FILE" ]; then
  enforce_budget "$OUTPUT_FILE" "$BUDGET"
fi

echo "$OUTPUT_FILE"
