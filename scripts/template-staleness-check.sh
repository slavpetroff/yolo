#!/bin/bash
set -u
# SessionStart hook: Warn when agent templates/overlays have changed since
# last regeneration, indicating generated agent .md files may be stale.
#
# Reads agents/.agent-generation-hash (written by regenerate-agents.sh),
# computes current hash of templates + overlays, and compares. If different
# or hash file missing, emits a warning for Claude Code to display.
#
# Exit 0 always (graceful degradation per DXP-01).

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
AGENTS_DIR="$REPO_ROOT/agents"
TEMPLATES_DIR="$AGENTS_DIR/templates"
OVERLAYS_DIR="$AGENTS_DIR/overlays"
HASH_FILE="$AGENTS_DIR/.agent-generation-hash"

# Skip if template system is not set up
[ ! -d "$TEMPLATES_DIR" ] && exit 0
[ ! -d "$OVERLAYS_DIR" ] && exit 0

# Skip if no hash file exists (templates have never been used to generate)
[ ! -f "$HASH_FILE" ] && exit 0

# Compute current hash (same algorithm as regenerate-agents.sh)
CURRENT_HASH=$(cat "$TEMPLATES_DIR"/*.md "$OVERLAYS_DIR"/*.json 2>/dev/null | shasum -a 256 | cut -d' ' -f1) || exit 0
STORED_HASH=$(cat "$HASH_FILE" 2>/dev/null) || exit 0

if [ "$CURRENT_HASH" != "$STORED_HASH" ]; then
  echo "status: stale_templates"
  echo "Agent templates or overlays have changed since last regeneration."
  echo "Run: bash scripts/regenerate-agents.sh --force"
fi

exit 0
