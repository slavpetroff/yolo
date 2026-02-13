#!/usr/bin/env bash
set -euo pipefail

# run-all.sh — Master test runner for YOLO test suite
# Usage: bash tests/run-all.sh [category]
#   category: unit, containment, static, integration, perf, all (default: all)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CATEGORY="${1:-all}"

case "$CATEGORY" in
  unit)
    bats --recursive "$SCRIPT_DIR/unit/"
    ;;
  containment)
    bats --recursive "$SCRIPT_DIR/containment/"
    ;;
  static)
    bats --recursive "$SCRIPT_DIR/static/"
    ;;
  integration)
    bats --recursive "$SCRIPT_DIR/integration/"
    ;;
  perf)
    bats "$SCRIPT_DIR/perf/baselines.bats"
    ;;
  all)
    echo "=== Static Validation ==="
    bats --recursive "$SCRIPT_DIR/static/"
    echo ""
    echo "=== Unit Tests ==="
    bats --recursive "$SCRIPT_DIR/unit/"
    echo ""
    echo "=== Containment Tests ==="
    bats --recursive "$SCRIPT_DIR/containment/"
    echo ""
    echo "=== Integration Tests ==="
    bats --recursive "$SCRIPT_DIR/integration/"
    echo ""
    echo "=== Performance Baselines ==="
    bats "$SCRIPT_DIR/perf/baselines.bats" || echo "(perf tests optional)"
    ;;
  *)
    echo "Usage: $0 [unit|containment|static|integration|perf|all]" >&2
    exit 1
    ;;
esac
