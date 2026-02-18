#!/usr/bin/env bats
# test-context-manifest.bats — Unit tests for context manifest integration in compile-context.sh
# Tests: manifest loading, fallback when absent, new role handling, budget from manifest, --measure flag.

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/compile-context.sh"

  # Set up .yolo-planning with phase dir, ROADMAP, conventions
  mkdir -p "$TEST_WORKDIR/.yolo-planning/phases/01-setup"
  mkdir -p "$TEST_WORKDIR/.yolo-planning/codebase"

  # Minimal ROADMAP.md
  cat > "$TEST_WORKDIR/.yolo-planning/ROADMAP.md" <<'EOF'
# Roadmap

## Phase 1: Setup
**Goal:** Initialize the project structure
**Reqs:** REQ-01
**Success Criteria:** All files created
EOF

  # Conventions file
  cat > "$TEST_WORKDIR/.yolo-planning/conventions.json" <<'EOF'
{"conventions":[{"category":"naming","rule":"Use kebab-case"}]}
EOF

  PHASES_DIR="$TEST_WORKDIR/.yolo-planning/phases"
}

# Helper: run compile-context from test workdir
run_cc() {
  local phase="$1" role="$2"
  shift 2
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT' '$phase' '$role' '$PHASES_DIR' $*"
}

# --- Manifest loading ---

@test "compile-context succeeds when context-manifest.json exists" {
  # The real manifest at config/context-manifest.json should be read
  run_cc 01 dev
  assert_success
}

@test "manifest is loaded from config/context-manifest.json" {
  # Verify the manifest file exists in the project
  assert_file_exists "$CONFIG_DIR/context-manifest.json"
  # Verify it has roles key
  run jq -e '.roles' "$CONFIG_DIR/context-manifest.json"
  assert_success
}

# --- Fallback when manifest absent ---

@test "compile-context succeeds when context-manifest.json absent" {
  # Use CLAUDE_PLUGIN_ROOT pointing to a dir without manifest
  run bash -c "cd '$TEST_WORKDIR' && CLAUDE_PLUGIN_ROOT='$TEST_WORKDIR' bash '$SUT' '01' 'dev' '$PHASES_DIR'"
  assert_success
}

@test "fallback produces valid .ctx-dev.toon without manifest" {
  run bash -c "cd '$TEST_WORKDIR' && CLAUDE_PLUGIN_ROOT='$TEST_WORKDIR' bash '$SUT' '01' 'dev' '$PHASES_DIR'"
  assert_success
  assert [ -f "$PHASES_DIR/01-setup/.ctx-dev.toon" ]
}

# --- New roles handle without error ---

@test "fe-security role produces output without error" {
  run_cc 01 fe-security
  assert_success
  assert [ -f "$PHASES_DIR/01-setup/.ctx-fe-security.toon" ]
}

@test "ux-security role produces output without error" {
  run_cc 01 ux-security
  assert_success
  assert [ -f "$PHASES_DIR/01-setup/.ctx-ux-security.toon" ]
}

@test "documenter role produces output without error" {
  run_cc 01 documenter
  assert_success
  assert [ -f "$PHASES_DIR/01-setup/.ctx-documenter.toon" ]
}

@test "fe-documenter role produces output without error" {
  run_cc 01 fe-documenter
  assert_success
  assert [ -f "$PHASES_DIR/01-setup/.ctx-fe-documenter.toon" ]
}

@test "ux-documenter role produces output without error" {
  run_cc 01 ux-documenter
  assert_success
  assert [ -f "$PHASES_DIR/01-setup/.ctx-ux-documenter.toon" ]
}

# --- Budget from manifest ---

@test "manifest defines budget for documenter role" {
  run jq -r '.roles.documenter.budget' "$CONFIG_DIR/context-manifest.json"
  assert_success
  assert_output "2000"
}

@test "manifest defines budget for fe-security role" {
  run jq -r '.roles["fe-security"].budget' "$CONFIG_DIR/context-manifest.json"
  assert_success
  assert_output "3000"
}

@test "manifest defines budget for ux-documenter role" {
  run jq -r '.roles["ux-documenter"].budget' "$CONFIG_DIR/context-manifest.json"
  assert_success
  assert_output "2000"
}

# --- --measure flag ---

@test "--measure flag reports reduction metrics" {
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT' --measure '01' 'dev' '$PHASES_DIR'"
  assert_success
  # Measure output should include some metric about token/char reduction
  assert_output --partial "toon"
}

@test "--measure flag still produces valid .toon file" {
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT' --measure '01' 'dev' '$PHASES_DIR'"
  assert_success
  assert [ -f "$PHASES_DIR/01-setup/.ctx-dev.toon" ]
}

# --- Manifest structure validation ---

@test "manifest has all new Phase 3 roles" {
  local manifest="$CONFIG_DIR/context-manifest.json"
  for role in fe-security ux-security documenter fe-documenter ux-documenter; do
    run jq -e --arg r "$role" '.roles[$r]' "$manifest"
    assert_success
  done
}

@test "each manifest role has budget field" {
  local manifest="$CONFIG_DIR/context-manifest.json"
  for role in fe-security ux-security documenter fe-documenter ux-documenter; do
    run jq -e --arg r "$role" '.roles[$r].budget | type == "number"' "$manifest"
    assert_success
  done
}
