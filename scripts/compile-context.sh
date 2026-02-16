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
# OPTIMIZATION 3: Use arithmetic instead of sed for leading zero removal
PHASE_NUM=$(( 10#$PHASE ))

# --- Find phase directory ---
# OPTIMIZATION 1: Use ls glob instead of find for phase dir lookup
PHASE_DIR=$(command ls -d "$PHASES_DIR/${PHASE}-"*/ 2>/dev/null | head -1)
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
ARCH_FILE=$(get_arch_file)

# OPTIMIZATION 6: Cache file existence flags (avoid repeated stat syscalls)
ARCH_EXISTS=false; [ -f "$ARCH_FILE" ] && ARCH_EXISTS=true
DECISIONS_EXISTS=false; [ -f "$PHASE_DIR/decisions.jsonl" ] && DECISIONS_EXISTS=true
HAS_CODEBASE=false; [ -d "$PLANNING_DIR/codebase" ] && HAS_CODEBASE=true

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
        echo ""
      fi
      # Conventions (compact)
      CONVENTIONS=$(get_conventions true)
      if [ -n "$CONVENTIONS" ]; then
        CONV_COUNT=$(echo "$CONVENTIONS" | wc -l | tr -d ' ')
        echo "conventions[${CONV_COUNT}]{category,rule}:"
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
        echo ""
      fi
      # Conventions to check
      CONVENTIONS=$(get_conventions)
      if [ -n "$CONVENTIONS" ]; then
        CONV_COUNT=$(echo "$CONVENTIONS" | wc -l | tr -d ' ')
        echo "conventions[${CONV_COUNT}]{category,rule}:"
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
        echo "conventions[${CONV_COUNT}]{category,rule}:"
        echo "$CONVENTIONS"
      fi
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
