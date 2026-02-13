#!/usr/bin/env bats
# bootstrap-requirements.bats — Unit tests for scripts/bootstrap/bootstrap-requirements.sh
# Generates REQUIREMENTS.md from discovery.json with answered[] and inferred[].

setup() {
  load '../../test_helper/common'
  load '../../test_helper/fixtures'
  load '../../test_helper/mock_stdin'
  mk_test_workdir
  SUT="$BOOTSTRAP_DIR/bootstrap-requirements.sh"
}

# --- Argument validation ---

@test "exits 1 with usage when fewer than 2 args" {
  run bash "$SUT"
  assert_failure
  assert_output --partial "Usage:"

  run bash "$SUT" "$TEST_WORKDIR/REQUIREMENTS.md"
  assert_failure
  assert_output --partial "Usage:"
}

@test "exits 1 when discovery file does not exist" {
  run bash "$SUT" "$TEST_WORKDIR/REQUIREMENTS.md" "$TEST_WORKDIR/nonexistent.json"
  assert_failure
  assert_output --partial "not found"
}

@test "exits 1 when discovery file contains invalid JSON" {
  echo "not json" > "$TEST_WORKDIR/bad.json"
  run bash "$SUT" "$TEST_WORKDIR/REQUIREMENTS.md" "$TEST_WORKDIR/bad.json"
  assert_failure
  assert_output --partial "Invalid JSON"
}

# --- File generation ---

@test "generates REQUIREMENTS.md from discovery with inferred requirements" {
  cat > "$TEST_WORKDIR/discovery.json" <<'EOF'
{
  "answered": [{"q": "What is the project?", "a": "A CLI tool"}],
  "inferred": [
    {"text": "CLI argument parsing", "priority": "Must-have"},
    {"text": "Config file support", "priority": "Should-have"}
  ]
}
EOF
  run bash "$SUT" "$TEST_WORKDIR/REQUIREMENTS.md" "$TEST_WORKDIR/discovery.json"
  assert_success
  assert_file_exist "$TEST_WORKDIR/REQUIREMENTS.md"

  run cat "$TEST_WORKDIR/REQUIREMENTS.md"
  assert_output --partial "# Requirements"
  assert_output --partial "REQ-01: CLI argument parsing"
  assert_output --partial "**Must-have**"
  assert_output --partial "REQ-02: Config file support"
  assert_output --partial "**Should-have**"
}

@test "generates placeholder when no inferred requirements" {
  cat > "$TEST_WORKDIR/discovery.json" <<'EOF'
{
  "answered": [],
  "inferred": []
}
EOF
  run bash "$SUT" "$TEST_WORKDIR/REQUIREMENTS.md" "$TEST_WORKDIR/discovery.json"
  assert_success

  run cat "$TEST_WORKDIR/REQUIREMENTS.md"
  assert_output --partial "No requirements defined yet"
}

@test "creates parent directories for output path" {
  cat > "$TEST_WORKDIR/discovery.json" <<'EOF'
{"answered": [], "inferred": [{"text": "Auth", "priority": "Must-have"}]}
EOF
  local nested="$TEST_WORKDIR/deep/nested/REQUIREMENTS.md"
  run bash "$SUT" "$nested" "$TEST_WORKDIR/discovery.json"
  assert_success
  assert_file_exist "$nested"
}
