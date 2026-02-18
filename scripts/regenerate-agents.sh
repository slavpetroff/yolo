#!/usr/bin/env bash
set -euo pipefail

# regenerate-agents.sh — Regenerate all 27 department agents from templates + overlays
# Usage: regenerate-agents.sh [--help]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GENERATE_SCRIPT="$SCRIPT_DIR/generate-agent.sh"

ROLES=(architect lead senior dev tester qa qa-code security documenter)
DEPTS=(backend frontend uiux)
TOTAL=$(( ${#ROLES[@]} * ${#DEPTS[@]} ))

usage() {
  cat <<'USAGE'
Usage: regenerate-agents.sh [--help]

Regenerate all 27 department agents (9 roles x 3 depts) from templates + overlays.

Options:
  --help    Show this help message

Roles: architect, lead, senior, dev, tester, qa, qa-code, security, documenter
Depts: backend, frontend, uiux
USAGE
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help) usage 0 ;;
    *)      echo "Error: unknown argument: $1" >&2; usage 1 ;;
  esac
done

# --- Regenerate all combinations ---
success=0
failed=0
failures=()

for dept in "${DEPTS[@]}"; do
  for role in "${ROLES[@]}"; do
    if bash "$GENERATE_SCRIPT" --role "$role" --dept "$dept"; then
      success=$(( success + 1 ))
    else
      failed=$(( failed + 1 ))
      failures+=("${dept}/${role}")
    fi
  done
done

# --- Report ---
echo ""
echo "Regeneration complete: ${success}/${TOTAL} succeeded, ${failed} failed"

if [[ ${#failures[@]} -gt 0 ]]; then
  echo "Failed combinations:"
  for f in "${failures[@]}"; do
    echo "  - $f"
  done
  exit 1
fi

exit 0
