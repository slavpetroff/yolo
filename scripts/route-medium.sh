#!/usr/bin/env bash
set -euo pipefail

# route-medium.sh — Medium complexity routing path
#
# Implements the medium path: skip Critic and Scout (no R&D pipeline),
# skip Architect (use existing architecture.toon if present), route to
# Lead for abbreviated plan decomposition (max 3 tasks), then Senior ->
# Dev -> Senior code review -> automated QA gate. Skip security.
#
# Does NOT create plans — that is Lead's job.
#
# Usage: route-medium.sh --phase-dir <path> --intent "text" --config <path> --analysis-json <path>
# Output: JSON to stdout with path, steps_skipped, steps_included, estimated_steps
# Exit codes: 0 = success, 1 = usage/runtime error

# --- jq dependency check ---
if ! command -v jq &>/dev/null; then
  echo '{"error":"jq is required but not installed"}' >&2
  exit 1
fi

# --- Arg parsing ---
PHASE_DIR=""
INTENT=""
CONFIG_PATH=""
ANALYSIS_JSON=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase-dir)
      PHASE_DIR="$2"
      shift 2
      ;;
    --intent)
      INTENT="$2"
      shift 2
      ;;
    --config)
      CONFIG_PATH="$2"
      shift 2
      ;;
    --analysis-json)
      ANALYSIS_JSON="$2"
      shift 2
      ;;
    *)
      echo "Usage: route-medium.sh --phase-dir <path> --intent \"text\" --config <path> --analysis-json <path>" >&2
      exit 1
      ;;
  esac
done

if [ -z "$PHASE_DIR" ] || [ -z "$INTENT" ]; then
  echo "Error: --phase-dir and --intent are required" >&2
  exit 1
fi

# --- Determine skipped/included steps ---
# Always skip: critique, research, security
# Conditionally skip: architecture (if architecture.toon exists, use it; otherwise skip)
# Always skip: formal QA agents (use post-plan gate only)
# Include: planning (Lead), design_review (Senior), implementation (Dev),
#          code_review (Senior), signoff (Lead)

STEPS_SKIPPED='["critique","research","architecture","test_authoring","qa","security"]'
STEPS_INCLUDED='["planning","design_review","implementation","code_review","signoff"]'
ESTIMATED_STEPS=5

# Check if architecture.toon exists — if so, note it for Lead
HAS_ARCHITECTURE="false"
if [ -d "$PHASE_DIR" ] && [ -f "$PHASE_DIR/architecture.toon" ]; then
  HAS_ARCHITECTURE="true"
fi

# --- Output JSON ---
jq -n \
  --arg path "medium" \
  --argjson steps_skipped "$STEPS_SKIPPED" \
  --argjson steps_included "$STEPS_INCLUDED" \
  --argjson estimated_steps "$ESTIMATED_STEPS" \
  --argjson has_architecture "$HAS_ARCHITECTURE" \
  '{
    path: $path,
    steps_skipped: $steps_skipped,
    steps_included: $steps_included,
    estimated_steps: $estimated_steps,
    has_architecture: $has_architecture
  }'
