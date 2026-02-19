#!/usr/bin/env bats
# qa-gate-cascade.bats -- Integration test: end-to-end QA gate cascade
# Plan 04-10 T4: Verifies post-task -> post-plan -> post-phase cascade behavior

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir

  PHASE_DIR="$TEST_WORKDIR/phase-test"
  mkdir -p "$PHASE_DIR"

  # Consolidated dispatcher replaces individual scripts
  SUT_POST_TASK="$SCRIPTS_DIR/qa-gate.sh"
  SUT_POST_TASK_ARGS="--tier task"
  SUT_POST_PLAN="$SCRIPTS_DIR/qa-gate.sh"
  SUT_POST_PLAN_ARGS="--tier plan"
  SUT_POST_PHASE="$SCRIPTS_DIR/qa-gate.sh"
  SUT_POST_PHASE_ARGS="--tier phase"

  # Mock bin directory prepended to PATH
  MOCK_DIR="$TEST_WORKDIR/mock-bin"
  mkdir -p "$MOCK_DIR"

  # Create mock test-summary.sh (default: passing)
  cat > "$MOCK_DIR/test-summary.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "PASS (10 tests)"
exit 0
SCRIPT
  chmod +x "$MOCK_DIR/test-summary.sh"

  # Create mock bats
  cat > "$MOCK_DIR/bats" <<'SCRIPT'
#!/usr/bin/env bash
echo "mock bats"
exit 0
SCRIPT
  chmod +x "$MOCK_DIR/bats"

  # Create mock validate-gates.sh (default: passing)
  cat > "$MOCK_DIR/validate-gates.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo '{"gate":"pass","step":"'"$2"'","missing":[]}'
exit 0
SCRIPT
  chmod +x "$MOCK_DIR/validate-gates.sh"

  # Create mock resolve-qa-config.sh (default: all enabled)
  cat > "$MOCK_DIR/resolve-qa-config.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo '{"post_task":true,"post_plan":true,"post_phase":true,"timeout_seconds":30}'
SCRIPT
  chmod +x "$MOCK_DIR/resolve-qa-config.sh"

  # Create valid plan.jsonl + summary.jsonl
  cat > "$PHASE_DIR/04-10.plan.jsonl" <<'JSONL'
{"p":"04","n":"10","t":"QA gate config","w":2,"d":[],"mh":{"tr":["config toggles work"],"ar":[],"kl":[]},"obj":"Wire config toggles"}
{"id":"T1","tp":"auto","a":"dev","f":["scripts/qa-gate-post-task.sh"],"v":"ok","done":"ok","spec":"add config toggle"}
{"id":"T2","tp":"auto","a":"dev","f":["scripts/validate-gates.sh"],"v":"ok","done":"ok","spec":"add entries"}
JSONL
  cat > "$PHASE_DIR/04-10.summary.jsonl" <<'JSONL'
{"s":"complete","p":"04","n":"10","tc":2,"tt":2,"fm":["scripts/validate-gates.sh"],"commits":["abc"],"desc":"Done"}
JSONL

  export PATH="$MOCK_DIR:$PATH"
}

# --- T4 Test 1: post-task gate passes with passing tests ---

@test "post-task gate passes with passing tests" {
  run bash "$SUT_POST_TASK" $SUT_POST_TASK_ARGS --phase-dir "$PHASE_DIR" --plan 04-10 --task T1
  assert_success
  # Verify .qa-gate-results.jsonl has 1 line with gl=post-task
  [ -f "$PHASE_DIR/.qa-gate-results.jsonl" ]
  local line_count gl
  line_count=$(wc -l < "$PHASE_DIR/.qa-gate-results.jsonl" | tr -d ' ')
  [ "$line_count" -ge 1 ]
  gl=$(head -1 "$PHASE_DIR/.qa-gate-results.jsonl" | jq -r '.gl')
  [ "$gl" = "post-task" ]
}

# --- T4 Test 2: post-plan gate passes after post-task results exist ---

