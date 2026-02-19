#!/usr/bin/env bats
# test-effort-cascading.bats — Unit tests for effort step-skip behavior
# Tests: turbo/fast/balanced/thorough step-skip rules, effort profile consistency,
# effort cascading language in go.md, and execution-state skip output format.

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir
  PROFILES_DIR="$PROJECT_ROOT/references"
  GO_MD="$PROJECT_ROOT/commands/go.md"
  EXEC_PROTOCOL="$PROJECT_ROOT/references/execute-protocol.md"
}

# --- Turbo step-skip rules ---

@test "turbo: skips critique (step 1)" {
  run grep -A1 '1: Critique' "$PROFILES_DIR/effort-profile-turbo.toon"
  assert_success
  assert_output --partial 'SKIP'
}

@test "turbo: skips research (step 2)" {
  run grep -A1 '2: Research' "$PROFILES_DIR/effort-profile-turbo.toon"
  assert_success
  assert_output --partial 'SKIP'
}

@test "turbo: skips test authoring (step 6)" {
  run grep -A1 '6: Test Authoring' "$PROFILES_DIR/effort-profile-turbo.toon"
  assert_success
  assert_output --partial 'SKIP'
}

@test "turbo: skips documentation (step 8.5)" {
  run grep -A1 '8.5: Documentation' "$PROFILES_DIR/effort-profile-turbo.toon"
  assert_success
  assert_output --partial 'SKIP'
}

@test "turbo: skips QA (step 9)" {
  run grep -A1 '9: QA' "$PROFILES_DIR/effort-profile-turbo.toon"
  assert_success
  assert_output --partial 'SKIP'
}

@test "turbo: skips security (step 10)" {
  run grep -A1 '10: Security' "$PROFILES_DIR/effort-profile-turbo.toon"
  assert_success
  assert_output --partial 'SKIP'
}

@test "turbo: runs architecture (step 3)" {
  run grep '3: Architecture' "$PROFILES_DIR/effort-profile-turbo.toon"
  assert_success
  assert_output --partial 'run'
}

@test "turbo: runs implementation (step 7)" {
  run grep '7: Implementation' "$PROFILES_DIR/effort-profile-turbo.toon"
  assert_success
  assert_output --partial 'run'
}

@test "turbo: runs sign-off (step 11)" {
  run grep '11: Sign-off' "$PROFILES_DIR/effort-profile-turbo.toon"
  assert_success
  assert_output --partial 'run'
}

# --- Fast step-skip rules ---

@test "fast: skips documentation (step 8.5)" {
  run grep -A1 '8.5: Documentation' "$PROFILES_DIR/effort-profile-fast.toon"
  assert_success
  assert_output --partial 'SKIP'
}

@test "fast: skips security (step 10)" {
  run grep -A1 '10: Security' "$PROFILES_DIR/effort-profile-fast.toon"
  assert_success
  assert_output --partial 'SKIP'
}

@test "fast: runs critique (step 1)" {
  run grep '1: Critique' "$PROFILES_DIR/effort-profile-fast.toon"
  assert_success
  assert_output --partial 'run'
}

@test "fast: runs research (step 2)" {
  run grep '2: Research' "$PROFILES_DIR/effort-profile-fast.toon"
  assert_success
  assert_output --partial 'run'
}

@test "fast: runs QA (step 9)" {
  run grep '9: QA' "$PROFILES_DIR/effort-profile-fast.toon"
  assert_success
  assert_output --partial 'run'
}

# --- Balanced step-skip rules (full 11-step) ---

@test "balanced: runs all steps (no SKIP entries)" {
  run grep 'SKIP' "$PROFILES_DIR/effort-profile-balanced.toon"
  assert_failure
}

@test "balanced: runs critique (step 1)" {
  run grep '1: Critique' "$PROFILES_DIR/effort-profile-balanced.toon"
  assert_success
  assert_output --partial 'run'
}

@test "balanced: runs security (step 10)" {
  run grep '10: Security' "$PROFILES_DIR/effort-profile-balanced.toon"
  assert_success
  assert_output --partial 'run'
}

@test "balanced: runs documentation (step 8.5)" {
  run grep '8.5: Documentation' "$PROFILES_DIR/effort-profile-balanced.toon"
  assert_success
  assert_output --partial 'run'
}

# --- Thorough step-skip rules (full + extra validation) ---

@test "thorough: runs all steps (no SKIP entries)" {
  run grep 'SKIP' "$PROFILES_DIR/effort-profile-thorough.toon"
  assert_failure
}

@test "thorough: code review has extra validation" {
  run grep '8: Code Review' "$PROFILES_DIR/effort-profile-thorough.toon"
  assert_success
  assert_output --partial 'extra validation'
}

