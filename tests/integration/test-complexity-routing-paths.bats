#!/usr/bin/env bats
# test-complexity-routing-paths.bats — Integration tests for complexity routing end-to-end
# Tests the full pipeline: complexity-classify.sh -> route-{trivial,medium,high}.sh
# Verifies: trivial skips Architect+Critique, medium skips Architect, high runs all steps.

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir

  CLASSIFY="$SCRIPTS_DIR/complexity-classify.sh"
  ROUTE_TRIVIAL="$SCRIPTS_DIR/route-trivial.sh"
  ROUTE_MEDIUM="$SCRIPTS_DIR/route-medium.sh"
  ROUTE_HIGH="$SCRIPTS_DIR/route-high.sh"

  # Create phase dir
  PHASE_DIR="$TEST_WORKDIR/phases/01-test"
  mkdir -p "$PHASE_DIR"

  # Single-department config (backend only)
  cat > "$TEST_WORKDIR/config-single.json" <<'JSON'
{
  "departments": {
    "backend": true,
    "frontend": false,
    "uiux": false
  }
}
JSON

  # Multi-department config
  cat > "$TEST_WORKDIR/config-multi.json" <<'JSON'
{
  "departments": {
    "backend": true,
    "frontend": true,
    "uiux": false
  }
}
JSON
}

# Helper: classify and route end-to-end
# Usage: classify_and_route "intent text" [config_path]
classify_and_route() {
  local intent="$1"
  local config="${2:-$TEST_WORKDIR/config-single.json}"

  # Step 1: Classify
  local analysis
  analysis=$(bash "$CLASSIFY" --intent "$intent" --config "$config")
  local suggested_path
  suggested_path=$(echo "$analysis" | jq -r '.suggested_path')
  local complexity
  complexity=$(echo "$analysis" | jq -r '.complexity')

  # Write analysis to file for route script
  echo "$analysis" > "$TEST_WORKDIR/analysis.json"

  # Step 2: Route based on suggested_path
  local route_script
  case "$suggested_path" in
    trivial_shortcut) route_script="$ROUTE_TRIVIAL" ;;
    medium_path)      route_script="$ROUTE_MEDIUM" ;;
    full_ceremony)    route_script="$ROUTE_HIGH" ;;
    *)                route_script="$ROUTE_HIGH" ;;
  esac

  local route_output
  route_output=$(bash "$route_script" \
    --phase-dir "$PHASE_DIR" \
    --intent "$intent" \
    --config "$config" \
    --analysis-json "$TEST_WORKDIR/analysis.json")

  # Combine classification + routing into single JSON
  jq -n \
    --argjson classification "$analysis" \
    --argjson routing "$route_output" \
    '{classification: $classification, routing: $routing}'
}

# --- End-to-end: trivial intent → trivial path ---

@test "e2e: 'fix typo' classifies as trivial and routes to trivial_shortcut" {
  run classify_and_route "fix typo in README"
  assert_success

  local complexity
  complexity=$(echo "$output" | jq -r '.classification.complexity')
  assert_equal "$complexity" "trivial"

  local path
  path=$(echo "$output" | jq -r '.routing.path')
  assert_equal "$path" "trivial"
}

@test "e2e: trivial path skips critique, research, architecture, qa, security" {
  run classify_and_route "fix typo in config"
  assert_success

  local skipped
  skipped=$(echo "$output" | jq -c '.routing.steps_skipped')
  for step in critique research architecture qa security; do
    local found
    found=$(echo "$skipped" | jq --arg s "$step" 'index($s) != null')
    [ "$found" = "true" ] || fail "Expected $step in steps_skipped for trivial path"
  done
}

@test "e2e: trivial path has estimated_steps <= 3" {
  run classify_and_route "rename config key"
  assert_success

  local steps
  steps=$(echo "$output" | jq '.routing.estimated_steps')
  [ "$steps" -le 3 ]
}

# --- End-to-end: medium intent → medium path ---

@test "e2e: 'add feature' classifies as medium and routes to medium_path" {
  run classify_and_route "add a new validation script"
  assert_success

  local complexity
  complexity=$(echo "$output" | jq -r '.classification.complexity')
  assert_equal "$complexity" "medium"

  local path
  path=$(echo "$output" | jq -r '.routing.path')
  assert_equal "$path" "medium"
}

