#!/usr/bin/env bats
# test-resolve-research-request.bats — Unit tests for scripts/resolve-research-request.sh
# Tests: blocking/informational routing, validation, config overrides, research.jsonl append.

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/resolve-research-request.sh"
  PHASE_DIR="$TEST_WORKDIR/phase"
  mkdir -p "$PHASE_DIR"
}

# Helper: create config with research_requests settings
mk_research_config() {
  local timeout="${1:-120}" max_scouts="${2:-4}"
  jq -n --argjson t "$timeout" --argjson ms "$max_scouts" \
    '{research_requests:{blocking_timeout_seconds:$t,max_concurrent_scouts:$ms}}' \
    > "$TEST_WORKDIR/config.json"
}

# --- Blocking request ---

@test "blocking request: outputs dispatching status with timeout" {
  run bash "$SUT" --phase-dir "$PHASE_DIR" \
    --request-json '{"query":"How to handle JWT refresh?","request_type":"blocking","from":"dev"}'
  assert_success
  local status
  status=$(echo "$output" | jq -r '.status')
  assert_equal "$status" "dispatching"
  local rt
  rt=$(echo "$output" | jq -r '.request_type')
  assert_equal "$rt" "blocking"
  local timeout
  timeout=$(echo "$output" | jq '.timeout')
  assert_equal "$timeout" "120"
}

# --- Informational request ---

@test "informational request: outputs queued status" {
  run bash "$SUT" --phase-dir "$PHASE_DIR" \
    --request-json '{"query":"Best practices for error handling","request_type":"informational","from":"senior"}'
  assert_success
  local status
  status=$(echo "$output" | jq -r '.status')
  assert_equal "$status" "queued"
  local rt
  rt=$(echo "$output" | jq -r '.request_type')
  assert_equal "$rt" "informational"
}

# --- Invalid request JSON ---

@test "invalid JSON: exits with error" {
  run bash "$SUT" --phase-dir "$PHASE_DIR" \
    --request-json 'not-valid-json{'
  assert_failure
}

# --- Missing required fields ---

@test "missing query field: exits with error" {
  run bash "$SUT" --phase-dir "$PHASE_DIR" \
    --request-json '{"request_type":"blocking","from":"dev"}'
  assert_failure
  assert_output --partial "Missing required field: query"
}

# --- Custom timeout from config ---

@test "custom blocking timeout from config" {
  mk_research_config 300 4
  run bash "$SUT" --phase-dir "$PHASE_DIR" \
    --config "$TEST_WORKDIR/config.json" \
    --request-json '{"query":"Test query","request_type":"blocking","from":"dev"}'
  assert_success
  local timeout
  timeout=$(echo "$output" | jq '.timeout')
  assert_equal "$timeout" "300"
}

# --- Custom max concurrent scouts ---

@test "custom max_concurrent_scouts from config" {
  mk_research_config 120 2
  run bash "$SUT" --phase-dir "$PHASE_DIR" \
    --config "$TEST_WORKDIR/config.json" \
    --request-json '{"query":"Test query","request_type":"informational","from":"dev"}'
  assert_success
  local max_scouts
  max_scouts=$(echo "$output" | jq '.max_concurrent_scouts')
  assert_equal "$max_scouts" "2"
}

# --- Appends to research.jsonl with ra and rt fields ---

@test "appends to research.jsonl with ra and rt fields" {
  run bash "$SUT" --phase-dir "$PHASE_DIR" \
    --request-json '{"query":"Test research","request_type":"blocking","from":"dev"}'
  assert_success
  assert_file_exists "$PHASE_DIR/research.jsonl"
  local ra
  ra=$(jq -r '.ra' "$PHASE_DIR/research.jsonl")
  assert_equal "$ra" "dev"
  local rt
  rt=$(jq -r '.rt' "$PHASE_DIR/research.jsonl")
  assert_equal "$rt" "blocking"
}

# --- Missing required flags ---

@test "missing required flags: exits with error" {
  run bash "$SUT"
  assert_failure
}
