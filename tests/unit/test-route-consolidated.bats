#!/usr/bin/env bats
# test-route-consolidated.bats — Unit tests for consolidated route.sh and lib/yolo-common.sh
# Plan 09-01 T3

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir
  ROUTE_SH="$SCRIPTS_DIR/route.sh"
  COMMON_LIB="$PROJECT_ROOT/lib/yolo-common.sh"

  # Create phase dir fixture
  PHASE_DIR="$TEST_WORKDIR/phases/01-test"
  mkdir -p "$PHASE_DIR"

  # Create config fixture
  cat > "$TEST_WORKDIR/config.json" <<'JSON'
{
  "complexity_routing": { "enabled": true },
  "departments": { "backend": true, "frontend": false, "uiux": false }
}
JSON

  # Create analysis JSON fixture (single dept)
  cat > "$TEST_WORKDIR/analysis.json" <<'JSON'
{
  "complexity": "trivial",
  "departments": ["backend"],
  "intent": "execute",
  "confidence": 0.92
}
JSON

  # Create multi-dept analysis fixture
  cat > "$TEST_WORKDIR/analysis-multi.json" <<'JSON'
{
  "complexity": "high",
  "departments": ["backend", "frontend"],
  "intent": "execute",
  "confidence": 0.95
}
JSON
}

# ============================================================
# lib/yolo-common.sh tests
# ============================================================

@test "yolo-common.sh loads without error" {
  run bash -c "source '$COMMON_LIB'"
  assert_success
}

@test "yolo-common.sh guard prevents double-source" {
  run bash -c "source '$COMMON_LIB'; source '$COMMON_LIB'; echo ok"
  assert_success
  assert_output "ok"
}

@test "require_jq succeeds when jq is available" {
  run bash -c "source '$COMMON_LIB'; require_jq; echo ok"
  assert_success
  assert_output "ok"
}

@test "json_output produces valid JSON" {
  run bash -c "source '$COMMON_LIB'; json_output --arg k v '{key: \$k}'"
  assert_success
  local val
  val=$(echo "$output" | jq -r '.key')
  [ "$val" = "v" ]
}

# ============================================================
# route.sh --path trivial
# ============================================================

@test "route.sh --path trivial outputs path=trivial" {
  run bash "$ROUTE_SH" --path trivial --phase-dir "$PHASE_DIR" --intent "fix typo" --config "$TEST_WORKDIR/config.json" --analysis-json "$TEST_WORKDIR/analysis.json"
  assert_success
  local path
  path=$(echo "$output" | jq -r '.path')
  [ "$path" = "trivial" ]
}

@test "route.sh --path trivial skips critique, research, architecture, qa, security" {
  run bash "$ROUTE_SH" --path trivial --phase-dir "$PHASE_DIR" --intent "fix typo" --config "$TEST_WORKDIR/config.json" --analysis-json "$TEST_WORKDIR/analysis.json"
  assert_success
  local skipped
  skipped=$(echo "$output" | jq -r '.steps_skipped')
  for step in critique research architecture qa security; do
    local found
    found=$(echo "$skipped" | jq --arg s "$step" 'index($s) != null')
    [ "$found" = "true" ] || fail "Expected $step in steps_skipped"
  done
}

@test "route.sh --path trivial creates minimal plan.jsonl" {
  run bash "$ROUTE_SH" --path trivial --phase-dir "$PHASE_DIR" --intent "fix typo" --config "$TEST_WORKDIR/config.json" --analysis-json "$TEST_WORKDIR/analysis.json"
  assert_success
  local plan_path
  plan_path=$(echo "$output" | jq -r '.plan_path // empty')
  [ -n "$plan_path" ]
  [ -f "$plan_path" ]
}

@test "route.sh --path trivial outputs valid JSON" {
  run bash "$ROUTE_SH" --path trivial --phase-dir "$PHASE_DIR" --intent "fix typo" --config "$TEST_WORKDIR/config.json" --analysis-json "$TEST_WORKDIR/analysis.json"
  assert_success
  run jq empty <<< "$output"
  assert_success
}

@test "route.sh --path trivial estimated_steps is 3" {
  run bash "$ROUTE_SH" --path trivial --phase-dir "$PHASE_DIR" --intent "fix typo" --config "$TEST_WORKDIR/config.json" --analysis-json "$TEST_WORKDIR/analysis.json"
  assert_success
  local steps
  steps=$(echo "$output" | jq '.estimated_steps')
  [ "$steps" -eq 3 ]
}

# ============================================================
# route.sh --path medium
# ============================================================

@test "route.sh --path medium outputs path=medium" {
  run bash "$ROUTE_SH" --path medium --phase-dir "$PHASE_DIR" --intent "add endpoint" --config "$TEST_WORKDIR/config.json" --analysis-json "$TEST_WORKDIR/analysis.json"
  assert_success
  local path
  path=$(echo "$output" | jq -r '.path')
  [ "$path" = "medium" ]
}

