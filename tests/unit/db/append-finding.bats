#!/usr/bin/env bats
# append-finding.bats — Unit tests for scripts/db/append-finding.sh

setup() {
  load '../../test_helper/common'
  load '../../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/db/append-finding.sh"
  DB="$TEST_WORKDIR/test.db"
  # Create DB with schema (includes FTS5 tables if available)
  sqlite3 "$DB" < "$SCRIPTS_DIR/db/schema.sql"
  sqlite3 "$DB" "PRAGMA journal_mode=WAL;"
}

@test "inserts critique with required fields" {
  run bash "$SUT" --type critique --phase 10 \
    --data '{"id":"C1","cat":"gap","sev":"major","q":"Missing error handling"}' \
    --db "$DB"
  assert_success
  assert_output --partial "ok: critique C1 appended"
  local q
  q=$(sqlite3 "$DB" "SELECT q FROM critique WHERE id='C1';")
  [ "$q" = "Missing error handling" ]
}

@test "critique validates required fields" {
  run bash "$SUT" --type critique --phase 10 \
    --data '{"id":"C1","cat":"gap"}' \
    --db "$DB"
  assert_failure
  assert_output --partial "requires id, cat, sev, q"
}

@test "inserts research with FTS update" {
  run bash "$SUT" --type research --phase 10 \
    --data '{"q":"How does auth work?","finding":"JWT tokens with refresh","conf":"high","src":"docs"}' \
    --db "$DB"
  assert_success
  assert_output --partial "ok: research appended"
  local finding
  finding=$(sqlite3 "$DB" "SELECT finding FROM research WHERE q='How does auth work?';")
  [ "$finding" = "JWT tokens with refresh" ]
}

@test "research validates required fields" {
  run bash "$SUT" --type research --phase 10 \
    --data '{"q":"test question"}' \
    --db "$DB"
  assert_failure
  assert_output --partial "requires q, finding, conf"
}

@test "inserts decision" {
  run bash "$SUT" --type decisions --phase 10 \
    --data '{"dec":"Use SQLite for storage","reason":"Zero deps, WAL mode","agent":"architect","ts":"2026-02-19T10:00:00Z"}' \
    --db "$DB"
  assert_success
  assert_output --partial "ok: decision appended"
  local dec
  dec=$(sqlite3 "$DB" "SELECT dec FROM decisions WHERE agent='architect';")
  [ "$dec" = "Use SQLite for storage" ]
}

@test "inserts escalation" {
  run bash "$SUT" --type escalation --phase 10 \
    --data '{"id":"ESC-10-03-T1","reason":"Blocked by missing schema","sev":"blocking","agent":"dev","tgt":"lead"}' \
    --db "$DB"
  assert_success
  assert_output --partial "ok: escalation ESC-10-03-T1 appended"
}

@test "inserts gap" {
  run bash "$SUT" --type gaps --phase 10 \
    --data '{"id":"G1","sev":"major","desc":"No error handling for DB writes","exp":"Transaction rollback","act":"Silent failure"}' \
    --db "$DB"
  assert_success
  assert_output --partial "ok: gap G1 appended"
}

@test "inserts code-review-comment" {
  run bash "$SUT" --type code-review-comment --phase 10 \
    --data '{"plan":"10-03","r":"approve","tdd":"pass","cycle":1,"dt":"2026-02-19"}' \
    --db "$DB"
  assert_success
  assert_output --partial "ok: code-review appended"
}

@test "inserts security-finding" {
  run bash "$SUT" --type security-finding --phase 10 \
    --data '{"r":"PASS","findings":0,"critical":0,"dt":"2026-02-19"}' \
    --db "$DB"
  assert_success
  assert_output --partial "ok: security-finding appended"
}

@test "inserts qa-gate-result" {
  run bash "$SUT" --type qa-gate-result --phase 10 \
    --data '{"gl":"post-task","r":"PASS","plan":"10-03","task":"T1","dt":"2026-02-19"}' \
    --db "$DB"
  assert_success
  assert_output --partial "ok: qa-gate-result appended"
}

@test "rejects unknown type" {
  run bash "$SUT" --type foobar --phase 10 \
    --data '{"key":"val"}' \
    --db "$DB"
  assert_failure
  assert_output --partial "unknown type"
}

@test "rejects invalid JSON" {
  run bash "$SUT" --type critique --phase 10 \
    --data 'not-json' \
    --db "$DB"
  assert_failure
  assert_output --partial "must be valid JSON"
}

@test "missing --type exits 1" {
  run bash "$SUT" --phase 10 --data '{}' --db "$DB"
  assert_failure
  assert_output --partial "--type is required"
}

@test "missing --phase exits 1" {
  run bash "$SUT" --type critique --data '{}' --db "$DB"
  assert_failure
  assert_output --partial "--phase is required"
}

@test "missing --data exits 1" {
  run bash "$SUT" --type critique --phase 10 --db "$DB"
  assert_failure
  assert_output --partial "--data is required"
}
