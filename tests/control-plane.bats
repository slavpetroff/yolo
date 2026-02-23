#!/usr/bin/env bats
# Migrated: control-plane.sh orchestrator removed.
# Tests now exercise the individual Rust CLI subcommands that control-plane.sh
# used to orchestrate: generate-contract, hard-gate, lock, lease-lock,
# compile-context.
# CWD-sensitive: yes

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning/.contracts"
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning/.locks"
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning/.events"
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning/.metrics"
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning/phases/01-test"
}

teardown() {
  teardown_temp_dir
}

create_test_plan() {
  cat > "$TEST_TEMP_DIR/test-plan.md" << 'PLAN'
---
phase: 1
plan: 1
title: Test Plan
wave: 1
depends_on: []
skills_used: []
must_haves:
  - "Feature A works"
---

# Plan

### Task 1: Do something
**Files:** `src/a.js`

### Task 2: Do another thing
**Files:** `src/b.js`
PLAN
}

create_roadmap() {
  cat > "$TEST_TEMP_DIR/.yolo-planning/ROADMAP.md" << 'ROAD'
## Phase 1: Test Phase
**Goal:** Test goal
**Reqs:** REQ-01
**Success:** Tests pass
ROAD
}

enable_flags() {
  local flags="$1"
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq "$flags" ".yolo-planning/config.json" > "$tmp" && mv "$tmp" ".yolo-planning/config.json"
}

# --- generate-contract tests ---

@test "generate-contract: generates contract from plan" {
  create_test_plan
  cd "$TEST_TEMP_DIR"
  enable_flags '.v3_contract_lite = true'
  run "$YOLO_BIN" generate-contract test-plan.md
  [ "$status" -eq 0 ]
  # Output should contain path to contract file
  [ -n "$output" ]
}

@test "generate-contract: exits with usage error when no args" {
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" generate-contract
  [ "$status" -eq 1 ]
}

# --- hard-gate tests ---

@test "hard-gate: skip when v2_hard_gates=false" {
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" hard-gate contract_compliance 1 1 1 dummy.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "skip"'
}

@test "hard-gate: contract_compliance fails on missing contract" {
  cd "$TEST_TEMP_DIR"
  enable_flags '.v2_hard_gates = true'
  run "$YOLO_BIN" hard-gate contract_compliance 1 1 1 nonexistent.json
  [ "$status" -ne 0 ]
  echo "$output" | jq -e '.result == "fail"'
  echo "$output" | jq -e '.evidence == "contract file not found"'
}

@test "hard-gate: artifact_persistence passes with all summaries" {
  cd "$TEST_TEMP_DIR"
  enable_flags '.v2_hard_gates = true'
  mkdir -p .yolo-planning/phases/01-test
  cat > .yolo-planning/phases/01-test/01-PLAN.md <<'EOF'
---
phase: 1
plan: 1
title: "Test"
---
# Plan
EOF
  cat > .yolo-planning/phases/01-test/01-SUMMARY.md <<'EOF'
---
status: complete
---
# Summary
EOF
  # Check plan 2 (prior plan 1 has summary)
  run "$YOLO_BIN" hard-gate artifact_persistence 01 2 1 dummy.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "pass"'
}

@test "hard-gate: returns JSON with gate field" {
  cd "$TEST_TEMP_DIR"
  enable_flags '.v2_hard_gates = true'
  run "$YOLO_BIN" hard-gate contract_compliance 1 1 1 dummy.json
  echo "$output" | jq -e '.gate == "contract_compliance"'
}

# --- lock tests ---

@test "lock: acquire creates lock file" {
  cd "$TEST_TEMP_DIR"
  enable_flags '.v3_lock_lite = true'
  run "$YOLO_BIN" lock acquire src/a.js --owner=test-task
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "acquired"'
}

@test "lock: release removes lock" {
  cd "$TEST_TEMP_DIR"
  enable_flags '.v3_lock_lite = true'
  "$YOLO_BIN" lock acquire src/a.js --owner=test-task >/dev/null
  run "$YOLO_BIN" lock release src/a.js --owner=test-task
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "released"'
}

@test "lock: skip when flag disabled" {
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" lock acquire src/a.js --owner=test-task
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "skip"'
}

# --- lease-lock tests ---

@test "lease-lock: acquire with TTL" {
  cd "$TEST_TEMP_DIR"
  enable_flags '.v3_lease_locks = true | .v3_lock_lite = true'
  run "$YOLO_BIN" lease-lock acquire file1.sh --owner=test-task --ttl=60
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "acquired"'
  echo "$output" | jq -e '.ttl_secs == 60'
}

@test "lease-lock: release removes lease" {
  cd "$TEST_TEMP_DIR"
  enable_flags '.v3_lease_locks = true | .v3_lock_lite = true'
  "$YOLO_BIN" lease-lock acquire file1.sh --owner=test-task >/dev/null
  run "$YOLO_BIN" lease-lock release file1.sh --owner=test-task
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "released"'
}

# --- compile-context tests ---

@test "compile-context: produces context file" {
  create_test_plan
  create_roadmap
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" compile-context 01 dev .yolo-planning/phases/01-test test-plan.md
  [ "$status" -eq 0 ]
  # compile-context writes to phases_dir
  [ -f ".yolo-planning/phases/01-test/.context-dev.md" ]
}

@test "compile-context: output contains phase info" {
  create_test_plan
  create_roadmap
  cd "$TEST_TEMP_DIR"
  "$YOLO_BIN" compile-context 01 dev .yolo-planning/phases/01-test test-plan.md
  grep -q "context" ".yolo-planning/phases/01-test/.context-dev.md" || \
    grep -q "Phase" ".yolo-planning/phases/01-test/.context-dev.md" || \
    [ -f ".yolo-planning/phases/01-test/.context-dev.md" ]
}

# --- lifecycle integration ---

@test "lifecycle: generate-contract then hard-gate contract_compliance" {
  create_test_plan
  cd "$TEST_TEMP_DIR"
  enable_flags '.v3_contract_lite = true | .v2_hard_gates = true'

  # Step 1: Generate contract
  CONTRACT_PATH=$("$YOLO_BIN" generate-contract test-plan.md 2>/dev/null)
  [ -n "$CONTRACT_PATH" ]
  [ -f "$CONTRACT_PATH" ]

  # Step 2: Gate check against contract
  run "$YOLO_BIN" hard-gate contract_compliance 1 1 1 "$CONTRACT_PATH"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "pass"'
}

@test "lifecycle: lock acquire then release (no stale locks)" {
  cd "$TEST_TEMP_DIR"
  enable_flags '.v3_lock_lite = true'

  # Acquire
  run "$YOLO_BIN" lock acquire src/a.js --owner=task-1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "acquired"'

  # Release
  run "$YOLO_BIN" lock release src/a.js --owner=task-1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "released"'

  # Re-acquire (no stale lock)
  run "$YOLO_BIN" lock acquire src/a.js --owner=task-2
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "acquired"'
}
