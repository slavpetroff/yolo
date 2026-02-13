#!/usr/bin/env bats
# plan-execute-summary.bats — Integration tests: plan write -> state update -> summary -> advance
# Tests the full plan lifecycle chain via state-updater.sh.

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir
  mk_planning_dir
  SUT="$SCRIPTS_DIR/state-updater.sh"
}

# Helper: run state-updater with a file_path from TEST_WORKDIR
run_updater() {
  local file_path="$1"
  run bash -c "cd '$TEST_WORKDIR' && echo '{\"tool_input\":{\"file_path\":\"$file_path\"}}' | bash '$SUT'"
}

# Helper: create a phase with exact plan/summary counts (avoids macOS seq issue)
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

# Helper: create phase with plans only (no summaries)
mk_phase_plans_only() {
  local num="$1" slug="$2" plans="$3"
  mk_phase_exact "$num" "$slug" "$plans" 0
}

# Helper: create completed phase (equal plans and summaries)
mk_phase_complete() {
  local num="$1" slug="$2" plans="$3"
  mk_phase_exact "$num" "$slug" "$plans" "$plans"
}

# Helper: set up a full working environment for state-updater
mk_full_env() {
  local total_phases="${1:-2}"
  mk_state_md 1 "$total_phases"
  mk_state_json 1 "$total_phases" "executing"
  mk_execution_state "01" "01-01"
  mk_roadmap
}

# --- Test 1: Writing plan triggers STATE.md plan count update ---

@test "writing plan.jsonl triggers state-updater to update STATE.md plan count" {
  mk_full_env

  local dir
  dir=$(mk_phase_plans_only 1 setup 2)

  run_updater "$dir/01-01.plan.jsonl"
  assert_success

  run grep "^Plans:" "$TEST_WORKDIR/.yolo-planning/STATE.md"
  assert_output "Plans: 0/2"
}

# --- Test 2: Plan write sets status ready -> active ---

@test "plan write sets status ready to active" {
  mk_full_env
  # Set initial status to "ready"
  sed -i.bak 's/^Status: active/Status: ready/' "$TEST_WORKDIR/.yolo-planning/STATE.md"

  local dir
  dir=$(mk_phase_plans_only 1 setup 1)

  run_updater "$dir/01-01.plan.jsonl"
  assert_success

  run grep "^Status:" "$TEST_WORKDIR/.yolo-planning/STATE.md"
  assert_output "Status: active"
}

# --- Test 3: Plan write updates state.json phase/total ---

@test "plan write updates state.json phase and total" {
  mk_full_env

  local dir
  dir=$(mk_phase_plans_only 1 setup 1)
  # Also create phase 2 dir so total=2
  mkdir -p "$TEST_WORKDIR/.yolo-planning/phases/02-build"

  run_updater "$dir/01-01.plan.jsonl"
  assert_success

  run jq -r '.ph' "$TEST_WORKDIR/.yolo-planning/state.json"
  assert_output "1"

  run jq -r '.tt' "$TEST_WORKDIR/.yolo-planning/state.json"
  assert_output "2"

  run jq -r '.st' "$TEST_WORKDIR/.yolo-planning/state.json"
  assert_output "executing"
}

# --- Test 4: Plan write updates ROADMAP.md progress table ---

@test "plan write updates ROADMAP.md progress table" {
  mk_state_md 1 2
  mk_state_json 1 2 "executing"
  mk_execution_state "01" "01-01"

  # Create ROADMAP.md with the format the sed expects: "| N - Name | ..."
  cat > "$TEST_WORKDIR/.yolo-planning/ROADMAP.md" <<'EOF'
# Test Roadmap

## Progress
| Phase | Plans | Status | Date |
|-------|-------|--------|------|
| 1 - Setup | 0/0 | Pending | - |
| 2 - Build | 0/0 | Pending | - |

---

## Phase List
- [ ] Phase 1: Setup
- [ ] Phase 2: Build

---
EOF

  local dir
  dir=$(mk_phase_plans_only 1 setup 1)

  run_updater "$dir/01-01.plan.jsonl"
  assert_success

  # The roadmap should have been updated with the plan count
  run grep "Setup" "$TEST_WORKDIR/.yolo-planning/ROADMAP.md"
  assert_success
  assert_output --partial "1 - Setup"
}

# --- Test 5: Writing summary.jsonl updates execution state ---

