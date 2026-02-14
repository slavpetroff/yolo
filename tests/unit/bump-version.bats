#!/usr/bin/env bats
# bump-version.bats — Unit tests for scripts/bump-version.sh
# Version bumping utility: updates 3 version files

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/bump-version.sh"

  # Create mock project structure with all 3 version files
  MOCK_ROOT="$TEST_WORKDIR/mock-project"
  mkdir -p "$MOCK_ROOT/scripts"
  mkdir -p "$MOCK_ROOT/.claude-plugin"

  echo "1.2.3" > "$MOCK_ROOT/VERSION"
  echo '{"version":"1.2.3","name":"yolo"}' > "$MOCK_ROOT/.claude-plugin/plugin.json"
  echo '{"plugins":[{"version":"1.2.3","name":"yolo"}]}' > "$MOCK_ROOT/.claude-plugin/marketplace.json"

  # Copy the script into mock project so ROOT resolves correctly
  cp "$SUT" "$MOCK_ROOT/scripts/bump-version.sh"

  # Stub curl to prevent network calls
  mkdir -p "$TEST_WORKDIR/bin"
  printf '#!/bin/bash\nexit 1\n' > "$TEST_WORKDIR/bin/curl"
  chmod +x "$TEST_WORKDIR/bin/curl"
}

# --- 1. --verify passes when all versions match ---

@test "--verify passes when all 3 files are in sync" {
  run bash -c "cd '$MOCK_ROOT' && bash scripts/bump-version.sh --verify"
  assert_success
  assert_output --partial "All 3 version files are in sync"
}

# --- 2. --verify fails on mismatch ---

@test "--verify fails when versions are mismatched" {
  echo "1.2.4" > "$MOCK_ROOT/VERSION"
  run bash -c "cd '$MOCK_ROOT' && bash scripts/bump-version.sh --verify"
  assert_failure
  assert_output --partial "MISMATCH"
}

# --- 3. Bumps patch version ---

@test "bumps patch version from 1.2.3 to 1.2.4" {
  run bash -c "cd '$MOCK_ROOT' && PATH='$TEST_WORKDIR/bin:$PATH' bash scripts/bump-version.sh"
  assert_success
  assert_output --partial "1.2.4"
  # Verify VERSION file was updated
  run cat "$MOCK_ROOT/VERSION"
  assert_output "1.2.4"
}

# --- 4. Updates all 3 files ---

@test "updates all 3 version files consistently" {
  run bash -c "cd '$MOCK_ROOT' && PATH='$TEST_WORKDIR/bin:$PATH' bash scripts/bump-version.sh"
  assert_success
  run jq -r '.version' "$MOCK_ROOT/.claude-plugin/plugin.json"
  assert_output "1.2.4"
  run jq -r '.plugins[0].version' "$MOCK_ROOT/.claude-plugin/marketplace.json"
  assert_output "1.2.4"
}

# --- 5. Shows old and new version ---

@test "displays local version and bumped version" {
  run bash -c "cd '$MOCK_ROOT' && PATH='$TEST_WORKDIR/bin:$PATH' bash scripts/bump-version.sh"
  assert_success
  assert_output --partial "Local version:   1.2.3"
  assert_output --partial "Bumping to:      1.2.4"
}

# --- 6. --verify shows all 3 file paths ---

@test "--verify output shows all 3 file versions" {
  run bash -c "cd '$MOCK_ROOT' && bash scripts/bump-version.sh --verify"
  assert_success
  assert_output --partial "VERSION"
  assert_output --partial ".claude-plugin/plugin.json"
  assert_output --partial ".claude-plugin/marketplace.json"
}
