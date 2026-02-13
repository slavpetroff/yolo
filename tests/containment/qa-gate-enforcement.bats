#!/usr/bin/env bats
# qa-gate-enforcement.bats — Edge cases for qa-gate.sh summary enforcement

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir
  mk_planning_dir
  mk_git_repo
}

@test "blocks idle with 2-plan gap even with recent conventional commits" {
  # 3 plans, 1 summary = gap of 2 => blocked even with good commits
  mk_phase 1 "build" 3 1
  mk_recent_commit "feat(01-01): add auth module"

  run_with_json '{"agent_name":"yolo-dev","status":"idle"}' "$SCRIPTS_DIR/qa-gate.sh"
  assert_failure 2
  assert_output --partial "SUMMARY.md gap"
}

@test "blocks idle with 3-plan gap" {
  # 4 plans, 1 summary = gap of 3 => always blocked
  mk_phase 1 "build" 4 1
  mk_recent_commit "feat(01-01): add auth module"

  run_with_json '{"agent_name":"yolo-dev","status":"idle"}' "$SCRIPTS_DIR/qa-gate.sh"
  assert_failure 2
  assert_output --partial "SUMMARY.md gap"
}

@test "grace: allows 1-plan gap with matching commit format feat(01-01):" {
  # 2 plans, 1 summary = gap of 1 + conventional commit = grace period
  mk_phase 1 "build" 2 1
  mk_recent_commit "feat(01-01): implement feature"

  run_with_json '{"agent_name":"yolo-dev","status":"idle"}' "$SCRIPTS_DIR/qa-gate.sh"
  assert_success
}

@test "no grace without conventional commit format" {
  # 2 plans, 1 summary = gap of 1, but no conventional commit = blocked
  mk_phase 1 "build" 2 1
  mk_recent_commit "added some stuff"

  run_with_json '{"agent_name":"yolo-dev","status":"idle"}' "$SCRIPTS_DIR/qa-gate.sh"
  assert_failure 2
  assert_output --partial "SUMMARY.md gap"
}

@test "handles phase with 0 plans (pass-through)" {
  # Phase directory with no plans at all
  mkdir -p "$TEST_WORKDIR/.yolo-planning/phases/01-empty"
  mk_recent_commit "chore(init): initial"

  run_with_json '{"agent_name":"yolo-dev","status":"idle"}' "$SCRIPTS_DIR/qa-gate.sh"
  assert_success
}

@test "handles phase with only legacy MD format plans" {
  # Create a phase with only legacy MD-format plans
  local phase_dir="$TEST_WORKDIR/.yolo-planning/phases/01-legacy"
  mkdir -p "$phase_dir"
  cat > "$phase_dir/01-01-PLAN.md" <<'EOF'
---
description: Legacy plan
files_modified:
  - src/foo.ts
---
# Plan
EOF
  cat > "$phase_dir/01-01-SUMMARY.md" <<'EOF'
---
description: Legacy summary
---
# Summary
EOF
  mk_recent_commit "feat(01-01): legacy plan"

  # All plans have summaries => pass
  run_with_json '{"agent_name":"yolo-dev","status":"idle"}' "$SCRIPTS_DIR/qa-gate.sh"
  assert_success
}

@test "handles phase with only JSONL format plans" {
  # Only JSONL plans, all with summaries => pass
  mk_phase 1 "modern" 2 2
  mk_recent_commit "feat(01-01): modern plan"

  run_with_json '{"agent_name":"yolo-dev","status":"idle"}' "$SCRIPTS_DIR/qa-gate.sh"
  assert_success
}

@test "handles mixed JSONL and MD formats in same phase" {
  # Phase with both formats: 1 JSONL plan + 1 MD plan, only 1 summary total => gap
  local phase_dir="$TEST_WORKDIR/.yolo-planning/phases/01-mixed"
  mkdir -p "$phase_dir"

  # JSONL plan with summary
  cp "$FIXTURES_DIR/plans/valid-plan.jsonl" "$phase_dir/01-01.plan.jsonl"
  cp "$FIXTURES_DIR/summaries/valid-summary.jsonl" "$phase_dir/01-01.summary.jsonl"

  # MD plan without summary
  cat > "$phase_dir/01-02-PLAN.md" <<'EOF'
---
description: Mixed plan
files_modified:
  - src/mixed.ts
---
# Mixed Plan
EOF

  mk_recent_commit "feat(01-02): mixed format work"

  # 2 plans, 1 summary = gap of 1, but has conventional commit => grace
  run_with_json '{"agent_name":"yolo-dev","status":"idle"}' "$SCRIPTS_DIR/qa-gate.sh"
  assert_success
}
