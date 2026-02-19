#!/usr/bin/env bats
# update-status.bats — Unit tests for scripts/db/update-status.sh

setup() {
  load '../../test_helper/common'
  load '../../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/db/update-status.sh"
  INSERT_TASK="$SCRIPTS_DIR/db/insert-task.sh"
  APPEND="$SCRIPTS_DIR/db/append-finding.sh"
  DB="$TEST_WORKDIR/test.db"
  # Create DB with schema
  sqlite3 "$DB" < "$SCRIPTS_DIR/db/schema.sql"
  sqlite3 "$DB" "PRAGMA journal_mode=WAL;"
}

# -- Task transitions --

@test "task: pending -> in_progress succeeds" {
  bash "$INSERT_TASK" --plan 10-03 --id T1 --action "Test task" --db "$DB"
  run bash "$SUT" --type task --id T1 --status in_progress --db "$DB"
  assert_success
  assert_output "pending -> in_progress"
}

@test "task: in_progress -> complete succeeds" {
  bash "$INSERT_TASK" --plan 10-03 --id T1 --action "Test task" --db "$DB"
  bash "$SUT" --type task --id T1 --status in_progress --db "$DB"
  run bash "$SUT" --type task --id T1 --status complete --db "$DB"
  assert_success
  assert_output "in_progress -> complete"
}

@test "task: complete -> pending rejected" {
  bash "$INSERT_TASK" --plan 10-03 --id T1 --action "Test task" --db "$DB"
  bash "$SUT" --type task --id T1 --status complete --db "$DB"
  run bash "$SUT" --type task --id T1 --status pending --db "$DB"
  assert_failure
  assert_output --partial "invalid transition"
}

# -- Escalation transitions --

@test "escalation: open -> escalated succeeds" {
  bash "$APPEND" --type escalation --phase 10 \
    --data '{"id":"ESC-1","reason":"blocked","sev":"blocking"}' --db "$DB"
  run bash "$SUT" --type escalation --id ESC-1 --status escalated --db "$DB"
  assert_success
  assert_output "open -> escalated"
}

@test "escalation: escalated -> resolved with resolution" {
  bash "$APPEND" --type escalation --phase 10 \
    --data '{"id":"ESC-2","reason":"blocked","sev":"major"}' --db "$DB"
  bash "$SUT" --type escalation --id ESC-2 --status escalated --db "$DB"
  run bash "$SUT" --type escalation --id ESC-2 --status resolved \
    --resolution "Fixed by adding retry logic" --db "$DB"
  assert_success
  assert_output "escalated -> resolved"
  # Verify resolution stored
  local res
  res=$(sqlite3 "$DB" "SELECT res FROM escalation WHERE id='ESC-2';")
  [ "$res" = "Fixed by adding retry logic" ]
}

@test "escalation: resolved -> open rejected" {
  bash "$APPEND" --type escalation --phase 10 \
    --data '{"id":"ESC-3","reason":"blocked","sev":"minor"}' --db "$DB"
  bash "$SUT" --type escalation --id ESC-3 --status resolved --db "$DB"
  run bash "$SUT" --type escalation --id ESC-3 --status open --db "$DB"
  assert_failure
  assert_output --partial "invalid transition"
}

# -- Gap transitions --

@test "gap: open -> fixed succeeds" {
  bash "$APPEND" --type gaps --phase 10 \
    --data '{"id":"G1","sev":"major","desc":"Missing handler"}' --db "$DB"
  run bash "$SUT" --type gap --id G1 --status fixed --db "$DB"
  assert_success
  assert_output "open -> fixed"
}

@test "gap: fixed -> accepted succeeds" {
  bash "$APPEND" --type gaps --phase 10 \
    --data '{"id":"G2","sev":"minor","desc":"Typo in message"}' --db "$DB"
  bash "$SUT" --type gap --id G2 --status fixed --db "$DB"
  run bash "$SUT" --type gap --id G2 --status accepted --db "$DB"
  assert_success
  assert_output "fixed -> accepted"
}

# -- Critique transitions --

@test "critique: open -> addressed succeeds" {
  bash "$APPEND" --type critique --phase 10 \
    --data '{"id":"C1","cat":"gap","sev":"major","q":"Missing validation"}' --db "$DB"
  run bash "$SUT" --type critique --id C1 --status addressed --db "$DB"
  assert_success
  assert_output "open -> addressed"
}

@test "critique: open -> rejected succeeds" {
  bash "$APPEND" --type critique --phase 10 \
    --data '{"id":"C2","cat":"improvement","sev":"minor","q":"Refactor suggestion"}' --db "$DB"
  run bash "$SUT" --type critique --id C2 --status rejected --db "$DB"
  assert_success
  assert_output "open -> rejected"
}

@test "critique: addressed -> rejected succeeds" {
  bash "$APPEND" --type critique --phase 10 \
    --data '{"id":"C3","cat":"risk","sev":"major","q":"Performance concern"}' --db "$DB"
  bash "$SUT" --type critique --id C3 --status addressed --db "$DB"
  run bash "$SUT" --type critique --id C3 --status rejected --db "$DB"
  assert_success
  assert_output "addressed -> rejected"
}

# -- Error cases --

@test "prints status change to stdout" {
  bash "$INSERT_TASK" --plan 10-03 --id T1 --action "Test" --db "$DB"
  run bash "$SUT" --type task --id T1 --status in_progress --db "$DB"
  assert_success
  assert_output "pending -> in_progress"
}

@test "exit 1 on not-found record" {
  run bash "$SUT" --type task --id T99 --status in_progress --db "$DB"
  assert_failure
  assert_output --partial "not found"
}

@test "exit 1 on unknown type" {
  run bash "$SUT" --type foobar --id X1 --status open --db "$DB"
  assert_failure
  assert_output --partial "unknown type"
}

@test "missing --type exits 1" {
  run bash "$SUT" --id T1 --status pending --db "$DB"
  assert_failure
  assert_output --partial "--type is required"
}

@test "missing --id exits 1" {
  run bash "$SUT" --type task --status pending --db "$DB"
  assert_failure
  assert_output --partial "--id is required"
}

@test "missing --status exits 1" {
  run bash "$SUT" --type task --id T1 --db "$DB"
  assert_failure
  assert_output --partial "--status is required"
}
