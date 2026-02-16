#!/usr/bin/env bats
# detect-stack-classify.bats — Unit tests for project type classification
# Tests the project_type and type_confidence fields added to detect-stack.sh
# Requires config/project-types.json with 7 type definitions.
# RED PHASE: All tests expected to FAIL until implementation in plan 01-01.

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/detect-stack.sh"

  # Override CLAUDE_CONFIG_DIR to avoid picking up real installed skills
  export CLAUDE_CONFIG_DIR="$TEST_WORKDIR/mock-claude"
  mkdir -p "$CLAUDE_CONFIG_DIR/skills"
}

# Helper: run detect-stack against test project dir
run_detect() {
  run bash -c "cd '$TEST_WORKDIR' && CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' bash '$SUT' '$TEST_WORKDIR'"
}

# --- Config Validation (project-types.json) ---

@test "project-types.json exists and is valid JSON" {
  run jq -e '.' "$CONFIG_DIR/project-types.json"
  assert_success
}

@test "project-types.json has exactly 7 types" {
  local count
  count=$(jq '.types | length' "$CONFIG_DIR/project-types.json")
  [ "$count" -eq 7 ]
}

@test "project-types.json: each type has required fields" {
  local valid_count
  valid_count=$(jq '[.types[] | select(.id and .name and .priority and .detect and .department_conventions and .ux_focus)] | length' "$CONFIG_DIR/project-types.json")
  [ "$valid_count" -eq 7 ]
}

@test "project-types.json: generic type has empty detect array" {
  local detect_len
  detect_len=$(jq '[.types[] | select(.id == "generic")] | .[0].detect | length' "$CONFIG_DIR/project-types.json")
  [ "$detect_len" -eq 0 ]
}

@test "project-types.json: priority values are unique integers 1-7" {
  local unique_count
  unique_count=$(jq '[.types[].priority] | unique | length' "$CONFIG_DIR/project-types.json")
  [ "$unique_count" -eq 7 ]
  # Verify range 1-7
  local min max
  min=$(jq '[.types[].priority] | min' "$CONFIG_DIR/project-types.json")
  max=$(jq '[.types[].priority] | max' "$CONFIG_DIR/project-types.json")
  [ "$min" -eq 1 ]
  [ "$max" -eq 7 ]
}

# --- Project Type Classification ---

@test "classifies empty project as generic" {
  run_detect
  assert_success
  echo "$output" | jq -e '.project_type == "generic"'
}

@test "classifies web-app from react dependency" {
  cat > "$TEST_WORKDIR/package.json" <<'EOF'
{
  "dependencies": {
    "react": "^18",
    "react-dom": "^18"
  }
}
EOF
  run_detect
  assert_success
  echo "$output" | jq -e '.project_type == "web-app"'
}

@test "classifies api-service from express dependency" {
  cat > "$TEST_WORKDIR/package.json" <<'EOF'
{
  "dependencies": {
    "express": "^4"
  }
}
EOF
  run_detect
  assert_success
  echo "$output" | jq -e '.project_type == "api-service"'
}

@test "classifies cli-tool from bin directory and scripts" {
  mkdir -p "$TEST_WORKDIR/bin" "$TEST_WORKDIR/scripts"
  echo '#!/bin/bash' > "$TEST_WORKDIR/scripts/run.sh"
  run_detect
  assert_success
  echo "$output" | jq -e '.project_type == "cli-tool"'
}

@test "classifies library from src/lib.rs and Cargo.toml" {
  mkdir -p "$TEST_WORKDIR/src"
  touch "$TEST_WORKDIR/Cargo.toml"
  touch "$TEST_WORKDIR/src/lib.rs"
  run_detect
  assert_success
  echo "$output" | jq -e '.project_type == "library"'
}

@test "classifies monorepo from workspaces in package.json" {
  cat > "$TEST_WORKDIR/package.json" <<'EOF'
{
  "workspaces": ["packages/*"]
}
EOF
  run_detect
  assert_success
  echo "$output" | jq -e '.project_type == "monorepo"'
}

# --- Backward Compatibility (must co-exist with new fields) ---

@test "backward compat: output has both detected_stack and project_type" {
  cat > "$TEST_WORKDIR/package.json" <<'EOF'
{
  "dependencies": {
    "react": "^18"
  }
}
EOF
  run_detect
  assert_success
  # Existing field still present
  echo "$output" | jq -e '.detected_stack'
  # New field also present
  echo "$output" | jq -e '.project_type'
}

@test "backward compat: output has both installed and type_confidence" {
  run_detect
  assert_success
  # Existing field still present
  echo "$output" | jq -e '.installed'
  # New field also present
  echo "$output" | jq -e '.type_confidence'
}

# --- Priority & Weight Resolution ---

@test "higher weight signal wins over lower" {
  # src/lib.rs (library w:8) + routes/ (api-service w:4) + Cargo.toml (library w:3)
  # Library total weight = 11, api-service total weight = 4
  mkdir -p "$TEST_WORKDIR/src" "$TEST_WORKDIR/routes"
  touch "$TEST_WORKDIR/Cargo.toml"
  touch "$TEST_WORKDIR/src/lib.rs"
  run_detect
  assert_success
  echo "$output" | jq -e '.project_type == "library"'
}

@test "monorepo beats web-app when both match (higher priority)" {
  # package.json with both react and workspaces
  # monorepo has higher priority (7) than web-app (5)
  cat > "$TEST_WORKDIR/package.json" <<'EOF'
{
  "dependencies": {
    "react": "^18"
  },
  "workspaces": ["packages/*"]
}
EOF
  run_detect
  assert_success
  echo "$output" | jq -e '.project_type == "monorepo"'
}
