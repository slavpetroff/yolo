#!/usr/bin/env bats
# concurrent-mixed.bats — Verify readers never see partial writes (atomicity)

setup() {
  load '../../test_helper/common'
  load '../../test_helper/db_helper'
  SUT_COMPLETE="$SCRIPTS_DIR/db/complete-task.sh"
  SUT_CHECK_PHASE="$SCRIPTS_DIR/db/check-phase-status.sh"
  SUT_GET_SUMMARIES="$SCRIPTS_DIR/db/get-summaries.sh"
  mk_test_db

  # Seed 30 tasks in phase 09, split across 3 plans
  # Use plan_num convention matching insert-task.sh: plan_num is suffix only (e.g. "01")
  for plan_i in 01 02 03; do
    db_insert_plan "09" "${plan_i}" "Plan ${plan_i}"
    for task_i in $(seq 1 10); do
      db_insert_task "${plan_i}" "T${task_i}" "Task ${plan_i}-${task_i}" "pending" "[]"
    done
  done
}

@test "5 writers + 10 readers all complete without errors" {
  local results_dir
  results_dir="$BATS_TEST_TMPDIR/mixed-results"
  mkdir -p "$results_dir"
  local pids=()

  # 5 writers: complete 5 tasks (T1-T5 in plan 09-01)
  for i in $(seq 1 5); do
    # Set tasks to in_progress first (complete-task.sh requires pending or in_progress)
    sqlite3 "$TEST_DB" "UPDATE tasks SET status='in_progress' WHERE task_id='T${i}' AND plan_id=(SELECT rowid FROM plans WHERE plan_num='01');"
    bash "$SUT_COMPLETE" "T${i}" --plan "09-01" --summary "Completed task ${i}" --db "$TEST_DB" \
      > "$results_dir/w${i}.out" 2>"$results_dir/w${i}.err" &
    pids+=($!)
  done

  # 10 readers: check phase status
  for i in $(seq 1 10); do
    bash "$SUT_CHECK_PHASE" "09" --json --db "$TEST_DB" \
      > "$results_dir/r${i}.out" 2>"$results_dir/r${i}.err" &
    pids+=($!)
  done

  local failures=0
  for pid in "${pids[@]}"; do
    wait "$pid" || ((failures++)) || true
  done

  [ "$failures" -eq 0 ]
}

@test "writers all succeed: 5 tasks become complete" {
  local results_dir
  results_dir="$BATS_TEST_TMPDIR/writer-verify"
  mkdir -p "$results_dir"
  local pids=()

  # Set tasks to in_progress first
  for i in $(seq 1 5); do
    sqlite3 "$TEST_DB" "UPDATE tasks SET status='in_progress' WHERE task_id='T${i}' AND plan_id=(SELECT rowid FROM plans WHERE plan_num='01');"
  done

  for i in $(seq 1 5); do
    bash "$SUT_COMPLETE" "T${i}" --plan "09-01" --summary "Done ${i}" --db "$TEST_DB" \
      > "$results_dir/w${i}.out" 2>"$results_dir/w${i}.err" &
    pids+=($!)
  done

  for pid in "${pids[@]}"; do
    wait "$pid" || true
  done

  # Verify final state
  local complete_count
  complete_count=$(sqlite3 "$TEST_DB" \
    "SELECT count(*) FROM tasks t JOIN plans p ON t.plan_id=p.rowid WHERE t.status='complete' AND p.plan_num='01';")
  [ "$complete_count" -eq 5 ]
}

