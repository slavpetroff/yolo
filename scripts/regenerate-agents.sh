#!/usr/bin/env bash
set -euo pipefail

# regenerate-agents.sh — Regenerate all 27 department agents from templates + overlays
# Usage: regenerate-agents.sh [--check] [--force] [--dry-run] [--help]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GENERATE_SCRIPT="$SCRIPT_DIR/generate-agent.sh"
AGENTS_DIR="$REPO_ROOT/agents"
OVERLAYS_DIR="$AGENTS_DIR/overlays"
TEMPLATES_DIR="$AGENTS_DIR/templates"
HASH_FILE="$AGENTS_DIR/.agent-generation-hash"

ROLES=(architect lead senior dev tester qa qa-code security documenter)
DEPTS=(backend frontend uiux)
TOTAL=$(( ${#ROLES[@]} * ${#DEPTS[@]} ))

CHECK=false
FORCE=false
DRY_RUN=false

usage() {
  cat <<'USAGE'
Usage: regenerate-agents.sh [--check] [--force] [--dry-run] [--help]

Regenerate all 27 department agents (9 roles x 3 depts) from templates + overlays.

Options:
  --check     Check if generated files match current agent files (exit 1 if stale)
  --force     Overwrite all agent files without prompting
  --dry-run   Pass --dry-run to generate-agent.sh (print output, don't write)
  --help      Show this help message

Roles: architect, lead, senior, dev, tester, qa, qa-code, security, documenter
Depts: backend, frontend, uiux
USAGE
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)   CHECK=true; shift ;;
    --force)   FORCE=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --help)    usage 0 ;;
    *)         echo "Error: unknown argument: $1" >&2; usage 1 ;;
  esac
done

# --- Resolve output filename for a dept/role combo ---
resolve_output_path() {
  local dept="$1" role="$2"
  local prefix
  prefix=$(jq -r '.common.DEPT_PREFIX' "$OVERLAYS_DIR/$dept.json")
  echo "$AGENTS_DIR/yolo-${prefix}${role}.md"
}

# --- Compute hash of all templates + overlays (source inputs) ---
compute_source_hash() {
  # Concatenate all template and overlay files in deterministic order, then hash
  local hash
  hash=$(cat "$TEMPLATES_DIR"/*.md "$OVERLAYS_DIR"/*.json 2>/dev/null | shasum -a 256 | cut -d' ' -f1)
  echo "$hash"
}

if $CHECK; then
  # --- Check source hash first ---
  current_hash=$(compute_source_hash)
  hash_stale=false
  if [[ -f "$HASH_FILE" ]]; then
    stored_hash=$(cat "$HASH_FILE")
    if [[ "$current_hash" != "$stored_hash" ]]; then
      echo "STALE: source hash mismatch (templates/overlays changed since last regeneration)"
      echo "  stored:  $stored_hash"
      echo "  current: $current_hash"
      echo ""
      hash_stale=true
    fi
  else
    echo "MISSING: $HASH_FILE (run regenerate-agents.sh to create)"
    echo ""
    hash_stale=true
  fi

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
  if [[ $stale -gt 0 ]] || $hash_stale; then
    exit 1
  fi
  exit 0
fi

# --- Build generate-agent.sh flags ---
GEN_FLAGS=()
if $DRY_RUN; then
  GEN_FLAGS+=(--dry-run)
fi

# --- Prompt unless --force or --dry-run ---
if ! $FORCE && ! $DRY_RUN; then
  echo "This will regenerate ${TOTAL} agent files in ${AGENTS_DIR}/"
  printf "Continue? [y/N] "
  read -r answer
  if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
    echo "Aborted."
    exit 0
  fi
fi

# --- Regenerate all combinations ---
success=0
failed=0
updated=0
unchanged=0
failures=()

for dept in "${DEPTS[@]}"; do
  for role in "${ROLES[@]}"; do
    output_path=$(resolve_output_path "$dept" "$role")

    # Capture before-hash for change detection (skip if dry-run or file missing)
    before_hash=""
    if ! $DRY_RUN && [[ -f "$output_path" ]]; then
      before_hash=$(shasum -a 256 "$output_path" | cut -d' ' -f1)
    fi

    if bash "$GENERATE_SCRIPT" --role "$role" --dept "$dept" ${GEN_FLAGS[@]+"${GEN_FLAGS[@]}"}; then
      success=$(( success + 1 ))

      # Detect if file actually changed
      if ! $DRY_RUN && [[ -n "$before_hash" && -f "$output_path" ]]; then
        after_hash=$(shasum -a 256 "$output_path" | cut -d' ' -f1)
        if [[ "$before_hash" == "$after_hash" ]]; then
          unchanged=$(( unchanged + 1 ))
        else
          updated=$(( updated + 1 ))
        fi
      else
        updated=$(( updated + 1 ))
      fi
    else
      failed=$(( failed + 1 ))
      failures+=("${dept}/${role}")
    fi
  done
done

# --- Write source hash (skip if dry-run or any failures) ---
if ! $DRY_RUN && [[ $failed -eq 0 ]]; then
  source_hash=$(compute_source_hash)
  echo "$source_hash" > "$HASH_FILE"
  echo "Wrote source hash to $HASH_FILE"
fi

# --- Report ---
echo ""
echo "Regenerated ${success}/${TOTAL} agents (${unchanged} unchanged, ${updated} updated)"

if [[ ${#failures[@]} -gt 0 ]]; then
  echo "Failed (${failed}):"
  for f in "${failures[@]}"; do
    echo "  - $f"
  done
  exit 1
fi

exit 0
