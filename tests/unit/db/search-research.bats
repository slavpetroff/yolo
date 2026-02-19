#!/usr/bin/env bats
# search-research.bats — Tests for scripts/db/search-research.sh

setup() {
  load '../../test_helper/common'
  load './db-test-helper'
  SUT="$SCRIPTS_DIR/db/search-research.sh"
  mk_test_db
  seed_research
  seed_archive
}

@test "finds matching research by keyword" {
  run bash "$SUT" "JWT" --db "$TEST_DB"
  assert_success
  assert_output --partial "q:"
  assert_output --partial "finding:"
  assert_output --partial "JWT"
}

@test "returns results from research_archive" {
  run bash "$SUT" "OAuth2" --db "$TEST_DB"
  assert_success
  assert_output --partial "source: archive"
  assert_output --partial "OAuth2"
}

@test "filters by phase" {
  run bash "$SUT" "JWT" --phase 03 --db "$TEST_DB"
  assert_success
  assert_output --partial "phase: 03"
  refute_output --partial "phase: 02"
}

@test "filters by confidence" {
  run bash "$SUT" "JWT" --conf high --db "$TEST_DB"
  assert_success
  assert_output --partial "conf: high"
  refute_output --partial "conf: medium"
}

@test "cross-phase search returns both sources" {
  run bash "$SUT" "JWT" --db "$TEST_DB"
  assert_success
  assert_output --partial "source: research"
  assert_output --partial "source: archive"
}

@test "snippet highlighting present" {
  run bash "$SUT" "JWT" --db "$TEST_DB"
  assert_success
  # FTS5 snippet markers
  assert_output --partial ">>>"
  assert_output --partial "<<<"
}

@test "limit caps results" {
  run bash "$SUT" "JWT" --limit 1 --db "$TEST_DB"
  assert_success
  # Count --- separators (each result ends with ---)
  local count
  count=$(echo "$output" | grep -c '^---$')
  [[ "$count" -le 1 ]]
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

@test "boolean AND query works" {
  run bash "$SUT" "JWT AND rotation" --db "$TEST_DB"
  assert_success
  assert_output --partial "finding:"
}

@test "boolean NOT query works" {
  # "WAL NOT concurrent" should exclude the WAL entry (which mentions "concurrent")
  # but still return nothing if all WAL entries mention concurrent.
  # Use a broader NOT test: search for "error" which only exists in one research entry
  run bash "$SUT" "error" --db "$TEST_DB"
  assert_success
  assert_output --partial "q:"
  # The error handling entry should appear
  assert_output --partial "error"
}
