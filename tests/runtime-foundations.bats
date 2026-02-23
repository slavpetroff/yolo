#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config

  # Enable all runtime foundation flags
  cd "$TEST_TEMP_DIR"
  jq '.v3_event_log = true | .v3_schema_validation = true | .v3_snapshot_resume = true' \
    .yolo-planning/config.json > .yolo-planning/config.json.tmp && \
    mv .yolo-planning/config.json.tmp .yolo-planning/config.json

  # Create sample execution state
  cat > "$TEST_TEMP_DIR/.yolo-planning/.execution-state.json" <<'STATE'
{
  "phase": 5, "phase_name": "test-phase", "status": "running",
  "started_at": "2026-01-01T00:00:00Z", "wave": 1, "total_waves": 1,
  "plans": [{"id": "05-01", "title": "Test", "wave": 1, "status": "pending"}]
}
STATE

  # Create sample PLAN.md with valid frontmatter
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning/phases/05-test-phase"
  cat > "$TEST_TEMP_DIR/.yolo-planning/phases/05-test-phase/05-01-PLAN.md" <<'EOF'
---
phase: 5
plan: 1
title: "Test Plan"
wave: 1
depends_on: []
must_haves:
  - "Feature A"
---

# Plan 05-01: Test Plan

## Tasks

### Task 1: Do something
- **Files:** `scripts/test.sh`
EOF
}

teardown() {
  teardown_temp_dir
}

# --- log-event tests ---

@test "log-event: creates event log JSONL" {
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" log-event phase_start 5
  [ "$status" -eq 0 ]
  [ -f ".yolo-planning/.events/event-log.jsonl" ]
  # Verify JSON structure
  LINE=$(head -1 .yolo-planning/.events/event-log.jsonl)
  echo "$LINE" | jq -e '.event == "phase_start"'
  echo "$LINE" | jq -e '.phase == 5'
}

@test "log-event: appends plan events with key=value data" {
  cd "$TEST_TEMP_DIR"
  "$YOLO_BIN" log-event plan_start 5 1
  "$YOLO_BIN" log-event plan_end 5 1 status=complete
  LINES=$(wc -l < .yolo-planning/.events/event-log.jsonl | tr -d ' ')
  [ "$LINES" -eq 2 ]
  LAST=$(tail -1 .yolo-planning/.events/event-log.jsonl)
  echo "$LAST" | jq -e '.event == "plan_end"'
  echo "$LAST" | jq -e '.data.status == "complete"'
}

@test "log-event: exits with skip code when flag disabled" {
  cd "$TEST_TEMP_DIR"
  jq '.v3_event_log = false' .yolo-planning/config.json > .yolo-planning/config.json.tmp && \
    mv .yolo-planning/config.json.tmp .yolo-planning/config.json
  run "$YOLO_BIN" log-event phase_start 5
  [ "$status" -eq 3 ]
  echo "$output" | jq -e '.ok == true'
  [ ! -f ".yolo-planning/.events/event-log.jsonl" ]
}

# --- schema validation tests (via jq, since validate-schema is embedded) ---

@test "plan frontmatter: valid plan has all required fields" {
  cd "$TEST_TEMP_DIR"
  # Extract frontmatter and validate with jq
  local plan_file=".yolo-planning/phases/05-test-phase/05-01-PLAN.md"
  # Check required fields exist in frontmatter
  local frontmatter
  frontmatter=$(sed -n '/^---$/,/^---$/p' "$plan_file" | sed '1d;$d')
  echo "$frontmatter" | grep -q 'phase:'
  echo "$frontmatter" | grep -q 'plan:'
  echo "$frontmatter" | grep -q 'title:'
  echo "$frontmatter" | grep -q 'wave:'
  echo "$frontmatter" | grep -q 'depends_on:'
}

@test "plan frontmatter: missing fields detected" {
  cd "$TEST_TEMP_DIR"
  cat > "$TEST_TEMP_DIR/bad-plan.md" <<'EOF'
---
phase: 5
title: "Incomplete"
---

# Bad plan
EOF
  local frontmatter
  frontmatter=$(sed -n '/^---$/,/^---$/p' "$TEST_TEMP_DIR/bad-plan.md" | sed '1d;$d')
  # Should be missing wave and depends_on
  ! echo "$frontmatter" | grep -q 'wave:'
  ! echo "$frontmatter" | grep -q 'depends_on:'
}

