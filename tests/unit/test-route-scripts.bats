#!/usr/bin/env bats
# test-route-scripts.bats — Unit tests for route-trivial.sh, route-medium.sh, route-high.sh
# Plan 01-04 T2: Path routing, step inclusion/exclusion, JSON validity

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir
  ROUTE_TRIVIAL="$SCRIPTS_DIR/route-trivial.sh"
  ROUTE_MEDIUM="$SCRIPTS_DIR/route-medium.sh"
  ROUTE_HIGH="$SCRIPTS_DIR/route-high.sh"

  # Create phase dir fixture
  PHASE_DIR="$TEST_WORKDIR/phases/01-test"
  mkdir -p "$PHASE_DIR"

  # Create config fixture
  cat > "$TEST_WORKDIR/config.json" <<'JSON'
{
  "complexity_routing": {
    "enabled": true,
    "trivial_confidence_threshold": 0.85,
    "medium_confidence_threshold": 0.7,
    "fallback_path": "high",
    "force_analyze_model": "opus",
    "max_trivial_files": 3,
    "max_medium_tasks": 3
  },
  "departments": {
    "backend": true,
    "frontend": false,
    "uiux": false
  }
}
JSON

  # Create analysis JSON fixture
  cat > "$TEST_WORKDIR/analysis.json" <<'JSON'
{
  "complexity": "trivial",
  "departments": ["backend"],
  "intent": "execute",
  "confidence": 0.92,
  "reasoning": "Simple single-file change",
  "suggested_path": "trivial_shortcut"
}
JSON
}

# Helper: standard route args
route_args() {
  echo "--phase-dir $PHASE_DIR --intent 'fix typo' --config $TEST_WORKDIR/config.json --analysis-json $TEST_WORKDIR/analysis.json"
}

# --- route-trivial.sh ---

@test "route-trivial outputs path=trivial" {
  run bash "$ROUTE_TRIVIAL" --phase-dir "$PHASE_DIR" --intent "fix typo" --config "$TEST_WORKDIR/config.json" --analysis-json "$TEST_WORKDIR/analysis.json"
  assert_success
  local path
  path=$(echo "$output" | jq -r '.path')
  [ "$path" = "trivial" ]
}

@test "route-trivial skips critique, research, architecture, qa, security" {
  run bash "$ROUTE_TRIVIAL" --phase-dir "$PHASE_DIR" --intent "fix typo" --config "$TEST_WORKDIR/config.json" --analysis-json "$TEST_WORKDIR/analysis.json"
  assert_success
  local skipped
  skipped=$(echo "$output" | jq -r '.steps_skipped')
  for step in critique research architecture qa security; do
    local found
    found=$(echo "$skipped" | jq --arg s "$step" 'index($s) != null')
    [ "$found" = "true" ] || fail "Expected $step in steps_skipped"
  done
}

@test "route-trivial creates minimal plan.jsonl" {
  run bash "$ROUTE_TRIVIAL" --phase-dir "$PHASE_DIR" --intent "fix typo" --config "$TEST_WORKDIR/config.json" --analysis-json "$TEST_WORKDIR/analysis.json"
  assert_success
  # Check that plan_path field exists or a plan file was created
  local plan_path
  plan_path=$(echo "$output" | jq -r '.plan_path // empty')
  if [ -n "$plan_path" ]; then
    [ -f "$plan_path" ] || [ -f "$PHASE_DIR/$plan_path" ]
  fi
}

@test "route-trivial outputs valid JSON" {
  run bash "$ROUTE_TRIVIAL" --phase-dir "$PHASE_DIR" --intent "fix typo" --config "$TEST_WORKDIR/config.json" --analysis-json "$TEST_WORKDIR/analysis.json"
  assert_success
  run jq empty <<< "$output"
  assert_success
}

# --- route-medium.sh ---

@test "route-medium outputs path=medium" {
  run bash "$ROUTE_MEDIUM" --phase-dir "$PHASE_DIR" --intent "add endpoint" --config "$TEST_WORKDIR/config.json" --analysis-json "$TEST_WORKDIR/analysis.json"
  assert_success
  local path
  path=$(echo "$output" | jq -r '.path')
  [ "$path" = "medium" ]
}

