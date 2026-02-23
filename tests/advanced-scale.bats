#!/usr/bin/env bats
# Migrated: lease-lock.sh -> yolo lease-lock, recover-state.sh -> yolo recover-state,
#           route-monorepo.sh -> yolo route-monorepo
# CWD-sensitive: yes

load test_helper

setup() {
  setup_temp_dir
  create_test_config

  # Enable all Phase 6 flags
  cd "$TEST_TEMP_DIR"
  jq '.v3_lease_locks = true | .v3_lock_lite = true | .v3_event_recovery = true | .v3_monorepo_routing = true | .v3_event_log = true' \
    .yolo-planning/config.json > .yolo-planning/config.json.tmp && \
    mv .yolo-planning/config.json.tmp .yolo-planning/config.json
}

teardown() {
  teardown_temp_dir
}

# --- lease-lock tests (yolo lease-lock) ---

@test "lease-lock: acquire creates lock with TTL" {
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" lease-lock acquire file1.sh --owner=test-task --ttl=60
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "acquired"'
  echo "$output" | jq -e '.ttl_secs == 60'
  echo "$output" | jq -e '.resource == "file1.sh"'
  echo "$output" | jq -e '.owner == "test-task"'
}

@test "lease-lock: renew extends lease" {
  cd "$TEST_TEMP_DIR"
  "$YOLO_BIN" lease-lock acquire file1.sh --owner=test-task --ttl=60 >/dev/null
  sleep 1
  run "$YOLO_BIN" lease-lock renew file1.sh --owner=test-task --ttl=120
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "renewed"'
  echo "$output" | jq -e '.ttl_secs == 120'
}

@test "lease-lock: cleanup detects expired locks" {
  cd "$TEST_TEMP_DIR"
  # Create a lease that's already expired via direct file write
  mkdir -p .yolo-planning/.locks
  cat > .yolo-planning/.locks/shared.sh.lease <<'JSON'
{"resource":"shared.sh","owner":"old-task","acquired_at":"2020-01-01T00:00:00Z","ttl_secs":1,"type":"lease"}
JSON

  run "$YOLO_BIN" lease-lock cleanup
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.action == "cleanup"'
  echo "$output" | jq -e '.cleaned >= 1'
  # Expired lease file should be removed
  [ ! -f ".yolo-planning/.locks/shared.sh.lease" ]
}

@test "lease-lock: release removes lock" {
  cd "$TEST_TEMP_DIR"
  "$YOLO_BIN" lease-lock acquire file1.sh --owner=test-task >/dev/null
  run "$YOLO_BIN" lease-lock release file1.sh --owner=test-task
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "released"'
  [ ! -f ".yolo-planning/.locks/file1.sh.lease" ]
}

@test "lease-lock: skip when both flags disabled" {
  cd "$TEST_TEMP_DIR"
  jq '.v3_lease_locks = false | .v3_lock_lite = false' .yolo-planning/config.json > .yolo-planning/config.json.tmp && \
    mv .yolo-planning/config.json.tmp .yolo-planning/config.json
  run "$YOLO_BIN" lease-lock acquire file1.sh --owner=test-task
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "skip"'
}

@test "lease-lock: exits non-zero on conflict when v2_hard_gates=true" {
  cd "$TEST_TEMP_DIR"
  jq '.v3_lease_locks = true | .v2_hard_gates = true' .yolo-planning/config.json > .yolo-planning/config.json.tmp && \
    mv .yolo-planning/config.json.tmp .yolo-planning/config.json
  "$YOLO_BIN" lease-lock acquire file1.sh --owner=other-task >/dev/null 2>&1
  run "$YOLO_BIN" lease-lock acquire file1.sh --owner=new-task
  [ "$status" -ne 0 ]
  echo "$output" | jq -e '.result == "conflict"'
}

@test "lease-lock: conflict returns non-zero when v2_hard_gates=false" {
  cd "$TEST_TEMP_DIR"
  jq '.v3_lease_locks = true | .v2_hard_gates = false' .yolo-planning/config.json > .yolo-planning/config.json.tmp && \
    mv .yolo-planning/config.json.tmp .yolo-planning/config.json
  "$YOLO_BIN" lease-lock acquire file1.sh --owner=other-task >/dev/null 2>&1
  run "$YOLO_BIN" lease-lock acquire file1.sh --owner=new-task
  [ "$status" -ne 0 ]
  echo "$output" | jq -e '.result == "conflict"'
}

@test "lease-lock: reentrant acquire renews" {
  cd "$TEST_TEMP_DIR"
  "$YOLO_BIN" lease-lock acquire file1.sh --owner=test-task --ttl=60 >/dev/null
  run "$YOLO_BIN" lease-lock acquire file1.sh --owner=test-task --ttl=120
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "renewed"'
}