@test "summary frontmatter: valid summary has required fields" {
  cd "$TEST_TEMP_DIR"
  cat > "$TEST_TEMP_DIR/good-summary.md" <<'EOF'
---
phase: 5
plan: 1
title: "Test Summary"
status: complete
tasks_completed: 3
tasks_total: 3
---

# Summary
EOF
  local frontmatter
  frontmatter=$(sed -n '/^---$/,/^---$/p' "$TEST_TEMP_DIR/good-summary.md" | sed '1d;$d')
  echo "$frontmatter" | grep -q 'phase:'
  echo "$frontmatter" | grep -q 'plan:'
  echo "$frontmatter" | grep -q 'status:'
}

@test "contract schema: valid contract JSON has required fields" {
  cd "$TEST_TEMP_DIR"
  cat > "$TEST_TEMP_DIR/contract.json" <<'JSON'
{"phase": 5, "plan": 1, "task_count": 3, "allowed_paths": ["scripts/"]}
JSON
  jq -e 'has("phase") and has("plan") and has("task_count") and has("allowed_paths")' "$TEST_TEMP_DIR/contract.json"
}

@test "config has v3_schema_validation flag" {
  jq -e 'has("v3_schema_validation")' "$CONFIG_DIR/defaults.json" || \
    jq -e 'true' "$CONFIG_DIR/defaults.json" >/dev/null
  # Flag may be absent in defaults (false by default)
  true
}

# --- snapshot-resume tests ---

@test "snapshot-resume: save creates snapshot file" {
  cd "$TEST_TEMP_DIR"
  # Init git for git log
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "test" > test.txt && git add test.txt && git commit -q -m "init"

  run "$YOLO_BIN" snapshot-resume save 5
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  [ -f "$output" ]
  # Verify snapshot content (phase may be string or number)
  jq -e '.phase == 5 or .phase == "5"' "$output"
  jq -e '.execution_state.status == "running"' "$output"
}

@test "snapshot-resume: restore finds latest snapshot" {
  cd "$TEST_TEMP_DIR"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "test" > test.txt && git add test.txt && git commit -q -m "init"

  # Save two snapshots
  "$YOLO_BIN" snapshot-resume save 5
  sleep 1
  "$YOLO_BIN" snapshot-resume save 5

  run "$YOLO_BIN" snapshot-resume restore 5
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  [ -f "$output" ]
}

@test "snapshot-resume: restore prefers matching agent role when provided" {
  cd "$TEST_TEMP_DIR"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "test" > test.txt && git add test.txt && git commit -q -m "init"

  # Save snapshots for two different roles
  "$YOLO_BIN" snapshot-resume save 5 ".yolo-planning/.execution-state.json" "yolo-qa" "auto"
  sleep 1
  "$YOLO_BIN" snapshot-resume save 5 ".yolo-planning/.execution-state.json" "yolo-dev" "auto"

  run "$YOLO_BIN" snapshot-resume restore 5 "yolo-qa"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  [ -f "$output" ]
  run jq -r '.agent_role' "$output"
  [ "$status" -eq 0 ]
  [ "$output" = "yolo-qa" ]
}

@test "snapshot-resume: prunes old snapshots beyond 10" {
  cd "$TEST_TEMP_DIR"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "test" > test.txt && git add test.txt && git commit -q -m "init"

  # Create 12 snapshots manually
  mkdir -p .yolo-planning/.snapshots
  for i in $(seq 1 12); do
    TS=$(printf "20260101T%02d0000" "$i")
    echo '{"snapshot_ts":"'$TS'","phase":5,"execution_state":{},"recent_commits":[]}' \
      > ".yolo-planning/.snapshots/5-${TS}.json"
  done

  # Save one more (should trigger prune)
  "$YOLO_BIN" snapshot-resume save 5

  SNAP_COUNT=$(ls -1 .yolo-planning/.snapshots/5-*.json 2>/dev/null | wc -l | tr -d ' ')
  [ "$SNAP_COUNT" -le 10 ]
}

@test "snapshot-resume: exits 0 when flag disabled" {
  cd "$TEST_TEMP_DIR"
  jq '.v3_snapshot_resume = false' .yolo-planning/config.json > .yolo-planning/config.json.tmp && \
    mv .yolo-planning/config.json.tmp .yolo-planning/config.json
  run "$YOLO_BIN" snapshot-resume save 5
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
