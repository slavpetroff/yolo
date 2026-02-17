#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
}

teardown() {
  teardown_temp_dir
}

@test "compile-rolling-summary.sh exists and is executable" {
  [ -f "$SCRIPTS_DIR/compile-rolling-summary.sh" ]
  [ -x "$SCRIPTS_DIR/compile-rolling-summary.sh" ]
}

@test "empty phases dir produces minimal header and exits 0" {
  mkdir -p "$TEST_TEMP_DIR/phases"
  OUTPUT="$TEST_TEMP_DIR/ROLLING-CONTEXT.md"
  run bash "$SCRIPTS_DIR/compile-rolling-summary.sh" "$TEST_TEMP_DIR/phases" "$OUTPUT"
  [ "$status" -eq 0 ]
  grep -q "Rolling Context" "$OUTPUT"
}

@test "single completed SUMMARY.md produces no-op minimal header" {
  mkdir -p "$TEST_TEMP_DIR/phases/01-test-phase"
  cat > "$TEST_TEMP_DIR/phases/01-test-phase/01-01-SUMMARY.md" <<'SUMMARY'
---
phase: 1
plan: 1
title: "Test Plan"
status: complete
deviations: 0
commit_hashes: ["abc1234"]
tasks_completed: 2
tasks_total: 2
---
# Summary
## What Was Built
Implemented feature X.
## Files Modified
- scripts/foo.sh
## Deviations
None.
SUMMARY
  OUTPUT="$TEST_TEMP_DIR/ROLLING-CONTEXT.md"
  run bash "$SCRIPTS_DIR/compile-rolling-summary.sh" "$TEST_TEMP_DIR/phases" "$OUTPUT"
  [ "$status" -eq 0 ]
  grep -q "No prior completed phases" "$OUTPUT"
}

@test "multi-phase: only status=complete summaries are included" {
  mkdir -p "$TEST_TEMP_DIR/phases/01-phase-one"
  mkdir -p "$TEST_TEMP_DIR/phases/02-phase-two"
  mkdir -p "$TEST_TEMP_DIR/phases/03-phase-three"
  cat > "$TEST_TEMP_DIR/phases/01-phase-one/01-01-SUMMARY.md" <<'SUMMARY'
---
phase: 1
plan: 1
title: "Phase One Plan"
status: complete
deviations: 0
commit_hashes: ["abc1234"]
tasks_completed: 2
tasks_total: 2
---
## What Was Built
Feature A.
## Files Modified
- scripts/a.sh
SUMMARY
  cat > "$TEST_TEMP_DIR/phases/02-phase-two/02-01-SUMMARY.md" <<'SUMMARY'
---
phase: 2
plan: 1
title: "Phase Two Plan"
status: complete
deviations: 0
commit_hashes: ["def5678"]
tasks_completed: 3
tasks_total: 3
---
## What Was Built
Feature B.
## Files Modified
- scripts/b.sh
SUMMARY
  cat > "$TEST_TEMP_DIR/phases/03-phase-three/03-01-SUMMARY.md" <<'SUMMARY'
---
phase: 3
plan: 1
title: "Phase Three Plan"
status: failed
deviations: 1
commit_hashes: []
tasks_completed: 0
tasks_total: 2
---
## What Was Built
Nothing (failed).
## Files Modified
SUMMARY
  OUTPUT="$TEST_TEMP_DIR/ROLLING-CONTEXT.md"
  run bash "$SCRIPTS_DIR/compile-rolling-summary.sh" "$TEST_TEMP_DIR/phases" "$OUTPUT"
  [ "$status" -eq 0 ]
  grep -q "Phase 1" "$OUTPUT"
  grep -q "Phase 2" "$OUTPUT"
  ! grep -q "Phase Three Plan" "$OUTPUT"
}

