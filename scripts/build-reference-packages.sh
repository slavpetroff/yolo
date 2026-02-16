#!/usr/bin/env bash
set -euo pipefail

# build-reference-packages.sh — Sync checker for per-role reference packages.
# Validates that all 9 hand-authored packages exist in references/packages/
# and contain expected keywords from source reference files.
# NOT a generator — packages are hand-authored static TOON files (D1).
#
# Usage: bash build-reference-packages.sh [--help] [--quiet]
# Output: JSON {valid:BOOL, missing:[], stale:[]}
# Exit: 0 if valid, 1 if invalid.

# --- jq dependency check ---
if ! command -v jq &>/dev/null; then
  echo '{"error":"jq is required but not installed. Install: brew install jq (macOS) / apt install jq (Linux)"}' >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGES_DIR="$SCRIPT_DIR/../references/packages"
SOURCE_DIR="$SCRIPT_DIR/../references"

# --- Flag parsing ---
QUIET=false
for arg in "$@"; do
  case "$arg" in
    --help)
      echo "Usage: bash build-reference-packages.sh [--help] [--quiet]"
      echo ""
      echo "Validates per-role reference packages in references/packages/."
      echo "Checks that all 9 role packages exist and contain expected keywords"
      echo "from source reference files (execute-protocol.md, artifact-formats.md)."
      echo ""
      echo "Options:"
      echo "  --help    Show this usage message"
      echo "  --quiet   Suppress stdout, exit code only"
      echo ""
      echo "Output: JSON {valid:BOOL, missing:[], stale:[]}"
      echo "Exit: 0 if valid, 1 if invalid"
      exit 0
      ;;
    --quiet)
      QUIET=true
      ;;
  esac
done

# --- Role definitions ---
ROLES="architect lead senior dev tester qa qa-code critic security"

# --- Keyword lookup per role (bash 3.2 compatible, no associative arrays) ---
get_keywords() {
  case "$1" in
    architect) echo "Step 2|architecture.toon|critique.jsonl|tech_decisions" ;;
    lead)      echo "Step 3|Step 10|plan.jsonl|wave|execution-state" ;;
    senior)    echo "Step 4|Step 7|spec|code-review.jsonl|design_review" ;;
    dev)       echo "Step 6|summary.jsonl|commit|escalat|TDD" ;;
    tester)    echo "Step 5|test-plan.jsonl|RED|red" ;;
    qa)        echo "Step 8|verification.jsonl|tier|must_have" ;;
    qa-code)   echo "Step 8|qa-code.jsonl|TDD|lint" ;;
    critic)    echo "Step 1|critique.jsonl|gap|finding" ;;
    security)  echo "Step 9|security-audit.jsonl|vulnerability|FAIL" ;;
  esac
}

# --- Validation ---
MISSING=""
STALE=""

for role in $ROLES; do
  pkg_file="$PACKAGES_DIR/${role}.toon"

  # Check existence
  if [ ! -f "$pkg_file" ]; then
    if [ -n "$MISSING" ]; then
      MISSING="$MISSING,$role"
    else
      MISSING="$role"
    fi
    continue
  fi

  # Check keywords
  keywords=$(get_keywords "$role")
  IFS='|' read -ra kw_arr <<< "$keywords"
  for kw in "${kw_arr[@]}"; do
    if ! grep -qi "$kw" "$pkg_file" 2>/dev/null; then
      entry="${role}:${kw}"
      if [ -n "$STALE" ]; then
        STALE="$STALE,$entry"
      else
        STALE="$entry"
      fi
    fi
  done
done

# --- Determine validity ---
VALID=true
if [ -n "$MISSING" ] || [ -n "$STALE" ]; then
  VALID=false
fi

# --- Build JSON output ---
MISSING_JSON=$(echo "$MISSING" | tr ',' '\n' | jq -R 'select(. != "")' | jq -s '.')
STALE_JSON=$(echo "$STALE" | tr ',' '\n' | jq -R 'select(. != "")' | jq -s '.')

OUTPUT=$(jq -n \
  --argjson valid "$VALID" \
  --argjson missing "$MISSING_JSON" \
  --argjson stale "$STALE_JSON" \
  '{valid:$valid,missing:$missing,stale:$stale}')

if [ "$QUIET" = false ]; then
  echo "$OUTPUT"
fi

if [ "$VALID" = true ]; then
  exit 0
else
  exit 1
fi
