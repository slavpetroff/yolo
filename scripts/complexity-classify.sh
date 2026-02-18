#!/usr/bin/env bash
set -euo pipefail

# complexity-classify.sh — Classify task complexity and suggest routing path
#
# Analyzes user intent, phase state, and config to determine if a task
# should route through trivial, medium, or high (full ceremony) path.
#
# Usage: complexity-classify.sh --intent "text" [--phase-state "k=v ..."] [--config path] [--codebase-map true|false]
# Output: JSON to stdout with complexity, departments, intent, confidence, reasoning, suggested_path
# Exit codes: 0 = classified, 1 = usage/runtime error

# --- jq dependency check ---
if ! command -v jq &>/dev/null; then
  echo '{"error":"jq is required but not installed"}' >&2
  exit 1
fi

# --- Arg parsing ---
INTENT=""
PHASE_STATE=""
CONFIG_PATH=""
CODEBASE_MAP="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --intent)
      INTENT="$2"
      shift 2
      ;;
    --phase-state)
      PHASE_STATE="$2"
      shift 2
      ;;
    --config)
      CONFIG_PATH="$2"
      shift 2
      ;;
    --codebase-map)
      CODEBASE_MAP="$2"
      shift 2
      ;;
    *)
      echo "Usage: complexity-classify.sh --intent \"text\" [--phase-state \"k=v ...\"] [--config path] [--codebase-map true|false]" >&2
      exit 1
      ;;
  esac
done

if [ -z "$INTENT" ]; then
  echo "Error: --intent is required" >&2
  exit 1
fi

# --- Normalize intent for matching ---
INTENT_LOWER=$(echo "$INTENT" | tr '[:upper:]' '[:lower:]')

# --- Department detection from config ---
ACTIVE_DEPTS="[]"
DEPT_COUNT=0

if [ -n "$CONFIG_PATH" ] && [ -f "$CONFIG_PATH" ]; then
  ACTIVE_DEPTS=$(jq -c '[.departments // {} | to_entries[] | select(.value == true) | .key]' "$CONFIG_PATH" 2>/dev/null || echo '[]')
  DEPT_COUNT=$(echo "$ACTIVE_DEPTS" | jq 'length')
fi

# --- Trivial keywords ---
# Single-file fix, typo, config change, rename, doc-only, no cross-file impact
TRIVIAL_KEYWORDS="typo|rename|config|doc|comment|version bump|small fix|quick fix|update version|fix typo|fix comment|fix doc|update doc|bump version|change name|update name|fix name|whitespace|formatting|lint fix|spelling|wording"

# --- Medium keywords ---
# Multi-file but bounded, single-department, clear implementation
MEDIUM_KEYWORDS="add feature|implement|refactor|update|extend|add support|create script|add script|new script|add command|modify|enhance|improve|add test|write test|add validation|add check|add hook|integrate|wire up|connect"

# --- High keywords ---
# Cross-department, architecture, new subsystem, significant scope
HIGH_KEYWORDS="new subsystem|new system|architecture|redesign|cross-department|multi-department|rewrite|overhaul|migrate|major refactor|breaking change|new department|new module|rebuild|rearchitect|cross-team|infrastructure"

# --- Classification logic ---
COMPLEXITY=""
CONFIDENCE=0
REASONING=""

# Check high first (most specific/impactful)
if echo "$INTENT_LOWER" | grep -qEi "$HIGH_KEYWORDS"; then
  COMPLEXITY="high"
  CONFIDENCE=0.9
  REASONING="Intent matches high-complexity keywords (architecture/cross-department/subsystem scope)"
elif [ "$DEPT_COUNT" -gt 1 ]; then
  # Multi-department active = likely high complexity
  COMPLEXITY="high"
  CONFIDENCE=0.85
  REASONING="Multiple departments active ($DEPT_COUNT), suggesting cross-department scope"
elif echo "$INTENT_LOWER" | grep -qEi "$TRIVIAL_KEYWORDS"; then
  COMPLEXITY="trivial"
  CONFIDENCE=0.9
  REASONING="Intent matches trivial keywords (single-file fix, doc change, config update)"
elif echo "$INTENT_LOWER" | grep -qEi "$MEDIUM_KEYWORDS"; then
  COMPLEXITY="medium"
  CONFIDENCE=0.85
  REASONING="Intent matches medium-complexity keywords (bounded feature, single-department)"
else
  # Ambiguous — default to medium with lower confidence
  COMPLEXITY="medium"
  CONFIDENCE=0.6
  REASONING="No strong keyword match; defaulting to medium complexity (ambiguous intent)"
fi

# --- Refine with phase state ---
if [ -n "$PHASE_STATE" ]; then
  # Check for brownfield indicator
  if echo "$PHASE_STATE" | grep -q "brownfield=true"; then
    if [ "$COMPLEXITY" = "trivial" ]; then
      # Brownfield trivial stays trivial but note codebase exists
      REASONING="$REASONING; brownfield project (existing codebase)"
    fi
  fi

  # Check for codebase map availability
  if echo "$PHASE_STATE" | grep -q "has_codebase_map=true" || [ "$CODEBASE_MAP" = "true" ]; then
    # Better confidence with codebase context
    if [ "$CONFIDENCE" != "0.9" ]; then
      CONFIDENCE=$(echo "$CONFIDENCE + 0.05" | bc 2>/dev/null || echo "$CONFIDENCE")
    fi
  fi
fi

# --- Intent detection (simplified from go.md Path 2 logic) ---
DETECTED_INTENT="implement"

if echo "$INTENT_LOWER" | grep -qEi "fix|bug|broken|crash|error|fail"; then
  DETECTED_INTENT="fix"
elif echo "$INTENT_LOWER" | grep -qEi "research|investigate|explore|analyze|understand|look into"; then
  DETECTED_INTENT="research"
elif echo "$INTENT_LOWER" | grep -qEi "test|spec|verify|validate|check"; then
  DETECTED_INTENT="test"
elif echo "$INTENT_LOWER" | grep -qEi "refactor|clean|reorganize|restructure"; then
  DETECTED_INTENT="refactor"
elif echo "$INTENT_LOWER" | grep -qEi "doc|document|readme|comment|explain"; then
  DETECTED_INTENT="document"
elif echo "$INTENT_LOWER" | grep -qEi "add|create|implement|build|new|extend|enhance"; then
  DETECTED_INTENT="implement"
fi

# --- Suggested path ---
SUGGESTED_PATH="$COMPLEXITY"

# --- Output JSON ---
jq -n \
  --arg complexity "$COMPLEXITY" \
  --argjson departments "$ACTIVE_DEPTS" \
  --arg intent "$DETECTED_INTENT" \
  --argjson confidence "$CONFIDENCE" \
  --arg reasoning "$REASONING" \
  --arg suggested_path "$SUGGESTED_PATH" \
  '{
    complexity: $complexity,
    departments: $departments,
    intent: $intent,
    confidence: $confidence,
    reasoning: $reasoning,
    suggested_path: $suggested_path
  }'
