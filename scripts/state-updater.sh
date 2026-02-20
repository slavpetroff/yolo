#!/bin/bash
set -u
# PostToolUse: Auto-update STATE.md, ROADMAP.md + .execution-state.json on PLAN/SUMMARY writes
# Offloaded to the Rust MCP `yolo` CLI
# Non-blocking, fail-open (always exit 0)

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

if ! echo "$FILE_PATH" | grep -qE 'phases/.*-(PLAN|SUMMARY)\.md$'; then
  exit 0
fi

# Locate the YOLO CLI binary
CLI_PATH="$(dirname "$0")/../yolo-mcp-server/target/release/yolo"

if [ -x "$CLI_PATH" ]; then
  "$CLI_PATH" update-state "$FILE_PATH" >/dev/null 2>&1
else
  # Fallback to cargo if not built
  DIR="$(pwd)"
  cd "$(dirname "$0")/../yolo-mcp-server" || exit 0
  cargo run -q --release --bin yolo -- update-state "${DIR}/${FILE_PATH}" >/dev/null 2>&1
fi

exit 0
