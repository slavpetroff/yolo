#!/usr/bin/env bash
set -e

echo "Installing YOLO Expert MCP Server..."

# Build the release binary
cd yolo-mcp-server || exit 1
cargo build --release --bins
cd ..

SERVER_PATH="$(pwd)/yolo-mcp-server/target/release/yolo-mcp-server"
CLI_PATH="$(pwd)/yolo-mcp-server/target/release/yolo"

# Inform the user how to install it
echo "------------------------------------------------------------"
echo "YOLO Expert MCP Server built successfully!"
echo "To install it into Claude Code, you can use the built-in command:"
echo ""
echo "    claude mcp add yolo-expert \"$SERVER_PATH\""
echo ""
echo "Or manually add it to your mcp.json config:"
echo "{"
echo "  \"mcpServers\": {"
echo "    \"yolo-expert\": {"
echo "      \"command\": \"$SERVER_PATH\""
echo "    }"
echo "  }"
echo "}"
echo ""
echo "--- TELEMETRY CLI ---"
echo "To view your caching ROI and token savings:"
echo "    alias yolo=\"$CLI_PATH\""
echo "    yolo report"
echo "------------------------------------------------------------"
