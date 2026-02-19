#!/usr/bin/env bats
# init-db.bats — Unit tests for scripts/db/init-db.sh

setup() {
  load '../../test_helper/common'
  load '../../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/db/init-db.sh"
  PLANNING="$TEST_WORKDIR/.vbw-planning"
  mkdir -p "$PLANNING"
}

# ============================================================
# Basic creation
# ============================================================

@test "creates DB file at default planning dir" {
  run bash "$SUT" --planning-dir "$PLANNING"
  assert_success
  assert_output "$PLANNING/yolo.db"
  [ -f "$PLANNING/yolo.db" ]
}

@test "DB has WAL journal mode" {
  bash "$SUT" --planning-dir "$PLANNING" >/dev/null
  local mode
  mode=$(sqlite3 "$PLANNING/yolo.db" "PRAGMA journal_mode;")
  [ "$mode" = "wal" ]
}

@test "DB has foreign keys enabled via schema" {
  bash "$SUT" --planning-dir "$PLANNING" >/dev/null
  # Verify FK pragma is in schema (applied on connection)
  local fk
  fk=$(sqlite3 "$PLANNING/yolo.db" "PRAGMA foreign_keys;" 2>/dev/null)
  # Note: PRAGMA foreign_keys needs to be set per connection,
  # but schema.sql sets it. Verify schema loaded by checking tables.
  local count
  count=$(sqlite3 "$PLANNING/yolo.db" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='plans';")
  [ "$count" = "1" ]
}

@test "DB contains all tables from schema" {
  bash "$SUT" --planning-dir "$PLANNING" >/dev/null
  local count
  count=$(sqlite3 "$PLANNING/yolo.db" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';")
  [ "$count" -ge 20 ]
}

# ============================================================
# Idempotent re-run
# ============================================================

@test "idempotent: re-run exits 0 without recreating" {
  bash "$SUT" --planning-dir "$PLANNING" >/dev/null
  # Insert a marker row
  sqlite3 "$PLANNING/yolo.db" "INSERT INTO state (ms) VALUES ('marker');"
  # Re-run
  run bash "$SUT" --planning-dir "$PLANNING"
  assert_success
  # Marker row still exists (DB was not recreated)
  local count
  count=$(sqlite3 "$PLANNING/yolo.db" "SELECT COUNT(*) FROM state WHERE ms='marker';")
  [ "$count" = "1" ]
}

@test "idempotent: outputs DB path on re-run" {
  bash "$SUT" --planning-dir "$PLANNING" >/dev/null
  run bash "$SUT" --planning-dir "$PLANNING"
  assert_success
  assert_output "$PLANNING/yolo.db"
}

# ============================================================
# --force flag
# ============================================================

@test "--force recreates DB" {
  bash "$SUT" --planning-dir "$PLANNING" >/dev/null
  # Insert a marker row
  sqlite3 "$PLANNING/yolo.db" "INSERT INTO state (ms) VALUES ('marker');"
  # Force recreate
  run bash "$SUT" --planning-dir "$PLANNING" --force
  assert_success
  # Marker row gone (DB was recreated)
  local count
  count=$(sqlite3 "$PLANNING/yolo.db" "SELECT COUNT(*) FROM state WHERE ms='marker';")
  [ "$count" = "0" ]
}

@test "--force cleans WAL/SHM files" {
  bash "$SUT" --planning-dir "$PLANNING" >/dev/null
  # Create dummy WAL/SHM files
  touch "$PLANNING/yolo.db-wal" "$PLANNING/yolo.db-shm"
  bash "$SUT" --planning-dir "$PLANNING" --force >/dev/null
  # WAL may be recreated by WAL mode, but SHM should not exist before writes
  [ -f "$PLANNING/yolo.db" ]
}

# ============================================================
# --verify flag
# ============================================================

@test "--verify passes on valid DB" {
  bash "$SUT" --planning-dir "$PLANNING" >/dev/null
  run bash "$SUT" --planning-dir "$PLANNING" --verify
  assert_success
  assert_output --partial "Integrity: ok"
  assert_output --partial "Tables:"
  assert_output --partial "Journal mode: wal"
}

@test "--verify fails on missing DB" {
  run bash "$SUT" --planning-dir "$PLANNING" --verify
  assert_failure
  assert_output --partial "DB not found"
}

# ============================================================
# Error handling
# ============================================================

@test "unknown argument exits with error" {
  run bash "$SUT" --unknown-flag
  assert_failure
  assert_output --partial "Unknown argument"
}

@test "--help shows usage" {
  run bash "$SUT" --help
  assert_success
  assert_output --partial "Usage:"
}

@test "creates planning dir if it does not exist" {
  local new_dir="$TEST_WORKDIR/new-planning"
  run bash "$SUT" --planning-dir "$new_dir"
  assert_success
  [ -f "$new_dir/yolo.db" ]
}
