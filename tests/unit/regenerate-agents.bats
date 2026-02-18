#!/usr/bin/env bats
# regenerate-agents.bats -- Tests for regenerate-agents.sh wrapper
# Plan 08-06: BATS tests for template generation pipeline

setup() {
  load '../test_helper/common'
  REGENERATE="$SCRIPTS_DIR/regenerate-agents.sh"
  GENERATE="$SCRIPTS_DIR/generate-agent.sh"
  HASH_FILE="$AGENTS_DIR/.agent-generation-hash"

  # Save original hash file if it exists
  if [[ -f "$HASH_FILE" ]]; then
    cp "$HASH_FILE" "$HASH_FILE.bak"
  fi
}

teardown() {
  # Restore original hash file
  if [[ -f "$HASH_FILE.bak" ]]; then
    mv "$HASH_FILE.bak" "$HASH_FILE"
  fi
}

# --- Help and usage ---

@test "regenerate-agents.sh --help exits 0" {
  run bash "$REGENERATE" --help
  assert_success
}

@test "regenerate-agents.sh --help shows usage information" {
  run bash "$REGENERATE" --help
  assert_output --partial "Usage:"
  assert_output --partial "--check"
  assert_output --partial "--force"
  assert_output --partial "--dry-run"
}

@test "regenerate-agents.sh unknown flag exits 1" {
  run bash "$REGENERATE" --invalid
  assert_failure
  assert_output --partial "unknown argument"
}

# --- Dry-run mode ---

@test "regenerate-agents.sh --dry-run exits 0" {
  run bash "$REGENERATE" --dry-run
  assert_success
}

@test "regenerate-agents.sh --dry-run reports 27 agents" {
  run bash "$REGENERATE" --dry-run
  assert_success
  assert_output --partial "27"
}

@test "regenerate-agents.sh --dry-run does not write hash file" {
  # Remove hash file first
  rm -f "$HASH_FILE"
  run bash "$REGENERATE" --dry-run
  assert_success
  [ ! -f "$HASH_FILE" ]
}

# --- Check mode ---

@test "regenerate-agents.sh --check exits 0 after fresh --force regeneration" {
  # First regenerate all agents
  run bash "$REGENERATE" --force
  assert_success

  # Then check should pass
  run bash "$REGENERATE" --check
  assert_success
  assert_output --partial "0 stale"
}

@test "regenerate-agents.sh --check reports check complete with count" {
  # Regenerate first
  bash "$REGENERATE" --force >/dev/null 2>&1

  run bash "$REGENERATE" --check
  assert_output --partial "Check complete:"
  assert_output --partial "/27 checked"
}

@test "regenerate-agents.sh --check exits 1 after modifying an agent file" {
  # Regenerate first to get clean state
  bash "$REGENERATE" --force >/dev/null 2>&1

  # Modify one generated agent
  local target="$AGENTS_DIR/yolo-dev.md"
  local original
  original=$(cat "$target")
  echo "# MODIFIED FOR TEST" >> "$target"

  # Check should detect staleness
  run bash "$REGENERATE" --check
  assert_failure
  assert_output --partial "STALE"

  # Restore original
  printf '%s' "$original" > "$target"
}

# --- Force mode ---

@test "regenerate-agents.sh --force does not prompt" {
  run bash "$REGENERATE" --force
  assert_success
  refute_output --partial "Continue?"
}

@test "regenerate-agents.sh --force writes hash file" {
  rm -f "$HASH_FILE"
  run bash "$REGENERATE" --force
  assert_success
  [ -f "$HASH_FILE" ]
}

@test "regenerate-agents.sh --force reports success count" {
  run bash "$REGENERATE" --force
  assert_success
  assert_output --partial "Regenerated 27/27"
}