@test "thorough: runs security (step 10)" {
  run grep '10: Security' "$PROFILES_DIR/effort-profile-thorough.toon"
  assert_success
  assert_output --partial 'run'
}

# --- Agent quality is always full ---

@test "turbo: agent_quality is full" {
  run grep 'agent_quality' "$PROFILES_DIR/effort-profile-turbo.toon"
  assert_success
  assert_output --partial 'full (always)'
}

@test "fast: agent_quality is full" {
  run grep 'agent_quality' "$PROFILES_DIR/effort-profile-fast.toon"
  assert_success
  assert_output --partial 'full (always)'
}

@test "balanced: agent_quality is full" {
  run grep 'agent_quality' "$PROFILES_DIR/effort-profile-balanced.toon"
  assert_success
  assert_output --partial 'full (always)'
}

@test "thorough: agent_quality is full" {
  run grep 'agent_quality' "$PROFILES_DIR/effort-profile-thorough.toon"
  assert_success
  assert_output --partial 'full (always)'
}

# --- Effort profiles use step_skips (not matrix) ---

@test "turbo: uses step_skips not matrix" {
  run grep 'step_skips:' "$PROFILES_DIR/effort-profile-turbo.toon"
  assert_success
  run grep '^matrix:' "$PROFILES_DIR/effort-profile-turbo.toon"
  assert_failure
}

@test "fast: uses step_skips not matrix" {
  run grep 'step_skips:' "$PROFILES_DIR/effort-profile-fast.toon"
  assert_success
  run grep '^matrix:' "$PROFILES_DIR/effort-profile-fast.toon"
  assert_failure
}

@test "balanced: uses step_skips not matrix" {
  run grep 'step_skips:' "$PROFILES_DIR/effort-profile-balanced.toon"
  assert_success
  run grep '^matrix:' "$PROFILES_DIR/effort-profile-balanced.toon"
  assert_failure
}

@test "thorough: uses step_skips not matrix" {
  run grep 'step_skips:' "$PROFILES_DIR/effort-profile-thorough.toon"
  assert_success
  run grep '^matrix:' "$PROFILES_DIR/effort-profile-thorough.toon"
  assert_failure
}

# --- go.md step-skip dispatch table exists ---

@test "go.md: contains step-skip dispatch table" {
  run grep 'Effort step-skip dispatch' "$GO_MD"
  assert_success
}

@test "go.md: dispatch table has turbo column" {
  run grep '| turbo |' "$GO_MD"
  assert_success
}

@test "go.md: dispatch table has all 4 effort levels" {
  run grep '| turbo | fast | balanced | thorough |' "$GO_MD"
  assert_success
}

# --- go.md effort cascading to agents ---

@test "go.md: contains effort level cascading section" {
  run grep 'Effort level cascading' "$GO_MD"
  assert_success
}

@test "go.md: cascading includes effort_level= in agent prompt" {
  run grep 'effort_level=' "$GO_MD"
  assert_success
}

@test "go.md: cascading notes agent quality is full" {
  run grep 'Execute your role at full quality' "$GO_MD"
  assert_success
}

# --- execute-protocol.md step-skip language ---

@test "execute-protocol.md: contains step-skip note" {
  run grep 'Effort level controls which steps execute, not how they execute' "$EXEC_PROTOCOL"
  assert_success
}

@test "execute-protocol.md: no per-agent effort degradation (DEV_EFFORT removed)" {
  run grep 'DEV_EFFORT' "$EXEC_PROTOCOL"
  assert_failure
}

@test "execute-protocol.md: uses effort_level= in Dev spawn" {
  run grep 'effort_level=' "$EXEC_PROTOCOL"
  assert_success
}

@test "execute-protocol.md: critique guard references step-skip" {
  run grep -A2 'Step 1: Critique' "$EXEC_PROTOCOL"
  assert_success
  run grep 'step-skip.*turbo' "$EXEC_PROTOCOL"
  assert_success
}

# --- No effort_mapping sections remain in profiles ---

@test "turbo: no effort_mapping section" {
  run grep 'effort_mapping:' "$PROFILES_DIR/effort-profile-turbo.toon"
  assert_failure
}

@test "fast: no effort_mapping section" {
  run grep 'effort_mapping:' "$PROFILES_DIR/effort-profile-fast.toon"
  assert_failure
}

@test "balanced: no effort_mapping section" {
  run grep 'effort_mapping:' "$PROFILES_DIR/effort-profile-balanced.toon"
  assert_failure
}

@test "thorough: no effort_mapping section" {
  run grep 'effort_mapping:' "$PROFILES_DIR/effort-profile-thorough.toon"
  assert_failure
}
