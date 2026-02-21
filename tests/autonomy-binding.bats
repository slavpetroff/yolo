#!/usr/bin/env bats
# Migrated: hard-gate.sh -> yolo hard-gate
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

@test "hard-gate: includes autonomy field in pass output" {
  cd "$TEST_TEMP_DIR"
  jq '.v2_hard_gates = true | .v2_hard_contracts = true | .v3_event_log = true' \
    .yolo-planning/config.json > .yolo-planning/config.json.tmp \
    && mv .yolo-planning/config.json.tmp .yolo-planning/config.json
  create_plan_file
  "$YOLO_BIN" generate-contract ".yolo-planning/phases/01-test/01-01-PLAN.md" >/dev/null
  run "$YOLO_BIN" hard-gate contract_compliance 1 1 1 ".yolo-planning/.contracts/1-1.json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.autonomy'
  AUTONOMY=$(echo "$output" | jq -r '.autonomy')
  [ "$AUTONOMY" = "standard" ]
}

@test "hard-gate: includes autonomy field in skip output" {
  cd "$TEST_TEMP_DIR"
  # v2_hard_gates defaults to false
  run "$YOLO_BIN" hard-gate contract_compliance 1 1 1 /dev/null
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.autonomy'
  echo "$output" | jq -e '.result == "skip"'
}

@test "hard-gate: autonomy value matches config" {
  cd "$TEST_TEMP_DIR"
  jq '.v2_hard_gates = true | .v2_hard_contracts = true | .v3_event_log = true | .autonomy = "yolo"' \
    .yolo-planning/config.json > .yolo-planning/config.json.tmp \
    && mv .yolo-planning/config.json.tmp .yolo-planning/config.json
  create_plan_file
  "$YOLO_BIN" generate-contract ".yolo-planning/phases/01-test/01-01-PLAN.md" >/dev/null
  run "$YOLO_BIN" hard-gate contract_compliance 1 1 1 ".yolo-planning/.contracts/1-1.json"
  [ "$status" -eq 0 ]
  AUTONOMY=$(echo "$output" | jq -r '.autonomy')
  [ "$AUTONOMY" = "yolo" ]
}

@test "hard-gate: gate fires regardless of autonomy=yolo" {
  cd "$TEST_TEMP_DIR"
  jq '.v2_hard_gates = true | .v2_hard_contracts = true | .v3_event_log = true | .autonomy = "yolo"' \
    .yolo-planning/config.json > .yolo-planning/config.json.tmp \
    && mv .yolo-planning/config.json.tmp .yolo-planning/config.json
  # Create contract with wrong hash to trigger failure
  cat > "$TEST_TEMP_DIR/.yolo-planning/.contracts/1-1.json" << 'CONTRACT'
{
  "phase_id": "phase-1",
  "plan_id": "phase-1-plan-1",
  "phase": 1,
  "plan": 1,
  "objective": "Test",
  "task_ids": ["1-1-T1"],
  "task_count": 1,
  "allowed_paths": [],
  "forbidden_paths": [],
  "depends_on": [],
  "must_haves": [],
  "verification_checks": [],
  "max_token_budget": 50000,
  "timeout_seconds": 600,
  "contract_hash": "tampered_hash_value"
}
CONTRACT
  run "$YOLO_BIN" hard-gate contract_compliance 1 1 1 "$TEST_TEMP_DIR/.yolo-planning/.contracts/1-1.json"
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.result == "fail"'
  echo "$output" | jq -e '.autonomy == "yolo"'
}
