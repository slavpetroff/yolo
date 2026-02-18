#!/usr/bin/env bash
set -euo pipefail

# token-audit.sh — Audit token costs per complexity path
#
# Reads context-manifest.json budgets and route-{trivial,medium}.sh skip lists
# to calculate per-path token estimates and verify ratio thresholds.
#
# Usage: token-audit.sh [--phase <NN>] [--dry-run] [--output <file>]
# Output: JSON with trivial_tokens, medium_tokens, high_tokens, ratios, pass/fail
# Exit codes: 0 = all thresholds pass, 1 = threshold failure, 2 = usage/runtime error

# --- jq dependency check ---
if ! command -v jq &>/dev/null; then
  echo '{"error":"jq is required but not installed"}' >&2
  exit 2
fi

# --- Resolve plugin root ---
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
MANIFEST="$PLUGIN_ROOT/config/context-manifest.json"

# --- Arg parsing ---
PHASE=""
DRY_RUN="false"
OUTPUT_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase)
      PHASE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    --output)
      OUTPUT_FILE="$2"
      shift 2
      ;;
    --help|-h)
      echo "Usage: token-audit.sh [--phase <NN>] [--dry-run] [--output <file>]"
      echo "  --phase <NN>   Phase number (informational, included in output)"
      echo "  --dry-run      Print what would be computed without writing output file"
      echo "  --output <f>   Write JSON result to file instead of stdout"
      exit 0
      ;;
    *)
      echo "Error: unknown argument '$1'" >&2
      echo "Usage: token-audit.sh [--phase <NN>] [--dry-run] [--output <file>]" >&2
      exit 2
      ;;
  esac
done

# --- Validate manifest exists ---
if [ ! -f "$MANIFEST" ]; then
  echo "{\"error\":\"context-manifest.json not found at $MANIFEST\"}" >&2
  exit 2
fi

# --- Define which roles are active per path ---
# High path: all roles
# Trivial path skips: critic, scout, architect, lead, tester, qa, qa-code, security, documenter, po, questionary, roadmap
#   (trivial = senior + dev + owner only)
# Medium path skips: critic, scout, architect, tester, qa, qa-code, security, documenter, po, questionary, roadmap
#   (medium = lead + senior + dev + owner)
#
# Derived from route-trivial.sh steps_skipped and route-medium.sh steps_skipped:
#   trivial skips: critique(critic/scout), research(scout), architecture(architect), planning(lead), test_authoring(tester), qa(qa/qa-code), security
#   medium  skips: critique(critic/scout), research(scout), architecture(architect), test_authoring(tester), qa(qa/qa-code), security

TRIVIAL_SKIP_ROLES='["architect","lead","tester","qa","qa-code","security","critic","scout","documenter","po","questionary","roadmap","fe-security","ux-security","fe-documenter","ux-documenter","integration-gate"]'
MEDIUM_SKIP_ROLES='["architect","tester","qa","qa-code","security","critic","scout","documenter","po","questionary","roadmap","fe-security","ux-security","fe-documenter","ux-documenter","integration-gate"]'

# --- Calculate tokens per path ---
# High = sum of all role budgets
HIGH_TOKENS=$(jq '[.roles[].budget] | add' "$MANIFEST")

# Trivial = sum of budgets for roles NOT in trivial skip list
TRIVIAL_TOKENS=$(jq --argjson skip "$TRIVIAL_SKIP_ROLES" '
  [.roles | to_entries[] | select(.key as $k | $skip | index($k) | not) | .value.budget] | add
' "$MANIFEST")

# Medium = sum of budgets for roles NOT in medium skip list
MEDIUM_TOKENS=$(jq --argjson skip "$MEDIUM_SKIP_ROLES" '
  [.roles | to_entries[] | select(.key as $k | $skip | index($k) | not) | .value.budget] | add
' "$MANIFEST")

# --- Calculate ratios ---
# Use awk for floating point division
TRIVIAL_RATIO=$(awk "BEGIN {printf \"%.4f\", $TRIVIAL_TOKENS / $HIGH_TOKENS}")
MEDIUM_RATIO=$(awk "BEGIN {printf \"%.4f\", $MEDIUM_TOKENS / $HIGH_TOKENS}")

# --- Threshold checks ---
# trivial_ratio must be < 0.60 (agents include mode-gated sections; runtime filtering reduces further)
# medium_ratio must be < 0.65
TRIVIAL_PASS="false"
MEDIUM_PASS="false"

if awk "BEGIN {exit !($TRIVIAL_RATIO < 0.60)}"; then
  TRIVIAL_PASS="true"
fi

if awk "BEGIN {exit !($MEDIUM_RATIO < 0.65)}"; then
  MEDIUM_PASS="true"
fi

OVERALL="PASS"
if [ "$TRIVIAL_PASS" = "false" ] || [ "$MEDIUM_PASS" = "false" ]; then
  OVERALL="FAIL"
fi

# --- Build result JSON ---
RESULT=$(jq -n \
  --argjson trivial_tokens "$TRIVIAL_TOKENS" \
  --argjson medium_tokens "$MEDIUM_TOKENS" \
  --argjson high_tokens "$HIGH_TOKENS" \
  --argjson trivial_ratio "$TRIVIAL_RATIO" \
  --argjson medium_ratio "$MEDIUM_RATIO" \
  --argjson trivial_pass "$TRIVIAL_PASS" \
  --argjson medium_pass "$MEDIUM_PASS" \
  --arg overall "$OVERALL" \
  --arg phase "${PHASE:-none}" \
  '{
    phase: $phase,
    trivial_tokens: $trivial_tokens,
    medium_tokens: $medium_tokens,
    high_tokens: $high_tokens,
    trivial_ratio: $trivial_ratio,
    medium_ratio: $medium_ratio,
    trivial_pass: $trivial_pass,
    medium_pass: $medium_pass,
    overall: $overall
  }')

# --- Output ---
if [ "$DRY_RUN" = "true" ]; then
  echo "[dry-run] Would output:"
  echo "$RESULT"
  exit 0
fi

if [ -n "$OUTPUT_FILE" ]; then
  echo "$RESULT" > "$OUTPUT_FILE"
  echo "Written to $OUTPUT_FILE"
else
  echo "$RESULT"
fi

# --- Exit code based on overall result ---
if [ "$OVERALL" = "FAIL" ]; then
  exit 1
fi
exit 0
