#!/usr/bin/env bats
# Migrated: generate-contract.sh -> yolo generate-contract
#           validate-contract.sh -> internal (no standalone CLI; tested via hard-contracts)
# CWD-sensitive: yes

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning/phases/03-test-phase"

  # Create a sample PLAN.md
  cat > "$TEST_TEMP_DIR/.yolo-planning/phases/03-test-phase/03-01-PLAN.md" <<'EOF'
---
phase: 3
plan: 1
title: "Test Plan"
wave: 1
depends_on: []
must_haves:
  - "Feature A implemented"
  - "Feature B tested"
---

# Plan 03-01: Test Plan

## Tasks

### Task 1: Implement feature A
- **Files:** `scripts/feature-a.sh`, `config/settings.json`
- **Action:** Create feature A.

### Task 2: Test feature B
- **Files:** `tests/feature-b.bats`
- **Action:** Add tests.
EOF
}

teardown() {
  teardown_temp_dir
}

@test "generate-contract exits 0 when v3_contract_lite=false" {
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" generate-contract ".yolo-planning/phases/03-test-phase/03-01-PLAN.md"
  [ "$status" -eq 0 ]
  [ ! -d ".yolo-planning/.contracts" ]
}

@test "generate-contract creates contract JSON when flag=true" {
  cd "$TEST_TEMP_DIR"
  jq '.v3_contract_lite = true' ".yolo-planning/config.json" > ".yolo-planning/config.tmp" && mv ".yolo-planning/config.tmp" ".yolo-planning/config.json"

  run "$YOLO_BIN" generate-contract ".yolo-planning/phases/03-test-phase/03-01-PLAN.md"
  [ "$status" -eq 0 ]
  [ -f ".yolo-planning/.contracts/3-1.json" ]
}

@test "generate-contract contract has correct must_haves" {
  cd "$TEST_TEMP_DIR"
  jq '.v3_contract_lite = true' ".yolo-planning/config.json" > ".yolo-planning/config.tmp" && mv ".yolo-planning/config.tmp" ".yolo-planning/config.json"

  "$YOLO_BIN" generate-contract ".yolo-planning/phases/03-test-phase/03-01-PLAN.md"

  run jq -r '.must_haves | length' ".yolo-planning/.contracts/3-1.json"
  [ "$output" = "2" ]

  run jq -r '.must_haves[0]' ".yolo-planning/.contracts/3-1.json"
  [ "$output" = "Feature A implemented" ]
}

@test "generate-contract contract has allowed_paths from task Files" {
  cd "$TEST_TEMP_DIR"
  jq '.v3_contract_lite = true' ".yolo-planning/config.json" > ".yolo-planning/config.tmp" && mv ".yolo-planning/config.tmp" ".yolo-planning/config.json"

  "$YOLO_BIN" generate-contract ".yolo-planning/phases/03-test-phase/03-01-PLAN.md"

  # Should include files from both tasks
  run jq -r '.allowed_paths | length' ".yolo-planning/.contracts/3-1.json"
  [ "$output" -ge 3 ]

  run jq -r '.allowed_paths[]' ".yolo-planning/.contracts/3-1.json"
  echo "$output" | grep -q "scripts/feature-a.sh"
  echo "$output" | grep -q "config/settings.json"
  echo "$output" | grep -q "tests/feature-b.bats"
}

@test "generate-contract contract has correct task_count" {
  cd "$TEST_TEMP_DIR"
  jq '.v3_contract_lite = true' ".yolo-planning/config.json" > ".yolo-planning/config.tmp" && mv ".yolo-planning/config.tmp" ".yolo-planning/config.json"

  "$YOLO_BIN" generate-contract ".yolo-planning/phases/03-test-phase/03-01-PLAN.md"

  run jq -r '.task_count' ".yolo-planning/.contracts/3-1.json"
  [ "$output" = "2" ]
}

@test "generate-contract v3 lite contract has correct phase and plan fields" {
  cd "$TEST_TEMP_DIR"
  jq '.v3_contract_lite = true' ".yolo-planning/config.json" > ".yolo-planning/config.tmp" && mv ".yolo-planning/config.tmp" ".yolo-planning/config.json"

  "$YOLO_BIN" generate-contract ".yolo-planning/phases/03-test-phase/03-01-PLAN.md"

  run jq -r '.phase' ".yolo-planning/.contracts/3-1.json"
  [ "$output" = "3" ]

  run jq -r '.plan' ".yolo-planning/.contracts/3-1.json"
  [ "$output" = "1" ]
}

@test "generate-contract v3 lite does not include v2 fields" {
  cd "$TEST_TEMP_DIR"
  jq '.v3_contract_lite = true' ".yolo-planning/config.json" > ".yolo-planning/config.tmp" && mv ".yolo-planning/config.tmp" ".yolo-planning/config.json"

  "$YOLO_BIN" generate-contract ".yolo-planning/phases/03-test-phase/03-01-PLAN.md"

  run jq -r '.contract_hash // "missing"' ".yolo-planning/.contracts/3-1.json"
  [ "$output" = "missing" ]
}

@test "generate-contract with v2_hard_contracts creates hash" {
  cd "$TEST_TEMP_DIR"
  jq '.v2_hard_contracts = true' ".yolo-planning/config.json" > ".yolo-planning/config.tmp" && mv ".yolo-planning/config.tmp" ".yolo-planning/config.json"

  "$YOLO_BIN" generate-contract ".yolo-planning/phases/03-test-phase/03-01-PLAN.md"
  [ -f ".yolo-planning/.contracts/3-1.json" ]

  HASH=$(jq -r '.contract_hash' ".yolo-planning/.contracts/3-1.json")
  [ -n "$HASH" ]
  [ "$HASH" != "null" ]
  [ "$HASH" != "missing" ]
}

@test "generate-contract hash is deterministic" {
  cd "$TEST_TEMP_DIR"
  jq '.v2_hard_contracts = true' ".yolo-planning/config.json" > ".yolo-planning/config.tmp" && mv ".yolo-planning/config.tmp" ".yolo-planning/config.json"

  "$YOLO_BIN" generate-contract ".yolo-planning/phases/03-test-phase/03-01-PLAN.md"
  HASH1=$(jq -r '.contract_hash' ".yolo-planning/.contracts/3-1.json")
  # Regenerate
  "$YOLO_BIN" generate-contract ".yolo-planning/phases/03-test-phase/03-01-PLAN.md"
  HASH2=$(jq -r '.contract_hash' ".yolo-planning/.contracts/3-1.json")
  [ "$HASH1" = "$HASH2" ]
}

@test "generate-contract no flags enabled exits silently" {
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" generate-contract ".yolo-planning/phases/03-test-phase/03-01-PLAN.md"
  [ "$status" -eq 0 ]
  [ ! -f ".yolo-planning/.contracts/3-1.json" ]
}
