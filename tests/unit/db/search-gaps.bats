#!/usr/bin/env bats
# search-gaps.bats — Tests for scripts/db/search-gaps.sh

setup() {
  load '../../test_helper/common'
  load './db-test-helper'
  SUT="$SCRIPTS_DIR/db/search-gaps.sh"
  mk_test_db
  seed_gaps
}

@test "finds matching gaps by keyword" {
  run bash "$SUT" "authentication" --db "$TEST_DB"
  assert_success
  assert_output --partial "id: G-01"
  assert_output --partial "desc:"
}

@test "filters by status" {
  run bash "$SUT" "validation OR authentication OR error" --status open --db "$TEST_DB"
  assert_success
  assert_output --partial "st: open"
  refute_output --partial "st: fixed"
}

@test "filters by severity" {
  run bash "$SUT" "authentication OR error" --sev critical --db "$TEST_DB"
  assert_success
  assert_output --partial "sev: critical"
  refute_output --partial "sev: major"
}

@test "filters by phase" {
  run bash "$SUT" "validation" --phase 04 --db "$TEST_DB"
  assert_success
  assert_output --partial "phase: 04"
  refute_output --partial "phase: 03"
}

@test "TOON format output" {
  run bash "$SUT" "authentication" --db "$TEST_DB"
  assert_success
  assert_output --partial "id:"
  assert_output --partial "sev:"
  assert_output --partial "desc:"
  assert_output --partial "st:"
  assert_output --partial "phase:"
  assert_output --partial "---"
}

@test "ranked results returned" {
  run bash "$SUT" "error" --db "$TEST_DB"
  assert_success
  assert_output --partial "desc:"
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

@test "combined status and severity filters" {
  run bash "$SUT" "authentication OR error OR validation" --status open --sev major --db "$TEST_DB"
  assert_success
  assert_output --partial "sev: major"
  assert_output --partial "st: open"
  refute_output --partial "sev: critical"
}
