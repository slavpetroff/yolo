#!/usr/bin/env bats
# db-only-no-fallbacks.bats — Validate no backward-compat fallback patterns remain
# Phase 11: DB-Only Default Mode

setup() {
  load '../test_helper/common'
}

@test "no DB_AVAILABLE in compile-context.sh" {
  run grep -c 'DB_AVAILABLE' "$SCRIPTS_DIR/compile-context.sh"
  assert_failure
}

@test "no db_available in go.md" {
  run grep -c 'db_available' "$COMMANDS_DIR/go.md"
  assert_failure
}

@test "no [sqlite] markers in templates" {
  run grep -rl '\[sqlite\]' "$AGENTS_DIR/templates/"
  assert_failure
}

@test "no [file] markers in templates" {
  run grep -rl '\[file\]' "$AGENTS_DIR/templates/"
  assert_failure
}

@test "no [sqlite]/[file] in generated agents" {
  run grep -rl '\[sqlite\]\|\[file\]' "$AGENTS_DIR"/yolo-*.md
  assert_failure
}

@test "no [sqlite]/[file] in execute-protocol.md" {
  run grep -c '\[sqlite\]\|\[file\]' "$PROJECT_ROOT/references/execute-protocol.md"
  assert_failure
}

@test "no dual-write guards in state-updater.sh" {
  run grep -c 'Dual-write' "$SCRIPTS_DIR/state-updater.sh"
  assert_failure
}

@test "compile-context.sh fails without DB" {
  # Run compile-context.sh with nonexistent DB path and verify exit code 1
  run bash "$SCRIPTS_DIR/compile-context.sh" --db /tmp/nonexistent-yolo-test.db --role dev --phase 01 --plan 01-01
  assert_failure
}
