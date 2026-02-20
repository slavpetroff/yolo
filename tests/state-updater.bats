#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
}

teardown() {
  teardown_temp_dir
}

create_state_and_roadmap() {
  local root="$1"
  local phase_num="$2"

  cat > "$root/STATE.md" <<EOF
Phase: ${phase_num} of 4 (Service Utility Tests)
Plans: 0/0
Progress: 0%
Status: pending
EOF

  cat > "$root/ROADMAP.md" <<EOF
- [ ] Phase ${phase_num}: Service Utility Tests

| Phase | Progress | Status | Completed |
|------|----------|--------|-----------|
| ${phase_num} - Service Utility Tests | 0/0 | pending | - |
EOF
}

@test "summary update advances STATE/ROADMAP without execution-state file" {
  cd "$TEST_TEMP_DIR"
  create_state_and_roadmap "$TEST_TEMP_DIR/.yolo-planning" 3

  mkdir -p .yolo-planning/phases/03-service-utility-tests
  echo "# plan" > .yolo-planning/phases/03-service-utility-tests/03-01-PLAN.md
  echo "# Summary without frontmatter" > .yolo-planning/phases/03-service-utility-tests/03-01-SUMMARY.md

  local summary_path input
  summary_path="$TEST_TEMP_DIR/.yolo-planning/phases/03-service-utility-tests/03-01-SUMMARY.md"
  input=$(jq -nc --arg p "$summary_path" '{tool_input:{file_path:$p}}')

  run bash -c "cd '$TEST_TEMP_DIR' && printf '%s' '$input' | bash '$SCRIPTS_DIR/state-updater.sh'"
  [ "$status" -eq 0 ]

  grep -q '^Plans: 1/1$' .yolo-planning/STATE.md
  grep -q '^Progress: 100%$' .yolo-planning/STATE.md
  grep -q '^- \[x\] Phase 3: Service Utility Tests$' .yolo-planning/ROADMAP.md
  grep -Eq '^\| 3 - Service Utility Tests \| 1/1 \| complete \| [0-9]{4}-[0-9]{2}-[0-9]{2} \|$' .yolo-planning/ROADMAP.md
}

@test "summary update patches execution state in .plans[] schema" {
  cd "$TEST_TEMP_DIR"
  create_state_and_roadmap "$TEST_TEMP_DIR/.yolo-planning" 3

  mkdir -p .yolo-planning/phases/03-service-utility-tests
  echo "# plan" > .yolo-planning/phases/03-service-utility-tests/03-01-PLAN.md
  cat > .yolo-planning/phases/03-service-utility-tests/03-01-SUMMARY.md <<'EOF'
---
phase: 3
plan: 1
status: complete
---

# Summary
EOF

  cat > .yolo-planning/.execution-state.json <<'EOF'
{
  "phase": 3,
  "phase_name": "service-utility-tests",
  "status": "running",
  "wave": 1,
  "total_waves": 1,
  "plans": [
    {"id": "03-01", "title": "test", "wave": 1, "status": "pending"}
  ]
}
EOF

  local summary_path input
  summary_path="$TEST_TEMP_DIR/.yolo-planning/phases/03-service-utility-tests/03-01-SUMMARY.md"
  input=$(jq -nc --arg p "$summary_path" '{tool_input:{file_path:$p}}')

  run bash -c "cd '$TEST_TEMP_DIR' && printf '%s' '$input' | bash '$SCRIPTS_DIR/state-updater.sh'"
  [ "$status" -eq 0 ]
  jq -e '.plans[0].status == "complete"' .yolo-planning/.execution-state.json >/dev/null
}

@test "PLAN trigger supports NN-PLAN naming and flips status ready to active" {
  cd "$TEST_TEMP_DIR"
  create_state_and_roadmap "$TEST_TEMP_DIR/.yolo-planning" 2
  sed -i.bak 's/^Status: .*/Status: ready/' .yolo-planning/STATE.md && rm -f .yolo-planning/STATE.md.bak

  mkdir -p .yolo-planning/phases/02-compat
  echo "# plan" > .yolo-planning/phases/02-compat/01-PLAN.md

  local plan_path input
  plan_path="$TEST_TEMP_DIR/.yolo-planning/phases/02-compat/01-PLAN.md"
  input=$(jq -nc --arg p "$plan_path" '{tool_input:{file_path:$p}}')

  run bash -c "cd '$TEST_TEMP_DIR' && printf '%s' '$input' | bash '$SCRIPTS_DIR/state-updater.sh'"
  [ "$status" -eq 0 ]

  grep -q '^Plans: 0/1$' .yolo-planning/STATE.md
  grep -q '^Status: active$' .yolo-planning/STATE.md
}

@test "summary update is milestone-aware for state, roadmap, and execution-state" {
  cd "$TEST_TEMP_DIR"

  mkdir -p .yolo-planning/milestones/m1/phases/03-service-utility-tests
  echo "m1" > .yolo-planning/ACTIVE

  # Root files should remain untouched
  cat > .yolo-planning/STATE.md <<'EOF'
Phase: 3 of 4 (Root)
Plans: 9/9
Progress: 100%
Status: complete
EOF
  cat > .yolo-planning/ROADMAP.md <<'EOF'
- [x] Phase 3: Root
| Phase | Progress | Status | Completed |
|------|----------|--------|-----------|
| 3 - Root | 9/9 | complete | 2026-01-01 |
EOF
  cat > .yolo-planning/.execution-state.json <<'EOF'
{"plans":[{"id":"03-01","status":"pending"}]}
EOF

  create_state_and_roadmap "$TEST_TEMP_DIR/.yolo-planning/milestones/m1" 3
  cat > .yolo-planning/milestones/m1/.execution-state.json <<'EOF'
{"plans":[{"id":"03-01","status":"pending"}]}
EOF

  echo "# plan" > .yolo-planning/milestones/m1/phases/03-service-utility-tests/03-01-PLAN.md
  cat > .yolo-planning/milestones/m1/phases/03-service-utility-tests/03-01-SUMMARY.md <<'EOF'
---
phase: 3
plan: 1
status: complete
---

# Summary
EOF

  local summary_path input
  summary_path="$TEST_TEMP_DIR/.yolo-planning/milestones/m1/phases/03-service-utility-tests/03-01-SUMMARY.md"
  input=$(jq -nc --arg p "$summary_path" '{tool_input:{file_path:$p}}')

  run bash -c "cd '$TEST_TEMP_DIR' && printf '%s' '$input' | bash '$SCRIPTS_DIR/state-updater.sh'"
  [ "$status" -eq 0 ]

  grep -q '^Plans: 1/1$' .yolo-planning/milestones/m1/STATE.md
  grep -q '^Plans: 9/9$' .yolo-planning/STATE.md

  jq -e '.plans[0].status == "complete"' .yolo-planning/milestones/m1/.execution-state.json >/dev/null
  jq -e '.plans[0].status == "pending"' .yolo-planning/.execution-state.json >/dev/null
}