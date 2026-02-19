#!/usr/bin/env bats
# checkpoint-db.bats — Unit tests for scripts/db/checkpoint-db.sh

setup() {
  load '../../test_helper/common'
  load '../../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/db/checkpoint-db.sh"
  DB="$TEST_WORKDIR/test.db"
  sqlite3 "$DB" < "$SCRIPTS_DIR/db/schema.sql"
  sqlite3 "$DB" "PRAGMA journal_mode=WAL;" >/dev/null
  sqlite3 "$DB" "PRAGMA busy_timeout=5000;" >/dev/null
  # Insert data to create WAL entries
  sqlite3 "$DB" "INSERT INTO plans (phase, plan_num, title) VALUES ('01','01','Test plan');"
  for i in $(seq 1 10); do
    sqlite3 "$DB" "INSERT INTO critique (id, cat, sev, q, phase) VALUES ('C${i}','risk','major','Finding ${i}','01');"
  done
}

@test "passive checkpoint succeeds" {
  run bash "$SUT" --mode passive --db "$DB"
  assert_success
  assert_output --partial "mode: passive"
  assert_output --partial "wal_pages:"
  assert_output --partial "checkpointed:"
}

@test "full checkpoint succeeds" {
  run bash "$SUT" --mode full --db "$DB"
  assert_success
  assert_output --partial "mode: full"
}

@test "truncate checkpoint reclaims WAL space" {
  # Generate WAL data
  for i in $(seq 11 50); do
    sqlite3 "$DB" "INSERT INTO critique (id, cat, sev, q, phase) VALUES ('X${i}','risk','minor','Extra ${i}','01');"
  done

  # Check WAL file exists and has data
  [ -f "${DB}-wal" ]

  run bash "$SUT" --mode truncate --db "$DB"
  assert_success
  assert_output --partial "mode: truncate"

  # After truncate, WAL should be small or empty
  local wal_size
  if [[ -f "${DB}-wal" ]]; then
    wal_size=$(wc -c < "${DB}-wal" | tr -d ' ')
  else
    wal_size=0
  fi
  [ "$wal_size" -lt 4096 ]
}

@test "reports WAL size in bytes" {
  run bash "$SUT" --db "$DB"
  assert_success
  assert_output --partial "wal_size_bytes:"
}

@test "default mode is passive" {
  run bash "$SUT" --db "$DB"
  assert_success
  assert_output --partial "mode: passive"
}

@test "invalid mode exits with error" {
  run bash "$SUT" --mode invalid --db "$DB"
  assert_failure
  assert_output --partial "invalid mode"
}

@test "exits 1 when database missing" {
  run bash "$SUT" --db "$TEST_WORKDIR/nonexistent.db"
  assert_failure
  assert_output --partial "database not found"
}

@test "restart checkpoint succeeds" {
  run bash "$SUT" --mode restart --db "$DB"
  assert_success
  assert_output --partial "mode: restart"
}
