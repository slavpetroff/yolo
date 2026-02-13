#!/usr/bin/env bats
# phase-lifecycle.bats — Integration tests: full phase lifecycle
# Tests: create -> plan -> execute -> complete -> advance

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir
  mk_planning_dir
}

# Helper: create a phase with exact plan/summary counts
mk_phase_exact() {
  local num="$1" slug="$2" plans="$3" summaries="$4"
  local dir="$TEST_WORKDIR/.yolo-planning/phases/$(printf '%02d' "$num")-${slug}"
  mkdir -p "$dir"
  local i
  for ((i = 1; i <= plans; i++)); do
    cp "$FIXTURES_DIR/plans/valid-plan.jsonl" "$dir/$(printf '%02d-%02d' "$num" "$i").plan.jsonl"
  done
  for ((i = 1; i <= summaries; i++)); do
    cp "$FIXTURES_DIR/summaries/valid-summary.jsonl" "$dir/$(printf '%02d-%02d' "$num" "$i").summary.jsonl"
  done
  echo "$dir"
}

# Helper: run phase-detect from test workdir
run_detect() {
  run bash -c "cd '$TEST_WORKDIR' && bash '$SCRIPTS_DIR/phase-detect.sh'"
}

# Helper: extract a key=value from phase-detect output
get_val() {
  local key="$1"
  echo "$output" | grep "^${key}=" | head -1 | sed "s/^${key}=//"
}

# Helper: run state-updater with a file_path
run_updater() {
  local file_path="$1"
  run bash -c "cd '$TEST_WORKDIR' && echo '{\"tool_input\":{\"file_path\":\"$file_path\"}}' | bash '$SCRIPTS_DIR/state-updater.sh'"
}

# --- Test 1: phase-detect reports needs_plan when empty phase exists ---

@test "phase-detect reports needs_plan when empty phase exists" {
  mk_phase_exact 1 setup 0 0
  mk_phase_exact 2 build 0 0

  run_detect
  assert_success

  local state
  state=$(get_val "next_phase_state")
  [ "$state" = "needs_plan_and_execute" ]

  local slug
  slug=$(get_val "next_phase_slug")
  [ "$slug" = "01-setup" ]
}

# --- Test 2: phase-detect reports needs_execute when plans exist without summaries ---

@test "phase-detect reports needs_execute when plans exist without summaries" {
  mk_phase_exact 1 setup 2 1

  run_detect
  assert_success

  local state
  state=$(get_val "next_phase_state")
  [ "$state" = "needs_execute" ]

  local plans
  plans=$(get_val "next_phase_plans")
  [ "$plans" = "2" ]

  local summaries
  summaries=$(get_val "next_phase_summaries")
  [ "$summaries" = "1" ]
}

# --- Test 3: phase-detect reports all_done when everything complete ---

@test "phase-detect reports all_done when everything complete" {
  mk_phase_exact 1 setup 1 1
  mk_phase_exact 2 build 2 2

  run_detect
  assert_success

  local state
  state=$(get_val "next_phase_state")
  [ "$state" = "all_done" ]
}

# --- Test 4: compile-context generates .ctx file for dev role ---

@test "compile-context generates .ctx file for dev role" {
  # Set up a phase with a plan
  local dir
  dir=$(mk_phase_exact 1 setup 1 0)

  # Create minimal ROADMAP.md for the script to read
  cat > "$TEST_WORKDIR/.yolo-planning/ROADMAP.md" <<'EOF'
# Test Roadmap

## Phase 1: Setup

**Goal:** Initialize project structure
**Success Criteria:** All directories exist

## Phase 2: Build
EOF

  local plan_path="$dir/01-01.plan.jsonl"

  run bash -c "cd '$TEST_WORKDIR' && bash '$SCRIPTS_DIR/compile-context.sh' 01 dev .yolo-planning/phases '$plan_path'"
  assert_success

  # Output should be the .ctx file path
  assert_output --partial ".ctx-dev.toon"

  # File should exist
  assert_file_exists "$dir/.ctx-dev.toon"

  # Should contain phase info
  run grep "^phase: 01" "$dir/.ctx-dev.toon"
  assert_success

  # Should contain goal
  run grep "^goal:" "$dir/.ctx-dev.toon"
  assert_success

  # Should contain tasks section (from plan.jsonl)
  run grep "^tasks\[" "$dir/.ctx-dev.toon"
  assert_success
}