@test "final state: 5 complete + 25 pending after mixed operations" {
  local results_dir
  results_dir="$BATS_TEST_TMPDIR/final-state"
  mkdir -p "$results_dir"
  local pids=()

  # Set T1-T5 in plan 09-01 to in_progress
  for i in $(seq 1 5); do
    sqlite3 "$TEST_DB" "UPDATE tasks SET status='in_progress' WHERE task_id='T${i}' AND plan_id=(SELECT rowid FROM plans WHERE plan_num='01');"
  done

  # Writers
  for i in $(seq 1 5); do
    bash "$SUT_COMPLETE" "T${i}" --plan "09-01" --summary "Done ${i}" --db "$TEST_DB" \
      > "$results_dir/w${i}.out" 2>/dev/null &
    pids+=($!)
  done

  # Readers
  for i in $(seq 1 10); do
    bash "$SUT_CHECK_PHASE" "09" --db "$TEST_DB" \
      > "$results_dir/r${i}.out" 2>/dev/null &
    pids+=($!)
  done

  for pid in "${pids[@]}"; do
    wait "$pid" || true
  done

  local complete pending
  complete=$(sqlite3 "$TEST_DB" "SELECT count(*) FROM tasks WHERE status='complete';")
  pending=$(sqlite3 "$TEST_DB" "SELECT count(*) FROM tasks WHERE status='pending';")
  [ "$complete" -eq 5 ]
  [ "$pending" -eq 25 ]
}

@test "readers see consistent percentages (no partial transactions)" {
  local results_dir
  results_dir="$BATS_TEST_TMPDIR/consistency"
  mkdir -p "$results_dir"
  local pids=()

  # Pre-set some tasks to in_progress for completion
  for i in $(seq 1 5); do
    sqlite3 "$TEST_DB" "UPDATE tasks SET status='in_progress' WHERE task_id='T${i}' AND plan_id=(SELECT rowid FROM plans WHERE plan_num='01');"
  done

  # Writers
  for i in $(seq 1 5); do
    bash "$SUT_COMPLETE" "T${i}" --plan "09-01" --summary "Done ${i}" --db "$TEST_DB" \
      > "$results_dir/w${i}.out" 2>/dev/null &
    pids+=($!)
  done

  # Readers
  for i in $(seq 1 10); do
    bash "$SUT_CHECK_PHASE" "09" --json --db "$TEST_DB" \
      > "$results_dir/r${i}.out" 2>/dev/null &
    pids+=($!)
  done

  for pid in "${pids[@]}"; do
    wait "$pid" || true
  done

  # Each reader's completed_tasks must be a valid number (0-5), never fractional
  for i in $(seq 1 10); do
    if [[ -s "$results_dir/r${i}.out" ]]; then
      local ct
      ct=$(jq -r '.completed_tasks' "$results_dir/r${i}.out" 2>/dev/null || echo "0")
      # Must be an integer between 0 and 5
      [[ "$ct" =~ ^[0-9]+$ ]]
      [ "$ct" -ge 0 ]
      [ "$ct" -le 5 ]
    fi
  done
}

@test "no SQLITE_BUSY errors in mixed read-write load" {
  local results_dir
  results_dir="$BATS_TEST_TMPDIR/busy-mixed"
  mkdir -p "$results_dir"
  local pids=()

  for i in $(seq 1 5); do
    sqlite3 "$TEST_DB" "UPDATE tasks SET status='in_progress' WHERE task_id='T${i}' AND plan_id=(SELECT rowid FROM plans WHERE plan_num='01');"
  done

  for i in $(seq 1 5); do
    bash "$SUT_COMPLETE" "T${i}" --plan "09-01" --summary "Done ${i}" --db "$TEST_DB" \
      > "$results_dir/w${i}.out" 2>"$results_dir/w${i}.err" &
    pids+=($!)
  done

  for i in $(seq 1 10); do
    bash "$SUT_CHECK_PHASE" "09" --db "$TEST_DB" \
      > "$results_dir/r${i}.out" 2>"$results_dir/r${i}.err" &
    pids+=($!)
  done

  for pid in "${pids[@]}"; do
    wait "$pid" || true
  done

  local busy_count=0
  for f in "$results_dir"/*.err; do
    if [[ -f "$f" ]] && grep -qi "busy\|locked" "$f" 2>/dev/null; then
      ((busy_count++)) || true
    fi
  done
  [ "$busy_count" -eq 0 ]
}
