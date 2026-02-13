#!/usr/bin/env bats
# baselines.bats — Performance baseline tests for YOLO scripts
# Uses hyperfine to benchmark each script and asserts mean < threshold.
# Thresholds derived from hooks.json timeouts (60-100x margin).

HYPERFINE="/opt/homebrew/bin/hyperfine"

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

  # Create a phase with one plan and one summary for scripts that scan phases
  mk_phase 1 "perf-test" 1 1

  # Git repo for scripts that need commit history
  mk_git_repo
  mk_recent_commit "feat(01-01): implement authentication module"

  # Hyperfine must be available
  if [ ! -x "$HYPERFINE" ]; then
    # Try system path as fallback (CI)
    HYPERFINE="$(command -v hyperfine 2>/dev/null || true)"
    [ -x "$HYPERFINE" ] || skip "hyperfine not installed"
  fi
}

# Helper: run a benchmark wrapper and assert mean_ms < threshold
# Usage: assert_perf_under <wrapper_script> <threshold_ms>
assert_perf_under() {
  local wrapper="$1" threshold="$2"

  "$HYPERFINE" --warmup 3 --min-runs 10 --ignore-failure \
    "$wrapper" \
    --export-json "$TEST_WORKDIR/bench.json" 2>/dev/null

  local mean_ms
  mean_ms=$(jq '.results[0].mean * 1000' "$TEST_WORKDIR/bench.json")

  # Use awk for float comparison (bc may not be installed)
  local under
  under=$(echo "$mean_ms $threshold" | awk '{print ($1 < $2)}')
  if [ "$under" -ne 1 ]; then
    echo "FAIL: mean ${mean_ms}ms >= ${threshold}ms threshold" >&2
    return 1
  fi
}

# -----------------------------------------------------------------------
# 1. security-filter.sh < 50ms (5s timeout in hooks.json)
# -----------------------------------------------------------------------
@test "security-filter completes in < 50ms" {
  local wrapper="$TEST_WORKDIR/bench.sh"
  cat > "$wrapper" <<BENCH
#!/bin/bash
echo '{"tool_input":{"file_path":"src/foo.ts"}}' | bash "$SCRIPTS_DIR/security-filter.sh"
BENCH
  chmod +x "$wrapper"

  assert_perf_under "$wrapper" 50
}

# -----------------------------------------------------------------------
# 2. file-guard.sh < 50ms (5s timeout)
# -----------------------------------------------------------------------
@test "file-guard completes in < 50ms" {
  local wrapper="$TEST_WORKDIR/bench.sh"
  cat > "$wrapper" <<BENCH
#!/bin/bash
cd "$TEST_WORKDIR"
echo '{"tool_input":{"file_path":"src/foo.ts"}}' | bash "$SCRIPTS_DIR/file-guard.sh"
BENCH
  chmod +x "$wrapper"

  assert_perf_under "$wrapper" 50
}

# -----------------------------------------------------------------------
# 3. hook-wrapper.sh < 30ms (all hooks route through it)
# -----------------------------------------------------------------------
@test "hook-wrapper completes in < 30ms" {
  # Point CLAUDE_CONFIG_DIR to a mock cache so hook-wrapper resolves quickly
  local mock_cache="$TEST_WORKDIR/mock-claude"
  mkdir -p "$mock_cache/plugins/cache/yolo-marketplace/yolo/1.0.0/scripts"
  # Create a trivial no-op script for the wrapper to call
  echo '#!/bin/bash' > "$mock_cache/plugins/cache/yolo-marketplace/yolo/1.0.0/scripts/noop.sh"
  echo 'exit 0' >> "$mock_cache/plugins/cache/yolo-marketplace/yolo/1.0.0/scripts/noop.sh"
  chmod +x "$mock_cache/plugins/cache/yolo-marketplace/yolo/1.0.0/scripts/noop.sh"

  # Clear any cached vdir
  rm -f "/tmp/yolo-vdir-$(id -u)" 2>/dev/null

  local wrapper="$TEST_WORKDIR/bench.sh"
  cat > "$wrapper" <<BENCH
#!/bin/bash
cd "$TEST_WORKDIR"
export CLAUDE_CONFIG_DIR="$mock_cache"
echo '{}' | bash "$SCRIPTS_DIR/hook-wrapper.sh" noop.sh
BENCH
  chmod +x "$wrapper"

  assert_perf_under "$wrapper" 30

  # Clean up cached vdir so it doesn't pollute other tests
  rm -f "/tmp/yolo-vdir-$(id -u)" 2>/dev/null
}

# -----------------------------------------------------------------------
# 4. phase-detect.sh < 100ms (called by commands)
# -----------------------------------------------------------------------
@test "phase-detect completes in < 100ms" {
  local wrapper="$TEST_WORKDIR/bench.sh"
  cat > "$wrapper" <<BENCH
#!/bin/bash
cd "$TEST_WORKDIR"
bash "$SCRIPTS_DIR/phase-detect.sh" > /dev/null
BENCH
  chmod +x "$wrapper"

  assert_perf_under "$wrapper" 100
}

