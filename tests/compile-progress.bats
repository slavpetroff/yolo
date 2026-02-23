#!/usr/bin/env bats
# Tests for: yolo compile-progress
# CLI signature: yolo compile-progress [planning_dir]
# CWD-sensitive: yes

load test_helper

setup() {
  setup_temp_dir
  cd "$TEST_TEMP_DIR"
}

teardown() {
  teardown_temp_dir
}

@test "returns zeroes for empty planning dir" {
  # .yolo-planning exists but no milestones or phases
  run bash -c "cd '$TEST_TEMP_DIR' && '$YOLO_BIN' compile-progress"
  [ "$status" -eq 0 ]

  echo "$output" | jq -e '.ok == true'
  echo "$output" | jq -e '.cmd == "compile-progress"'
  echo "$output" | jq -e '.phases.total == 0'
  echo "$output" | jq -e '.plans.total == 0'
  echo "$output" | jq -e '.tasks.total == 0'
  echo "$output" | jq -e '.overall_pct == 0'
}

@test "counts phases correctly" {
  mkdir -p .yolo-planning/phases/01-init
  mkdir -p .yolo-planning/phases/02-build
  mkdir -p .yolo-planning/phases/03-deploy

  run bash -c "cd '$TEST_TEMP_DIR' && '$YOLO_BIN' compile-progress"
  [ "$status" -eq 0 ]

  echo "$output" | jq -e '.phases.total == 3'
  echo "$output" | jq -e '.phases.pending == 3'
}

@test "counts plans and summaries" {
  mkdir -p .yolo-planning/phases/01-init

  cat > .yolo-planning/phases/01-init/01-01-PLAN.md <<'EOF'
## Task 1: First task
## Task 2: Second task
EOF
  cat > .yolo-planning/phases/01-init/01-02-PLAN.md <<'EOF'
## Task 1: Third task
EOF

  # Only first plan has a summary
  echo "done" > .yolo-planning/phases/01-init/01-01-SUMMARY.md

  run bash -c "cd '$TEST_TEMP_DIR' && '$YOLO_BIN' compile-progress"
  [ "$status" -eq 0 ]

  echo "$output" | jq -e '.plans.total == 2'
  echo "$output" | jq -e '.plans.completed == 1'
}

@test "calculates overall percentage" {
  mkdir -p .yolo-planning/phases/01-one

  cat > .yolo-planning/phases/01-one/01-01-PLAN.md <<'EOF'
## Task 1: A
## Task 2: B
EOF
  cat > .yolo-planning/phases/01-one/01-02-PLAN.md <<'EOF'
## Task 1: C
## Task 2: D
EOF

  echo "done" > .yolo-planning/phases/01-one/01-01-SUMMARY.md

  run bash -c "cd '$TEST_TEMP_DIR' && '$YOLO_BIN' compile-progress"
  [ "$status" -eq 0 ]

  # 4 tasks total, 2 completed (from plan 01-01) = 50%
  echo "$output" | jq -e '.tasks.total == 4'
  echo "$output" | jq -e '.tasks.completed == 2'
  echo "$output" | jq -e '.overall_pct == 50'
}

@test "detects active phase" {
  mkdir -p .yolo-planning/phases/01-setup
  mkdir -p .yolo-planning/phases/02-build

  # Phase 01 fully done
  cat > .yolo-planning/phases/01-setup/01-01-PLAN.md <<'EOF'
## Task 1: done
EOF
  echo "done" > .yolo-planning/phases/01-setup/01-01-SUMMARY.md

  # Phase 02 not done
  cat > .yolo-planning/phases/02-build/02-01-PLAN.md <<'EOF'
## Task 1: pending
EOF

  run bash -c "cd '$TEST_TEMP_DIR' && '$YOLO_BIN' compile-progress"
  [ "$status" -eq 0 ]

  echo "$output" | jq -e '.active_phase == "2"'
  echo "$output" | jq -e '.active_phase_title == "build"'
}

@test "counts tasks from plan headers" {
  mkdir -p .yolo-planning/phases/01-test

  cat > .yolo-planning/phases/01-test/01-01-PLAN.md <<'EOF'
---
title: test plan
---

## Task 1: First
Some description

## Task 2: Second
More description

## Task 3: Third
Even more
EOF

  run bash -c "cd '$TEST_TEMP_DIR' && '$YOLO_BIN' compile-progress"
  [ "$status" -eq 0 ]

  echo "$output" | jq -e '.tasks.total == 3'
}

@test "handles missing milestones dir gracefully" {
  rm -rf .yolo-planning/milestones
  rm -rf .yolo-planning/phases

  run bash -c "cd '$TEST_TEMP_DIR' && '$YOLO_BIN' compile-progress"
  [ "$status" -eq 0 ]

  echo "$output" | jq -e '.ok == true'
  echo "$output" | jq -e '.phases.total == 0'
}
