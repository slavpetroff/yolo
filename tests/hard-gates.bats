#!/usr/bin/env bats
# Migrated: hard-gate.sh -> yolo hard-gate
#           auto-repair.sh -> yolo auto-repair
# CWD-sensitive: yes

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning/.contracts"
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning/.events"
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning/.metrics"
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning/phases/01-test"

  # Enable V2 hard gates + contracts + events
  jq '.v2_hard_gates = true | .v2_hard_contracts = true | .v3_event_log = true' \
    "$TEST_TEMP_DIR/.yolo-planning/config.json" > "$TEST_TEMP_DIR/.yolo-planning/config.json.tmp" \
    && mv "$TEST_TEMP_DIR/.yolo-planning/config.json.tmp" "$TEST_TEMP_DIR/.yolo-planning/config.json"
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

# Generate a valid contract using the CLI (ensures matching hash)
generate_valid_contract() {
  create_plan_file
  cd "$TEST_TEMP_DIR"
  "$YOLO_BIN" generate-contract ".yolo-planning/phases/01-test/01-01-PLAN.md" >/dev/null
}

# --- yolo hard-gate tests ---

@test "gate: contract_compliance passes with valid contract" {
  generate_valid_contract
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" hard-gate contract_compliance 1 1 1 ".yolo-planning/.contracts/1-1.json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "pass"'
}

@test "gate: contract_compliance fails on tampered contract" {
  generate_valid_contract
  cd "$TEST_TEMP_DIR"
  # Tamper with contract (change task_count)
  jq '.task_count = 99' ".yolo-planning/.contracts/1-1.json" > ".yolo-planning/.contracts/1-1.json.tmp" \
    && mv ".yolo-planning/.contracts/1-1.json.tmp" ".yolo-planning/.contracts/1-1.json"
  run "$YOLO_BIN" hard-gate contract_compliance 1 1 1 ".yolo-planning/.contracts/1-1.json"
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.result == "fail"'
}

@test "gate: contract_compliance fails on task out of range" {
  generate_valid_contract
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" hard-gate contract_compliance 1 1 99 ".yolo-planning/.contracts/1-1.json"
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.result == "fail"'
}

@test "gate: contract_compliance fails on missing contract" {
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" hard-gate contract_compliance 1 1 1 ".yolo-planning/.contracts/nonexistent.json"
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.result == "fail"'
}

@test "gate: required_checks passes when checks succeed" {
  generate_valid_contract
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" hard-gate required_checks 1 1 1 ".yolo-planning/.contracts/1-1.json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "pass"'
}

@test "gate: required_checks fails when check command fails" {
  cd "$TEST_TEMP_DIR"
  # Create plan with failing verification_checks
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
verification_checks:
  - "false"
---

# Plan 01-01: Test Plan

### Task 1: Implement feature A
**Files:** `src/a.js`

### Task 2: Test feature A
**Files:** `tests/a.test.js`
PLAN
  "$YOLO_BIN" generate-contract ".yolo-planning/phases/01-test/01-01-PLAN.md" >/dev/null
  run "$YOLO_BIN" hard-gate required_checks 1 1 1 ".yolo-planning/.contracts/1-1.json"
  [ "$status" -eq 2 ]
  # CLI may print debug lines before JSON; extract last line
  echo "$output" | tail -1 | jq -e '.result == "fail"'
}

@test "gate: commit_hygiene returns pass" {
  cd "$TEST_TEMP_DIR"
  git init -q
  git config user.name "test" && git config user.email "test@test.com"
  echo "test" > file.txt
  git add file.txt && git commit -q -m "feat(test): valid commit"
  generate_valid_contract
  run "$YOLO_BIN" hard-gate commit_hygiene 1 1 1 ".yolo-planning/.contracts/1-1.json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "pass"'
}

