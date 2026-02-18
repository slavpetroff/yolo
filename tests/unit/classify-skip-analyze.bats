#!/usr/bin/env bats
# classify-skip-analyze.bats — Tests for skip_analyze field in complexity-classify.sh
# Plan 07-03 T4: Verify skip_analyze logic and classification routing

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/complexity-classify.sh"

  # Create a minimal config for tests
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
  shift
  run bash "$SUT" --intent "$intent" --config "$TEST_WORKDIR/config.json" --codebase-map false "$@"
}

# Helper: extract JSON field from output
get_field() {
  echo "$output" | jq -r ".$1"
}

# --- skip_analyze=true for high-confidence trivial ---

@test "skip_analyze=true for trivial with confidence 0.9" {
  run_classify "fix typo in README"
  assert_success
  local skip
  skip=$(get_field skip_analyze)
  [ "$skip" = "true" ]
}

@test "skip_analyze=true for trivial 'rename variable'" {
  run_classify "rename variable"
  assert_success
  local skip complexity
  skip=$(get_field skip_analyze)
  complexity=$(get_field complexity)
  [ "$complexity" = "trivial" ]
  [ "$skip" = "true" ]
}

@test "skip_analyze=true for trivial 'update version number'" {
  run_classify "update version number"
  assert_success
  local skip
  skip=$(get_field skip_analyze)
  [ "$skip" = "true" ]
}

# --- skip_analyze=true for high-confidence medium ---

@test "skip_analyze=true for medium with confidence >= 0.7" {
  run_classify "implement a new API endpoint"
  assert_success
  local skip complexity conf
  skip=$(get_field skip_analyze)
  complexity=$(get_field complexity)
  conf=$(get_field confidence)
  [ "$complexity" = "medium" ]
  [ "$skip" = "true" ]
  local above_threshold
  above_threshold=$(echo "$conf >= 0.7" | bc -l)
  [ "$above_threshold" -eq 1 ]
}

@test "skip_analyze=true for medium 'implement pagination'" {
  run_classify "implement pagination"
  assert_success
  local skip complexity
  skip=$(get_field skip_analyze)
  complexity=$(get_field complexity)
  [ "$complexity" = "medium" ]
  [ "$skip" = "true" ]
}

# --- skip_analyze=false for low-confidence (ambiguous) ---

@test "skip_analyze=false for ambiguous intent with low confidence" {
  run_classify "do something vague"
  assert_success
  local skip conf
  skip=$(get_field skip_analyze)
  conf=$(get_field confidence)
  [ "$skip" = "false" ]
  local below_threshold
  below_threshold=$(echo "$conf < 0.7" | bc -l)
  [ "$below_threshold" -eq 1 ]
}

@test "skip_analyze=false for unrecognized intent" {
  run_classify "foobar baz qux"
  assert_success
  local skip
  skip=$(get_field skip_analyze)
  [ "$skip" = "false" ]
}

# --- skip_analyze=false for high complexity (always) ---

@test "skip_analyze=false for high complexity 'redesign the database schema'" {
  run_classify "redesign the database schema"
  assert_success
  local skip complexity
  skip=$(get_field skip_analyze)
  complexity=$(get_field complexity)
  [ "$complexity" = "high" ]
  [ "$skip" = "false" ]
}

@test "skip_analyze=false for high complexity 'add multi-tenant support'" {
  run_classify "add multi-tenant support"
  assert_success
  local skip complexity
  skip=$(get_field skip_analyze)
  complexity=$(get_field complexity)
  [ "$complexity" = "high" ]
  [ "$skip" = "false" ]
}

@test "skip_analyze=false for high complexity even with high confidence" {
  run_classify "build a new dashboard with backend API"
  assert_success
  local skip complexity conf
  skip=$(get_field skip_analyze)
  complexity=$(get_field complexity)
  conf=$(get_field confidence)
  [ "$complexity" = "high" ]
  [ "$skip" = "false" ]
  # Confidence is high but still skip_analyze=false because complexity=high
  local high_conf
  high_conf=$(echo "$conf >= 0.7" | bc -l)
  [ "$high_conf" -eq 1 ]
}

# --- --medium-threshold flag override ---

@test "skip_analyze respects --medium-threshold flag override" {
  # With threshold 0.95, trivial (conf 0.9) should still be skip_analyze=true (0.9 >= 0.7 default? no, flag overrides)
  # Actually: trivial conf=0.9, threshold=0.95: 0.9 < 0.95 => skip_analyze=false
  run_classify "fix typo in README" --medium-threshold 0.95
  assert_success
  local skip
  skip=$(get_field skip_analyze)
  [ "$skip" = "false" ]
}

@test "skip_analyze=true with low --medium-threshold" {
  # Ambiguous case has conf=0.6, if threshold=0.5, then 0.6 >= 0.5 => skip_analyze=true
  run_classify "do something vague" --medium-threshold 0.5
  assert_success
  local skip
  skip=$(get_field skip_analyze)
  [ "$skip" = "true" ]
}

# --- Config-driven threshold ---

@test "skip_analyze uses config medium_confidence_threshold" {
  # Override config to set threshold to 0.95
  cat > "$TEST_WORKDIR/config.json" <<'JSON'
{
  "complexity_routing": {
    "enabled": true,
    "trivial_confidence_threshold": 0.85,
    "medium_confidence_threshold": 0.95,
    "fallback_path": "high"
  },
  "departments": {
    "backend": true,
    "frontend": false,
    "uiux": false
  }
}
JSON
  # Trivial has conf=0.9, threshold=0.95: 0.9 < 0.95 => skip_analyze=false
  run_classify "fix typo in README"
  assert_success
  local skip
  skip=$(get_field skip_analyze)
  [ "$skip" = "false" ]
}

# --- Output format includes skip_analyze ---

@test "output contains skip_analyze field" {
  run_classify "fix typo in README"
  assert_success
  local has_field
  has_field=$(echo "$output" | jq 'has("skip_analyze")')
  [ "$has_field" = "true" ]
}

@test "skip_analyze is boolean not string" {
  run_classify "fix typo in README"
  assert_success
  local type
  type=$(echo "$output" | jq -r '.skip_analyze | type')
  [ "$type" = "boolean" ]
}

# --- Multi-department always skip_analyze=false (high complexity from dept count) ---

@test "skip_analyze=false when multiple departments active" {
  cat > "$TEST_WORKDIR/config.json" <<'JSON'
{
  "complexity_routing": {
    "enabled": true,
    "medium_confidence_threshold": 0.7
  },
  "departments": {
    "backend": true,
    "frontend": true,
    "uiux": false
  }
}
JSON
  run_classify "add a button"
  assert_success
  local skip complexity
  skip=$(get_field skip_analyze)
  complexity=$(get_field complexity)
  [ "$complexity" = "high" ]
  [ "$skip" = "false" ]
}
