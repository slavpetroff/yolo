#!/usr/bin/env bats
# file-guard-escape.bats — Path traversal and normalization edge cases for file-guard.sh

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir
  mk_planning_dir

  # Create a phase with a plan (no summary) declaring src/foo.ts, src/bar.ts, config/app.json
  # Note: mk_phase with 0 summaries is unreliable on macOS (seq 1 0 counts down),
  # so we create the structure manually.
  PHASE_DIR="$TEST_WORKDIR/.yolo-planning/phases/01-setup"
  mkdir -p "$PHASE_DIR"
  cp "$FIXTURES_DIR/plans/valid-plan.jsonl" "$PHASE_DIR/01-01.plan.jsonl"

  # file-guard.sh requires execution state with status "running" to enforce guards
  echo '{"status":"running"}' > "$TEST_WORKDIR/.yolo-planning/.execution-state.json"
}

# --- Blocking undeclared paths ---

@test "blocks absolute path not in plan" {
  run_with_json '{"tool_input":{"file_path":"/Users/foo/bar.ts"}}' "$SCRIPTS_DIR/file-guard.sh"
  assert_success
  assert_output --partial "deny"
  assert_output --partial "not in active plan"
}

@test "blocks ./prefixed path not in plan" {
  run_with_json '{"tool_input":{"file_path":"./src/evil.ts"}}' "$SCRIPTS_DIR/file-guard.sh"
  assert_success
  assert_output --partial "deny"
  assert_output --partial "not in active plan"
}

@test "blocks path traversal ../../../etc/passwd" {
  run_with_json '{"tool_input":{"file_path":"../../../etc/passwd"}}' "$SCRIPTS_DIR/file-guard.sh"
  assert_success
  assert_output --partial "deny"
  assert_output --partial "not in active plan"
}

# --- Allowing declared paths in various forms ---

@test "allows declared file via absolute path" {
  # Plan has src/foo.ts as relative; absolute path should normalize and match
  run_with_json "{\"tool_input\":{\"file_path\":\"$TEST_WORKDIR/src/foo.ts\"}}" "$SCRIPTS_DIR/file-guard.sh"
  assert_success
}

@test "allows declared file via relative path" {
  run_with_json '{"tool_input":{"file_path":"src/foo.ts"}}' "$SCRIPTS_DIR/file-guard.sh"
  assert_success
}

@test "allows declared file with ./ prefix" {
  run_with_json '{"tool_input":{"file_path":"./src/bar.ts"}}' "$SCRIPTS_DIR/file-guard.sh"
  assert_success
}

# --- Subdirectory specificity ---

@test "blocks file in subdirectory not declared" {
  # Plan has src/foo.ts but NOT src/sub/foo.ts
  run_with_json '{"tool_input":{"file_path":"src/sub/foo.ts"}}' "$SCRIPTS_DIR/file-guard.sh"
  assert_success
  assert_output --partial "deny"
  assert_output --partial "not in active plan"
}

# --- Fail-open edge cases ---

@test "fail-open when plan has empty fm array" {
  # Replace the plan with one that has empty fm
  cp "$FIXTURES_DIR/plans/no-fm-plan.jsonl" "$PHASE_DIR/01-01.plan.jsonl"
  run_with_json '{"tool_input":{"file_path":"anything.ts"}}' "$SCRIPTS_DIR/file-guard.sh"
  assert_success
}

@test "fail-open when plan has no fm field" {
  # Create a plan with no fm field at all
  echo '{"p":"01","n":"01-01","g":"Setup","tc":1}' > "$PHASE_DIR/01-01.plan.jsonl"
  run_with_json '{"tool_input":{"file_path":"anything.ts"}}' "$SCRIPTS_DIR/file-guard.sh"
  assert_success
}

@test "uses first plan without matching summary (not random)" {
  # Add summary for 01-01, making it complete
  cp "$FIXTURES_DIR/summaries/valid-summary.jsonl" "$PHASE_DIR/01-01.summary.jsonl"
  # Create second plan 01-02 without summary — this becomes the active plan
  echo '{"p":"01","n":"01-02","g":"Second plan","fm":["src/second.ts"],"tc":1}' > "$PHASE_DIR/01-02.plan.jsonl"

  # src/foo.ts is in 01-01 (completed), should now be blocked since active plan is 01-02
  run_with_json '{"tool_input":{"file_path":"src/foo.ts"}}' "$SCRIPTS_DIR/file-guard.sh"
  assert_success
  assert_output --partial "deny"

  # src/second.ts is in 01-02 (active), should be allowed
  run_with_json '{"tool_input":{"file_path":"src/second.ts"}}' "$SCRIPTS_DIR/file-guard.sh"
  assert_success
}
