#!/usr/bin/env bats

load test_helper

RUST_SRC="$PROJECT_ROOT/yolo-mcp-server/src"

setup() {
  setup_temp_dir
  export YOLO_BIN="${YOLO_BIN:-$HOME/.cargo/bin/yolo}"
}

teardown() {
  teardown_temp_dir
}

# =============================================================================
# Bug #2: No destructive git commands in session-start (Rust source)
# =============================================================================

@test "session-start.rs contains no destructive git commands" {
  # Destructive patterns: reset --hard, checkout ., restore ., clean -f
  run grep -E 'reset.*hard|checkout.*\.\"|restore.*\.\"|clean.*-f' "$RUST_SRC/commands/session_start.rs"
  [ "$status" -eq 1 ]  # grep returns 1 = no matches found
}

@test "session-start.rs marketplace sync uses safe merge" {
  # Must use --ff-only (safe merge) and git diff --quiet (dirty-check guard)
  grep -q 'ff-only' "$RUST_SRC/commands/session_start.rs"
  grep -q 'diff.*quiet' "$RUST_SRC/commands/session_start.rs"
}

# =============================================================================
# Bug #3: update-state CLI handles plan and summary files
# =============================================================================

@test "update-state rejects non-plan non-summary files" {
  echo "some content" > "$TEST_TEMP_DIR/random.txt"
  run "$YOLO_BIN" update-state "$TEST_TEMP_DIR/random.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Not a PLAN.md or SUMMARY.md"* ]]
}

@test "update-state reports missing file gracefully" {
  run "$YOLO_BIN" update-state "$TEST_TEMP_DIR/nonexistent.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "update-state accepts PLAN.md files" {
  cd "$TEST_TEMP_DIR"
  mkdir -p .yolo-planning/phases/01-test
  create_test_config
  cat > .yolo-planning/ROADMAP.md <<'EOF'
## Phases
## Phase 1: Test
**Goal:** Test
**Success:** Works
EOF
  cat > .yolo-planning/STATE.md <<'EOF'
Phase: 1 of 1 (Test)
Status: ready
Progress: 0%
EOF
  cat > .yolo-planning/phases/01-test/01-01-PLAN.md <<'EOF'
---
phase: 1
plan: 01
title: Test Plan
---
### Task 1
Test task
EOF
  run "$YOLO_BIN" update-state ".yolo-planning/phases/01-test/01-01-PLAN.md"
  [ "$status" -eq 0 ]
}

# =============================================================================
# Bug #8: compile-context supports all 6 roles
# =============================================================================

# Helper: set up minimal .yolo-planning structure for compile-context
setup_compile_context() {
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning/phases/01-test"
  create_test_config

  cat > "$TEST_TEMP_DIR/.yolo-planning/ROADMAP.md" <<'ROADMAP'
## Phases

## Phase 1: Test Phase
**Goal:** Test the context compiler
**Reqs:** REQ-01
**Success:** All roles produce context files

---

## Phase 2: Future Phase
**Goal:** Placeholder for parser termination
**Reqs:** REQ-02
**Success:** Parser correctly terminates section
ROADMAP

  cat > "$TEST_TEMP_DIR/.yolo-planning/REQUIREMENTS.md" <<'REQS'
## Requirements
- [REQ-01] Sample requirement for testing
REQS

  cat > "$TEST_TEMP_DIR/.yolo-planning/STATE.md" <<'STATE'
## Status
Phase: 1 of 1 (Test Phase)
Status: executing
Progress: 50%

## Activity
- Task 1 completed
- Task 2 in progress

## Decisions
- Decided to test all roles
STATE
}

@test "compile-context supports all 6 roles" {
  setup_compile_context
  cd "$TEST_TEMP_DIR"
  for role in lead dev qa reviewer debugger architect; do
    run "$YOLO_BIN" compile-context "01" "$role" ".yolo-planning/phases"
    [ "$status" -eq 0 ]
    [ -f ".yolo-planning/phases/.context-${role}.md" ]
    # File must be non-empty
    [ -s ".yolo-planning/phases/.context-${role}.md" ]
  done
}

@test "compile-context lead context includes ROADMAP content" {
  setup_compile_context
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" compile-context "01" "lead" ".yolo-planning/phases"
  [ "$status" -eq 0 ]
  grep -q "Test the context compiler" ".yolo-planning/phases/.context-lead.md"
}

@test "compile-context architect context includes requirements" {
  setup_compile_context
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" compile-context "01" "architect" ".yolo-planning/phases"
  [ "$status" -eq 0 ]
  grep -q "Requirements\|REQ-01" ".yolo-planning/phases/.context-architect.md"
}

@test "compile-context extracts goal from ROADMAP" {
  setup_compile_context
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" compile-context "01" "lead" ".yolo-planning/phases"
  [ "$status" -eq 0 ]
  # Goal should be actual text from ROADMAP
  grep -q "Test the context compiler" ".yolo-planning/phases/.context-lead.md"
  # Success criteria should also be extracted
  grep -q "All roles produce context files" ".yolo-planning/phases/.context-lead.md"
}