@test "multi-phase aggregation includes phase title and files" {
  mkdir -p "$TEST_TEMP_DIR/phases/01-phase-one"
  mkdir -p "$TEST_TEMP_DIR/phases/02-phase-two"
  cat > "$TEST_TEMP_DIR/phases/01-phase-one/01-01-SUMMARY.md" <<'SUMMARY'
---
phase: 1
plan: 1
title: "Phase One Plan"
status: complete
deviations: 0
commit_hashes: ["abc1234"]
tasks_completed: 2
tasks_total: 2
---
## What Was Built
Feature A built.
## Files Modified
- scripts/a.sh
SUMMARY
  cat > "$TEST_TEMP_DIR/phases/02-phase-two/02-01-SUMMARY.md" <<'SUMMARY'
---
phase: 2
plan: 1
title: "Phase Two Plan"
status: complete
deviations: 0
commit_hashes: ["def5678"]
tasks_completed: 3
tasks_total: 3
---
## What Was Built
Feature B built.
## Files Modified
- scripts/b.sh
SUMMARY
  OUTPUT="$TEST_TEMP_DIR/ROLLING-CONTEXT.md"
  run bash "$SCRIPTS_DIR/compile-rolling-summary.sh" "$TEST_TEMP_DIR/phases" "$OUTPUT"
  [ "$status" -eq 0 ]
  grep -q "Phase One Plan" "$OUTPUT"
  grep -q "Phase Two Plan" "$OUTPUT"
  grep -q "scripts/a.sh" "$OUTPUT"
}

@test "output is capped at 200 lines" {
  for i in $(seq 1 10); do
    PHASE_DIR="$TEST_TEMP_DIR/phases/$(printf '%02d' "$i")-phase-$i"
    mkdir -p "$PHASE_DIR"
    {
      echo "---"
      echo "phase: $i"
      echo "plan: 1"
      echo "title: \"Phase $i Plan\""
      echo "status: complete"
      echo "deviations: 0"
      echo "commit_hashes: [\"abc$i\"]"
      echo "tasks_completed: 5"
      echo "tasks_total: 5"
      echo "---"
      echo "## What Was Built"
      for j in $(seq 1 25); do
        echo "- Implemented item $j for phase $i"
      done
      echo "## Files Modified"
      for j in $(seq 1 10); do
        echo "- scripts/phase${i}/file${j}.sh"
      done
    } > "$PHASE_DIR/$(printf '%02d' "$i")-01-SUMMARY.md"
  done
  OUTPUT="$TEST_TEMP_DIR/ROLLING-CONTEXT.md"
  run bash "$SCRIPTS_DIR/compile-rolling-summary.sh" "$TEST_TEMP_DIR/phases" "$OUTPUT"
  [ "$status" -eq 0 ]
  LINE_COUNT=$(wc -l < "$OUTPUT" | tr -d ' ')
  [ "$LINE_COUNT" -le 200 ]
}

@test "partial/failed phases (status != complete) are skipped" {
  mkdir -p "$TEST_TEMP_DIR/phases/01-phase-one"
  mkdir -p "$TEST_TEMP_DIR/phases/02-phase-two"
  mkdir -p "$TEST_TEMP_DIR/phases/03-phase-three"
  cat > "$TEST_TEMP_DIR/phases/01-phase-one/01-01-SUMMARY.md" <<'SUMMARY'
---
phase: 1
plan: 1
title: "Failed Phase"
status: failed
deviations: 1
commit_hashes: []
tasks_completed: 0
tasks_total: 2
---
## What Was Built
Nothing.
## Files Modified
SUMMARY
  cat > "$TEST_TEMP_DIR/phases/02-phase-two/02-01-SUMMARY.md" <<'SUMMARY'
---
phase: 2
plan: 1
title: "Running Phase"
status: running
deviations: 0
commit_hashes: []
tasks_completed: 1
tasks_total: 3
---
## What Was Built
Partial work.
## Files Modified
- scripts/partial.sh
SUMMARY
  cat > "$TEST_TEMP_DIR/phases/03-phase-three/03-01-SUMMARY.md" <<'SUMMARY'
---
phase: 3
plan: 1
title: "Complete Phase"
status: complete
deviations: 0
commit_hashes: ["abc1234"]
tasks_completed: 2
tasks_total: 2
---
## What Was Built
Feature C.
## Files Modified
- scripts/c.sh
SUMMARY
  OUTPUT="$TEST_TEMP_DIR/ROLLING-CONTEXT.md"
  run bash "$SCRIPTS_DIR/compile-rolling-summary.sh" "$TEST_TEMP_DIR/phases" "$OUTPUT"
  [ "$status" -eq 0 ]
  ! grep -q "Failed Phase" "$OUTPUT"
  ! grep -q "Running Phase" "$OUTPUT"
  grep -q "Complete Phase" "$OUTPUT"
}
