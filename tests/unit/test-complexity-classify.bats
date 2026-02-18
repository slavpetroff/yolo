#!/usr/bin/env bats
# test-complexity-classify.bats — Unit tests for scripts/complexity-classify.sh
# Plan 01-04 T1: Classification accuracy, intent detection, confidence, edge cases

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/complexity-classify.sh"

  # Create a minimal config for tests
  mkdir -p "$TEST_WORKDIR/config"
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
}

# Helper: run classifier with standard args
run_classify() {
  local intent="$1"
  run bash "$SUT" --intent "$intent" --config "$TEST_WORKDIR/config.json" --codebase-map false
}

# Helper: extract JSON field from output
get_field() {
  echo "$output" | jq -r ".$1"
}

# --- Trivial classification ---

@test "classifies 'fix typo in README' as trivial" {
  run_classify "fix typo in README"
  assert_success
  local complexity
  complexity=$(get_field complexity)
  [ "$complexity" = "trivial" ]
}

@test "classifies 'update version number' as trivial" {
  run_classify "update version number"
  assert_success
  local complexity
  complexity=$(get_field complexity)
  [ "$complexity" = "trivial" ]
}

@test "classifies 'rename variable' as trivial" {
  run_classify "rename variable"
  assert_success
  local complexity
  complexity=$(get_field complexity)
  [ "$complexity" = "trivial" ]
}

@test "classifies 'add comment to function' as trivial" {
  run_classify "add comment to function"
  assert_success
  local complexity
  complexity=$(get_field complexity)
  [ "$complexity" = "trivial" ]
}

# --- Medium classification ---

@test "classifies 'add a new API endpoint for users' as medium" {
  run_classify "add a new API endpoint for users"
  assert_success
  local complexity
  complexity=$(get_field complexity)
  [ "$complexity" = "medium" ]
}

@test "classifies 'refactor the auth module' as medium" {
  run_classify "refactor the auth module"
  assert_success
  local complexity
  complexity=$(get_field complexity)
  [ "$complexity" = "medium" ]
}

@test "classifies 'implement pagination' as medium" {
  run_classify "implement pagination"
  assert_success
  local complexity
  complexity=$(get_field complexity)
  [ "$complexity" = "medium" ]
}

# --- High classification ---

@test "classifies 'redesign the database schema' as high" {
  run_classify "redesign the database schema"
  assert_success
  local complexity
  complexity=$(get_field complexity)
  [ "$complexity" = "high" ]
}

@test "classifies 'add multi-tenant support' as high" {
  run_classify "add multi-tenant support"
  assert_success
  local complexity
  complexity=$(get_field complexity)
  [ "$complexity" = "high" ]
}

@test "classifies 'build a new dashboard with backend API' as high" {
  run_classify "build a new dashboard with backend API"
  assert_success
  local complexity
  complexity=$(get_field complexity)
  [ "$complexity" = "high" ]
}

# --- Intent detection ---

@test "debug keywords return intent=debug" {
  run_classify "debug the login failure"
  assert_success
  local intent
  intent=$(get_field intent)
  [ "$intent" = "debug" ]
}

@test "fix keywords return intent=fix" {
  run_classify "fix the broken auth endpoint"
  assert_success
  local intent
  intent=$(get_field intent)
  [ "$intent" = "fix" ]
}

@test "research keywords return intent=research" {
  run_classify "research best practices for caching"
  assert_success
  local intent
  intent=$(get_field intent)
  [ "$intent" = "research" ]
}

# --- Confidence thresholds ---

@test "exact keyword match has confidence >= 0.85" {
  run_classify "fix typo in README"
  assert_success
  local conf
  conf=$(get_field confidence)
  # Use bc for float comparison
  local result
  result=$(echo "$conf >= 0.85" | bc -l)
  [ "$result" -eq 1 ]
}

@test "heuristic match has confidence >= 0.7" {
  run_classify "implement pagination"
  assert_success
  local conf
  conf=$(get_field confidence)
  local result
  result=$(echo "$conf >= 0.7" | bc -l)
  [ "$result" -eq 1 ]
}

# --- Department detection ---

@test "single backend department returns correct array" {
  run_classify "add a new endpoint"
  assert_success
  local depts
  depts=$(echo "$output" | jq -r '.departments | length')
  [ "$depts" -ge 1 ]
  local has_backend
  has_backend=$(echo "$output" | jq -r '.departments | index("backend") != null')
  [ "$has_backend" = "true" ]
}

@test "multi-dept config returns correct department array" {
  # Enable frontend department in config
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
    "frontend": true,
    "uiux": false
  }
}
JSON
  run_classify "build a new dashboard with backend API"
  assert_success
  local dept_count
  dept_count=$(echo "$output" | jq -r '.departments | length')
  [ "$dept_count" -ge 2 ]
}

# --- Edge cases ---

@test "empty input exits non-zero" {
  run bash "$SUT" --intent "" --config "$TEST_WORKDIR/config.json" --codebase-map false
  assert_failure
}

@test "very long input does not crash" {
  local long_input
  long_input=$(printf 'add feature %.0s' {1..100})
  run_classify "$long_input"
  assert_success
  # Should still produce valid JSON
  echo "$output" | jq empty
}

@test "special characters in input do not crash" {
  run_classify "fix the 'quoted' bug & handle <html> tags"
  assert_success
  echo "$output" | jq empty
}

# --- Output format ---

@test "output is valid JSON" {
  run_classify "fix typo in README"
  assert_success
  run jq empty <<< "$output"
  assert_success
}

@test "output contains all required fields" {
  run_classify "fix typo in README"
  assert_success
  for field in complexity departments intent confidence reasoning suggested_path; do
    local has_field
    has_field=$(echo "$output" | jq "has(\"$field\")")
    [ "$has_field" = "true" ] || fail "Missing required field: $field"
  done
}

@test "missing --intent flag exits non-zero" {
  run bash "$SUT" --config "$TEST_WORKDIR/config.json" --codebase-map false
  assert_failure
}

@test "missing --config flag exits 0 with defaults" {
  run bash "$SUT" --intent "fix typo" --codebase-map false
  assert_success
  # Should still produce valid JSON with empty departments
  run jq empty <<< "$output"
  assert_success
}