@test "post-plan gate passes after post-task results exist" {
  # First run post-task to create result entry
  run bash "$SUT_POST_TASK" $SUT_POST_TASK_ARGS --phase-dir "$PHASE_DIR" --plan 04-10 --task T1
  assert_success

  # Now run post-plan
  run bash "$SUT_POST_PLAN" $SUT_POST_PLAN_ARGS --phase-dir "$PHASE_DIR" --plan 04-10
  assert_success

  # Verify .qa-gate-results.jsonl has 2 lines (post-task + post-plan)
  local line_count
  line_count=$(wc -l < "$PHASE_DIR/.qa-gate-results.jsonl" | tr -d ' ')
  [ "$line_count" -ge 2 ]

  # Verify both levels present
  local has_post_task has_post_plan
  has_post_task=$(jq -r 'select(.gl == "post-task")' "$PHASE_DIR/.qa-gate-results.jsonl" 2>/dev/null | head -1)
  has_post_plan=$(jq -r 'select(.gl == "post-plan")' "$PHASE_DIR/.qa-gate-results.jsonl" 2>/dev/null | head -1)
  [ -n "$has_post_task" ]
  [ -n "$has_post_plan" ]
}

# --- T4 Test 3: post-phase gate passes when all plans complete and gates pass ---

@test "post-phase gate passes when all plans complete and gates pass" {
  # Run post-task first
  run bash "$SUT_POST_TASK" $SUT_POST_TASK_ARGS --phase-dir "$PHASE_DIR" --plan 04-10 --task T1
  assert_success

  # Run post-plan
  run bash "$SUT_POST_PLAN" $SUT_POST_PLAN_ARGS --phase-dir "$PHASE_DIR" --plan 04-10
  assert_success

  # Run post-phase
  run bash "$SUT_POST_PHASE" $SUT_POST_PHASE_ARGS --phase-dir "$PHASE_DIR"
  assert_success

  # Verify .qa-gate-results.jsonl has 3 lines
  local line_count
  line_count=$(wc -l < "$PHASE_DIR/.qa-gate-results.jsonl" | tr -d ' ')
  [ "$line_count" -ge 3 ]
}

# --- T4 Test 4: post-task gate blocks on test failure ---

@test "post-task gate blocks on test failure" {
  # Overwrite mock test-summary.sh to fail
  cat > "$MOCK_DIR/test-summary.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "FAIL (1/10 failed)"
exit 1
SCRIPT
  chmod +x "$MOCK_DIR/test-summary.sh"

  run bash "$SUT_POST_TASK" $SUT_POST_TASK_ARGS --phase-dir "$PHASE_DIR" --plan 04-10 --task T1
  assert_failure

  # Verify gate=fail in output
  local gate
  gate=$(echo "$output" | jq -r '.gate')
  [ "$gate" = "fail" ]
}

# --- T4 Test 5: cascade shows post-task failure recorded in results ---

@test "cascade shows post-task failure prevents clean post-plan" {
  # First run post-task with failure
  cat > "$MOCK_DIR/test-summary.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "FAIL (1/10 failed)"
exit 1
SCRIPT
  chmod +x "$MOCK_DIR/test-summary.sh"

  run bash "$SUT_POST_TASK" $SUT_POST_TASK_ARGS --phase-dir "$PHASE_DIR" --plan 04-10 --task T1
  assert_failure

  # .qa-gate-results.jsonl should contain a FAIL entry
  [ -f "$PHASE_DIR/.qa-gate-results.jsonl" ]
  local fail_entry
  fail_entry=$(jq -r 'select(.r == "FAIL")' "$PHASE_DIR/.qa-gate-results.jsonl" 2>/dev/null | head -1)
  [ -n "$fail_entry" ]

  # Post-plan still runs (it's independent -- runs its own test suite)
  # But since test-summary still fails, post-plan also fails
  run bash "$SUT_POST_PLAN" $SUT_POST_PLAN_ARGS --phase-dir "$PHASE_DIR" --plan 04-10
  assert_failure

  # Verify post-plan failure also recorded
  local post_plan_fail
  post_plan_fail=$(jq -r 'select(.gl == "post-plan") | select(.r == "FAIL")' "$PHASE_DIR/.qa-gate-results.jsonl" 2>/dev/null | head -1)
  [ -n "$post_plan_fail" ]
}

# --- T4 Test 6: config toggle skips gate in cascade ---

@test "config toggle skips gate in cascade" {
  # Overwrite mock resolve-qa-config.sh to disable post_task
  cat > "$MOCK_DIR/resolve-qa-config.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo '{"post_task":false,"post_plan":true,"post_phase":true,"timeout_seconds":30}'
SCRIPT
  chmod +x "$MOCK_DIR/resolve-qa-config.sh"

  run bash "$SUT_POST_TASK" $SUT_POST_TASK_ARGS --phase-dir "$PHASE_DIR" --plan 04-10 --task T1
  assert_success

  # Verify gate=skipped
  local gate
  gate=$(echo "$output" | jq -r '.gate')
  [ "$gate" = "skipped" ]
}
