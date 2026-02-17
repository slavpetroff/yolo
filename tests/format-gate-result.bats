#!/usr/bin/env bats
# format-gate-result.bats — RED phase tests for scripts/format-gate-result.sh
# Plan 04-04 T4: Formats QA gate results into abbreviated JSONL output.

setup() {
  load 'test_helper/common'
  load 'test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/format-gate-result.sh"
}

@test "formats post-task result with abbreviated keys" {
  local input='{"result":"PASS","plan_id":"04-03","task_id":"T1","tests":{"passed":12,"failed":0},"duration_ms":2450,"files_tested":["foo.bats"]}'
  run bash -c "echo '$input' | bash '$SUT' post-task"
  assert_success
  # Validate output is valid JSON
  echo "$output" | jq -e '.' >/dev/null 2>&1
  # Check abbreviated keys
  local gl r plan task
  gl=$(echo "$output" | jq -r '.gl')
  r=$(echo "$output" | jq -r '.r')
  plan=$(echo "$output" | jq -r '.plan')
  task=$(echo "$output" | jq -r '.task')
  [ "$gl" = "post-task" ]
  [ "$r" = "PASS" ]
  [ "$plan" = "04-03" ]
  [ "$task" = "T1" ]
}

@test "formats post-plan result with aggregation fields" {
  local input='{"result":"PASS","plan_id":"04-03","tasks_completed":5,"tasks_total":5,"must_have_coverage":true,"duration_ms":12000}'
  run bash -c "echo '$input' | bash '$SUT' post-plan"
  assert_success
  echo "$output" | jq -e '.' >/dev/null 2>&1
  local tc tt mh
  tc=$(echo "$output" | jq -r '.tc')
  tt=$(echo "$output" | jq -r '.tt')
  mh=$(echo "$output" | jq -r '.mh')
  [ "$tc" = "5" ]
  [ "$tt" = "5" ]
  [ "$mh" = "true" ]
}

@test "formats post-phase result with escalations and gate checks" {
  local input='{"result":"PASS","phase":"04","plans":["04-01","04-02","04-03"],"escalations":[],"gates":{"critique":true,"architecture":true,"qa":true}}'
  run bash -c "echo '$input' | bash '$SUT' post-phase"
  assert_success
  echo "$output" | jq -e '.' >/dev/null 2>&1
  local ph plans esc gates
  ph=$(echo "$output" | jq -r '.ph')
  plans=$(echo "$output" | jq '.plans | length')
  esc=$(echo "$output" | jq '.esc | length')
  gates=$(echo "$output" | jq '.gates | keys | length')
  [ "$ph" = "04" ]
  [ "$plans" = "3" ]
  [ "$esc" = "0" ]
  [ "$gates" = "3" ]
}

@test "rejects invalid gate level" {
  local input='{"result":"PASS"}'
  run bash -c "echo '$input' | bash '$SUT' invalid-level"
  assert_failure
  assert_output --partial "Invalid gate level"
}

@test "rejects invalid JSON input" {
  run bash -c "echo 'not json' | bash '$SUT' post-task"
  assert_failure
  assert_output --partial "Invalid JSON"
}

@test "adds dt timestamp to output" {
  local input='{"result":"PASS","plan_id":"04-03","task_id":"T1","tests":{"passed":1,"failed":0},"duration_ms":100,"files_tested":[]}'
  run bash -c "echo '$input' | bash '$SUT' post-task"
  assert_success
  # dt field should exist and contain a date-like pattern (YYYY-MM-DD)
  local dt
  dt=$(echo "$output" | jq -r '.dt')
  [[ "$dt" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]]
}

@test "accepts abbreviated keys in input" {
  local input='{"r":"PASS","plan":"04-03","task":"T1","tst":{"ps":12,"fl":0},"dur":2450,"f":["foo.bats"]}'
  run bash -c "echo '$input' | bash '$SUT' post-task"
  assert_success
  echo "$output" | jq -e '.' >/dev/null 2>&1
  local r plan
  r=$(echo "$output" | jq -r '.r')
  plan=$(echo "$output" | jq -r '.plan')
  [ "$r" = "PASS" ]
  [ "$plan" = "04-03" ]
}
