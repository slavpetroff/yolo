#!/usr/bin/env bats
# token-optimization.bats -- Integration tests for Phase 3 token optimization pipeline
# Tests the full chain: validate-plan, validate-gates, generate-execution-state,
# compile-context with packages, resolve-tool-permissions.
# Scripts from 03-01/03-03 guarded with skip when not present.

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir

  # Set script paths
  VALIDATE_PLAN="$SCRIPTS_DIR/validate-plan.sh"
  VALIDATE_GATES="$SCRIPTS_DIR/validate-gates.sh"
  GEN_STATE="$SCRIPTS_DIR/generate-execution-state.sh"
  COMPILE_CTX="$SCRIPTS_DIR/compile-context.sh"
  RESOLVE_PERMS="$SCRIPTS_DIR/resolve-tool-permissions.sh"
  DETECT_STACK="$SCRIPTS_DIR/detect-stack.sh"

  # Create full phase environment
  mkdir -p "$TEST_WORKDIR/.yolo-planning/phases/01-setup"
  mkdir -p "$TEST_WORKDIR/.yolo-planning/codebase"

  # ROADMAP
  cat > "$TEST_WORKDIR/.yolo-planning/ROADMAP.md" <<'EOF'
# Roadmap

## Phase 1: Setup
**Goal:** Initialize the project structure
**Reqs:** REQ-01, REQ-02
**Success Criteria:** All files created

## Phase 2: Build
**Goal:** Build the core
EOF

  # Conventions
  cat > "$TEST_WORKDIR/.yolo-planning/conventions.json" <<'EOF'
{"conventions":[{"category":"naming","rule":"Use kebab-case for files"},{"category":"style","rule":"One commit per task"}]}
EOF

  # Codebase mapping files
  if [ -d "$FIXTURES_DIR/codebase" ]; then
    cp "$FIXTURES_DIR/codebase/INDEX.md" "$TEST_WORKDIR/.yolo-planning/codebase/INDEX.md" 2>/dev/null || true
    cp "$FIXTURES_DIR/codebase/PATTERNS.md" "$TEST_WORKDIR/.yolo-planning/codebase/PATTERNS.md" 2>/dev/null || true
  fi

  # Copy valid plan to phase dir
  cp "$FIXTURES_DIR/plans/valid-plan.jsonl" "$TEST_WORKDIR/.yolo-planning/phases/01-setup/01-01.plan.jsonl"

  # Create mock reference packages
  mkdir -p "$TEST_WORKDIR/references/packages"

  for role in architect lead senior dev tester qa qa-code critic security; do
    cat > "$TEST_WORKDIR/references/packages/${role}.toon" <<TOOF
role: ${role}
step_protocol: Step extract for ${role}
escalation: ${role} escalation chain
TOOF
  done

  PHASES_DIR="$TEST_WORKDIR/.yolo-planning/phases"
}

# Helper: run command from test workdir
run_from_workdir() {
  run bash -c "cd '$TEST_WORKDIR' && $*"
}

# --- Test 1: validate-plan.sh accepts valid plan ---

@test "validate-plan.sh accepts valid plan" {
  [ -f "$VALIDATE_PLAN" ] || skip "validate-plan.sh not yet built (03-01 dependency)"
  # Create a fully valid plan with all required keys
  local full_plan="$TEST_WORKDIR/.yolo-planning/phases/01-setup/01-02.plan.jsonl"
  cat > "$full_plan" <<'PLAN'
{"p":"01","n":"02","t":"Full plan","w":1,"d":[],"xd":[],"mh":{"tr":["it works"]},"obj":"Test","sk":[],"fm":["src/a.ts"],"auto":true}
{"id":"T1","tp":"auto","a":"Do thing","f":["src/a.ts"],"v":"test passes","done":"file exists","spec":"Create file"}
PLAN
  run_from_workdir bash "$VALIDATE_PLAN" "$full_plan"
  assert_success
  echo "$output" | jq -r '.valid' | grep -q 'true'
}

# --- Test 2: validate-plan.sh rejects invalid plan ---

