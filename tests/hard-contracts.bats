#!/usr/bin/env bats
# Migrated: generate-contract.sh -> yolo generate-contract
#           validate-contract.sh -> internal (v2 hard validation tested here via generate + hard-gate)
#           contract-revision.sh -> yolo contract-revision
# CWD-sensitive: yes

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning/.contracts"
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning/.events"
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning/.metrics"
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning/phases/01-test"
}

teardown() {
  teardown_temp_dir
}

create_plan_file() {
  cat > "$TEST_TEMP_DIR/.yolo-planning/phases/01-test/01-01-PLAN.md" << 'PLAN'
---
phase: 1
plan: 1
title: Test Plan
wave: 1
depends_on: []
must_haves:
  - "Feature A works"
  - "Feature B passes tests"
forbidden_paths:
  - ".env"
  - "secrets/"
verification_checks:
  - "true"
---

# Plan 01-01: Test Plan

### Task 1: Implement feature A
**Files:** `src/a.js`

### Task 2: Implement feature B
**Files:** `src/b.js`, `tests/b.test.js`
PLAN
}

enable_v2_contracts() {
  jq '.v2_hard_contracts = true' "$TEST_TEMP_DIR/.yolo-planning/config.json" > "$TEST_TEMP_DIR/.yolo-planning/config.json.tmp" \
    && mv "$TEST_TEMP_DIR/.yolo-planning/config.json.tmp" "$TEST_TEMP_DIR/.yolo-planning/config.json"
}

enable_v3_lite() {
  jq '.v3_contract_lite = true' "$TEST_TEMP_DIR/.yolo-planning/config.json" > "$TEST_TEMP_DIR/.yolo-planning/config.json.tmp" \
    && mv "$TEST_TEMP_DIR/.yolo-planning/config.json.tmp" "$TEST_TEMP_DIR/.yolo-planning/config.json"
}

# --- generate-contract tests ---

@test "generate-contract: v2 hard emits all 11 fields + hash" {
  create_plan_file
  enable_v2_contracts
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" generate-contract ".yolo-planning/phases/01-test/01-01-PLAN.md"
  [ "$status" -eq 0 ]
  CONTRACT=".yolo-planning/.contracts/1-1.json"
  [ -f "$CONTRACT" ]
  # Check all fields present
  [ "$(jq -r '.phase_id' "$CONTRACT")" = "phase-1" ]
  [ "$(jq -r '.plan_id' "$CONTRACT")" = "phase-1-plan-1" ]
  [ "$(jq -r '.objective' "$CONTRACT")" = "Test Plan" ]
  [ "$(jq '.task_count' "$CONTRACT")" = "2" ]
  [ "$(jq '.task_ids | length' "$CONTRACT")" = "2" ]
  [ "$(jq '.allowed_paths | length' "$CONTRACT")" -ge 1 ]
  [ "$(jq '.forbidden_paths | length' "$CONTRACT")" = "2" ]
  [ "$(jq '.must_haves | length' "$CONTRACT")" = "2" ]
  [ "$(jq '.verification_checks | length' "$CONTRACT")" = "1" ]
  [ "$(jq '.max_token_budget' "$CONTRACT")" -gt 0 ]
  [ "$(jq '.timeout_seconds' "$CONTRACT")" -gt 0 ]
  # Hash present and non-empty
  HASH=$(jq -r '.contract_hash' "$CONTRACT")
  [ -n "$HASH" ]
  [ "$HASH" != "null" ]
}

@test "generate-contract: v3 lite emits 5 fields only" {
  create_plan_file
  enable_v3_lite
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" generate-contract ".yolo-planning/phases/01-test/01-01-PLAN.md"
  [ "$status" -eq 0 ]
  CONTRACT=".yolo-planning/.contracts/1-1.json"
  [ -f "$CONTRACT" ]
  # V3 lite: only 5 fields
  [ "$(jq -r '.phase' "$CONTRACT")" = "1" ]
  [ "$(jq -r '.plan' "$CONTRACT")" = "1" ]
  [ "$(jq '.task_count' "$CONTRACT")" = "2" ]
  # Should NOT have V2 fields
  [ "$(jq -r '.contract_hash // "missing"' "$CONTRACT")" = "missing" ]
  [ "$(jq -r '.phase_id // "missing"' "$CONTRACT")" = "missing" ]
}

@test "generate-contract: contract hash is deterministic" {
  create_plan_file
  enable_v2_contracts
  cd "$TEST_TEMP_DIR"
  "$YOLO_BIN" generate-contract ".yolo-planning/phases/01-test/01-01-PLAN.md" >/dev/null
  HASH1=$(jq -r '.contract_hash' ".yolo-planning/.contracts/1-1.json")
  # Regenerate
  "$YOLO_BIN" generate-contract ".yolo-planning/phases/01-test/01-01-PLAN.md" >/dev/null
  HASH2=$(jq -r '.contract_hash' ".yolo-planning/.contracts/1-1.json")
  [ "$HASH1" = "$HASH2" ]
}

@test "generate-contract: no flags enabled exits silently" {
  create_plan_file
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" generate-contract ".yolo-planning/phases/01-test/01-01-PLAN.md"
  [ "$status" -eq 0 ]
  [ ! -f ".yolo-planning/.contracts/1-1.json" ]
}

