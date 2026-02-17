#!/usr/bin/env bats
# resolve-task-deps.bats — Behavioral tests for scripts/resolve-task-deps.sh
# Resolves task execution order from plan.jsonl td/d fields
# RED phase: script does not exist yet, all tests must FAIL

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/resolve-task-deps.sh"
}

# Helper: create a plan.jsonl with header and tasks
# Usage: mk_plan_file <path> <header_json> <task_lines...>
mk_plan_file() {
  local path="$1"; shift
  local header="$1"; shift
  echo "$header" > "$path"
  for task_line in "$@"; do
    echo "$task_line" >> "$path"
  done
}

# --- Existence and executability ---

@test "resolve-task-deps.sh exists and is executable" {
  assert_file_executable "$SUT"
}

# --- Linear chain: T1 -> T2 -> T3 ---

@test "linear chain: T1 then T2 then T3 in correct order" {
  local plan="$TEST_WORKDIR/plan.jsonl"
  mk_plan_file "$plan" \
    '{"p":"03","n":"01","t":"test plan","d":[]}' \
    '{"id":"T1","a":"task one","f":["a.sh"]}' \
    '{"id":"T2","a":"task two","f":["b.sh"],"td":["T1"]}' \
    '{"id":"T3","a":"task three","f":["c.sh"],"td":["T2"]}'

  run bash "$SUT" --plan "$plan"
  assert_success

  # T1 must appear before T2, T2 must appear before T3
  local t1_pos t2_pos t3_pos
  t2_pos=$(echo "$output" | jq 'to_entries | map(select(.value.tasks | index("T2"))) | .[0].key')
  t3_pos=$(echo "$output" | jq 'to_entries | map(select(.value.tasks | index("T3"))) | .[0].key')
  t1_pos=$(echo "$output" | jq 'to_entries | map(select(.value.tasks | index("T1"))) | .[0].key')

  # T1 group index must be less than T2 group index
  [ "$t1_pos" -lt "$t2_pos" ]
  # T2 group index must be less than T3 group index
  [ "$t2_pos" -lt "$t3_pos" ]
}

# --- Parallel tasks: no td field means all independent ---

@test "parallel tasks: no td field means all tasks in first group" {
  local plan="$TEST_WORKDIR/plan.jsonl"
  mk_plan_file "$plan" \
    '{"p":"03","n":"01","t":"test plan","d":[]}' \
    '{"id":"T1","a":"task one","f":["a.sh"]}' \
    '{"id":"T2","a":"task two","f":["b.sh"]}' \
    '{"id":"T3","a":"task three","f":["c.sh"]}'

  run bash "$SUT" --plan "$plan"
  assert_success

  # All tasks should be in group 1 (all parallel)
  local group_count task_count
  group_count=$(echo "$output" | jq 'length')
  task_count=$(echo "$output" | jq '.[0].tasks | length')
  assert_equal "$group_count" "1"
  assert_equal "$task_count" "3"
}

# --- Mixed dependencies: some parallel, some sequential ---

@test "mixed deps: T1 and T2 parallel, T3 depends on both" {
  local plan="$TEST_WORKDIR/plan.jsonl"
  mk_plan_file "$plan" \
    '{"p":"03","n":"01","t":"test plan","d":[]}' \
    '{"id":"T1","a":"task one","f":["a.sh"]}' \
    '{"id":"T2","a":"task two","f":["b.sh"]}' \
    '{"id":"T3","a":"task three","f":["c.sh"],"td":["T1","T2"]}'

  run bash "$SUT" --plan "$plan"
  assert_success

  # Should be 2 groups: group 1 = [T1, T2], group 2 = [T3]
  local group_count
  group_count=$(echo "$output" | jq 'length')
  assert_equal "$group_count" "2"

  # T3 must be in the second group
  local t3_group
  t3_group=$(echo "$output" | jq 'to_entries | map(select(.value.tasks | index("T3"))) | .[0].key')
  assert_equal "$t3_group" "1"
}

# --- Circular dependency detection ---

@test "circular dep: T1 -> T2 -> T1 exits 1 with error message" {
  local plan="$TEST_WORKDIR/plan.jsonl"
  mk_plan_file "$plan" \
    '{"p":"03","n":"01","t":"test plan","d":[]}' \
    '{"id":"T1","a":"task one","f":["a.sh"],"td":["T2"]}' \
    '{"id":"T2","a":"task two","f":["b.sh"],"td":["T1"]}'

  run bash "$SUT" --plan "$plan"
  assert_failure
  assert_output --partial "ircular"
}

# --- Empty plan: no tasks ---

@test "empty plan: no tasks outputs empty array" {
  local plan="$TEST_WORKDIR/plan.jsonl"
  mk_plan_file "$plan" \
    '{"p":"03","n":"01","t":"test plan","d":[]}'

  run bash "$SUT" --plan "$plan"
  assert_success

  local result
  result=$(echo "$output" | jq 'length')
  assert_equal "$result" "0"
}

# --- Error handling ---

@test "missing --plan flag exits 1 with usage message" {
  run bash "$SUT"
  assert_failure
  assert_output --partial "Usage"
}

@test "nonexistent plan file exits 1 with error message" {
  run bash "$SUT" --plan "$TEST_WORKDIR/nonexistent.jsonl"
  assert_failure
  assert_output --partial "ERROR"
}

# --- Output is valid JSON ---

@test "output is valid JSON array" {
  local plan="$TEST_WORKDIR/plan.jsonl"
  mk_plan_file "$plan" \
    '{"p":"03","n":"01","t":"test plan","d":[]}' \
    '{"id":"T1","a":"task one","f":["a.sh"]}'

  run bash "$SUT" --plan "$plan"
  assert_success

  # Must be valid JSON
  echo "$output" | jq . >/dev/null 2>&1
  assert_equal "$?" "0"

  # Must be an array
  local arr_type
  arr_type=$(echo "$output" | jq -r 'type')
  assert_equal "$arr_type" "array"
}