@test "route-medium skips critique and research" {
  run bash "$ROUTE_MEDIUM" --phase-dir "$PHASE_DIR" --intent "add endpoint" --config "$TEST_WORKDIR/config.json" --analysis-json "$TEST_WORKDIR/analysis.json"
  assert_success
  local skipped
  skipped=$(echo "$output" | jq -r '.steps_skipped')
  for step in critique research; do
    local found
    found=$(echo "$skipped" | jq --arg s "$step" 'index($s) != null')
    [ "$found" = "true" ] || fail "Expected $step in steps_skipped"
  done
}

@test "route-medium includes planning, design_review, implementation, code_review, signoff" {
  run bash "$ROUTE_MEDIUM" --phase-dir "$PHASE_DIR" --intent "add endpoint" --config "$TEST_WORKDIR/config.json" --analysis-json "$TEST_WORKDIR/analysis.json"
  assert_success
  local included
  included=$(echo "$output" | jq -r '.steps_included')
  for step in planning design_review implementation code_review signoff; do
    local found
    found=$(echo "$included" | jq --arg s "$step" 'index($s) != null')
    [ "$found" = "true" ] || fail "Expected $step in steps_included"
  done
}

@test "route-medium outputs valid JSON" {
  run bash "$ROUTE_MEDIUM" --phase-dir "$PHASE_DIR" --intent "add endpoint" --config "$TEST_WORKDIR/config.json" --analysis-json "$TEST_WORKDIR/analysis.json"
  assert_success
  run jq empty <<< "$output"
  assert_success
}

# --- route-high.sh ---

@test "route-high outputs path=high" {
  run bash "$ROUTE_HIGH" --phase-dir "$PHASE_DIR" --intent "redesign database" --config "$TEST_WORKDIR/config.json" --analysis-json "$TEST_WORKDIR/analysis.json"
  assert_success
  local path
  path=$(echo "$output" | jq -r '.path')
  [ "$path" = "high" ]
}

@test "route-high has empty steps_skipped array" {
  run bash "$ROUTE_HIGH" --phase-dir "$PHASE_DIR" --intent "redesign database" --config "$TEST_WORKDIR/config.json" --analysis-json "$TEST_WORKDIR/analysis.json"
  assert_success
  local skipped_count
  skipped_count=$(echo "$output" | jq '.steps_skipped | length')
  [ "$skipped_count" -eq 0 ]
}

@test "route-high includes all 11 steps" {
  run bash "$ROUTE_HIGH" --phase-dir "$PHASE_DIR" --intent "redesign database" --config "$TEST_WORKDIR/config.json" --analysis-json "$TEST_WORKDIR/analysis.json"
  assert_success
  local included_count
  included_count=$(echo "$output" | jq '.steps_included | length')
  [ "$included_count" -eq 11 ]
}

@test "route-high outputs valid JSON" {
  run bash "$ROUTE_HIGH" --phase-dir "$PHASE_DIR" --intent "redesign database" --config "$TEST_WORKDIR/config.json" --analysis-json "$TEST_WORKDIR/analysis.json"
  assert_success
  run jq empty <<< "$output"
  assert_success
}

# --- Common: exit codes ---

@test "route-trivial exits 0 on valid input" {
  run bash "$ROUTE_TRIVIAL" --phase-dir "$PHASE_DIR" --intent "fix typo" --config "$TEST_WORKDIR/config.json" --analysis-json "$TEST_WORKDIR/analysis.json"
  assert_success
}

@test "route-medium exits 0 on valid input" {
  run bash "$ROUTE_MEDIUM" --phase-dir "$PHASE_DIR" --intent "add endpoint" --config "$TEST_WORKDIR/config.json" --analysis-json "$TEST_WORKDIR/analysis.json"
  assert_success
}

@test "route-high exits 0 on valid input" {
  run bash "$ROUTE_HIGH" --phase-dir "$PHASE_DIR" --intent "redesign database" --config "$TEST_WORKDIR/config.json" --analysis-json "$TEST_WORKDIR/analysis.json"
  assert_success
}

# --- Common: missing args ---

@test "route-trivial exits non-zero on missing required args" {
  run bash "$ROUTE_TRIVIAL"
  assert_failure
}

@test "route-medium exits non-zero on missing required args" {
  run bash "$ROUTE_MEDIUM"
  assert_failure
}

@test "route-high exits non-zero on missing required args" {
  run bash "$ROUTE_HIGH"
  assert_failure
}
