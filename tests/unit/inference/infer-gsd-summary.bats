#!/usr/bin/env bats
# infer-gsd-summary.bats — Unit tests for scripts/infer-gsd-summary.sh
# Extracts recent work context from archived GSD planning data.
# Always exits 0; missing data produces minimal JSON, not errors.

setup() {
  load '../../test_helper/common'
  load '../../test_helper/fixtures'
  load '../../test_helper/mock_stdin'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/infer-gsd-summary.sh"
}

# --- Graceful empty output ---

@test "outputs empty JSON when no args provided" {
  run bash "$SUT"
  assert_success
  run bash -c "echo '$output' | jq -r '.latest_milestone'"
  assert_output "null"
  run bash -c "echo '${lines[*]}' | jq -r '.recent_phases | length'"
  assert_output "0"
}

@test "outputs empty JSON when archive directory does not exist" {
  run bash "$SUT" "$TEST_WORKDIR/nonexistent"
  assert_success
  run bash -c "echo '$output' | jq -r '.latest_milestone'"
  assert_output "null"
}

# --- Milestone extraction ---

@test "extracts latest milestone from INDEX.json" {
  local archive="$TEST_WORKDIR/gsd-archive"
  mkdir -p "$archive"
  cat > "$archive/INDEX.json" <<'EOF'
{
  "milestones": ["Init", "v2.0"],
  "phases_total": 3,
  "phases_complete": 3,
  "phases": [
    {"num": 1, "slug": "setup", "plans": 1, "status": "complete"},
    {"num": 2, "slug": "build", "plans": 2, "status": "complete"},
    {"num": 3, "slug": "test", "plans": 1, "status": "complete"}
  ]
}
EOF
  run bash "$SUT" "$archive"
  assert_success
  local result="$output"
  run bash -c "echo '$result' | jq -r '.latest_milestone.name'"
  assert_output "v2.0"
  run bash -c "echo '$result' | jq -r '.latest_milestone.status'"
  assert_output "complete"
}

# --- Recent phases extraction ---

@test "extracts last 3 completed phases with task counts" {
  local archive="$TEST_WORKDIR/gsd-archive"
  mkdir -p "$archive"
  cat > "$archive/INDEX.json" <<'EOF'
{
  "milestones": ["Milestone"],
  "phases_total": 4,
  "phases_complete": 4,
  "phases": [
    {"num": 1, "slug": "init", "plans": 1, "status": "complete"},
    {"num": 2, "slug": "core", "plans": 2, "status": "complete"},
    {"num": 3, "slug": "api", "plans": 3, "status": "complete"},
    {"num": 4, "slug": "deploy", "plans": 1, "status": "complete"}
  ]
}
EOF
  run bash "$SUT" "$archive"
  assert_success
  local result="$output"
  # Should return last 3 completed phases (2, 3, 4)
  run bash -c "echo '$result' | jq '.recent_phases | length'"
  assert_output "3"
}

# --- Key decisions extraction ---

@test "extracts key decisions from STATE.md table" {
  local archive="$TEST_WORKDIR/gsd-archive"
  mkdir -p "$archive"
  # Minimal INDEX.json so the script doesn't fail
  echo '{"milestones":[],"phases_total":0,"phases_complete":0,"phases":[]}' > "$archive/INDEX.json"
  cat > "$archive/STATE.md" <<'EOF'
# State

## Key Decisions
| Decision | Date | Rationale |
|----------|------|-----------|
| Use REST API | 2026-01-15 | Simpler than GraphQL |
| Choose Postgres | 2026-01-16 | Better JSON support |

## Recent Activity
- Did stuff
EOF
  run bash "$SUT" "$archive"
  assert_success
  local result="$output"
  run bash -c "echo '$result' | jq '.key_decisions | length'"
  assert_output "2"
  run bash -c "echo '$result' | jq -r '.key_decisions[0]'"
  assert_output "Use REST API"
}

# --- Current work detection ---

@test "detects in_progress phase as current work" {
  local archive="$TEST_WORKDIR/gsd-archive"
  mkdir -p "$archive"
  cat > "$archive/INDEX.json" <<'EOF'
{
  "milestones": ["Build"],
  "phases_total": 2,
  "phases_complete": 1,
  "phases": [
    {"num": 1, "slug": "setup", "plans": 1, "status": "complete"},
    {"num": 2, "slug": "core", "plans": 2, "status": "in_progress"}
  ]
}
EOF
  run bash "$SUT" "$archive"
  assert_success
  local result="$output"
  run bash -c "echo '$result' | jq -r '.current_work.phase'"
  assert_output "2-core"
  run bash -c "echo '$result' | jq -r '.current_work.status'"
  assert_output "in_progress"
}
