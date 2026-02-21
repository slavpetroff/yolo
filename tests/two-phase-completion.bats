#!/usr/bin/env bats
# Migrated: two-phase-complete.sh -> yolo two-phase-complete
#           artifact-registry.sh -> yolo artifact
# CWD-sensitive: yes

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning/.contracts"
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning/.events"
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning/.artifacts"
  # Enable flags
  jq '.v2_two_phase_completion = true | .v3_event_log = true' \
    "$TEST_TEMP_DIR/.yolo-planning/config.json" > "$TEST_TEMP_DIR/.yolo-planning/config.json.tmp" \
    && mv "$TEST_TEMP_DIR/.yolo-planning/config.json.tmp" "$TEST_TEMP_DIR/.yolo-planning/config.json"
}

teardown() {
  teardown_temp_dir
}

create_passing_contract() {
  cat > "$TEST_TEMP_DIR/.yolo-planning/.contracts/1-1.json" << 'CONTRACT'
{"phase_id":"phase-1","plan_id":"1-1","phase":1,"plan":1,"objective":"Test","task_ids":["1-1-T1"],"task_count":1,"allowed_paths":["src/a.js"],"forbidden_paths":[],"depends_on":[],"must_haves":["Feature works"],"verification_checks":["true"],"max_token_budget":50000,"timeout_seconds":300,"contract_hash":"abc"}
CONTRACT
}

create_failing_contract() {
  cat > "$TEST_TEMP_DIR/.yolo-planning/.contracts/1-1.json" << 'CONTRACT'
{"phase_id":"phase-1","plan_id":"1-1","phase":1,"plan":1,"objective":"Test","task_ids":["1-1-T1"],"task_count":1,"allowed_paths":["src/a.js"],"forbidden_paths":[],"depends_on":[],"must_haves":["Feature works"],"verification_checks":["false"],"max_token_budget":50000,"timeout_seconds":300,"contract_hash":"abc"}
CONTRACT
}

# --- Two-phase completion ---

@test "two-phase: confirmed when all checks pass" {
  cd "$TEST_TEMP_DIR"
  create_passing_contract
  run "$YOLO_BIN" two-phase-complete "1-1-T1" 1 1 ".yolo-planning/.contracts/1-1.json" "all tests pass"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "confirmed"'
  echo "$output" | jq -e '.checks_passed > 0'
}

@test "two-phase: rejected when verification check fails" {
  cd "$TEST_TEMP_DIR"
  create_failing_contract
  run "$YOLO_BIN" two-phase-complete "1-1-T1" 1 1 ".yolo-planning/.contracts/1-1.json" "incomplete"
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.result == "rejected"'
  echo "$output" | jq -e '.errors | length > 0'
}

@test "two-phase: emits candidate and confirmed events" {
  cd "$TEST_TEMP_DIR"
  create_passing_contract
  "$YOLO_BIN" two-phase-complete "1-1-T1" 1 1 ".yolo-planning/.contracts/1-1.json" "evidence" >/dev/null
  EVENTS=$(cat ".yolo-planning/.events/event-log.jsonl")
  [[ "$EVENTS" == *"task_completed_candidate"* ]]
  [[ "$EVENTS" == *"task_completed_confirmed"* ]]
}

@test "two-phase: emits rejection event on failure" {
  cd "$TEST_TEMP_DIR"
  create_failing_contract
  "$YOLO_BIN" two-phase-complete "1-1-T1" 1 1 ".yolo-planning/.contracts/1-1.json" "bad" 2>/dev/null || true
  EVENTS=$(cat ".yolo-planning/.events/event-log.jsonl")
  [[ "$EVENTS" == *"task_completed_candidate"* ]]
  [[ "$EVENTS" == *"task_completion_rejected"* ]]
}

