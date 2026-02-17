#!/usr/bin/env bats
# execute-protocol-parallel.bats -- Unit tests for parallel dispatch in execute-protocol.md

setup() {
  load '../test_helper/common'
  PROTOCOL_FILE="$PROJECT_ROOT/references/execute-protocol.md"
}

# --- Step 5: Design Review parallel dispatch ---

@test "Step 5 contains team_mode conditional for parallel Senior dispatch" {
  # team_mode=teammate should appear at least 3 times (Step 5, Step 7, Step 8)
  run grep -c 'team_mode=teammate' "$PROTOCOL_FILE"
  assert_success
  [[ "$output" -ge 3 ]] || fail "Expected at least 3 team_mode=teammate mentions, got $output"
}

@test "Step 5 documents 2+ plan threshold for parallel dispatch" {
  run grep -E '2\+.*plan|2 or more plans|wave has 2' "$PROTOCOL_FILE"
  assert_success
}

@test "Step 5 documents parallel Senior dispatch" {
  run grep -E 'concurrent.*Senior|parallel.*Senior|Dispatch Senior.*concurrently|Seniors concurrently' "$PROTOCOL_FILE"
  assert_success
}

# --- Step 7: Implementation parallel dispatch ---

@test "Step 7 documents TaskCreate mapping" {
  run grep -E 'TaskCreate.*mapping|TaskCreate.*plan' "$PROTOCOL_FILE"
  assert_success
}

@test "Step 7 documents dynamic Dev scaling formula" {
  run grep -E 'min.*available.*5|compute-dev-count' "$PROTOCOL_FILE"
  assert_success
}

@test "Step 7 documents Lead summary aggregation" {
  run grep -E 'Lead.*aggregat|summary.*aggregat' "$PROTOCOL_FILE"
  assert_success
}

@test "Step 7 documents task-level blocking via td field" {
  run grep -E 'td.*task_depends|task.level.*block|task-level.*block|Task-Level Blocking' "$PROTOCOL_FILE"
  assert_success
}

@test "Step 7 documents file-overlap enforcement" {
  run grep -E 'file.overlap|claimed_files|File-overlap' "$PROTOCOL_FILE"
  assert_success
}

@test "Step 7 documents serialized commits" {
  run grep 'git-commit-serialized' "$PROTOCOL_FILE"
  assert_success
}

@test "Step 7 documents summary.jsonl ownership split" {
  run grep -E 'summary.jsonl.*ownership|sole writer|SOLE writer|Lead-written summary' "$PROTOCOL_FILE"
  assert_success
}

# --- Step 8: Code Review parallel dispatch ---

@test "Step 8 contains team_mode conditional for parallel Senior dispatch" {
  # Extract Step 8 section and verify team_mode appears
  run bash -c "sed -n '/### Step 8: Code Review/,/### Step 9/p' \"$PROTOCOL_FILE\" | grep -c 'team_mode'"
  assert_success
  [[ "$output" -ge 1 ]] || fail "Step 8 section missing team_mode reference"
}

@test "Step 8 documents 2+ plan threshold" {
  run bash -c "sed -n '/### Step 8: Code Review/,/### Step 9/p' \"$PROTOCOL_FILE\" | grep -E '2\\+.*plan|wave has 2'"
  assert_success
}

@test "Step 8 exit gate references code-review.jsonl r:approve" {
  run bash -c "sed -n '/### Step 8: Code Review/,/### Step 9/p' \"$PROTOCOL_FILE\" | grep -E 'code-review.jsonl.*approve|r:.*approve|r: .approve'"
  assert_success
}