@test "e2e: medium path skips critique and research but includes planning" {
  run classify_and_route "implement new endpoint handler"
  assert_success

  local skipped
  skipped=$(echo "$output" | jq -c '.routing.steps_skipped')
  for step in critique research; do
    local found
    found=$(echo "$skipped" | jq --arg s "$step" 'index($s) != null')
    [ "$found" = "true" ] || fail "Expected $step in steps_skipped for medium path"
  done

  local included
  included=$(echo "$output" | jq -c '.routing.steps_included')
  local has_planning
  has_planning=$(echo "$included" | jq 'index("planning") != null')
  [ "$has_planning" = "true" ] || fail "Expected planning in steps_included for medium path"
}

@test "e2e: medium path includes code_review and signoff" {
  run classify_and_route "refactor the validation module"
  assert_success

  local included
  included=$(echo "$output" | jq -c '.routing.steps_included')
  for step in code_review signoff; do
    local found
    found=$(echo "$included" | jq --arg s "$step" 'index($s) != null')
    [ "$found" = "true" ] || fail "Expected $step in steps_included for medium path"
  done
}

# --- End-to-end: high intent → full ceremony ---

@test "e2e: 'redesign architecture' classifies as high and routes to full_ceremony" {
  run classify_and_route "redesign the authentication subsystem"
  assert_success

  local complexity
  complexity=$(echo "$output" | jq -r '.classification.complexity')
  assert_equal "$complexity" "high"

  local path
  path=$(echo "$output" | jq -r '.routing.path')
  assert_equal "$path" "high"
}

@test "e2e: high path has zero steps_skipped" {
  run classify_and_route "new subsystem for multi-tenant support"
  assert_success

  local skipped_count
  skipped_count=$(echo "$output" | jq '.routing.steps_skipped | length')
  assert_equal "$skipped_count" "0"
}

@test "e2e: high path includes all 11 steps" {
  run classify_and_route "overhaul the entire build pipeline"
  assert_success

  local included_count
  included_count=$(echo "$output" | jq '.routing.steps_included | length')
  assert_equal "$included_count" "11"
}

@test "e2e: high path estimated_steps is 11" {
  run classify_and_route "rearchitect the agent spawning system"
  assert_success

  local steps
  steps=$(echo "$output" | jq '.routing.estimated_steps')
  assert_equal "$steps" "11"
}

# --- Multi-department triggers high complexity ---

@test "e2e: multi-department config forces high complexity" {
  run classify_and_route "add a new validation script" "$TEST_WORKDIR/config-multi.json"
  assert_success

  local complexity
  complexity=$(echo "$output" | jq -r '.classification.complexity')
  assert_equal "$complexity" "high"

  local path
  path=$(echo "$output" | jq -r '.routing.path')
  assert_equal "$path" "high"
}

# --- Confidence levels ---

@test "e2e: trivial classification has high confidence (>= 0.85)" {
  run classify_and_route "fix typo"
  assert_success

  local confidence
  confidence=$(echo "$output" | jq '.classification.confidence')
  local is_high
  is_high=$(echo "$confidence >= 0.85" | bc)
  [ "$is_high" -eq 1 ] || fail "Expected confidence >= 0.85 for trivial, got $confidence"
}

@test "e2e: high classification has high confidence (>= 0.85)" {
  run classify_and_route "new subsystem for distributed caching"
  assert_success

  local confidence
  confidence=$(echo "$output" | jq '.classification.confidence')
  local is_high
  is_high=$(echo "$confidence >= 0.85" | bc)
  [ "$is_high" -eq 1 ] || fail "Expected confidence >= 0.85 for high, got $confidence"
}

# --- Both scripts produce valid JSON ---

@test "e2e: entire pipeline produces valid JSON output" {
  run classify_and_route "fix typo"
  assert_success
  echo "$output" | jq empty
  assert_success

  run classify_and_route "add endpoint"
  assert_success
  echo "$output" | jq empty
  assert_success

  run classify_and_route "redesign architecture"
  assert_success
  echo "$output" | jq empty
  assert_success
}