@test "two-phase: skips when flag disabled" {
  cd "$TEST_TEMP_DIR"
  jq '.v2_two_phase_completion = false' ".yolo-planning/config.json" > ".yolo-planning/config.json.tmp" \
    && mv ".yolo-planning/config.json.tmp" ".yolo-planning/config.json"
  run "$YOLO_BIN" two-phase-complete "1-1-T1" 1 1 "any" "any"
  [ "$status" -eq 0 ]
  [[ "$output" == *"v2_two_phase_completion=false"* ]]
}

@test "two-phase: missing contract returns error" {
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" two-phase-complete "1-1-T1" 1 1 "nonexistent.json" "evidence"
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.result == "rejected"'
}

@test "two-phase: rejects when no evidence provided" {
  cd "$TEST_TEMP_DIR"
  create_passing_contract
  run "$YOLO_BIN" two-phase-complete "1-1-T1" 1 1 ".yolo-planning/.contracts/1-1.json"
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.result == "rejected"'
}

@test "two-phase: rejects when files_modified outside allowed_paths" {
  cd "$TEST_TEMP_DIR"
  create_passing_contract
  run "$YOLO_BIN" two-phase-complete "1-1-T1" 1 1 ".yolo-planning/.contracts/1-1.json" "files_modified=bad/path.js" "some evidence"
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.result == "rejected"'
}

@test "two-phase: passes when files_modified within allowed_paths" {
  cd "$TEST_TEMP_DIR"
  create_passing_contract
  run "$YOLO_BIN" two-phase-complete "1-1-T1" 1 1 ".yolo-planning/.contracts/1-1.json" "files_modified=src/a.js" "feature works"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "confirmed"'
}

# --- Artifact registry ---

@test "artifact-registry: register creates entry" {
  cd "$TEST_TEMP_DIR"
  echo "test content" > "$TEST_TEMP_DIR/test-artifact.txt"
  run "$YOLO_BIN" artifact register "test-artifact.txt" "evt-001" 1 1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "registered"'
  [ -f ".yolo-planning/.artifacts/registry.jsonl" ]
}

@test "artifact-registry: query finds registered artifact" {
  cd "$TEST_TEMP_DIR"
  echo "content" > "$TEST_TEMP_DIR/found.txt"
  "$YOLO_BIN" artifact register "found.txt" "evt-002" 1 1 >/dev/null
  run "$YOLO_BIN" artifact query "found.txt"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "found"'
  echo "$output" | jq -e '.count == 1'
}

@test "artifact-registry: query not found returns empty" {
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" artifact query "missing.txt"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "not_found"'
}

@test "artifact-registry: list returns all artifacts" {
  cd "$TEST_TEMP_DIR"
  echo "a" > "$TEST_TEMP_DIR/a.txt"
  echo "b" > "$TEST_TEMP_DIR/b.txt"
  "$YOLO_BIN" artifact register "a.txt" "evt-003" 1 1 >/dev/null
  "$YOLO_BIN" artifact register "b.txt" "evt-004" 1 1 >/dev/null
  run "$YOLO_BIN" artifact list
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.count == 2'
}

@test "artifact-registry: list filters by phase" {
  cd "$TEST_TEMP_DIR"
  echo "a" > "$TEST_TEMP_DIR/a.txt"
  echo "b" > "$TEST_TEMP_DIR/b.txt"
  "$YOLO_BIN" artifact register "a.txt" "evt-005" 1 1 >/dev/null
  "$YOLO_BIN" artifact register "b.txt" "evt-006" 2 1 >/dev/null
  run "$YOLO_BIN" artifact list 1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.count == 1'
}

# --- Config flag ---

@test "defaults.json includes v2_two_phase_completion flag" {
  run jq '.v2_two_phase_completion' "$CONFIG_DIR/defaults.json"
  [ "$output" = "false" ]
}

# --- Execute protocol integration ---

@test "execute-protocol references two-phase completion" {
  run grep -c "two-phase-complete" "$PROJECT_ROOT/skills/execute-protocol/SKILL.md"
  [ "$output" -ge 1 ]
}