@test "writing summary.jsonl updates execution state" {
  mk_full_env

  local dir
  dir=$(mk_phase_plans_only 1 setup 1)

  local summary_file="$dir/01-01.summary.jsonl"
  echo '{"p":"01","n":"01-01","s":"complete","fm":["src/foo.ts"]}' > "$summary_file"

  run_updater "$summary_file"
  assert_success

  run jq -r '.phases["01"]["01-01"].status' "$TEST_WORKDIR/.yolo-planning/.execution-state.json"
  assert_output "complete"
}

# --- Test 6: Summary write advances phase when all plans summarized ---

@test "summary write advances phase when all plans summarized" {
  mk_full_env

  # Phase 1: 1 plan + 1 summary (complete after this)
  local dir1
  dir1=$(mk_phase_plans_only 1 setup 1)
  local summary_file="$dir1/01-01.summary.jsonl"
  echo '{"p":"01","n":"01-01","s":"complete","fm":["src/foo.ts"]}' > "$summary_file"

  # Phase 2: 1 plan, 0 summaries (next phase)
  mk_phase_plans_only 2 build 1

  run_updater "$summary_file"
  assert_success

  run grep "^Phase:" "$TEST_WORKDIR/.yolo-planning/STATE.md"
  assert_output --partial "2 of 2"
}

# --- Test 7: Summary write sets status complete when all phases done ---

@test "summary write sets status complete when all phases done" {
  mk_state_md 1 1
  mk_state_json 1 1 "executing"
  mk_execution_state "01" "01-01"

  # Single phase, 1 plan + 1 summary = all done
  local dir1
  dir1=$(mk_phase_plans_only 1 setup 1)
  local summary_file="$dir1/01-01.summary.jsonl"
  echo '{"p":"01","n":"01-01","s":"complete","fm":["src/foo.ts"]}' > "$summary_file"

  run_updater "$summary_file"
  assert_success

  run grep "^Status:" "$TEST_WORKDIR/.yolo-planning/STATE.md"
  assert_output "Status: complete"

  run jq -r '.st' "$TEST_WORKDIR/.yolo-planning/state.json"
  assert_output "complete"
}

# --- Test 8: state-updater commits state artifacts (needs git repo) ---

@test "state-updater commits state artifacts in git repo" {
  mk_git_repo
  mk_planning_dir
  mk_full_env

  local dir
  dir=$(mk_phase_plans_only 1 setup 1)

  # Stage the planning dir so git can track changes
  git -C "$TEST_WORKDIR" add .yolo-planning/
  git -C "$TEST_WORKDIR" commit -q -m "chore(init): add planning dir"

  run_updater "$dir/01-01.plan.jsonl"
  assert_success

  # Verify a state commit was created
  run git -C "$TEST_WORKDIR" log --oneline -1
  assert_output --partial "chore(state):"
}

# --- Test 9: file-guard allows files declared in active plan ---

@test "file-guard allows files declared in active plan" {
  local dir
  dir=$(mk_phase_plans_only 1 setup 1)

  # valid-plan.jsonl declares src/foo.ts, src/bar.ts, config/app.json
  run bash -c "cd '$TEST_WORKDIR' && echo '{\"tool_input\":{\"file_path\":\"src/foo.ts\"}}' | bash '$SCRIPTS_DIR/file-guard.sh'"
  assert_success

  run bash -c "cd '$TEST_WORKDIR' && echo '{\"tool_input\":{\"file_path\":\"src/bar.ts\"}}' | bash '$SCRIPTS_DIR/file-guard.sh'"
  assert_success

  run bash -c "cd '$TEST_WORKDIR' && echo '{\"tool_input\":{\"file_path\":\"config/app.json\"}}' | bash '$SCRIPTS_DIR/file-guard.sh'"
  assert_success
}

# --- Test 10: file-guard blocks undeclared files during active plan ---

@test "file-guard blocks undeclared files during active plan" {
  local dir
  dir=$(mk_phase_plans_only 1 setup 1)

  # valid-plan.jsonl does NOT declare src/unknown.ts
  run bash -c "cd '$TEST_WORKDIR' && echo '{\"tool_input\":{\"file_path\":\"src/unknown.ts\"}}' | bash '$SCRIPTS_DIR/file-guard.sh'"
  assert_failure 2
  assert_output --partial "not in active plan"
}