@test "route.sh --path medium skips critique and research" {
  run bash "$ROUTE_SH" --path medium --phase-dir "$PHASE_DIR" --intent "add endpoint" --config "$TEST_WORKDIR/config.json" --analysis-json "$TEST_WORKDIR/analysis.json"
  assert_success
  local skipped
  skipped=$(echo "$output" | jq -r '.steps_skipped')
  for step in critique research; do
    local found
    found=$(echo "$skipped" | jq --arg s "$step" 'index($s) != null')
    [ "$found" = "true" ] || fail "Expected $step in steps_skipped"
  done
}

@test "route.sh --path medium includes planning, design_review, implementation, code_review, signoff" {
  run bash "$ROUTE_SH" --path medium --phase-dir "$PHASE_DIR" --intent "add endpoint" --config "$TEST_WORKDIR/config.json" --analysis-json "$TEST_WORKDIR/analysis.json"
  assert_success
  local included
  included=$(echo "$output" | jq -r '.steps_included')
  for step in planning design_review implementation code_review signoff; do
    local found
    found=$(echo "$included" | jq --arg s "$step" 'index($s) != null')
    [ "$found" = "true" ] || fail "Expected $step in steps_included"
  done
}

@test "route.sh --path medium outputs valid JSON" {
  run bash "$ROUTE_SH" --path medium --phase-dir "$PHASE_DIR" --intent "add endpoint" --config "$TEST_WORKDIR/config.json" --analysis-json "$TEST_WORKDIR/analysis.json"
  assert_success
  run jq empty <<< "$output"
  assert_success
}

@test "route.sh --path medium detects architecture.toon" {
  touch "$PHASE_DIR/architecture.toon"
  run bash "$ROUTE_SH" --path medium --phase-dir "$PHASE_DIR" --intent "add endpoint" --config "$TEST_WORKDIR/config.json" --analysis-json "$TEST_WORKDIR/analysis.json"
  assert_success
  local has_arch
  has_arch=$(echo "$output" | jq -r '.has_architecture')
  [ "$has_arch" = "true" ]
}

# ============================================================
# route.sh --path high
# ============================================================

@test "route.sh --path high outputs path=high" {
  run bash "$ROUTE_SH" --path high --phase-dir "$PHASE_DIR" --intent "redesign database" --config "$TEST_WORKDIR/config.json" --analysis-json "$TEST_WORKDIR/analysis.json"
  assert_success
  local path
  path=$(echo "$output" | jq -r '.path')
  [ "$path" = "high" ]
}

@test "route.sh --path high has empty steps_skipped array" {
  run bash "$ROUTE_SH" --path high --phase-dir "$PHASE_DIR" --intent "redesign database" --config "$TEST_WORKDIR/config.json" --analysis-json "$TEST_WORKDIR/analysis.json"
  assert_success
  local skipped_count
  skipped_count=$(echo "$output" | jq '.steps_skipped | length')
  [ "$skipped_count" -eq 0 ]
}

@test "route.sh --path high includes all 11 steps" {
  run bash "$ROUTE_SH" --path high --phase-dir "$PHASE_DIR" --intent "redesign database" --config "$TEST_WORKDIR/config.json" --analysis-json "$TEST_WORKDIR/analysis.json"
  assert_success
  local included_count
  included_count=$(echo "$output" | jq '.steps_included | length')
  [ "$included_count" -eq 11 ]
}

@test "route.sh --path high detects multi-department" {
  run bash "$ROUTE_SH" --path high --phase-dir "$PHASE_DIR" --intent "redesign database" --config "$TEST_WORKDIR/config.json" --analysis-json "$TEST_WORKDIR/analysis-multi.json"
  assert_success
  local multi
  multi=$(echo "$output" | jq -r '.multi_dept')
  [ "$multi" = "true" ]
}

@test "route.sh --path high outputs valid JSON" {
  run bash "$ROUTE_SH" --path high --phase-dir "$PHASE_DIR" --intent "redesign database" --config "$TEST_WORKDIR/config.json" --analysis-json "$TEST_WORKDIR/analysis.json"
  assert_success
  run jq empty <<< "$output"
  assert_success
}

# ============================================================
# Error handling
# ============================================================

@test "route.sh errors on missing --path" {
  run bash "$ROUTE_SH" --phase-dir "$PHASE_DIR" --intent "test"
  assert_failure
}

@test "route.sh errors on invalid --path value" {
  run bash "$ROUTE_SH" --path invalid --phase-dir "$PHASE_DIR" --intent "test"
  assert_failure
}

@test "route.sh errors on missing --phase-dir and --intent" {
  run bash "$ROUTE_SH" --path trivial
  assert_failure
}

@test "route.sh errors on unknown flag" {
  run bash "$ROUTE_SH" --path trivial --phase-dir "$PHASE_DIR" --intent "test" --bogus flag
  assert_failure
}
