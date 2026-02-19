#!/usr/bin/env bats
# import-research-archive.bats — Tests for import/export research archive scripts

setup() {
  load '../../test_helper/common'
  load './db-test-helper'
  IMPORT_SUT="$SCRIPTS_DIR/db/import-research-archive.sh"
  EXPORT_SUT="$SCRIPTS_DIR/db/export-research-archive.sh"
  mk_test_db

  # Create test archive JSONL file
  ARCHIVE_FILE="$BATS_TEST_TMPDIR/research-archive.jsonl"
  cat > "$ARCHIVE_FILE" <<'JSONL'
{"q":"How to handle JWT?","finding":"Use RS256 with key rotation","conf":"high","phase":"01","dt":"2026-01-10","src":"RFC 7519"}
{"q":"Database migration strategy?","finding":"Use versioned SQL files with checksums","conf":"medium","phase":"02","dt":"2026-01-15","src":"flyway docs"}
{"q":"Rate limiting approach?","finding":"Token bucket algorithm with Redis backend","conf":"high","phase":"03","dt":"2026-01-20","src":"stripe blog"}
JSONL
}

@test "imports archive entries" {
  run bash "$IMPORT_SUT" --file "$ARCHIVE_FILE" --db "$TEST_DB"
  assert_success
  assert_output --partial "imported 3 entries"

  # Verify rows in table
  local count
  count=$(sqlite3 "$TEST_DB" "SELECT count(*) FROM research_archive;")
  [[ "$count" -eq 3 ]]
}

@test "deduplicates on reimport" {
  bash "$IMPORT_SUT" --file "$ARCHIVE_FILE" --db "$TEST_DB"
  bash "$IMPORT_SUT" --file "$ARCHIVE_FILE" --db "$TEST_DB"

  local count
  count=$(sqlite3 "$TEST_DB" "SELECT count(*) FROM research_archive;")
  [[ "$count" -eq 3 ]]
}

@test "FTS searchable after import" {
  bash "$IMPORT_SUT" --file "$ARCHIVE_FILE" --db "$TEST_DB"

  local result
  result=$(sqlite3 "$TEST_DB" "SELECT q FROM ra_fts WHERE ra_fts MATCH 'JWT';")
  [[ "$result" == *"JWT"* ]]
}

@test "export matches import" {
  bash "$IMPORT_SUT" --file "$ARCHIVE_FILE" --db "$TEST_DB"

  EXPORT_FILE="$BATS_TEST_TMPDIR/exported.jsonl"
  bash "$EXPORT_SUT" --file "$EXPORT_FILE" --db "$TEST_DB"

  # Both should have 3 lines
  local import_count export_count
  import_count=$(wc -l < "$ARCHIVE_FILE" | tr -d ' ')
  export_count=$(wc -l < "$EXPORT_FILE" | tr -d ' ')
  [[ "$export_count" -eq "$import_count" ]]

  # Verify key fields preserved
  run jq -r '.q' "$EXPORT_FILE"
  assert_output --partial "How to handle JWT?"
  assert_output --partial "Database migration strategy?"
}

@test "import fails on missing file" {
  run bash "$IMPORT_SUT" --file "/nonexistent/path.jsonl" --db "$TEST_DB"
  assert_failure
  assert_output --partial "error: archive file not found"
}

@test "skips empty lines and entries without required fields" {
  SPARSE_FILE="$BATS_TEST_TMPDIR/sparse-archive.jsonl"
  cat > "$SPARSE_FILE" <<'JSONL'
{"q":"Valid entry","finding":"Some finding","conf":"high","phase":"01"}

{"q":"","finding":"Missing q field","conf":"low","phase":"01"}
{"q":"Another valid","finding":"Another finding","conf":"medium","phase":"02"}
JSONL

  run bash "$IMPORT_SUT" --file "$SPARSE_FILE" --db "$TEST_DB"
  assert_success

  local count
  count=$(sqlite3 "$TEST_DB" "SELECT count(*) FROM research_archive;")
  [[ "$count" -eq 2 ]]
}
