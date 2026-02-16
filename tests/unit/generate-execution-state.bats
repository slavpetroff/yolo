#!/usr/bin/env bats
# generate-execution-state.bats — Unit tests for scripts/generate-execution-state.sh
# Generates initial .execution-state.json from plan.jsonl files in a phase directory.

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/generate-execution-state.sh"
}

# Helper: create a valid plan.jsonl header line
mk_plan_header() {
  local phase="$1" num="$2" title="$3" wave="$4"
  local file="$PHASE_DIR/${phase}-${num}.plan.jsonl"
  echo "{\"p\":\"${phase}\",\"n\":\"${num}\",\"t\":\"${title}\",\"w\":${wave},\"d\":[],\"mh\":{},\"obj\":\"${title}\"}" > "$file"
  echo '{"id":"T1","tp":"auto","a":"task","f":["src/a.sh"],"v":"ok","done":"ok","spec":"do stuff"}' >> "$file"
}

@test "generates state from single plan" {
  PHASE_DIR="$TEST_WORKDIR/03-test-phase"
  mkdir -p "$PHASE_DIR"
  mk_plan_header "03" "01" "Test Plan" 1

  run bash "$SUT" --phase-dir "$PHASE_DIR" --phase 03
  assert_success

  # Verify file exists
  [ -f "$PHASE_DIR/.execution-state.json" ]

  # Verify schema
  local state
  state=$(cat "$PHASE_DIR/.execution-state.json")
  [ "$(echo "$state" | jq '.phase')" -eq 3 ]
  [ "$(echo "$state" | jq -r '.status')" = "running" ]
  [ "$(echo "$state" | jq -r '.step')" = "planning" ]
  [ "$(echo "$state" | jq '.plans | length')" -eq 1 ]
  [ "$(echo "$state" | jq -r '.plans[0].id')" = "03-01" ]
  [ "$(echo "$state" | jq -r '.plans[0].status')" = "pending" ]

  # Verify all 10 steps exist
  [ "$(echo "$state" | jq '.steps | keys | length')" -eq 10 ]
}

@test "generates state from multiple plans" {
  PHASE_DIR="$TEST_WORKDIR/03-multi"
  mkdir -p "$PHASE_DIR"
  mk_plan_header "03" "01" "Plan A" 1
  mk_plan_header "03" "02" "Plan B" 1
  mk_plan_header "03" "03" "Plan C" 2

  run bash "$SUT" --phase-dir "$PHASE_DIR" --phase 03
  assert_success

  local state
  state=$(cat "$PHASE_DIR/.execution-state.json")
  [ "$(echo "$state" | jq '.plans | length')" -eq 3 ]
  [ "$(echo "$state" | jq '.total_waves')" -eq 2 ]
  [ "$(echo "$state" | jq '.wave')" -eq 1 ]
}

@test "detects completed plans from summary.jsonl" {
  PHASE_DIR="$TEST_WORKDIR/03-completed"
  mkdir -p "$PHASE_DIR"
  mk_plan_header "03" "01" "Plan A" 1
  mk_plan_header "03" "02" "Plan B" 1

  # Create summary for 03-01 (completed)
  echo '{"p":"03","n":"01","t":"Plan A","s":"complete","dt":"2026-02-16","tc":1,"tt":1,"ch":["abc"],"fm":["src/a.sh"],"dv":[],"built":["test"],"tst":"green_only"}' > "$PHASE_DIR/03-01.summary.jsonl"

  run bash "$SUT" --phase-dir "$PHASE_DIR" --phase 03
  assert_success

  local state
  state=$(cat "$PHASE_DIR/.execution-state.json")
  [ "$(echo "$state" | jq -r '.plans[0].status')" = "complete" ]
  [ "$(echo "$state" | jq -r '.plans[1].status')" = "pending" ]
}

@test "refuses to overwrite existing running state" {
  PHASE_DIR="$TEST_WORKDIR/03-running"
  mkdir -p "$PHASE_DIR"
  mk_plan_header "03" "01" "Plan A" 1

  # Create existing state with running status
  jq -n '{status:"running",phase:3}' > "$PHASE_DIR/.execution-state.json"

  run bash "$SUT" --phase-dir "$PHASE_DIR" --phase 03
  assert_failure
  assert_output --partial "Existing state found"
}

@test "--force overwrites existing state" {
  PHASE_DIR="$TEST_WORKDIR/03-force"
  mkdir -p "$PHASE_DIR"
  mk_plan_header "03" "01" "Plan A" 1

  # Create existing state with running status
  jq -n '{status:"running",phase:3}' > "$PHASE_DIR/.execution-state.json"

  run bash "$SUT" --phase-dir "$PHASE_DIR" --phase 03 --force
  assert_success

  # Verify new state was generated
  local state
  state=$(cat "$PHASE_DIR/.execution-state.json")
  [ "$(echo "$state" | jq '.plans | length')" -eq 1 ]
}

@test "fails with no plan files" {
  PHASE_DIR="$TEST_WORKDIR/03-empty"
  mkdir -p "$PHASE_DIR"

  run bash "$SUT" --phase-dir "$PHASE_DIR" --phase 03
  assert_failure
  assert_output --partial "No plan.jsonl files"
}

@test "detects completed critique step from artifact" {
  PHASE_DIR="$TEST_WORKDIR/03-critique"
  mkdir -p "$PHASE_DIR"
  mk_plan_header "03" "01" "Plan A" 1

  # Create critique.jsonl artifact
  echo '{"id":"C1","cat":"gap","sev":"minor","q":"test"}' > "$PHASE_DIR/critique.jsonl"

  run bash "$SUT" --phase-dir "$PHASE_DIR" --phase 03
  assert_success

  local state
  state=$(cat "$PHASE_DIR/.execution-state.json")
  [ "$(echo "$state" | jq -r '.steps.critique.status')" = "complete" ]
}

@test "phase_name extracted from directory name" {
  PHASE_DIR="$TEST_WORKDIR/03-token-optimization"
  mkdir -p "$PHASE_DIR"
  mk_plan_header "03" "01" "Plan A" 1

  run bash "$SUT" --phase-dir "$PHASE_DIR" --phase 03
  assert_success

  local state
  state=$(cat "$PHASE_DIR/.execution-state.json")
  [ "$(echo "$state" | jq -r '.phase_name')" = "token-optimization" ]
}