@test "validate-plan.sh rejects invalid plan" {
  [ -f "$VALIDATE_PLAN" ] || skip "validate-plan.sh not yet built (03-01 dependency)"
  echo '{"bad":true}' > "$TEST_WORKDIR/invalid.plan.jsonl"
  run_from_workdir bash "$VALIDATE_PLAN" "$TEST_WORKDIR/invalid.plan.jsonl"
  assert_failure
}

# --- Test 3: generate-execution-state.sh produces valid state from phase dir ---

@test "generate-execution-state.sh produces valid state from phase dir" {
  [ -f "$GEN_STATE" ] || skip "generate-execution-state.sh not yet built (03-01 dependency)"
  run_from_workdir bash "$GEN_STATE" --phase-dir "$TEST_WORKDIR/.yolo-planning/phases/01-setup" --phase 1
  assert_success

  # Script writes .execution-state.json to phase dir and prints path to stdout
  local state_file="$TEST_WORKDIR/.yolo-planning/phases/01-setup/.execution-state.json"
  [ -f "$state_file" ]

  # Validate the JSON file has correct schema
  run jq -r '.status' "$state_file"
  assert_output "running"

  run jq -r '.plans | length' "$state_file"
  [ "$output" -gt 0 ]

  run jq -r '.steps.critique.status' "$state_file"
  assert_output "pending"
}

# --- Test 4: compile-context.sh with packages includes reference_package section ---

@test "compile-context.sh with packages includes reference_package section" {
  run_from_workdir bash "$COMPILE_CTX" 01 dev "$TEST_WORKDIR/.yolo-planning/phases" "$TEST_WORKDIR/.yolo-planning/phases/01-setup/01-01.plan.jsonl"
  assert_success
  local ctx="$TEST_WORKDIR/.yolo-planning/phases/01-setup/.ctx-dev.toon"
  run cat "$ctx"
  assert_output --partial "reference_package:"
}

# --- Test 5: compile-context.sh without packages omits reference_package section ---

@test "compile-context.sh without packages omits reference_package section" {
  rm -rf "$TEST_WORKDIR/references/packages"
  run_from_workdir bash "$COMPILE_CTX" 01 dev "$TEST_WORKDIR/.yolo-planning/phases" "$TEST_WORKDIR/.yolo-planning/phases/01-setup/01-01.plan.jsonl"
  assert_success
  local ctx="$TEST_WORKDIR/.yolo-planning/phases/01-setup/.ctx-dev.toon"
  run grep 'reference_package' "$ctx"
  assert_failure
}

# --- Test 6: full pipeline -- senior context is valid and within budget ---

@test "full pipeline: senior context is valid TOON with all sections" {
  run_from_workdir bash "$COMPILE_CTX" 01 senior "$TEST_WORKDIR/.yolo-planning/phases"
  assert_success
  local ctx="$TEST_WORKDIR/.yolo-planning/phases/01-setup/.ctx-senior.toon"
  run cat "$ctx"
  assert_output --partial "phase: 01"
  assert_output --partial "goal:"
  assert_output --partial "conventions"
  assert_output --partial "reference_package:"

  # Verify tokens within budget
  local chars
  chars=$(wc -c < "$ctx")
  local tokens=$((chars / 4))
  [ "$tokens" -le 4000 ]
}

# --- Test 7: resolve-tool-permissions.sh returns JSON for dev role ---

@test "resolve-tool-permissions.sh returns JSON for dev role" {
  [ -f "$RESOLVE_PERMS" ] || skip "resolve-tool-permissions.sh not yet built (03-03 dependency)"
  run_from_workdir bash "$RESOLVE_PERMS" --role dev --project-dir "$TEST_WORKDIR"
  assert_success
  echo "$output" | jq empty
  echo "$output" | jq -r '.role' | grep -q 'dev'
}

# --- Test 8: validate-gates.sh returns structured JSON ---

@test "validate-gates.sh checks gate and returns structured JSON" {
  [ -f "$VALIDATE_GATES" ] || skip "validate-gates.sh not yet built (03-01 dependency)"
  run_from_workdir bash "$VALIDATE_GATES" --step critique --phase-dir "$TEST_WORKDIR/.yolo-planning/phases/01-setup"
  # Gate may pass or fail depending on whether critique.jsonl exists
  # Either way, verify output is valid JSON
  echo "$output" | jq empty
}
