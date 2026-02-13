#!/usr/bin/env bats
# bootstrap-reqs-jsonl.bats — Unit tests for scripts/bootstrap/bootstrap-reqs-jsonl.sh
# Converts REQUIREMENTS.md to reqs.jsonl with requirement IDs, titles, and priorities.

setup() {
  load '../../test_helper/common'
  load '../../test_helper/fixtures'
  load '../../test_helper/mock_stdin'
  mk_test_workdir
  SUT="$BOOTSTRAP_DIR/bootstrap-reqs-jsonl.sh"
}

# --- Argument / input validation ---

@test "exits 1 when REQUIREMENTS.md does not exist at default path" {
  cd "$TEST_WORKDIR"
  run bash "$SUT"
  assert_failure
  assert_output --partial "not found"
}

@test "exits 1 when explicit REQUIREMENTS.md path does not exist" {
  run bash "$SUT" "$TEST_WORKDIR/nonexistent.md"
  assert_failure
  assert_output --partial "not found"
}

# --- Conversion ---

@test "converts requirements to JSONL with correct fields" {
  cat > "$TEST_WORKDIR/REQUIREMENTS.md" <<'EOF'
# Requirements

## Requirements

### REQ-01: CLI argument parsing
**Must-have**

### REQ-02: Config file support
**Should-have**

### REQ-03: Plugin system
**Nice-to-have**
EOF
  run bash "$SUT" "$TEST_WORKDIR/REQUIREMENTS.md" "$TEST_WORKDIR/reqs.jsonl"
  assert_success
  assert_file_exist "$TEST_WORKDIR/reqs.jsonl"

  # Check line count
  run wc -l < "$TEST_WORKDIR/reqs.jsonl"
  assert_output --partial "3"

  # Check first requirement
  run bash -c "head -1 '$TEST_WORKDIR/reqs.jsonl' | jq -r '.id'"
  assert_output "REQ-01"

  run bash -c "head -1 '$TEST_WORKDIR/reqs.jsonl' | jq -r '.t'"
  assert_output "CLI argument parsing"

  run bash -c "head -1 '$TEST_WORKDIR/reqs.jsonl' | jq -r '.pri'"
  assert_output "must"
}

@test "maps priority values correctly" {
  cat > "$TEST_WORKDIR/REQUIREMENTS.md" <<'EOF'
### REQ-01: Feature A
**Must-have**

### REQ-02: Feature B
**Should-have**

### REQ-03: Feature C
**Nice-to-have**
EOF
  bash "$SUT" "$TEST_WORKDIR/REQUIREMENTS.md" "$TEST_WORKDIR/reqs.jsonl"

  run bash -c "sed -n '1p' '$TEST_WORKDIR/reqs.jsonl' | jq -r '.pri'"
  assert_output "must"

  run bash -c "sed -n '2p' '$TEST_WORKDIR/reqs.jsonl' | jq -r '.pri'"
  assert_output "should"

  run bash -c "sed -n '3p' '$TEST_WORKDIR/reqs.jsonl' | jq -r '.pri'"
  assert_output "nice"
}

@test "each JSONL line has st=open and empty ac" {
  cat > "$TEST_WORKDIR/REQUIREMENTS.md" <<'EOF'
### REQ-01: Test feature
**Must-have**
EOF
  bash "$SUT" "$TEST_WORKDIR/REQUIREMENTS.md" "$TEST_WORKDIR/reqs.jsonl"

  run bash -c "head -1 '$TEST_WORKDIR/reqs.jsonl' | jq -r '.st'"
  assert_output "open"

  run bash -c "head -1 '$TEST_WORKDIR/reqs.jsonl' | jq -r '.ac'"
  assert_output ""
}

@test "produces empty file when no requirements found" {
  cat > "$TEST_WORKDIR/REQUIREMENTS.md" <<'EOF'
# Requirements

No requirements here.
EOF
  run bash "$SUT" "$TEST_WORKDIR/REQUIREMENTS.md" "$TEST_WORKDIR/reqs.jsonl"
  assert_success
  assert_file_exist "$TEST_WORKDIR/reqs.jsonl"

  run wc -l < "$TEST_WORKDIR/reqs.jsonl"
  assert_output --partial "0"
}
