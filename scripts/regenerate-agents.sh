#!/usr/bin/env bash
set -euo pipefail

# regenerate-agents.sh — Regenerate all 27 department agents from templates + overlays
# Usage: regenerate-agents.sh [--check] [--help]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GENERATE_SCRIPT="$SCRIPT_DIR/generate-agent.sh"
AGENTS_DIR="$REPO_ROOT/agents"
OVERLAYS_DIR="$AGENTS_DIR/overlays"

ROLES=(architect lead senior dev tester qa qa-code security documenter)
DEPTS=(backend frontend uiux)
TOTAL=$(( ${#ROLES[@]} * ${#DEPTS[@]} ))

CHECK=false

usage() {
  cat <<'USAGE'
Usage: regenerate-agents.sh [--check] [--help]

Regenerate all 27 department agents (9 roles x 3 depts) from templates + overlays.

Options:
  --check   Check if generated files match current agent files (exit 1 if stale)
  --help    Show this help message

Roles: architect, lead, senior, dev, tester, qa, qa-code, security, documenter
Depts: backend, frontend, uiux
USAGE
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) CHECK=true; shift ;;
    --help)  usage 0 ;;
    *)       echo "Error: unknown argument: $1" >&2; usage 1 ;;
  esac
done

# --- Resolve output filename for a dept/role combo ---
resolve_output_path() {
  local dept="$1" role="$2"
  local prefix
  prefix=$(jq -r '.common.DEPT_PREFIX' "$OVERLAYS_DIR/$dept.json")
  echo "$AGENTS_DIR/yolo-${prefix}${role}.md"
}

if $CHECK; then
  # --- Check mode: compare dry-run output against existing files ---
  stale=0
  checked=0

  for dept in "${DEPTS[@]}"; do
    for role in "${ROLES[@]}"; do
      output_path=$(resolve_output_path "$dept" "$role")
      checked=$(( checked + 1 ))

      if [[ ! -f "$output_path" ]]; then
        echo "MISSING: $output_path (${dept}/${role})"
        stale=$(( stale + 1 ))
        continue
      fi

      generated=$(bash "$GENERATE_SCRIPT" --role "$role" --dept "$dept" --dry-run 2>/dev/null)
      if ! diff_output=$(diff <(printf '%s\n' "$generated") "$output_path" 2>&1); then
        echo "STALE: $output_path (${dept}/${role})"
        echo "$diff_output"
        echo ""
        stale=$(( stale + 1 ))
      fi
    done
  done

  echo "Check complete: ${checked}/${TOTAL} checked, ${stale} stale"
  if [[ $stale -gt 0 ]]; then
    exit 1
  fi
  exit 0
fi

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
