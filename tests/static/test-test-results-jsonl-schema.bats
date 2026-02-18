#!/usr/bin/env bats
# test-test-results-jsonl-schema.bats — Static validation tests for test-results.jsonl format
# Tests: required fields, valid dept/phase values, tasks structure, numeric invariants.

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir
}

# Helper: validate a test-results entry has all required fields
validate_required() {
  local entry="$1"
  echo "$entry" | jq -e '
    has("plan") and has("dept") and has("phase") and
    has("tc") and has("ps") and has("fl") and has("dt") and has("tasks")
  ' > /dev/null 2>&1
}

VALID_ENTRY='{"plan":"04-03","dept":"backend","phase":"green","tc":12,"ps":12,"fl":0,"dt":"2026-02-18","tasks":[{"id":"T1","ps":4,"fl":0,"tf":["tests/auth.test.ts"]},{"id":"T2","ps":8,"fl":0,"tf":["tests/session.test.ts"]}]}'

# --- Valid entry ---

@test "valid entry parses with all required fields" {
  run validate_required "$VALID_ENTRY"
  assert_success
}

# --- Valid dept values only ---

@test "valid dept values: backend, frontend, uiux" {
  for dept in backend frontend uiux; do
    run bash -c "echo '$VALID_ENTRY' | jq --arg d '$dept' '.dept = \$d' | jq -e '.dept == \"backend\" or .dept == \"frontend\" or .dept == \"uiux\"'"
    assert_success
  done
}

@test "invalid dept value rejected" {
  run bash -c "echo '{\"dept\":\"devops\"}' | jq -e '.dept == \"backend\" or .dept == \"frontend\" or .dept == \"uiux\"'"
  assert_failure
}

# --- Valid phase values only ---

@test "valid phase values: red, green" {
  for phase in red green; do
    run bash -c "echo '$VALID_ENTRY' | jq --arg p '$phase' '.phase = \$p' | jq -e '.phase == \"red\" or .phase == \"green\"'"
    assert_success
  done
}

@test "invalid phase value rejected" {
  run bash -c "echo '{\"phase\":\"blue\"}' | jq -e '.phase == \"red\" or .phase == \"green\"'"
  assert_failure
}

# --- tasks[] entries have required fields ---

@test "tasks entries have required fields: id, ps, fl, tf" {
  run bash -c "echo '$VALID_ENTRY' | jq -e '.tasks | all(has(\"id\") and has(\"ps\") and has(\"fl\") and has(\"tf\"))'"
  assert_success
}

# --- ps + fl = tc at top level ---

@test "ps + fl equals tc at top level" {
  run bash -c "echo '$VALID_ENTRY' | jq -e '.ps + .fl == .tc'"
  assert_success
}

# --- Sum of tasks[].ps = top-level ps ---

@test "sum of tasks ps equals top-level ps" {
  run bash -c "echo '$VALID_ENTRY' | jq -e '[.tasks[].ps] | add == .ps' 2>/dev/null || echo '$VALID_ENTRY' | jq -e '([.tasks[].ps] | add) as \$sum | \$sum == .ps'"
  assert_success
}

# --- tf[] must be non-empty array of strings ---

@test "tf must be non-empty array of strings" {
  run bash -c "echo '$VALID_ENTRY' | jq -e '.tasks | all(.tf | type == \"array\" and length > 0 and all(type == \"string\"))'"
  assert_success
}

@test "empty tf array is rejected" {
  local bad_entry
  bad_entry=$(echo "$VALID_ENTRY" | jq '.tasks[0].tf = []')
  run bash -c "echo '$bad_entry' | jq -e '.tasks | all(.tf | type == \"array\" and length > 0)'"
  assert_failure
}
