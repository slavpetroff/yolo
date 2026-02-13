#!/usr/bin/env bats
# regression.bats — Performance regression tests for YOLO scripts
# Compares current benchmark results against saved baselines in .baselines.json.
# Fails if current mean exceeds 2x the saved baseline.
# If .baselines.json does not exist, tests are skipped (not failed).

HYPERFINE="/opt/homebrew/bin/hyperfine"
BASELINES_FILE=""

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir
  mk_planning_dir
  mk_state_json
  mk_state_md
  mk_roadmap
  mk_execution_state

  mk_phase 1 "perf-test" 1 1

  mk_git_repo
  mk_recent_commit "feat(01-01): implement authentication module"

  # Resolve baselines file path
  _TESTS_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  BASELINES_FILE="$_TESTS_DIR/perf/.baselines.json"

  if [ ! -f "$BASELINES_FILE" ]; then
    skip "No .baselines.json found — run capture-baselines.sh first"
  fi

  if [ ! -x "$HYPERFINE" ]; then
    HYPERFINE="$(command -v hyperfine 2>/dev/null || true)"
    [ -x "$HYPERFINE" ] || skip "hyperfine not installed"
  fi
}

# Helper: benchmark a script and compare against saved baseline
# Usage: assert_no_regression <script_key> <wrapper_script>
#   script_key: key in .baselines.json (e.g., "security-filter")
#   Fails if current mean > 2x saved baseline
assert_no_regression() {
  local key="$1" wrapper="$2"

  # Extract saved baseline (ms)
  local saved_ms
  saved_ms=$(jq -r --arg k "$key" '.[$k].mean_ms // empty' "$BASELINES_FILE")
  if [ -z "$saved_ms" ]; then
    skip "No baseline saved for '$key'"
  fi

  # Run current benchmark
  "$HYPERFINE" --warmup 3 --min-runs 10 --ignore-failure \
    "$wrapper" \
    --export-json "$TEST_WORKDIR/bench.json" 2>/dev/null

  local current_ms
  current_ms=$(jq '.results[0].mean * 1000' "$TEST_WORKDIR/bench.json")

  # Threshold = 2x saved baseline
  local threshold
  threshold=$(echo "$saved_ms" | awk '{printf "%.4f", $1 * 2}')

  local regressed
  regressed=$(echo "$current_ms $threshold" | awk '{print ($1 > $2)}')
  if [ "$regressed" -eq 1 ]; then
    echo "REGRESSION: $key current=${current_ms}ms > 2x baseline=${saved_ms}ms (threshold=${threshold}ms)" >&2
    return 1
  fi
}

# -----------------------------------------------------------------------
# 1. security-filter regression check
# -----------------------------------------------------------------------
@test "security-filter: no regression vs saved baseline" {
  local wrapper="$TEST_WORKDIR/bench.sh"
  cat > "$wrapper" <<BENCH
#!/bin/bash
echo '{"tool_input":{"file_path":"src/foo.ts"}}' | bash "$SCRIPTS_DIR/security-filter.sh"
BENCH
  chmod +x "$wrapper"

  assert_no_regression "security-filter" "$wrapper"
}

# -----------------------------------------------------------------------
# 2. file-guard regression check
# -----------------------------------------------------------------------
@test "file-guard: no regression vs saved baseline" {
  local wrapper="$TEST_WORKDIR/bench.sh"
  cat > "$wrapper" <<BENCH
#!/bin/bash
cd "$TEST_WORKDIR"
echo '{"tool_input":{"file_path":"src/foo.ts"}}' | bash "$SCRIPTS_DIR/file-guard.sh"
BENCH
  chmod +x "$wrapper"

  assert_no_regression "file-guard" "$wrapper"
}

# -----------------------------------------------------------------------
# 3. phase-detect regression check
# -----------------------------------------------------------------------
@test "phase-detect: no regression vs saved baseline" {
  local wrapper="$TEST_WORKDIR/bench.sh"
  cat > "$wrapper" <<BENCH
#!/bin/bash
cd "$TEST_WORKDIR"
bash "$SCRIPTS_DIR/phase-detect.sh" > /dev/null
BENCH
  chmod +x "$wrapper"

  assert_no_regression "phase-detect" "$wrapper"
}

# -----------------------------------------------------------------------
# 4. qa-gate regression check
# -----------------------------------------------------------------------
@test "qa-gate: no regression vs saved baseline" {
  local wrapper="$TEST_WORKDIR/bench.sh"
  cat > "$wrapper" <<BENCH
#!/bin/bash
cd "$TEST_WORKDIR"
echo '{"agent_name":"yolo-dev","status":"idle"}' | bash "$SCRIPTS_DIR/qa-gate.sh"
BENCH
  chmod +x "$wrapper"

  assert_no_regression "qa-gate" "$wrapper"
}

# -----------------------------------------------------------------------
# 5. hook-wrapper regression check
# -----------------------------------------------------------------------
@test "hook-wrapper: no regression vs saved baseline" {
  local mock_cache="$TEST_WORKDIR/mock-claude"
  mkdir -p "$mock_cache/plugins/cache/yolo-marketplace/yolo/1.0.0/scripts"
  echo '#!/bin/bash' > "$mock_cache/plugins/cache/yolo-marketplace/yolo/1.0.0/scripts/noop.sh"
  echo 'exit 0' >> "$mock_cache/plugins/cache/yolo-marketplace/yolo/1.0.0/scripts/noop.sh"
  chmod +x "$mock_cache/plugins/cache/yolo-marketplace/yolo/1.0.0/scripts/noop.sh"

  rm -f "/tmp/yolo-vdir-$(id -u)" 2>/dev/null

  local wrapper="$TEST_WORKDIR/bench.sh"
  cat > "$wrapper" <<BENCH
#!/bin/bash
cd "$TEST_WORKDIR"
export CLAUDE_CONFIG_DIR="$mock_cache"
echo '{}' | bash "$SCRIPTS_DIR/hook-wrapper.sh" noop.sh
BENCH
  chmod +x "$wrapper"

  assert_no_regression "hook-wrapper" "$wrapper"

  rm -f "/tmp/yolo-vdir-$(id -u)" 2>/dev/null
}

# -----------------------------------------------------------------------
# 6. state-updater regression check
# -----------------------------------------------------------------------
@test "state-updater: no regression vs saved baseline" {
  local plan_path="$TEST_WORKDIR/.yolo-planning/phases/01-perf-test/01-01.plan.jsonl"

  local wrapper="$TEST_WORKDIR/bench.sh"
  cat > "$wrapper" <<BENCH
#!/bin/bash
cd "$TEST_WORKDIR"
echo '{"tool_input":{"file_path":"$plan_path"}}' | bash "$SCRIPTS_DIR/state-updater.sh"
BENCH
  chmod +x "$wrapper"

  assert_no_regression "state-updater" "$wrapper"
}