@test "gate: skip when v2_hard_gates=false" {
  generate_valid_contract
  cd "$TEST_TEMP_DIR"
  jq '.v2_hard_gates = false' ".yolo-planning/config.json" > ".yolo-planning/config.json.tmp" \
    && mv ".yolo-planning/config.json.tmp" ".yolo-planning/config.json"
  run "$YOLO_BIN" hard-gate contract_compliance 1 1 1 ".yolo-planning/.contracts/1-1.json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "skip"'
}

@test "gate: JSON output format correct" {
  generate_valid_contract
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" hard-gate contract_compliance 1 1 1 ".yolo-planning/.contracts/1-1.json"
  [ "$status" -eq 0 ]
  # Verify all JSON fields present
  echo "$output" | jq -e '.gate == "contract_compliance"'
  echo "$output" | jq -e '.result'
  echo "$output" | jq -e '.evidence'
  echo "$output" | jq -e '.ts'
}

@test "gate: logs gate_passed event" {
  generate_valid_contract
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" hard-gate contract_compliance 1 1 1 ".yolo-planning/.contracts/1-1.json"
  [ "$status" -eq 0 ]
  [ -f ".yolo-planning/.events/event-log.jsonl" ]
  EVENT=$(tail -1 ".yolo-planning/.events/event-log.jsonl")
  echo "$EVENT" | jq -e '.event == "gate_passed"'
}

# --- yolo auto-repair tests ---

@test "auto-repair: non-repairable gate escalates immediately" {
  generate_valid_contract
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" auto-repair protected_file 1 1 1 ".yolo-planning/.contracts/1-1.json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.repaired == false'
  echo "$output" | jq -e '.attempts == 0'
  [[ "$output" == *"not repairable"* ]]
}

@test "auto-repair: repairable gate attempts max 2 retries" {
  generate_valid_contract
  cd "$TEST_TEMP_DIR"
  # Tamper with the contract
  jq '.task_count = 99' ".yolo-planning/.contracts/1-1.json" > ".yolo-planning/.contracts/1-1.json.tmp" \
    && mv ".yolo-planning/.contracts/1-1.json.tmp" ".yolo-planning/.contracts/1-1.json"
  run "$YOLO_BIN" auto-repair contract_compliance 1 1 1 ".yolo-planning/.contracts/1-1.json"
  [ "$status" -eq 0 ]
  # Should attempt repair (regenerate contract)
  ATTEMPTS=$(echo "$output" | jq -r '.attempts')
  [ "$ATTEMPTS" -le 2 ]
}

@test "auto-repair: skip when v2_hard_gates=false" {
  generate_valid_contract
  cd "$TEST_TEMP_DIR"
  jq '.v2_hard_gates = false' ".yolo-planning/config.json" > ".yolo-planning/config.json.tmp" \
    && mv ".yolo-planning/config.json.tmp" ".yolo-planning/config.json"
  run "$YOLO_BIN" auto-repair contract_compliance 1 1 1 ".yolo-planning/.contracts/1-1.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"v2_hard_gates=false"* ]]
}

@test "auto-repair: blocker event logged on final failure" {
  cd "$TEST_TEMP_DIR"
  # Create a tampered contract with no plan file -> repair can't regenerate
  generate_valid_contract
  jq '.task_count = 99' ".yolo-planning/.contracts/1-1.json" > ".yolo-planning/.contracts/1-1.json.tmp" \
    && mv ".yolo-planning/.contracts/1-1.json.tmp" ".yolo-planning/.contracts/1-1.json"
  # Remove plan file so auto-repair can't regenerate
  rm -f ".yolo-planning/phases/01-test/01-01-PLAN.md"
  "$YOLO_BIN" auto-repair contract_compliance 1 1 1 ".yolo-planning/.contracts/1-1.json" >/dev/null 2>&1
  [ -f ".yolo-planning/.events/event-log.jsonl" ]
  # Check for task_blocked event
  BLOCKED=$(grep 'task_blocked' ".yolo-planning/.events/event-log.jsonl" | tail -1)
  [ -n "$BLOCKED" ]
  echo "$BLOCKED" | jq -e '.data.owner == "lead"'
}
