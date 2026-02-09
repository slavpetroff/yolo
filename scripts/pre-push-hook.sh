#!/usr/bin/env bash
set -euo pipefail
# Git pre-push hook: enforce version bump before push
# Install: ln -sf ../../scripts/pre-push-hook.sh .git/hooks/pre-push
# Bypass:  git push --no-verify

# Version sync check: ensure all 4 version files are consistent
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [ -f "$ROOT/scripts/bump-version.sh" ]; then
  VERIFY_OUTPUT=$(bash "$ROOT/scripts/bump-version.sh" --verify 2>&1) || {
    echo ""
    echo "ERROR: Push blocked -- version files are out of sync."
    echo ""
    echo "$VERIFY_OUTPUT" | grep -A 10 "MISMATCH"
    echo ""
    echo "  Run: bash scripts/bump-version.sh"
    echo ""
    exit 1
  }
fi

while read -r local_ref local_sha remote_ref remote_sha; do
  # Skip tag pushes and deletes
  [[ "$local_sha" == "0000000000000000000000000000000000000000" ]] && continue
  [[ "$local_ref" != refs/heads/* ]] && continue

  # Determine commit range
  if [[ "$remote_sha" == "0000000000000000000000000000000000000000" ]]; then
    # New branch — check all commits
    range="$local_sha"
  else
    range="${remote_sha}..${local_sha}"
  fi

  # Get files changed in the commits being pushed
  changed_files=$(git diff --name-only "$range" 2>/dev/null) || continue

  # If no files changed, skip (e.g. force push to same commit)
  [[ -z "$changed_files" ]] && continue

  # Check if VERSION is among changed files
  if ! echo "$changed_files" | grep -qx "VERSION"; then
    echo ""
    echo "ERROR: Push blocked — VERSION not updated."
    echo ""
    echo "  Commits being pushed change these files but don't bump the version:"
    echo "$changed_files" | head -10 | sed 's/^/    /'
    count=$(echo "$changed_files" | wc -l | tr -d ' ')
    [[ "$count" -gt 10 ]] && echo "    ... and $((count - 10)) more"
    echo ""
    echo "  Run:  bash scripts/bump-version.sh && git add -A && git commit --amend --no-edit"
    echo "  Skip: git push --no-verify  (use sparingly)"
    echo ""
    exit 1
  fi
done

exit 0
