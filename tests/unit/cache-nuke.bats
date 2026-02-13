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
