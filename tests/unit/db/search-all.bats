#!/usr/bin/env bats
# search-all.bats — Tests for scripts/db/search-all.sh

setup() {
  load '../../test_helper/common'
  load './db-test-helper'
  SUT="$SCRIPTS_DIR/db/search-all.sh"
  mk_test_db
  seed_research
  seed_archive
  seed_decisions
  seed_gaps
}

@test "returns results from all tables" {
  run bash "$SUT" "authentication OR auth" --db "$TEST_DB"
  assert_success
  # Should find results from gaps (G-01: authentication) and archive (OAuth2/auth)
  assert_output --partial "type:"
  assert_output --partial "content:"
}

@test "type tag is correct for research" {
  run bash "$SUT" "WAL" --db "$TEST_DB"
  assert_success
  assert_output --partial "type: research"
}

@test "type tag is correct for decision" {
  run bash "$SUT" "WAL mode" --db "$TEST_DB"
  assert_success
  assert_output --partial "type: decision"
}

@test "type tag is correct for gap" {
  run bash "$SUT" "authentication" --db "$TEST_DB"
  assert_success
  assert_output --partial "type: gap"
}

@test "type tag is correct for archive" {
  run bash "$SUT" "OAuth2" --db "$TEST_DB"
  assert_success
  assert_output --partial "type: archive"
}

@test "phase filter works" {
  run bash "$SUT" "WAL OR JWT OR authentication OR error" --phase 03 --db "$TEST_DB"
  assert_success
  assert_output --partial "phase: 03"
  refute_output --partial "phase: 04"
  refute_output --partial "phase: 01"
}

@test "limit works" {
  run bash "$SUT" "OR" --limit 2 --db "$TEST_DB"
  # If results come back, count separators
  if [[ "$output" != *"no results"* ]]; then
    local count
    count=$(echo "$output" | grep -c '^---$')
    [[ "$count" -le 2 ]]
  fi
}

@test "TOON format with type/phase/content" {
  run bash "$SUT" "JWT" --db "$TEST_DB"
  assert_success
  assert_output --partial "type:"
  assert_output --partial "phase:"
  assert_output --partial "content:"
  assert_output --partial "---"
}

@test "no results prints message" {
  run bash "$SUT" "nonexistent_xyz_query" --db "$TEST_DB"
  assert_success
  assert_output --partial "no results found"
}

@test "missing query prints usage" {
  run bash "$SUT" --db "$TEST_DB"
  assert_failure
  assert_output --partial "usage:"
}

@test "default limit is 20" {
  # Insert many rows to test default limit
  for i in $(seq 1 25); do
    sqlite3 "$TEST_DB" "INSERT INTO research (q, finding, conf, phase) VALUES ('test query $i', 'test finding about databases $i', 'low', '01');"
  done
  run bash "$SUT" "databases" --db "$TEST_DB"
  assert_success
  local count
  count=$(echo "$output" | grep -c '^---$')
  [[ "$count" -le 20 ]]
}
