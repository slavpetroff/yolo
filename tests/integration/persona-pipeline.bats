#!/usr/bin/env bats
# persona-pipeline.bats — End-to-end integration tests for the full
# detect-stack -> classify -> generate-department-toons -> compile-context pipeline.
# Tests web-app, shell/cli-tool, and YOLO self-detection scenarios.
# GREEN PHASE: All 23 tests passing after plans 01-01 through 01-04 implementation.

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir
  mk_planning_dir

  # Script paths
  DETECT="$SCRIPTS_DIR/detect-stack.sh"
  GENERATE="$SCRIPTS_DIR/generate-department-toons.sh"
  COMPILE="$SCRIPTS_DIR/compile-context.sh"

  # Override CLAUDE_CONFIG_DIR
  export CLAUDE_CONFIG_DIR="$TEST_WORKDIR/mock-claude"
  mkdir -p "$CLAUDE_CONFIG_DIR/skills"

  # Create phase dir and ROADMAP for compile-context
  PHASE_DIR=$(mk_phase 1 pipeline 1 0)

  # Create ROADMAP
  mk_roadmap

  # Create conventions
  cat > "$TEST_WORKDIR/.yolo-planning/conventions.json" <<'EOF'
{"conventions":[{"category":"naming","rule":"Use kebab-case for files"},{"category":"style","rule":"One commit per task"}]}
EOF
}

# --- Fixture Helpers ---

mk_webapp_project() {
  cat > "$TEST_WORKDIR/package.json" <<'EOF'
{"dependencies":{"react":"^18","react-dom":"^18"}}
EOF
  touch "$TEST_WORKDIR/tsconfig.json"
}

mk_shell_project() {
  mkdir -p "$TEST_WORKDIR/scripts" "$TEST_WORKDIR/bin"
  echo '#!/bin/bash' > "$TEST_WORKDIR/scripts/run.sh"
  chmod +x "$TEST_WORKDIR/scripts/run.sh"
}

mk_yolo_fixture() {
  mkdir -p "$TEST_WORKDIR/scripts" "$TEST_WORKDIR/agents" "$TEST_WORKDIR/commands"
  mkdir -p "$TEST_WORKDIR/hooks" "$TEST_WORKDIR/config" "$TEST_WORKDIR/references/departments"
  mkdir -p "$TEST_WORKDIR/tests"
  touch "$TEST_WORKDIR/scripts/detect-stack.sh" "$TEST_WORKDIR/scripts/compile-context.sh"
  touch "$TEST_WORKDIR/VERSION"
}

# --- Run Helpers ---

run_detect() {
  run bash -c "cd '$TEST_WORKDIR' && CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' bash '$DETECT' '$TEST_WORKDIR'"
}

run_generate() {
  run bash -c "cd '$TEST_WORKDIR' && CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' bash '$GENERATE' '$TEST_WORKDIR'"
}

run_compile() {
  local role="$1"
  run bash -c "cd '$TEST_WORKDIR' && bash '$COMPILE' 01 '$role' '$TEST_WORKDIR/.yolo-planning/phases'"
}

# ============================================================
# Web-app Pipeline
# ============================================================

@test "pipeline: web-app detect -> classify" {
  mk_webapp_project
  run_detect
  assert_success
  echo "$output" | jq -e '.project_type == "web-app"'
}

@test "pipeline: web-app generate -> backend.toon has TypeScript" {
  mk_webapp_project
  run_generate
  assert_success
  assert_file_contains "$TEST_WORKDIR/.yolo-planning/departments/backend.toon" "TypeScript"
}

@test "pipeline: web-app generate -> uiux.toon has design tokens" {
  mk_webapp_project
  run_generate
  assert_success
  assert_file_contains "$TEST_WORKDIR/.yolo-planning/departments/uiux.toon" "design tokens"
}

@test "pipeline: web-app compile -> dev context has dept_conventions" {
  mk_webapp_project
  # Generate department TOONs first (direct call so files exist on disk)
  bash -c "cd '$TEST_WORKDIR' && CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' bash '$GENERATE' '$TEST_WORKDIR'" >/dev/null 2>&1
  run_compile dev
  assert_success
  assert_file_contains "$PHASE_DIR/.ctx-dev.toon" "dept_conventions"
}

@test "pipeline: web-app compile -> dev has TypeScript in context" {
  mk_webapp_project
  bash -c "cd '$TEST_WORKDIR' && CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' bash '$GENERATE' '$TEST_WORKDIR'" >/dev/null 2>&1
  run_compile dev
  assert_success
  assert_file_contains "$PHASE_DIR/.ctx-dev.toon" "TypeScript"
}

# ============================================================
# Shell/CLI-tool Pipeline
# ============================================================

@test "pipeline: shell-project detect -> cli-tool" {
  mk_shell_project
  run_detect
  assert_success
  echo "$output" | jq -e '.project_type == "cli-tool"'
}

@test "pipeline: shell-project generate -> Bash conventions" {
  mk_shell_project
  run_generate
  assert_success
  assert_file_contains "$TEST_WORKDIR/.yolo-planning/departments/backend.toon" "Bash"
}

@test "pipeline: shell-project generate -> CLI UX focus" {
  mk_shell_project
  run_generate
  assert_success
  assert_file_contains "$TEST_WORKDIR/.yolo-planning/departments/uiux.toon" "help text"
}

