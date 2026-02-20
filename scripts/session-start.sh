#!/bin/bash
set -u
# SessionStart: YOLO project state detection, update checks, cache maintenance (exit 0)

# Delegate the entire session start execution to the compiled yolo Rust CLI
# Note: Claude expects a zero exit and a JSON payload describing context.

if command -v yolo &> /dev/null; then
  yolo session-start "$@"
elif [ -f "$HOME/.yolo/bin/yolo" ]; then
  "$HOME/.yolo/bin/yolo" session-start "$@"
elif [ -f "$(dirname "$0")/../yolo-mcp-server/target/release/yolo" ]; then
  "$(dirname "$0")/../yolo-mcp-server/target/release/yolo" session-start "$@"
elif [ -f "$(dirname "$0")/../yolo-mcp-server/target/debug/yolo" ]; then
  "$(dirname "$0")/../yolo-mcp-server/target/debug/yolo" session-start "$@"
else
  echo '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"YOLO EXECUTABLE NOT FOUND. PLEASE BUILD YOLO-MCP-SERVER."}}'
fi
exit 0
