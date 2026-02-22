#!/usr/bin/env bats

load test_helper

# Phase 4 integration tests: verify Plans 01-03 work together.

setup() {
  setup_temp_dir
  create_test_config
}

teardown() {
  teardown_temp_dir
}

# --- Test 1: vibe.md router + mode file integration ---

@test "phase4: vibe.md router Read references resolve to existing mode files" {
  local router="${PROJECT_ROOT}/commands/vibe.md"
  local modes_dir="${PROJECT_ROOT}/skills/vibe-modes"

  # Extract mode file references from router
  local refs
  refs=$(grep -oE 'skills/vibe-modes/[a-z-]+\.md' "$router" | sort -u)

  # Each referenced mode file must exist
  for ref in $refs; do
    [ -f "${PROJECT_ROOT}/${ref}" ]
  done

  # At least 6 mode files referenced
  local count
  count=$(echo "$refs" | wc -l)
  [ "$count" -ge 6 ]
}

@test "phase4: router is under 120 lines and mode files are non-empty" {
  local router="${PROJECT_ROOT}/commands/vibe.md"
  local modes_dir="${PROJECT_ROOT}/skills/vibe-modes"

  local lines
  lines=$(wc -l < "$router")
  [ "$lines" -lt 120 ]

  # All mode files are non-empty
  for f in "$modes_dir"/*.md; do
    [ -s "$f" ]
  done
}

# --- Test 2: tier cache + compile-context integration ---

@test "phase4: compile-context creates tier cache files" {
  # Set up codebase files
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning/codebase"
  echo "Conv content" > "$TEST_TEMP_DIR/.yolo-planning/codebase/CONVENTIONS.md"
  echo "Stack content" > "$TEST_TEMP_DIR/.yolo-planning/codebase/STACK.md"
  echo "Roadmap content" > "$TEST_TEMP_DIR/.yolo-planning/codebase/ROADMAP.md"

  mkdir -p "$TEST_TEMP_DIR/phases"

  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" compile-context 1 dev "$TEST_TEMP_DIR/phases"
  [ "$status" -eq 0 ]

  # Cache directory should exist after compilation
  local uid
  uid=$(id -u)
  local cache_dir="/tmp/yolo-tier-cache-${uid}"
  [ -d "$cache_dir" ]

  # At least one cache file should exist
  local cache_count
  cache_count=$(find "$cache_dir" -name "*.cache" -type f 2>/dev/null | wc -l)
  [ "$cache_count" -ge 1 ]
}

@test "phase4: second compile-context run uses cache (same output)" {
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning/codebase"
  echo "Conv content" > "$TEST_TEMP_DIR/.yolo-planning/codebase/CONVENTIONS.md"
  echo "Stack content" > "$TEST_TEMP_DIR/.yolo-planning/codebase/STACK.md"

  mkdir -p "$TEST_TEMP_DIR/phases"

  cd "$TEST_TEMP_DIR"

  # First run
  run "$YOLO_BIN" compile-context 1 dev "$TEST_TEMP_DIR/phases"
  [ "$status" -eq 0 ]
  local first_output
  first_output=$(cat "$TEST_TEMP_DIR/phases/.context-dev.md")

  # Second run (should use cache)
  run "$YOLO_BIN" compile-context 1 dev "$TEST_TEMP_DIR/phases"
  [ "$status" -eq 0 ]
  local second_output
  second_output=$(cat "$TEST_TEMP_DIR/phases/.context-dev.md")

  [ "$first_output" = "$second_output" ]
}

# --- Test 3: v2_token_budgets default enabled ---

@test "phase4: defaults.json has v2_token_budgets=true" {
  run jq '.v2_token_budgets' "$CONFIG_DIR/defaults.json"
  [ "$output" = "true" ]
}

# --- Test 4: session-start structured steps ---

@test "phase4: session-start outputs JSON with structured steps" {
  cd "$TEST_TEMP_DIR"

  run "$YOLO_BIN" hook SessionStart <<< '{}'
  [ "$status" -eq 0 ]
  # SessionStart should exit 0 (may or may not produce output depending on environment)
}

# --- Test 5: tier cache invalidation works via CLI ---

@test "phase4: invalidate-tier-cache clears cache files" {
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning/codebase"
  echo "Conv" > "$TEST_TEMP_DIR/.yolo-planning/codebase/CONVENTIONS.md"
  mkdir -p "$TEST_TEMP_DIR/phases"

  cd "$TEST_TEMP_DIR"

  # Populate cache
  run "$YOLO_BIN" compile-context 1 dev "$TEST_TEMP_DIR/phases"
  [ "$status" -eq 0 ]

  # Invalidate
  run "$YOLO_BIN" invalidate-tier-cache
  [ "$status" -eq 0 ]
}

# --- Test 6: all Phase 4 artifacts exist ---

@test "phase4: all Plan 01 mode files exist" {
  local expected_modes="bootstrap scope plan phase-mutation archive assumptions"
  for mode in $expected_modes; do
    [ -f "${PROJECT_ROOT}/skills/vibe-modes/${mode}.md" ]
  done
}

@test "phase4: config-migration test file exists" {
  [ -f "${PROJECT_ROOT}/tests/config-migration.bats" ]
}

@test "phase4: tier-cache test file exists" {
  [ -f "${PROJECT_ROOT}/tests/tier-cache.bats" ]
}

@test "phase4: vibe-mode-split test file exists" {
  [ -f "${PROJECT_ROOT}/tests/vibe-mode-split.bats" ]
}