@test "lease-lock: release non-existent returns not_held" {
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" lease-lock release nonexistent --owner=test-task
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "not_held"'
}

# --- recover-state tests (yolo recover-state) ---

@test "recover-state: reconstructs state from event log and summaries" {
  cd "$TEST_TEMP_DIR"
  # Create phase directory with plans and a summary
  mkdir -p .yolo-planning/phases/05-test-phase
  cat > .yolo-planning/phases/05-test-phase/05-01-PLAN.md <<'EOF'
---
phase: 5
plan: 1
title: "Test Plan"
wave: 1
depends_on: []
must_haves: []
---
# Plan 05-01
EOF
  cat > .yolo-planning/phases/05-test-phase/05-02-PLAN.md <<'EOF'
---
phase: 5
plan: 2
title: "Test Plan 2"
wave: 2
depends_on: [1]
must_haves: []
---
# Plan 05-02
EOF
  # Only first plan has a summary
  cat > .yolo-planning/phases/05-test-phase/05-01-SUMMARY.md <<'EOF'
---
phase: 5
plan: 1
title: "Test Plan"
status: complete
tasks_completed: 3
tasks_total: 3
---
# Summary
EOF

  # Create event log
  mkdir -p .yolo-planning/.events
  echo '{"ts":"2026-01-01T00:00:00Z","event":"phase_start","phase":5}' > .yolo-planning/.events/event-log.jsonl
  echo '{"ts":"2026-01-01T00:01:00Z","event":"plan_end","phase":5,"plan":1,"data":{"status":"complete"}}' >> .yolo-planning/.events/event-log.jsonl

  run "$YOLO_BIN" recover-state 5 .yolo-planning/phases
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.delta.phase == 5'
  echo "$output" | jq -e '.delta.status == "running"'
  echo "$output" | jq -e '.delta.plans | length == 2'
  echo "$output" | jq -e '.delta.plans[0].status == "complete"'
  echo "$output" | jq -e '.delta.plans[1].status == "pending"'
}

@test "recover-state: exits with skip code when flag disabled" {
  cd "$TEST_TEMP_DIR"
  jq '.v3_event_recovery = false' .yolo-planning/config.json > .yolo-planning/config.json.tmp && \
    mv .yolo-planning/config.json.tmp .yolo-planning/config.json
  run "$YOLO_BIN" recover-state 5
  [ "$status" -eq 3 ]
  echo "$output" | jq -e '.ok == true'
  echo "$output" | jq -e '.delta.recovered == false'
}

# --- route-monorepo tests (yolo route-monorepo) ---

@test "route-monorepo: detects package roots from plan files" {
  cd "$TEST_TEMP_DIR"
  # Create monorepo structure
  mkdir -p packages/core packages/utils apps/web
  echo '{}' > packages/core/package.json
  echo '{}' > packages/utils/package.json
  echo '{}' > apps/web/package.json

  # Create a plan referencing files in packages/core
  mkdir -p .yolo-planning/phases/01-test
  cat > .yolo-planning/phases/01-test/01-01-PLAN.md <<'EOF'
---
phase: 1
plan: 1
title: "Test"
wave: 1
depends_on: []
must_haves: []
---
# Plan
## Tasks
### Task 1: Update core
- **Files:** `packages/core/index.js`, `packages/core/utils.js`
### Task 2: Update web
- **Files:** `apps/web/app.js`
EOF

  run "$YOLO_BIN" route-monorepo .yolo-planning/phases/01-test
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length == 2'
  echo "$output" | jq -e 'any(. == "packages/core")'
  echo "$output" | jq -e 'any(. == "apps/web")'
}

@test "route-monorepo: returns empty for non-monorepo" {
  cd "$TEST_TEMP_DIR"
  # No sub-package markers
  mkdir -p .yolo-planning/phases/01-test
  cat > .yolo-planning/phases/01-test/01-01-PLAN.md <<'EOF'
---
phase: 1
plan: 1
title: "Test"
wave: 1
depends_on: []
must_haves: []
---
# Plan
## Tasks
### Task 1: Do something
- **Files:** `src/main.js`
EOF

  run "$YOLO_BIN" route-monorepo .yolo-planning/phases/01-test
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "route-monorepo: exits 0 when flag disabled" {
  cd "$TEST_TEMP_DIR"
  jq '.v3_monorepo_routing = false' .yolo-planning/config.json > .yolo-planning/config.json.tmp && \
    mv .yolo-planning/config.json.tmp .yolo-planning/config.json
  run "$YOLO_BIN" route-monorepo .yolo-planning/phases/01-test
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}
