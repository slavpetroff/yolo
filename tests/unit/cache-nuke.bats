#!/usr/bin/env bats
# cache-nuke.bats — Unit tests for scripts/cache-nuke.sh
# Cache clearing utility

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/cache-nuke.sh"

  # Isolate from real HOME
  export CLAUDE_CONFIG_DIR="$TEST_WORKDIR/mock-claude"
  PLUGIN_CACHE="$CLAUDE_CONFIG_DIR/plugins/cache/yolo-marketplace/yolo"
}

# --- 1. Outputs valid JSON summary ---

@test "outputs valid JSON summary" {
  run bash -c "CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' bash '$SUT'"
  assert_success
  echo "$output" | jq -e '.wiped' >/dev/null
}

# --- 2. Wipes plugin cache directory ---

@test "wipes entire plugin cache when called without flags" {
  mkdir -p "$PLUGIN_CACHE/1.0.0/commands"
  mkdir -p "$PLUGIN_CACHE/1.0.1/commands"
  run bash -c "CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' bash '$SUT'"
  assert_success
  [ ! -d "$PLUGIN_CACHE" ]
  echo "$output" | jq -e '.wiped.plugin_cache == true' >/dev/null
}

# --- 3. Wipes global commands ---

@test "wipes global commands directory" {
  mkdir -p "$CLAUDE_CONFIG_DIR/commands/yolo"
  echo "test" > "$CLAUDE_CONFIG_DIR/commands/yolo/test.md"
  run bash -c "CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' bash '$SUT'"
  assert_success
  [ ! -d "$CLAUDE_CONFIG_DIR/commands/yolo" ]
  echo "$output" | jq -e '.wiped.global_commands == true' >/dev/null
}

# --- 4. Keep-latest preserves newest version ---

@test "keeps latest version with --keep-latest" {
  mkdir -p "$PLUGIN_CACHE/1.0.0/commands"
  mkdir -p "$PLUGIN_CACHE/1.0.1/commands"
  echo "old" > "$PLUGIN_CACHE/1.0.0/commands/test.md"
  echo "new" > "$PLUGIN_CACHE/1.0.1/commands/test.md"
  run bash -c "CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' bash '$SUT' --keep-latest"
  assert_success
  # Latest should still exist
  [ -d "$PLUGIN_CACHE/1.0.1" ]
  # Old should be gone
  [ ! -d "$PLUGIN_CACHE/1.0.0" ]
}

# --- 5. Reports zero when nothing to wipe ---

@test "reports false for all wipe categories when nothing exists" {
  run bash -c "CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' bash '$SUT'"
  assert_success
  echo "$output" | jq -e '.wiped.plugin_cache == false' >/dev/null
  echo "$output" | jq -e '.wiped.global_commands == false' >/dev/null
}

# --- 6. Reports versions removed count ---

@test "reports correct versions_removed count" {
  mkdir -p "$PLUGIN_CACHE/1.0.0/commands"
  mkdir -p "$PLUGIN_CACHE/1.0.1/commands"
  mkdir -p "$PLUGIN_CACHE/1.0.2/commands"
  run bash -c "CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' bash '$SUT'"
  assert_success
  echo "$output" | jq -e '.wiped.versions_removed == 3' >/dev/null
}

# --- 7. DB file cleanup ---

@test "cleans up yolo.db files by default" {
  mkdir -p "$TEST_WORKDIR/.yolo-planning"
  sqlite3 "$TEST_WORKDIR/.yolo-planning/yolo.db" "PRAGMA journal_mode=WAL; CREATE TABLE t(x);"
  # Create WAL/SHM files
  touch "$TEST_WORKDIR/.yolo-planning/yolo.db-wal"
  touch "$TEST_WORKDIR/.yolo-planning/yolo.db-shm"

  run bash -c "cd '$TEST_WORKDIR' && CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' bash '$SUT'"
  assert_success
  [ ! -f "$TEST_WORKDIR/.yolo-planning/yolo.db" ]
  [ ! -f "$TEST_WORKDIR/.yolo-planning/yolo.db-wal" ]
  [ ! -f "$TEST_WORKDIR/.yolo-planning/yolo.db-shm" ]
  echo "$output" | jq -e '.wiped.db == true' >/dev/null
}

@test "--keep-db preserves yolo.db files" {
  mkdir -p "$TEST_WORKDIR/.yolo-planning"
  sqlite3 "$TEST_WORKDIR/.yolo-planning/yolo.db" "PRAGMA journal_mode=WAL; CREATE TABLE t(x);"
  touch "$TEST_WORKDIR/.yolo-planning/yolo.db-wal"

  run bash -c "cd '$TEST_WORKDIR' && CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' bash '$SUT' --keep-db"
  assert_success
  [ -f "$TEST_WORKDIR/.yolo-planning/yolo.db" ]
  [ -f "$TEST_WORKDIR/.yolo-planning/yolo.db-wal" ]
  echo "$output" | jq -e '.wiped.db == false' >/dev/null
}

@test "cleans vbw-planning yolo.db too" {
  mkdir -p "$TEST_WORKDIR/.vbw-planning"
  sqlite3 "$TEST_WORKDIR/.vbw-planning/yolo.db" "PRAGMA journal_mode=WAL; CREATE TABLE t(x);"

  run bash -c "cd '$TEST_WORKDIR' && CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' bash '$SUT'"
  assert_success
  [ ! -f "$TEST_WORKDIR/.vbw-planning/yolo.db" ]
}
