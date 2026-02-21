#!/usr/bin/env bats
# Migrated: assess-plan-risk.sh -> yolo assess-risk
#           resolve-gate-policy.sh -> yolo gate-policy
# CWD-sensitive: yes

load test_helper

setup() {
  setup_temp_dir
  create_test_config
}

teardown() {
  teardown_temp_dir
}

# --- yolo assess-risk tests ---

@test "assess-plan-risk returns low for small plan" {
  cat > "$TEST_TEMP_DIR/small-plan.md" <<'EOF'
---
phase: 1
plan: 1
title: "Small Plan"
wave: 1
depends_on: []
must_haves:
  - "One thing"
---

# Small Plan

## Tasks

### Task 1: Do something
- **Files:** `scripts/foo.sh`
- **Action:** Create foo.

### Task 2: Test it
- **Files:** `tests/foo.bats`
- **Action:** Add tests.
EOF

  run bash -c "cd '$TEST_TEMP_DIR' && '$YOLO_BIN' assess-risk '$TEST_TEMP_DIR/small-plan.md'"
  [ "$status" -eq 0 ]
  [ "$output" = "low" ]
}

@test "assess-plan-risk returns high for complex plan" {
  # 7 tasks, 10+ files, 5 must_haves, cross_phase_deps
  cat > "$TEST_TEMP_DIR/complex-plan.md" <<'EOF'
---
phase: 3
plan: 1
title: "Complex Plan"
wave: 1
depends_on: []
cross_phase_deps:
  - phase: 2
must_haves:
  - "Feature A"
  - "Feature B"
  - "Feature C"
  - "Feature D"
  - "Feature E"
---

# Complex Plan

## Tasks

### Task 1: A
- **Files:** `scripts/a.sh`, `scripts/b.sh`, `scripts/c.sh`

### Task 2: B
- **Files:** `scripts/d.sh`, `scripts/e.sh`

### Task 3: C
- **Files:** `config/f.json`, `config/g.json`

### Task 4: D
- **Files:** `tests/h.bats`, `tests/i.bats`

### Task 5: E
- **Files:** `references/j.md`

### Task 6: F
- **Files:** `commands/k.md`

### Task 7: G (extra)
- **Files:** No files.
EOF

  run bash -c "cd '$TEST_TEMP_DIR' && '$YOLO_BIN' assess-risk '$TEST_TEMP_DIR/complex-plan.md'"
  [ "$status" -eq 0 ]
  [ "$output" = "high" ]
}

@test "assess-plan-risk defaults to medium on missing file" {
  run bash -c "cd '$TEST_TEMP_DIR' && '$YOLO_BIN' assess-risk '$TEST_TEMP_DIR/nonexistent.md'"
  [ "$status" -eq 0 ]
  [ "$output" = "medium" ]
}

@test "assess-plan-risk defaults to medium with no arguments" {
  run bash -c "cd '$TEST_TEMP_DIR' && '$YOLO_BIN' assess-risk"
  [ "$status" -eq 0 ]
  [ "$output" = "medium" ]
}

# --- yolo gate-policy tests ---

@test "resolve-gate-policy returns skip QA for turbo" {
  run bash -c "cd '$TEST_TEMP_DIR' && '$YOLO_BIN' gate-policy turbo low standard"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.qa_tier == "skip"'
  echo "$output" | jq -e '.approval_required == false'
  echo "$output" | jq -e '.communication_level == "none"'
}

@test "resolve-gate-policy returns approval for high-risk balanced" {
  run bash -c "cd '$TEST_TEMP_DIR' && '$YOLO_BIN' gate-policy balanced high standard"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.approval_required == true'
  echo "$output" | jq -e '.two_phase == true'
  echo "$output" | jq -e '.qa_tier == "standard"'
}

@test "resolve-gate-policy no approval for confident at balanced" {
  run bash -c "cd '$TEST_TEMP_DIR' && '$YOLO_BIN' gate-policy balanced high confident"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.approval_required == false'
}

@test "resolve-gate-policy returns deep QA for thorough" {
  run bash -c "cd '$TEST_TEMP_DIR' && '$YOLO_BIN' gate-policy thorough medium cautious"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.qa_tier == "deep"'
  echo "$output" | jq -e '.approval_required == true'
  echo "$output" | jq -e '.communication_level == "full"'
}

@test "resolve-gate-policy returns quick QA for fast" {
  run bash -c "cd '$TEST_TEMP_DIR' && '$YOLO_BIN' gate-policy fast low standard"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.qa_tier == "quick"'
  echo "$output" | jq -e '.approval_required == false'
  echo "$output" | jq -e '.communication_level == "blockers"'
}

@test "resolve-gate-policy defaults gracefully with no args" {
  run bash -c "cd '$TEST_TEMP_DIR' && '$YOLO_BIN' gate-policy"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.qa_tier == "standard"'
}
