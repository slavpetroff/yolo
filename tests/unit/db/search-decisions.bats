#!/usr/bin/env bats
# search-decisions.bats — Tests for scripts/db/search-decisions.sh

setup() {
  load '../../test_helper/common'
  load './db-test-helper'
  SUT="$SCRIPTS_DIR/db/search-decisions.sh"
  mk_test_db
  seed_decisions
}

@test "finds matching decisions by keyword" {
  run bash "$SUT" "WAL" --db "$TEST_DB"
  assert_success
  assert_output --partial "dec:"
  assert_output --partial "WAL"
}

@test "filters by agent" {
  run bash "$SUT" "WAL" --agent architect --db "$TEST_DB"
  assert_success
  assert_output --partial "agent: architect"
  refute_output --partial "agent: lead"
}

@test "filters by phase" {
  run bash "$SUT" "format" --phase 04 --db "$TEST_DB"
  assert_success
  assert_output --partial "phase: 04"
  refute_output --partial "phase: 03"
}

@test "ranked by relevance" {
  run bash "$SUT" "SQLite" --db "$TEST_DB"
  assert_success
  assert_output --partial "dec:"
  assert_output --partial "reason:"
}

@test "TOON format output with agent field" {
  run bash "$SUT" "WAL" --db "$TEST_DB"
  assert_success
  assert_output --partial "agent:"
  assert_output --partial "dec:"
  assert_output --partial "reason:"
  assert_output --partial "task:"
  assert_output --partial "phase:"
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

@test "boolean OR query works" {
  run bash "$SUT" "WAL OR FTS5" --db "$TEST_DB"
  assert_success
  # Should find results from both decisions
  assert_output --partial "dec:"
}

@test "limit caps results" {
  run bash "$SUT" "SQLite OR format OR search" --limit 1 --db "$TEST_DB"
  assert_success
  local count
  count=$(echo "$output" | grep -c '^---$')
  [[ "$count" -le 1 ]]
}