# --- Test 5: state-updater advances to next phase after completion ---

@test "state-updater advances to next phase after completion" {
  mk_state_md 1 2
  mk_state_json 1 2 "executing"
  mk_execution_state "01" "01-01"

  # Phase 1: complete (1 plan + 1 summary)
  local dir1
  dir1=$(mk_phase_exact 1 setup 1 0)
  local summary_file="$dir1/01-01.summary.jsonl"
  echo '{"p":"01","n":"01-01","s":"complete","fm":["src/foo.ts"]}' > "$summary_file"

  # Phase 2: unbuilt (1 plan, 0 summaries)
  mk_phase_exact 2 build 1 0

  run_updater "$summary_file"
  assert_success

  # STATE.md should show phase 2
  run grep "^Phase:" "$TEST_WORKDIR/.yolo-planning/STATE.md"
  assert_output --partial "2 of 2"

  # state.json should advance
  run jq -r '.ph' "$TEST_WORKDIR/.yolo-planning/state.json"
  assert_output "2"
}

# --- Test 6: qa-gate blocks idle during active phase with gaps ---

@test "qa-gate blocks idle during active phase with gaps" {
  mk_git_repo
  mk_planning_dir

  # 3 plans, 1 summary = gap of 2 (exceeds grace)
  mk_phase_exact 1 setup 3 1

  # Recent conventional commit (grace for gap=1 only)
  mk_recent_commit "feat(01-01): add feature"

  run bash -c "cd '$TEST_WORKDIR' && echo '{\"agent_name\":\"yolo-dev\"}' | bash '$SCRIPTS_DIR/qa-gate.sh'"
  assert_failure 2
  assert_output --partial "SUMMARY.md gap detected"
}

# --- Test 7: suggest-next recommends correct action based on state ---

@test "suggest-next recommends correct action based on state" {
  # Set up a project with phases
  echo "# My Project" > "$TEST_WORKDIR/.yolo-planning/PROJECT.md"
  cp "$FIXTURES_DIR/config/balanced-config.json" "$TEST_WORKDIR/.yolo-planning/config.json"

  # Phase 1 complete, phase 2 needs work
  mk_phase_exact 1 setup 1 1
  mk_phase_exact 2 build 1 0

  run bash -c "cd '$TEST_WORKDIR' && bash '$SCRIPTS_DIR/suggest-next.sh' vibe"
  assert_success
  assert_output --partial "Next Up"
  assert_output --partial "/yolo:go"
}

# --- Test 8: session-start detects interrupted execution ---

@test "session-start detects interrupted execution (plan without summary)" {
  # Create the minimum environment session-start needs
  cp "$FIXTURES_DIR/config/balanced-config.json" "$TEST_WORKDIR/.yolo-planning/config.json"
  mk_state_json 1 2 "executing"
  mk_git_repo
  mk_planning_dir

  # Create a phase with plans but no summaries
  mk_phase_exact 1 setup 1 0

  # Create an execution-state.json that looks like an interrupted run
  cat > "$TEST_WORKDIR/.yolo-planning/.execution-state.json" <<'EOF'
{
  "status": "running",
  "phase": "01",
  "phase_name": "setup",
  "step": "execute",
  "current_task": "T1",
  "plans": ["01-01"]
}
EOF

  echo "# My Project" > "$TEST_WORKDIR/.yolo-planning/PROJECT.md"

  # Remove update-check cache so SCRIPT_DIR gets set inside session-start
  rm -f "/tmp/yolo-update-check-$(id -u)" 2>/dev/null

  # Run session-start (it reads stdin but does not require specific input)
  run bash -c "cd '$TEST_WORKDIR' && echo '{}' | bash '$SCRIPTS_DIR/session-start.sh'"
  assert_success

  # Should detect the interrupted build and report it
  assert_output --partial "hookSpecificOutput"
  assert_output --partial "interrupted"
}