# --- hard-gate contract_compliance tests (replaces validate-contract.sh) ---

@test "hard-gate: contract_compliance passes with valid contract" {
  create_plan_file
  enable_v2_contracts
  jq '.v2_hard_gates = true | .v3_event_log = true' "$TEST_TEMP_DIR/.yolo-planning/config.json" > "$TEST_TEMP_DIR/.yolo-planning/config.json.tmp" \
    && mv "$TEST_TEMP_DIR/.yolo-planning/config.json.tmp" "$TEST_TEMP_DIR/.yolo-planning/config.json"
  cd "$TEST_TEMP_DIR"
  "$YOLO_BIN" generate-contract ".yolo-planning/phases/01-test/01-01-PLAN.md" >/dev/null
  CONTRACT=".yolo-planning/.contracts/1-1.json"
  run "$YOLO_BIN" hard-gate contract_compliance 1 1 1 "$CONTRACT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "pass"'
}

@test "hard-gate: hash mismatch hard stop" {
  create_plan_file
  enable_v2_contracts
  jq '.v2_hard_gates = true | .v3_event_log = true' "$TEST_TEMP_DIR/.yolo-planning/config.json" > "$TEST_TEMP_DIR/.yolo-planning/config.json.tmp" \
    && mv "$TEST_TEMP_DIR/.yolo-planning/config.json.tmp" "$TEST_TEMP_DIR/.yolo-planning/config.json"
  cd "$TEST_TEMP_DIR"
  "$YOLO_BIN" generate-contract ".yolo-planning/phases/01-test/01-01-PLAN.md" >/dev/null
  CONTRACT=".yolo-planning/.contracts/1-1.json"
  # Tamper with contract (change task_count)
  jq '.task_count = 99' "$CONTRACT" > "${CONTRACT}.tmp" && mv "${CONTRACT}.tmp" "$CONTRACT"
  run "$YOLO_BIN" hard-gate contract_compliance 1 1 1 "$CONTRACT"
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.result == "fail"'
}

@test "hard-gate: valid hash passes" {
  create_plan_file
  enable_v2_contracts
  jq '.v2_hard_gates = true | .v3_event_log = true' "$TEST_TEMP_DIR/.yolo-planning/config.json" > "$TEST_TEMP_DIR/.yolo-planning/config.json.tmp" \
    && mv "$TEST_TEMP_DIR/.yolo-planning/config.json.tmp" "$TEST_TEMP_DIR/.yolo-planning/config.json"
  cd "$TEST_TEMP_DIR"
  "$YOLO_BIN" generate-contract ".yolo-planning/phases/01-test/01-01-PLAN.md" >/dev/null
  CONTRACT=".yolo-planning/.contracts/1-1.json"
  run "$YOLO_BIN" hard-gate contract_compliance 1 1 1 "$CONTRACT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "pass"'
}

@test "hard-gate: v3 lite advisory only" {
  create_plan_file
  enable_v3_lite
  cd "$TEST_TEMP_DIR"
  "$YOLO_BIN" generate-contract ".yolo-planning/phases/01-test/01-01-PLAN.md" >/dev/null
  # No v2_hard_gates enabled — should skip
  run "$YOLO_BIN" hard-gate contract_compliance 1 1 1 ".yolo-planning/.contracts/1-1.json"
  [ "$status" -eq 0 ]
}

# --- contract-revision tests ---

@test "contract-revision: detects scope change and archives old" {
  create_plan_file
  enable_v2_contracts
  # Enable event log for revision events
  jq '.v3_event_log = true' "$TEST_TEMP_DIR/.yolo-planning/config.json" > "$TEST_TEMP_DIR/.yolo-planning/config.json.tmp" \
    && mv "$TEST_TEMP_DIR/.yolo-planning/config.json.tmp" "$TEST_TEMP_DIR/.yolo-planning/config.json"
  cd "$TEST_TEMP_DIR"
  "$YOLO_BIN" generate-contract ".yolo-planning/phases/01-test/01-01-PLAN.md" >/dev/null
  CONTRACT=".yolo-planning/.contracts/1-1.json"
  OLD_HASH=$(jq -r '.contract_hash' "$CONTRACT")

  # Modify plan (add a task)
  cat >> ".yolo-planning/phases/01-test/01-01-PLAN.md" << 'EXTRA'

### Task 3: Extra task
**Files:** `src/c.js`
EXTRA

  run "$YOLO_BIN" contract-revision "$CONTRACT" ".yolo-planning/phases/01-test/01-01-PLAN.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"revised:"* ]]
  # Old contract archived
  [ -f ".yolo-planning/.contracts/1-1.rev1.json" ]
  # New contract has different hash
  NEW_HASH=$(jq -r '.contract_hash' "$CONTRACT")
  [ "$OLD_HASH" != "$NEW_HASH" ]
}

@test "contract-revision: no change returns no_change" {
  create_plan_file
  enable_v2_contracts
  cd "$TEST_TEMP_DIR"
  "$YOLO_BIN" generate-contract ".yolo-planning/phases/01-test/01-01-PLAN.md" >/dev/null
  CONTRACT=".yolo-planning/.contracts/1-1.json"
  run "$YOLO_BIN" contract-revision "$CONTRACT" ".yolo-planning/phases/01-test/01-01-PLAN.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no_change"* ]]
}