# -----------------------------------------------------------------------
# 5. validate-commit.sh < 30ms (10s timeout)
# -----------------------------------------------------------------------
@test "validate-commit completes in < 30ms" {
  local wrapper="$TEST_WORKDIR/bench.sh"
  cat > "$wrapper" <<BENCH
#!/bin/bash
echo '{"tool_input":{"command":"git commit -m \"feat(01-01): add auth\""}}' | bash "$SCRIPTS_DIR/validate-commit.sh"
BENCH
  chmod +x "$wrapper"

  assert_perf_under "$wrapper" 30
}

# -----------------------------------------------------------------------
# 6. validate-summary.sh < 30ms (15s timeout)
# -----------------------------------------------------------------------
@test "validate-summary completes in < 30ms" {
  # Create a valid summary file for the script to check
  local summary="$TEST_WORKDIR/.yolo-planning/phases/01-perf-test/01-01.summary.jsonl"
  cp "$FIXTURES_DIR/summaries/valid-summary.jsonl" "$summary"

  local wrapper="$TEST_WORKDIR/bench.sh"
  cat > "$wrapper" <<BENCH
#!/bin/bash
cd "$TEST_WORKDIR"
echo '{"tool_input":{"file_path":"$summary"}}' | bash "$SCRIPTS_DIR/validate-summary.sh"
BENCH
  chmod +x "$wrapper"

  assert_perf_under "$wrapper" 30
}

# -----------------------------------------------------------------------
# 7. validate-frontmatter.sh < 30ms (5s timeout)
# -----------------------------------------------------------------------
@test "validate-frontmatter completes in < 30ms" {
  # Create a valid markdown file with frontmatter
  local md_file="$TEST_WORKDIR/test-doc.md"
  cat > "$md_file" <<'EOF'
---
description: A single-line description for testing
phase: "01"
---

# Test Document
Content here.
EOF

  local wrapper="$TEST_WORKDIR/bench.sh"
  cat > "$wrapper" <<BENCH
#!/bin/bash
echo '{"tool_input":{"file_path":"$md_file"}}' | bash "$SCRIPTS_DIR/validate-frontmatter.sh"
BENCH
  chmod +x "$wrapper"

  assert_perf_under "$wrapper" 30
}

# -----------------------------------------------------------------------
# 8. qa-gate.sh < 100ms (30s timeout)
# -----------------------------------------------------------------------
@test "qa-gate completes in < 100ms" {
  local wrapper="$TEST_WORKDIR/bench.sh"
  cat > "$wrapper" <<BENCH
#!/bin/bash
cd "$TEST_WORKDIR"
echo '{"agent_name":"yolo-dev","status":"idle"}' | bash "$SCRIPTS_DIR/qa-gate.sh"
BENCH
  chmod +x "$wrapper"

  assert_perf_under "$wrapper" 100
}

# -----------------------------------------------------------------------
# 9. task-verify.sh < 150ms (15s timeout)
# -----------------------------------------------------------------------
@test "task-verify completes in < 150ms" {
  local wrapper="$TEST_WORKDIR/bench.sh"
  cat > "$wrapper" <<BENCH
#!/bin/bash
cd "$TEST_WORKDIR"
echo '{"task_subject":"Implement authentication module"}' | bash "$SCRIPTS_DIR/task-verify.sh"
BENCH
  chmod +x "$wrapper"

  assert_perf_under "$wrapper" 150
}

# -----------------------------------------------------------------------
# 10. agent-start.sh < 20ms (3s timeout)
# -----------------------------------------------------------------------
@test "agent-start completes in < 20ms" {
  local wrapper="$TEST_WORKDIR/bench.sh"
  cat > "$wrapper" <<BENCH
#!/bin/bash
cd "$TEST_WORKDIR"
echo '{"agent_type":"yolo-dev"}' | bash "$SCRIPTS_DIR/agent-start.sh"
BENCH
  chmod +x "$wrapper"

  assert_perf_under "$wrapper" 20
}

# -----------------------------------------------------------------------
# 11. agent-stop.sh < 20ms (3s timeout)
# -----------------------------------------------------------------------
@test "agent-stop completes in < 20ms" {
  # Create the marker file that agent-stop removes
  echo "dev" > "$TEST_WORKDIR/.yolo-planning/.active-agent"

  local wrapper="$TEST_WORKDIR/bench.sh"
  cat > "$wrapper" <<BENCH
#!/bin/bash
cd "$TEST_WORKDIR"
echo '{}' | bash "$SCRIPTS_DIR/agent-stop.sh"
# Re-create for next iteration
echo "dev" > ".yolo-planning/.active-agent"
BENCH
  chmod +x "$wrapper"

  assert_perf_under "$wrapper" 20
}

# -----------------------------------------------------------------------
# 12. state-updater.sh < 150ms (5s timeout)
# -----------------------------------------------------------------------
@test "state-updater completes in < 150ms" {
  # state-updater triggers on plan/summary writes — give it a plan write event
  local plan_path="$TEST_WORKDIR/.yolo-planning/phases/01-perf-test/01-01.plan.jsonl"

  local wrapper="$TEST_WORKDIR/bench.sh"
  cat > "$wrapper" <<BENCH
#!/bin/bash
cd "$TEST_WORKDIR"
echo '{"tool_input":{"file_path":"$plan_path"}}' | bash "$SCRIPTS_DIR/state-updater.sh"
BENCH
  chmod +x "$wrapper"

  assert_perf_under "$wrapper" 150
}
