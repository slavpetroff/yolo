#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning/phases/02-test-phase"
  cat > "$TEST_TEMP_DIR/.yolo-planning/ROADMAP.md" <<'EOF'
# Test Roadmap
## Phase 2: Test Phase
**Goal:** Test goal
EOF
}

teardown() {
  teardown_temp_dir
}

@test "collect-metrics.sh creates .metrics dir" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/collect-metrics.sh" cache_hit 2 1 role=dev
  [ "$status" -eq 0 ]
  [ -d ".yolo-planning/.metrics" ]
}

@test "collect-metrics.sh appends valid JSONL" {
  cd "$TEST_TEMP_DIR"
  bash "$SCRIPTS_DIR/collect-metrics.sh" cache_hit 2 1 role=dev
  bash "$SCRIPTS_DIR/collect-metrics.sh" compile_context 2 role=lead duration_ms=100

  # Should have 2 lines
  LINE_COUNT=$(wc -l < ".yolo-planning/.metrics/run-metrics.jsonl" | tr -d ' ')
  [ "$LINE_COUNT" -eq 2 ]

  # Each line should be valid JSON
  while IFS= read -r line; do
    echo "$line" | jq -e '.' >/dev/null 2>&1
  done < ".yolo-planning/.metrics/run-metrics.jsonl"
}

@test "collect-metrics.sh includes key=value data pairs" {
  cd "$TEST_TEMP_DIR"
  bash "$SCRIPTS_DIR/collect-metrics.sh" compile_context 2 role=dev duration_ms=50 delta_files=3
  run jq -r '.data.role' ".yolo-planning/.metrics/run-metrics.jsonl"
  [ "$output" = "dev" ]
  run jq -r '.data.delta_files' ".yolo-planning/.metrics/run-metrics.jsonl"
  [ "$output" = "3" ]
}

@test "compile-context.sh emits metrics when v3_metrics=true" {
  cd "$TEST_TEMP_DIR"
  jq '.v3_metrics = true' ".yolo-planning/config.json" > ".yolo-planning/config.tmp" && mv ".yolo-planning/config.tmp" ".yolo-planning/config.json"

  cat > ".yolo-planning/phases/02-test-phase/02-01-PLAN.md" <<'EOF'
---
phase: 2
plan: 1
title: "Test"
wave: 1
depends_on: []
must_haves: ["test"]
---
# Test
EOF

  bash "$SCRIPTS_DIR/compile-context.sh" 02 dev ".yolo-planning/phases" ".yolo-planning/phases/02-test-phase/02-01-PLAN.md"
  [ -f ".yolo-planning/.metrics/run-metrics.jsonl" ]
  grep -q "compile_context" ".yolo-planning/.metrics/run-metrics.jsonl"
}

@test "compile-context.sh skips metrics when v3_metrics=false" {
  cd "$TEST_TEMP_DIR"

  cat > ".yolo-planning/phases/02-test-phase/02-01-PLAN.md" <<'EOF'
---
phase: 2
plan: 1
title: "Test"
wave: 1
depends_on: []
must_haves: ["test"]
---
# Test
EOF

  bash "$SCRIPTS_DIR/compile-context.sh" 02 dev ".yolo-planning/phases" ".yolo-planning/phases/02-test-phase/02-01-PLAN.md"
  [ ! -d ".yolo-planning/.metrics" ]
}
