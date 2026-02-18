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

# --- T4: Staleness detection tests ---

@test "hash file is created after --force regeneration" {
  rm -f "$HASH_FILE"
  bash "$REGENERATE" --force >/dev/null 2>&1
  [ -f "$HASH_FILE" ]
  # Hash should be a 64-char hex string (sha256)
  local hash
  hash=$(cat "$HASH_FILE")
  [[ ${#hash} -eq 64 ]]
}

@test "hash file content is deterministic (same inputs = same hash)" {
  bash "$REGENERATE" --force >/dev/null 2>&1
  local hash1
  hash1=$(cat "$HASH_FILE")

  bash "$REGENERATE" --force >/dev/null 2>&1
  local hash2
  hash2=$(cat "$HASH_FILE")

  [ "$hash1" = "$hash2" ]
}

@test "hash changes when template content changes" {
  # Regenerate to get baseline hash
  bash "$REGENERATE" --force >/dev/null 2>&1
  local hash_before
  hash_before=$(cat "$HASH_FILE")

  # Append to a template
  local template="$PROJECT_ROOT/agents/templates/dev.md"
  local original
  original=$(cat "$template")
  echo "<!-- test modification -->" >> "$template"

  # Regenerate and check hash changed
  bash "$REGENERATE" --force >/dev/null 2>&1
  local hash_after
  hash_after=$(cat "$HASH_FILE")

  # Restore original template
  printf '%s' "$original" > "$template"
  # Regenerate again to restore agents
  bash "$REGENERATE" --force >/dev/null 2>&1

  [ "$hash_before" != "$hash_after" ]
}

@test "hash changes when overlay content changes" {
  # Regenerate to get baseline hash
  bash "$REGENERATE" --force >/dev/null 2>&1
  local hash_before
  hash_before=$(cat "$HASH_FILE")

  # Modify overlay (append a comment key)
  local overlay="$PROJECT_ROOT/agents/overlays/backend.json"
  local original
  original=$(cat "$overlay")
  local modified
  modified=$(jq '. + {"_test_key": "test_value"}' "$overlay")
  printf '%s\n' "$modified" > "$overlay"

  # Regenerate and check hash changed
  bash "$REGENERATE" --force >/dev/null 2>&1
  local hash_after
  hash_after=$(cat "$HASH_FILE")

  # Restore original overlay
  printf '%s' "$original" > "$overlay"
  # Regenerate again to restore agents
  bash "$REGENERATE" --force >/dev/null 2>&1

  [ "$hash_before" != "$hash_after" ]
}

@test "--check detects stale hash after template modification" {
  # Regenerate to get clean state
  bash "$REGENERATE" --force >/dev/null 2>&1

  # Verify clean state
  run bash "$REGENERATE" --check
  assert_success

  # Modify a template (but don't regenerate)
  local template="$PROJECT_ROOT/agents/templates/dev.md"
  local original
  original=$(cat "$template")
  echo "<!-- staleness test -->" >> "$template"

  # Check should detect hash mismatch
  run bash "$REGENERATE" --check
  assert_failure
  assert_output --partial "STALE"

  # Restore original template
  printf '%s' "$original" > "$template"
}

@test "--check detects stale hash after overlay modification" {
  # Regenerate to get clean state
  bash "$REGENERATE" --force >/dev/null 2>&1

  # Modify overlay
  local overlay="$PROJECT_ROOT/agents/overlays/backend.json"
  local original
  original=$(cat "$overlay")
  local modified
  modified=$(jq '. + {"_test_key": "test_value"}' "$overlay")
  printf '%s\n' "$modified" > "$overlay"

  # Check should detect hash mismatch
  run bash "$REGENERATE" --check
  assert_failure
  assert_output --partial "STALE"

  # Restore original overlay
  printf '%s' "$original" > "$overlay"
}

@test "--check reports MISSING when hash file does not exist" {
  # Regenerate first then remove hash
  bash "$REGENERATE" --force >/dev/null 2>&1
  rm -f "$HASH_FILE"

  run bash "$REGENERATE" --check
  assert_failure
  assert_output --partial "MISSING"
}