@test "compile-context includes REQUIREMENTS.md content" {
  setup_compile_context
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" compile-context "01" "architect" ".yolo-planning/phases"
  [ "$status" -eq 0 ]
  grep -q "REQ-01" ".yolo-planning/phases/.context-architect.md"
}

@test "compile-context handles empty event log gracefully" {
  setup_compile_context
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" compile-context "01" "dev" ".yolo-planning/phases"
  [ "$status" -eq 0 ]
  [ -f ".yolo-planning/phases/.context-dev.md" ]
}

@test "compile-context output contains tier structure" {
  setup_compile_context
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" compile-context "01" "lead" ".yolo-planning/phases"
  [ "$status" -eq 0 ]
  grep -q "TIER" ".yolo-planning/phases/.context-lead.md"
}

# =============================================================================
# Bug #10: compaction-instructions via PreCompact hook
# =============================================================================

@test "pre-compact hook outputs role-specific priorities" {
  cd "$TEST_TEMP_DIR"
  mkdir -p .yolo-planning
  create_test_config
  # Dev agent should get commit/file priorities
  run bash -c 'echo "{\"agent_name\":\"yolo-dev-01\",\"matcher\":\"auto\"}" | "'"$YOLO_BIN"'" hook pre-compact'
  [ "$status" -eq 0 ]
  [[ "$output" == *"commit hashes"* ]]
  [[ "$output" == *"file paths modified"* ]]
}

@test "pre-compact hook returns valid JSON" {
  cd "$TEST_TEMP_DIR"
  mkdir -p .yolo-planning
  create_test_config
  run bash -c 'echo "{\"agent_name\":\"yolo-dev-01\",\"matcher\":\"auto\"}" | "'"$YOLO_BIN"'" hook pre-compact'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext' > /dev/null
}

# =============================================================================
# Bug #11: Blocked agent notification in execute-protocol
# =============================================================================

@test "execute-protocol.md contains blocked agent notification" {
  grep -q "Blocked agent notification" "$PROJECT_ROOT/skills/execute-protocol/SKILL.md"
}

# =============================================================================
# Bug #14: task-verify uses keyword matching (Rust source)
# =============================================================================

@test "post-tool-use hook handles SUMMARY.md writes" {
  cd "$TEST_TEMP_DIR"
  mkdir -p .yolo-planning/phases/01-test
  create_test_config
  INPUT='{"tool_name":"Write","tool_input":{"file_path":".yolo-planning/phases/01-test/01-01-SUMMARY.md","content":"test"}}'
  run bash -c "echo '$INPUT' | \"$YOLO_BIN\" hook post-tool-use"
  [ "$status" -eq 0 ]
}

# =============================================================================
# Bug #16: route-monorepo detects monorepo structures
# =============================================================================

# Helper: set up monorepo test structure
setup_monorepo() {
  cd "$TEST_TEMP_DIR"
  mkdir -p .yolo-planning/phases/01-test
  create_test_config
  # Enable monorepo routing
  local TMP
  TMP=$(mktemp)
  jq '.v3_monorepo_routing = true' .yolo-planning/config.json > "$TMP" && mv "$TMP" .yolo-planning/config.json
}

@test "route-monorepo detects package roots" {
  setup_monorepo
  # Create monorepo structure
  mkdir -p packages/core apps/web
  echo '{}' > packages/core/package.json
  echo '{}' > apps/web/package.json
  echo '{}' > package.json

  cat > .yolo-planning/phases/01-test/01-01-PLAN.md <<'PLAN'
---
phase: 1
plan: 1
title: "Test Plan"
---
### Task 1
- **Files:** `packages/core/src/index.ts`
PLAN

  run "$YOLO_BIN" route-monorepo ".yolo-planning/phases/01-test"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '. | length > 0' >/dev/null
  echo "$output" | grep -q "packages/core"
}

@test "route-monorepo returns empty for non-monorepo" {
  setup_monorepo
  # Only root package.json, no sub-packages
  echo '{}' > package.json

  cat > .yolo-planning/phases/01-test/01-01-PLAN.md <<'PLAN'
---
phase: 1
plan: 1
title: "Test Plan"
---
### Task 1
- **Files:** `src/index.ts`
PLAN

  run "$YOLO_BIN" route-monorepo ".yolo-planning/phases/01-test"
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "route-monorepo detects multiple package markers" {
  setup_monorepo
  # Create mixed-language monorepo
  mkdir -p packages/api packages/worker
  echo 'module example.com/api' > packages/api/go.mod
  echo '[package]' > packages/worker/Cargo.toml
  echo '{}' > package.json

  cat > .yolo-planning/phases/01-test/01-01-PLAN.md <<'PLAN'
---
phase: 1
plan: 1
title: "Test Plan"
---
### Task 1
- **Files:** `packages/api/main.go`, `packages/worker/src/lib.rs`
PLAN

  run "$YOLO_BIN" route-monorepo ".yolo-planning/phases/01-test"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '. | length == 2' >/dev/null
  echo "$output" | grep -q "packages/api"
  echo "$output" | grep -q "packages/worker"
}
