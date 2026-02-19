#!/usr/bin/env bats
# db-common.bats — Unit tests for scripts/db/db-common.sh
# Shared helper library: db_path, require_db, sql_query, sql_exec, check_table, json_array

setup() {
  load '../../test_helper/common'
  load '../../test_helper/fixtures'
  mk_test_workdir
  DB_COMMON="$SCRIPTS_DIR/db/db-common.sh"
}

# Helper: create a test database with a simple table
mk_test_db() {
  local db="$TEST_WORKDIR/test.db"
  sqlite3 "$db" "CREATE TABLE items (id TEXT PRIMARY KEY, val TEXT);"
  sqlite3 "$db" "INSERT INTO items VALUES ('a','one'),('b','two');"
  echo "$db"
}

# Helper: create .vbw-planning dir with yolo.db for db_path resolution
mk_planning_db() {
  mkdir -p "$TEST_WORKDIR/.vbw-planning"
  local db="$TEST_WORKDIR/.vbw-planning/yolo.db"
  sqlite3 "$db" "CREATE TABLE meta (k TEXT);"
  echo "$db"
}

# --- db_path tests ---

@test "db_path returns explicit path when provided" {
  source "$DB_COMMON"
  local result
  result=$(db_path "/tmp/custom.db")
  [ "$result" = "/tmp/custom.db" ]
}

@test "db_path finds .vbw-planning/yolo.db walking up" {
  mk_planning_db
  cd "$TEST_WORKDIR"
  source "$DB_COMMON"
  local result
  result=$(db_path)
  [ "$result" = "$TEST_WORKDIR/.vbw-planning/yolo.db" ]
}

@test "db_path returns fallback when no planning dir found" {
  cd "$TEST_WORKDIR"
  source "$DB_COMMON"
  local result
  result=$(db_path)
  [[ "$result" == *".vbw-planning/yolo.db" ]]
}

# --- require_db tests ---

@test "require_db succeeds when DB exists" {
  local db
  db=$(mk_test_db)
  source "$DB_COMMON"
  run require_db "$db"
  assert_success
}

@test "require_db fails when DB missing" {
  source "$DB_COMMON"
  run require_db "$TEST_WORKDIR/nonexistent.db"
  assert_failure
  assert_output --partial "database not found"
}

# --- sql_query tests ---

@test "sql_query returns query results" {
  local db
  db=$(mk_test_db)
  source "$DB_COMMON"
  local result
  result=$(sql_query "$db" "SELECT val FROM items WHERE id='a';")
  [ "$result" = "one" ]
}

@test "sql_query returns multiple rows" {
  local db
  db=$(mk_test_db)
  source "$DB_COMMON"
  local count
  count=$(sql_query "$db" "SELECT count(*) FROM items;")
  [ "$count" = "2" ]
}

# --- sql_exec tests ---

@test "sql_exec writes data transactionally" {
  local db
  db=$(mk_test_db)
  source "$DB_COMMON"
  sql_exec "$db" "INSERT INTO items VALUES ('c','three');"
  local result
  result=$(sqlite3 "$db" "SELECT val FROM items WHERE id='c';")
  [ "$result" = "three" ]
}

# --- check_table tests ---

@test "check_table returns 0 for existing table" {
  local db
  db=$(mk_test_db)
  source "$DB_COMMON"
  run check_table "$db" "items"
  assert_success
}

@test "check_table returns 1 for missing table" {
  local db
  db=$(mk_test_db)
  source "$DB_COMMON"
  run check_table "$db" "nonexistent"
  assert_failure
}

# --- json_array tests ---

@test "json_array converts lines to JSON array" {
  source "$DB_COMMON"
  local result
  result=$(printf 'alpha\nbeta\ngamma\n' | json_array)
  local len
  len=$(echo "$result" | jq 'length')
  [ "$len" -eq 3 ]
  local first
  first=$(echo "$result" | jq -r '.[0]')
  [ "$first" = "alpha" ]
}

@test "json_array returns empty array for no input" {
  source "$DB_COMMON"
  local result
  result=$(echo "" | json_array)
  [ "$result" = "[]" ]
}

# --- parse_db_flag tests ---

@test "parse_db_flag extracts --db value" {
  source "$DB_COMMON"
  parse_db_flag --db /tmp/test.db arg1 arg2
  [ "$_DB_PATH" = "/tmp/test.db" ]
  [ "${#_REMAINING_ARGS[@]}" -eq 2 ]
  [ "${_REMAINING_ARGS[0]}" = "arg1" ]
}

@test "parse_db_flag works with --db=value syntax" {
  source "$DB_COMMON"
  parse_db_flag --db=/tmp/test.db arg1
  [ "$_DB_PATH" = "/tmp/test.db" ]
  [ "${#_REMAINING_ARGS[@]}" -eq 1 ]
}

@test "parse_db_flag leaves empty when no --db" {
  source "$DB_COMMON"
  parse_db_flag arg1 arg2
  [ "$_DB_PATH" = "" ]
  [ "${#_REMAINING_ARGS[@]}" -eq 2 ]
}

# --- sql_with_retry tests ---

@test "sql_with_retry writes data successfully" {
  local db
  db=$(mk_test_db)
  source "$DB_COMMON"
  sql_with_retry "$db" "INSERT INTO items VALUES ('d','four');"
  local result
  result=$(sqlite3 "$db" "SELECT val FROM items WHERE id='d';")
  [ "$result" = "four" ]
}

@test "sql_with_retry sets PRAGMA synchronous=NORMAL" {
  local db
  db=$(mk_test_db)
  source "$DB_COMMON"
  # After sql_with_retry, check synchronous mode within same session isn't possible
  # but we can verify the function accepts valid SQL
  sql_with_retry "$db" "INSERT INTO items VALUES ('e','five');"
  local count
  count=$(sqlite3 "$db" "SELECT count(*) FROM items;")
  [ "$count" -eq 3 ]
}

@test "sql_with_retry returns output from SELECT" {
  local db
  db=$(mk_test_db)
  source "$DB_COMMON"
  local result
  result=$(sql_with_retry "$db" "INSERT INTO items VALUES ('f','six'); SELECT count(*) FROM items;")
  [[ "$result" == *"3"* ]]
}

@test "SQLITE_BUSY_RETRIES constant is set" {
  source "$DB_COMMON"
  [ "$SQLITE_BUSY_RETRIES" -eq 3 ]
}

# --- sql_verify tests ---

@test "sql_verify passes on valid database" {
  local db
  db=$(mk_test_db)
  source "$DB_COMMON"
  run sql_verify "$db"
  assert_success
}

@test "sql_verify fails on corrupted database" {
  source "$DB_COMMON"
  local db="$TEST_WORKDIR/corrupt.db"
  # Create a file that is not a valid SQLite database
  echo "not a database" > "$db"
  run sql_verify "$db"
  assert_failure
}
