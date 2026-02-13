#!/usr/bin/env bash
set -euo pipefail
# capture-baselines.sh — Run all performance benchmarks and save to .baselines.json
# Usage: bash tests/perf/capture-baselines.sh
#
# Creates tests/perf/.baselines.json with mean_ms for each script.
# This file is used by regression.bats to detect performance regressions.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TESTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
SCRIPTS_DIR="$PROJECT_ROOT/scripts"
FIXTURES_DIR="$TESTS_DIR/fixtures"
OUTPUT="$SCRIPT_DIR/.baselines.json"

HYPERFINE="/opt/homebrew/bin/hyperfine"
if [ ! -x "$HYPERFINE" ]; then
  HYPERFINE="$(command -v hyperfine 2>/dev/null || true)"
fi
if [ ! -x "$HYPERFINE" ]; then
  echo "ERROR: hyperfine not found. Install with: brew install hyperfine" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq not found. Install with: brew install jq" >&2
  exit 1
fi

# Set up isolated working directory
WORKDIR=$(mktemp -d "/tmp/yolo-perf-capture-XXXXXX")
trap 'rm -rf "$WORKDIR"' EXIT

# Create .yolo-planning skeleton
mkdir -p "$WORKDIR/.yolo-planning/phases/01-perf-test"
cp "$FIXTURES_DIR/config/balanced-config.json" "$WORKDIR/.yolo-planning/config.json"
cp "$FIXTURES_DIR/plans/valid-plan.jsonl" "$WORKDIR/.yolo-planning/phases/01-perf-test/01-01.plan.jsonl"
cp "$FIXTURES_DIR/summaries/valid-summary.jsonl" "$WORKDIR/.yolo-planning/phases/01-perf-test/01-01.summary.jsonl"
cp "$FIXTURES_DIR/state/state.json" "$WORKDIR/.yolo-planning/state.json"
cp "$FIXTURES_DIR/state/execution-state.json" "$WORKDIR/.yolo-planning/.execution-state.json"

# STATE.md
cat > "$WORKDIR/.yolo-planning/STATE.md" <<'EOF'
# Perf Baseline

Phase: 1 of 1 (Perf Test)
Status: active
Plans: 1/1
Progress: 100%

## Codebase Profile
- **Language:** Bash
- **Test Coverage:** None
EOF

# ROADMAP.md
cat > "$WORKDIR/.yolo-planning/ROADMAP.md" <<'EOF'
# Perf Roadmap

## Progress
| Phase | Status | Plans | Tasks | Commits |
|-------|--------|-------|-------|---------|
| 1 | Complete | 1 | 0 | 0 |

---

## Phase List
- [x] Phase 1: Perf Test

---
EOF

# Git repo
cd "$WORKDIR"
git init -q
git config user.email "perf@test.com"
git config user.name "PerfTest"
echo "init" > README.md
git add README.md && git commit -q -m "chore(init): initial commit"
git commit --allow-empty -q -m "feat(01-01): perf baseline commit"

# Hook-wrapper mock cache
MOCK_CACHE="$WORKDIR/mock-claude"
mkdir -p "$MOCK_CACHE/plugins/cache/yolo-marketplace/yolo/1.0.0/scripts"
printf '#!/bin/bash\nexit 0\n' > "$MOCK_CACHE/plugins/cache/yolo-marketplace/yolo/1.0.0/scripts/noop.sh"
chmod +x "$MOCK_CACHE/plugins/cache/yolo-marketplace/yolo/1.0.0/scripts/noop.sh"

# Summary fixture for validate-summary
SUMMARY_FILE="$WORKDIR/.yolo-planning/phases/01-perf-test/01-01.summary.jsonl"

# Markdown fixture for validate-frontmatter
MD_FILE="$WORKDIR/test-doc.md"
cat > "$MD_FILE" <<'EOF'
---
description: A single-line description for testing
phase: "01"
---

