#!/usr/bin/env bats
# concurrent-reads.bats — Verify 15+ parallel readers never block under WAL mode

setup() {
  load '../../test_helper/common'
  load '../../test_helper/db_helper'
  SUT_GET_TASK="$SCRIPTS_DIR/db/get-task.sh"
  SUT_GET_SUMMARIES="$SCRIPTS_DIR/db/get-summaries.sh"
  SUT_CHECK_PHASE="$SCRIPTS_DIR/db/check-phase-status.sh"
  mk_test_db

  # Seed 100+ tasks across 10 plans in phase 09
  for plan_i in $(seq -w 1 10); do
    db_insert_plan "09" "09-${plan_i}" "Plan ${plan_i}"
    for task_i in $(seq 1 10); do
      db_insert_task "09-${plan_i}" "T${task_i}" "Task ${plan_i}-${task_i}" "complete"
    done
    db_insert_summary "09-${plan_i}" "complete"
  done
}

@test "15 parallel get-task.sh readers all succeed" {
  local pids=() results_dir
  results_dir="$BATS_TEST_TMPDIR/read-results"
  mkdir -p "$results_dir"

  # Launch 15 parallel readers
  for i in $(seq 1 15); do
    plan_idx=$(( (i % 10) + 1 ))
    plan_num=$(printf '09-%02d' "$plan_idx")
    plan_rowid=$(sqlite3 "$TEST_DB" "SELECT rowid FROM plans WHERE plan_num='$plan_num';")
    bash "$SUT_GET_TASK" "$plan_rowid" "T1" --db "$TEST_DB" > "$results_dir/r${i}.out" 2>"$results_dir/r${i}.err" &
    pids+=($!)
  done

  # Wait for all
  local failures=0
  for pid in "${pids[@]}"; do
    wait "$pid" || ((failures++)) || true
  done

  [ "$failures" -eq 0 ]
}

@test "15 parallel check-phase-status.sh readers all return consistent data" {
  local pids=() results_dir
  results_dir="$BATS_TEST_TMPDIR/phase-results"
  mkdir -p "$results_dir"

  for i in $(seq 1 15); do
    bash "$SUT_CHECK_PHASE" "09" --db "$TEST_DB" > "$results_dir/r${i}.out" 2>"$results_dir/r${i}.err" &
    pids+=($!)
  done

  local failures=0
  for pid in "${pids[@]}"; do
    wait "$pid" || ((failures++)) || true
  done

  [ "$failures" -eq 0 ]

  # All 15 should return identical results
  local first_hash
  first_hash=$(shasum "$results_dir/r1.out" | cut -d' ' -f1)
  for i in $(seq 2 15); do
    local h
    h=$(shasum "$results_dir/r${i}.out" | cut -d' ' -f1)
    [ "$h" = "$first_hash" ]
  done
}

@test "no SQLITE_BUSY errors under parallel reads" {
  local results_dir
  results_dir="$BATS_TEST_TMPDIR/busy-check"
  mkdir -p "$results_dir"
  local pids=()

  # Pre-resolve plan_rowid before concurrent work
  local plan_rowid
  plan_rowid=$(sqlite3 "$TEST_DB" "SELECT rowid FROM plans WHERE plan_num='09-01';")

  # Mix of read operations — all launched in parallel
  for i in $(seq 1 15); do
    case $((i % 3)) in
      0)
        bash "$SUT_GET_TASK" "$plan_rowid" "T1" --db "$TEST_DB" >"$results_dir/r${i}.out" 2>"$results_dir/r${i}.err" &
        ;;
      1)
        bash "$SUT_CHECK_PHASE" "09" --db "$TEST_DB" >"$results_dir/r${i}.out" 2>"$results_dir/r${i}.err" &
        ;;
      2)
        bash "$SUT_CHECK_PHASE" "09" --json --db "$TEST_DB" >"$results_dir/r${i}.out" 2>"$results_dir/r${i}.err" &
        ;;
    esac
    pids+=($!)
  done

  for pid in "${pids[@]}"; do
    wait "$pid" || true
  done

  # Check no SQLITE_BUSY in any stderr
  local busy_count=0
  for i in $(seq 1 15); do
    if [[ -f "$results_dir/r${i}.err" ]] && grep -qi "busy\|locked" "$results_dir/r${i}.err" 2>/dev/null; then
      ((busy_count++)) || true
    fi
  done
  [ "$busy_count" -eq 0 ]
}

@test "wall-clock time for 15 parallel reads under 5s" {
  local results_dir
  results_dir="$BATS_TEST_TMPDIR/timing"
  mkdir -p "$results_dir"
  local pids=()

  local start_time
  start_time=$(date +%s)

  for i in $(seq 1 15); do
    bash "$SUT_CHECK_PHASE" "09" --json --db "$TEST_DB" >"$results_dir/r${i}.out" 2>/dev/null &
    pids+=($!)
  done

  for pid in "${pids[@]}"; do
    wait "$pid" || true
  done

  local end_time elapsed
  end_time=$(date +%s)
  elapsed=$((end_time - start_time))
  [ "$elapsed" -lt 5 ]
}

@test "WAL mode maintained throughout parallel reads" {
  local pids=()
  local results_dir
  results_dir="$BATS_TEST_TMPDIR/wal-check"
  mkdir -p "$results_dir"

  # Parallel reads
  for i in $(seq 1 15); do
    bash "$SUT_CHECK_PHASE" "09" --db "$TEST_DB" >/dev/null 2>/dev/null &
    pids+=($!)
  done

  for pid in "${pids[@]}"; do
    wait "$pid" || true
  done

  # Verify WAL mode still active
  local journal
  journal=$(sqlite3 "$TEST_DB" "PRAGMA journal_mode;")
  [ "$journal" = "wal" ]
}
