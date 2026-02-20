#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "=== verify-claude-bootstrap ==="
echo "The native bash test suite has been offloaded to Rust."
echo "Running Rust unit tests for bootstrap_claude in yolo-mcp-server/..."

cd "$ROOT/yolo-mcp-server"
cargo test --test-threads=1 bootstrap_claude::tests
