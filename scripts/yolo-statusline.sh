#!/bin/bash
set -eo pipefail

# This script has been offloaded to the Rust MCP `yolo` CLI logic.
CLI_PATH="$(dirname "$0")/../yolo-mcp-server/target/release/yolo"

if [ -x "$CLI_PATH" ]; then
  "$CLI_PATH" statusline
else
  # Fallback to cargo if not built
  cd "$(dirname "$0")/../yolo-mcp-server" || exit 0
  cargo run -q --release --bin yolo -- statusline 2>/dev/null
fi
