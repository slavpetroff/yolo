#!/usr/bin/env bats
# concurrent-writes.bats — Verify concurrent writes serialize correctly via WAL

setup() {
  load '../../test_helper/common'
  load '../../test_helper/db_helper'
  SUT_NEXT_TASK="$SCRIPTS_DIR/db/next-task.sh"
  SUT_APPEND="$SCRIPTS_DIR/db/append-finding.sh"
  mk_test_db

  # Seed 20 pending tasks across 2 plans (no deps so all are claimable)
  db_insert_plan "09" "09-01" "Plan A"
  for i in $(seq 1 10); do
    db_insert_task "09-01" "T${i}" "Task A-${i}" "pending" "[]"
  done
  db_insert_plan "09" "09-02" "Plan B"
  for i in $(seq 1 10); do
    db_insert_task "09-02" "T${i}" "Task B-${i}" "pending" "[]"
  done
}

@test "10 parallel next-task.sh calls each claim exactly 1 unique task" {
  local results_dir
  results_dir="$BATS_TEST_TMPDIR/claim-results"
  mkdir -p "$results_dir"
  local pids=()

  for i in $(seq 1 10); do
    YOLO_AGENT="agent-${i}" bash "$SUT_NEXT_TASK" --db "$TEST_DB" \
      > "$results_dir/a${i}.out" 2>"$results_dir/a${i}.err" &
    pids+=($!)
  done

  for pid in "${pids[@]}"; do
    wait "$pid" || true
  done

  # Count how many agents got a task
  local claimed=0
  for i in $(seq 1 10); do
    if [[ -s "$results_dir/a${i}.out" ]]; then
      ((claimed++)) || true
    fi
  done
  [ "$claimed" -eq 10 ]

  # Verify no duplicate claims (each task_id appears at most once)
  local task_ids
  task_ids=$(cat "$results_dir"/a*.out | grep '^id: ' | sort)
  local unique_count dup_count
  unique_count=$(echo "$task_ids" | sort -u | wc -l | tr -d ' ')
  dup_count=$(echo "$task_ids" | wc -l | tr -d ' ')
  [ "$unique_count" -eq "$dup_count" ]
}

@test "exactly 10 tasks claimed, 10 remain pending" {
  local results_dir
  results_dir="$BATS_TEST_TMPDIR/claim-count"
  mkdir -p "$results_dir"
  local pids=()

  for i in $(seq 1 10); do
    YOLO_AGENT="agent-${i}" bash "$SUT_NEXT_TASK" --db "$TEST_DB" \
      > "$results_dir/a${i}.out" 2>/dev/null &
    pids+=($!)
  done

  for pid in "${pids[@]}"; do
    wait "$pid" || true
  done

  local in_progress pending
  in_progress=$(sqlite3 "$TEST_DB" "SELECT count(*) FROM tasks WHERE status='in_progress';")
  pending=$(sqlite3 "$TEST_DB" "SELECT count(*) FROM tasks WHERE status='pending';")
  [ "$in_progress" -eq 10 ]
  [ "$pending" -eq 10 ]
}

@test "5 parallel append-finding.sh to critique table all succeed" {
  local results_dir
  results_dir="$BATS_TEST_TMPDIR/append-results"
  mkdir -p "$results_dir"
  local pids=()

  for i in $(seq 1 5); do
    bash "$SUT_APPEND" \
      --type critique \
      --phase "09" \
      --data "{\"id\":\"C${i}\",\"cat\":\"risk\",\"sev\":\"major\",\"q\":\"Finding ${i}\"}" \
      --db "$TEST_DB" \
      > "$results_dir/f${i}.out" 2>"$results_dir/f${i}.err" &
    pids+=($!)
  done

  for pid in "${pids[@]}"; do
    wait "$pid" || true
  done

  # All 5 should have succeeded
  local ok_count=0
  for i in $(seq 1 5); do
    if grep -q "^ok:" "$results_dir/f${i}.out" 2>/dev/null; then
      ((ok_count++)) || true
    fi
  done
  [ "$ok_count" -eq 5 ]

  # All 5 inserted (no lost writes)
  local critique_count
  critique_count=$(sqlite3 "$TEST_DB" "SELECT count(*) FROM critique WHERE phase='09';")
  [ "$critique_count" -eq 5 ]
}

@test "no SQLITE_BUSY errors during parallel writes" {
  local results_dir
  results_dir="$BATS_TEST_TMPDIR/busy-writes"
  mkdir -p "$results_dir"
  local pids=()

  for i in $(seq 1 10); do
    YOLO_AGENT="agent-${i}" bash "$SUT_NEXT_TASK" --db "$TEST_DB" \
      > "$results_dir/a${i}.out" 2>"$results_dir/a${i}.err" &
    pids+=($!)
  done

  for pid in "${pids[@]}"; do
    wait "$pid" || true
  done

  local busy_count=0
  for i in $(seq 1 10); do
    if [[ -f "$results_dir/a${i}.err" ]] && grep -qi "busy\|locked" "$results_dir/a${i}.err" 2>/dev/null; then
      ((busy_count++)) || true
    fi
  done
  [ "$busy_count" -eq 0 ]
}

@test "busy_timeout prevents failures under contention" {
  # Start a long-running writer that holds a lock briefly
  sqlite3 "$TEST_DB" "BEGIN IMMEDIATE; INSERT INTO critique (id, cat, sev, q, phase) VALUES ('SLOW','risk','major','slow write','09'); SELECT randomblob(1000); COMMIT;" >/dev/null &
  local slow_pid=$!

  # Immediately try another write — busy_timeout should handle it
  run bash "$SUT_APPEND" \
    --type critique \
    --phase "09" \
    --data '{"id":"FAST","cat":"risk","sev":"minor","q":"fast write"}' \
    --db "$TEST_DB"

  wait "$slow_pid" 2>/dev/null || true
  assert_success
  assert_output --partial "ok:"
}