# Test Document
Content here.
EOF

# Plan path for state-updater
PLAN_PATH="$WORKDIR/.yolo-planning/phases/01-perf-test/01-01.plan.jsonl"

echo "Capturing baselines in: $WORKDIR"
echo "================================================"

# Initialize output JSON
echo '{}' > "$OUTPUT"

# Define benchmarks as key=command pairs (bash 3.2 compatible)
BENCH_KEYS="security-filter file-guard phase-detect qa-gate hook-wrapper state-updater"

get_bench_cmd() {
  case "$1" in
    security-filter) echo "echo '{\"tool_input\":{\"file_path\":\"src/foo.ts\"}}' | bash '$SCRIPTS_DIR/security-filter.sh'" ;;
    file-guard) echo "cd '$WORKDIR' && echo '{\"tool_input\":{\"file_path\":\"src/foo.ts\"}}' | bash '$SCRIPTS_DIR/file-guard.sh'" ;;
    phase-detect) echo "cd '$WORKDIR' && bash '$SCRIPTS_DIR/phase-detect.sh' > /dev/null" ;;
    qa-gate) echo "cd '$WORKDIR' && echo '{\"agent_name\":\"yolo-dev\",\"status\":\"idle\"}' | bash '$SCRIPTS_DIR/qa-gate.sh'" ;;
    hook-wrapper) echo "cd '$WORKDIR' && CLAUDE_CONFIG_DIR='$MOCK_CACHE' bash '$SCRIPTS_DIR/hook-wrapper.sh' noop.sh <<< '{}'" ;;
    state-updater) echo "cd '$WORKDIR' && echo '{\"tool_input\":{\"file_path\":\"$PLAN_PATH\"}}' | bash '$SCRIPTS_DIR/state-updater.sh'" ;;
  esac
}

for key in $BENCH_KEYS; do
  cmd=$(get_bench_cmd "$key")

  # Write wrapper script
  wrapper="$WORKDIR/bench-${key}.sh"
  printf '#!/bin/bash\n%s\n' "$cmd" > "$wrapper"
  chmod +x "$wrapper"

  echo ""
  echo "--- Benchmarking: $key ---"

  # Clear cached vdir for hook-wrapper
  rm -f "/tmp/yolo-vdir-$(id -u)" 2>/dev/null

  bench_json="$WORKDIR/bench-${key}.json"
  "$HYPERFINE" --warmup 3 --min-runs 10 \
    "$wrapper" \
    --export-json "$bench_json" 2>&1 || true

  if [ -f "$bench_json" ]; then
    mean_ms=$(jq '.results[0].mean * 1000' "$bench_json")
    stddev_ms=$(jq '.results[0].stddev * 1000' "$bench_json")
    min_ms=$(jq '.results[0].min * 1000' "$bench_json")
    max_ms=$(jq '.results[0].max * 1000' "$bench_json")

    jq --arg k "$key" \
       --argjson mean "$mean_ms" \
       --argjson stddev "$stddev_ms" \
       --argjson min "$min_ms" \
       --argjson max "$max_ms" \
      '.[$k] = {mean_ms: $mean, stddev_ms: $stddev, min_ms: $min, max_ms: $max, captured: (now | strftime("%Y-%m-%dT%H:%M:%SZ"))}' \
      "$OUTPUT" > "${OUTPUT}.tmp" && mv "${OUTPUT}.tmp" "$OUTPUT"

    printf "  mean=%.2fms  stddev=%.2fms  min=%.2fms  max=%.2fms\n" \
      "$mean_ms" "$stddev_ms" "$min_ms" "$max_ms"
  else
    echo "  WARNING: benchmark failed for $key"
  fi
done

# Clean up cached vdir
rm -f "/tmp/yolo-vdir-$(id -u)" 2>/dev/null

echo ""
echo "================================================"
echo "Baselines saved to: $OUTPUT"
echo ""
jq '.' "$OUTPUT"