@test "pipeline: shell-project compile -> dev has Bash in context" {
  mk_shell_project
  bash -c "cd '$TEST_WORKDIR' && CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' bash '$GENERATE' '$TEST_WORKDIR'" >/dev/null 2>&1
  run_compile dev
  assert_success
  assert_file_contains "$PHASE_DIR/.ctx-dev.toon" "Bash"
}

# ============================================================
# Compile-context Department Injection
# ============================================================

@test "pipeline: architect context does NOT include dept_conventions" {
  mk_webapp_project
  bash -c "cd '$TEST_WORKDIR' && CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' bash '$GENERATE' '$TEST_WORKDIR'" >/dev/null 2>&1
  run_compile architect
  assert_success
  assert_file_not_contains "$PHASE_DIR/.ctx-architect.toon" "dept_conventions"
}

@test "pipeline: senior context includes dept_conventions" {
  mk_webapp_project
  bash -c "cd '$TEST_WORKDIR' && CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' bash '$GENERATE' '$TEST_WORKDIR'" >/dev/null 2>&1
  run_compile senior
  assert_success
  assert_file_contains "$PHASE_DIR/.ctx-senior.toon" "dept_conventions"
}

@test "pipeline: lead context does NOT include dept_conventions" {
  mk_webapp_project
  bash -c "cd '$TEST_WORKDIR' && CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' bash '$GENERATE' '$TEST_WORKDIR'" >/dev/null 2>&1
  run_compile lead
  assert_success
  assert_file_not_contains "$PHASE_DIR/.ctx-lead.toon" "dept_conventions"
}

# ============================================================
# Refresh Mechanism
# ============================================================

@test "refresh: first run creates .stack-hash" {
  mk_webapp_project
  run_generate
  assert_success
  assert_file_exists "$TEST_WORKDIR/.yolo-planning/departments/.stack-hash"
}

@test "refresh: second run skips regeneration" {
  mk_webapp_project
  # First run (direct call)
  bash -c "cd '$TEST_WORKDIR' && CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' bash '$GENERATE' '$TEST_WORKDIR'" >/dev/null 2>&1
  # Second run (captured)
  run_generate
  assert_success
  assert_output --partial "TOONs up to date"
}

@test "refresh: --force flag regenerates" {
  mk_webapp_project
  # First run
  bash -c "cd '$TEST_WORKDIR' && CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' bash '$GENERATE' '$TEST_WORKDIR'" >/dev/null 2>&1
  # Force run
  run bash -c "cd '$TEST_WORKDIR' && CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' bash '$GENERATE' '$TEST_WORKDIR' --force"
  assert_success
  assert_output --partial "Generated department TOONs"
}

@test "refresh: project change triggers regeneration" {
  mk_webapp_project
  # First run
  bash -c "cd '$TEST_WORKDIR' && CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' bash '$GENERATE' '$TEST_WORKDIR'" >/dev/null 2>&1
  # Change project -- add express (different stack detection output = different hash)
  cat > "$TEST_WORKDIR/package.json" <<'EOF'
{"dependencies":{"react":"^18","react-dom":"^18","express":"^4"}}
EOF
  # Second run should detect change
  run_generate
  assert_success
  assert_output --partial "Stack changed"
}

# ============================================================
# YOLO Self-Detection (cli-tool classification)
# ============================================================

@test "self-test: YOLO-like project detects as cli-tool" {
  mk_yolo_fixture
  run_detect
  assert_success
  echo "$output" | jq -e '.project_type == "cli-tool"'
}

@test "self-test: YOLO-like project backend.toon has Bash" {
  mk_yolo_fixture
  run_generate
  assert_success
  assert_file_contains "$TEST_WORKDIR/.yolo-planning/departments/backend.toon" "Bash"
}

@test "self-test: YOLO-like project backend.toon has BATS testing" {
  mk_yolo_fixture
  run_generate
  assert_success
  # Check for bats or BATS (case-insensitive match via grep)
  run bash -c "grep -i 'bats' '$TEST_WORKDIR/.yolo-planning/departments/backend.toon'"
  assert_success
}

@test "self-test: YOLO-like project uiux.toon has CLI UX focus" {
  mk_yolo_fixture
  run_generate
  assert_success
  assert_file_contains "$TEST_WORKDIR/.yolo-planning/departments/uiux.toon" "help text"
}

@test "self-test: YOLO-like project uiux.toon has error output formatting" {
  mk_yolo_fixture
  run_generate
  assert_success
  assert_file_contains "$TEST_WORKDIR/.yolo-planning/departments/uiux.toon" "error output formatting"
}

@test "self-test: YOLO-like project has no TypeScript references" {
  mk_yolo_fixture
  run_generate
  assert_success
  assert_file_not_contains "$TEST_WORKDIR/.yolo-planning/departments/backend.toon" "TypeScript"
  assert_file_not_contains "$TEST_WORKDIR/.yolo-planning/departments/backend.toon" "React"
}

@test "self-test: YOLO-like project has no React references" {
  mk_yolo_fixture
  run_generate
  assert_success
  assert_file_not_contains "$TEST_WORKDIR/.yolo-planning/departments/frontend.toon" "React"
}
