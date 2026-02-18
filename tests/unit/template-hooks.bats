#!/usr/bin/env bats
# template-hooks.bats -- Tests for template generation hook scripts
# Plan 08-06: BATS tests for template generation pipeline
# Note: Hook scripts are created by plan 08-05 (running in parallel).
# Tests use `skip` when scripts don't exist yet.

setup() {
  load '../test_helper/common'
  GENERATE_HOOK="$SCRIPTS_DIR/template-generate-hook.sh"
  STALENESS_HOOK="$SCRIPTS_DIR/template-staleness-check.sh"
  REGENERATE="$SCRIPTS_DIR/regenerate-agents.sh"
  HASH_FILE="$AGENTS_DIR/.agent-generation-hash"
}

# --- template-generate-hook.sh existence ---

@test "template-generate-hook.sh exists" {
  [[ -f "$GENERATE_HOOK" ]] || skip "template-generate-hook.sh not yet created (08-05 dependency)"
  assert_file_exist "$GENERATE_HOOK"
}

@test "template-generate-hook.sh is executable" {
  [[ -f "$GENERATE_HOOK" ]] || skip "template-generate-hook.sh not yet created (08-05 dependency)"
  [[ -x "$GENERATE_HOOK" ]]
}

# --- template-generate-hook.sh behavior ---

@test "template-generate-hook.sh exits 0 for non-dept agent (yolo-owner)" {
  [[ -f "$GENERATE_HOOK" ]] || skip "template-generate-hook.sh not yet created (08-05 dependency)"
  run bash "$GENERATE_HOOK" "yolo-owner"
  assert_success
}

@test "template-generate-hook.sh exits 0 for non-dept agent (yolo-critic)" {
  [[ -f "$GENERATE_HOOK" ]] || skip "template-generate-hook.sh not yet created (08-05 dependency)"
  run bash "$GENERATE_HOOK" "yolo-critic"
  assert_success
}

@test "template-generate-hook.sh exits 0 for non-dept agent (yolo-scout)" {
  [[ -f "$GENERATE_HOOK" ]] || skip "template-generate-hook.sh not yet created (08-05 dependency)"
  run bash "$GENERATE_HOOK" "yolo-scout"
  assert_success
}

@test "template-generate-hook.sh exits 0 for non-dept agent (yolo-debugger)" {
  [[ -f "$GENERATE_HOOK" ]] || skip "template-generate-hook.sh not yet created (08-05 dependency)"
  run bash "$GENERATE_HOOK" "yolo-debugger"
  assert_success
}

@test "template-generate-hook.sh identifies dept agent (yolo-dev)" {
  [[ -f "$GENERATE_HOOK" ]] || skip "template-generate-hook.sh not yet created (08-05 dependency)"
  run bash "$GENERATE_HOOK" "yolo-dev"
  assert_success
}

@test "template-generate-hook.sh identifies dept agent (yolo-fe-dev)" {
  [[ -f "$GENERATE_HOOK" ]] || skip "template-generate-hook.sh not yet created (08-05 dependency)"
  run bash "$GENERATE_HOOK" "yolo-fe-dev"
  assert_success
}

@test "template-generate-hook.sh identifies dept agent (yolo-ux-architect)" {
  [[ -f "$GENERATE_HOOK" ]] || skip "template-generate-hook.sh not yet created (08-05 dependency)"
  run bash "$GENERATE_HOOK" "yolo-ux-architect"
  assert_success
}

# --- template-staleness-check.sh existence ---

@test "template-staleness-check.sh exists" {
  [[ -f "$STALENESS_HOOK" ]] || skip "template-staleness-check.sh not yet created (08-05 dependency)"
  assert_file_exist "$STALENESS_HOOK"
}

@test "template-staleness-check.sh is executable" {
  [[ -f "$STALENESS_HOOK" ]] || skip "template-staleness-check.sh not yet created (08-05 dependency)"
  [[ -x "$STALENESS_HOOK" ]]
}

# --- template-staleness-check.sh behavior ---

@test "template-staleness-check.sh exits 0 when hash matches" {
  [[ -f "$STALENESS_HOOK" ]] || skip "template-staleness-check.sh not yet created (08-05 dependency)"

  # Ensure fresh hash exists
  bash "$REGENERATE" --force >/dev/null 2>&1

  run bash "$STALENESS_HOOK"
  assert_success
}

@test "template-staleness-check.sh emits warning when hash mismatches" {
  [[ -f "$STALENESS_HOOK" ]] || skip "template-staleness-check.sh not yet created (08-05 dependency)"

  # Ensure fresh hash, then corrupt it
  bash "$REGENERATE" --force >/dev/null 2>&1
  local original_hash
  original_hash=$(cat "$HASH_FILE")
  echo "0000000000000000000000000000000000000000000000000000000000000000" > "$HASH_FILE"

  run bash "$STALENESS_HOOK"
  # Should warn or fail
  [[ "$status" -ne 0 ]] || echo "$output" | grep -qi "stale\|warn\|mismatch"

  # Restore hash
  echo "$original_hash" > "$HASH_FILE"
}

@test "template-staleness-check.sh exits 0 silently when hash file missing (DXP-01)" {
  [[ -f "$STALENESS_HOOK" ]] || skip "template-staleness-check.sh not yet created (08-05 dependency)"

  # Remove hash file
  local had_hash=false
  if [[ -f "$HASH_FILE" ]]; then
    had_hash=true
    cp "$HASH_FILE" "$HASH_FILE.test-bak"
  fi
  rm -f "$HASH_FILE"

  run bash "$STALENESS_HOOK"
  # Graceful degradation (DXP-01): exits 0 with no output when hash file missing
  assert_success
  [ -z "$output" ]

  # Restore
  if $had_hash; then
    mv "$HASH_FILE.test-bak" "$HASH_FILE"
  fi
}
