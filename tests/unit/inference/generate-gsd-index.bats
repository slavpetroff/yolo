#!/usr/bin/env bats
# generate-gsd-index.bats — Unit tests for scripts/generate-gsd-index.sh
# Generates lightweight JSON index for archived GSD projects.
# Writes INDEX.json to .yolo-planning/gsd-archive/.

setup() {
  load '../../test_helper/common'
  load '../../test_helper/fixtures'
  load '../../test_helper/mock_stdin'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/generate-gsd-index.sh"
}

# --- Graceful exit when no archive ---

@test "exits 0 silently when archive directory does not exist" {
  cd "$TEST_WORKDIR"
  run bash "$SUT"
  assert_success
  refute_output
}

# --- Index generation ---

@test "generates INDEX.json with correct structure" {
  cd "$TEST_WORKDIR"
  mkdir -p ".yolo-planning/gsd-archive/phases/01-setup"
  echo '{"version":"1.0"}' > ".yolo-planning/gsd-archive/config.json"
  # Create a plan and summary so phase is complete
  touch ".yolo-planning/gsd-archive/phases/01-setup/01-01.plan.jsonl"
  touch ".yolo-planning/gsd-archive/phases/01-setup/01-01.summary.jsonl"

  run bash "$SUT"
  assert_success
  assert_file_exist "$TEST_WORKDIR/.yolo-planning/gsd-archive/INDEX.json"

  run jq -r '.gsd_version' "$TEST_WORKDIR/.yolo-planning/gsd-archive/INDEX.json"
  assert_output "1.0"

  run jq -r '.phases_total' "$TEST_WORKDIR/.yolo-planning/gsd-archive/INDEX.json"
  assert_output "1"
}

@test "detects complete phases when plans equal summaries" {
  cd "$TEST_WORKDIR"
  mkdir -p ".yolo-planning/gsd-archive/phases/01-setup"
  touch ".yolo-planning/gsd-archive/phases/01-setup/01-01.plan.jsonl"
  touch ".yolo-planning/gsd-archive/phases/01-setup/01-01.summary.jsonl"

  bash "$SUT"
  run jq -r '.phases[0].status' "$TEST_WORKDIR/.yolo-planning/gsd-archive/INDEX.json"
  assert_output "complete"

  run jq -r '.phases_complete' "$TEST_WORKDIR/.yolo-planning/gsd-archive/INDEX.json"
  assert_output "1"
}

@test "detects in_progress phases when summaries fewer than plans" {
  cd "$TEST_WORKDIR"
  mkdir -p ".yolo-planning/gsd-archive/phases/01-core"
  touch ".yolo-planning/gsd-archive/phases/01-core/01-01.plan.jsonl"
  touch ".yolo-planning/gsd-archive/phases/01-core/01-02.plan.jsonl"
  touch ".yolo-planning/gsd-archive/phases/01-core/01-01.summary.jsonl"
  # Only 1 summary for 2 plans = in_progress

  bash "$SUT"
  run jq -r '.phases[0].status' "$TEST_WORKDIR/.yolo-planning/gsd-archive/INDEX.json"
  assert_output "in_progress"

  run jq -r '.phases_complete' "$TEST_WORKDIR/.yolo-planning/gsd-archive/INDEX.json"
  assert_output "0"
}

@test "extracts milestones from ROADMAP.md headings" {
  cd "$TEST_WORKDIR"
  mkdir -p ".yolo-planning/gsd-archive"
  cat > ".yolo-planning/gsd-archive/ROADMAP.md" <<'EOF'
# Project Roadmap

## Phase 1: Setup
Content here.

## Phase 2: Build
More content.
EOF

  bash "$SUT"
  run jq '.milestones | length' "$TEST_WORKDIR/.yolo-planning/gsd-archive/INDEX.json"
  assert_output "2"

  run jq -r '.milestones[0]' "$TEST_WORKDIR/.yolo-planning/gsd-archive/INDEX.json"
  assert_output "Phase 1: Setup"
}

@test "INDEX.json includes quick_paths for common files" {
  cd "$TEST_WORKDIR"
  mkdir -p ".yolo-planning/gsd-archive/phases/01-init"
  touch ".yolo-planning/gsd-archive/phases/01-init/01-01.plan.jsonl"
  touch ".yolo-planning/gsd-archive/phases/01-init/01-01.summary.jsonl"

  bash "$SUT"
  run jq -r '.quick_paths.roadmap' "$TEST_WORKDIR/.yolo-planning/gsd-archive/INDEX.json"
  assert_output "gsd-archive/ROADMAP.md"

  run jq -r '.quick_paths.phases' "$TEST_WORKDIR/.yolo-planning/gsd-archive/INDEX.json"
  assert_output "gsd-archive/phases/"
}
