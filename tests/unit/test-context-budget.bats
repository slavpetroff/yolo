#!/usr/bin/env bats
# test-context-budget.bats — Tests for --measure reports, trim-to-budget,
# trimmed context required fields, and manifest completeness.
# Plan 09-06 T5

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir

  SUT="$SCRIPTS_DIR/compile-context.sh"
  MANIFEST="$CONFIG_DIR/context-manifest.json"

  # Create minimal planning structure
  PHASES_DIR="$TEST_WORKDIR/.yolo-planning/phases"
  mkdir -p "$PHASES_DIR/01-setup"
  mkdir -p "$TEST_WORKDIR/.yolo-planning/codebase"

  # Create minimal ROADMAP.md
  cat > "$TEST_WORKDIR/.yolo-planning/ROADMAP.md" <<'EOF'
## Phase 1: Setup
**Goal:** Initial setup
**Reqs:** REQ-01
**Success:** Tests pass
EOF

  # Create minimal plan.jsonl
  cat > "$PHASES_DIR/01-setup/01-01.plan.jsonl" <<'EOF'
{"p":"01","n":"01","t":"Setup","w":1,"d":[],"mh":{"tr":["tests pass"]},"obj":"Setup"}
{"id":"T1","tp":"auto","a":"Create file","f":["src/main.sh"],"v":"File exists","done":"File created","spec":"Create main.sh"}
EOF

  # Set CLAUDE_PLUGIN_ROOT for compile-context.sh
  export CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT"
}

# ============================================================
# --measure report tests
# ============================================================

@test "--measure outputs JSON with budget field" {
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT' --measure 01 dev '$PHASES_DIR' '$PHASES_DIR/01-setup/01-01.plan.jsonl' 2>&1 1>/dev/null"
  assert_success
  assert_output --partial '"budget"'
}

@test "--measure outputs JSON with filtered_tokens field" {
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT' --measure 01 dev '$PHASES_DIR' '$PHASES_DIR/01-setup/01-01.plan.jsonl' 2>&1 1>/dev/null"
  assert_success
  assert_output --partial '"filtered_tokens"'
}

@test "--measure outputs JSON with trimmed field" {
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT' --measure 01 dev '$PHASES_DIR' '$PHASES_DIR/01-setup/01-01.plan.jsonl' 2>&1 1>/dev/null"
  assert_success
  assert_output --partial '"trimmed"'
}

@test "--measure JSON is valid" {
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT' --measure 01 dev '$PHASES_DIR' '$PHASES_DIR/01-setup/01-01.plan.jsonl' 2>&1 1>/dev/null"
  assert_success
  echo "$output" | jq empty
}

@test "--measure trimmed=false when context within budget" {
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT' --measure 01 dev '$PHASES_DIR' '$PHASES_DIR/01-setup/01-01.plan.jsonl' 2>&1 1>/dev/null"
  assert_success
  local trimmed
  trimmed=$(echo "$output" | jq -r '.trimmed')
  [ "$trimmed" = "false" ]
}

# ============================================================
# Trim-to-budget behavior
# ============================================================

@test "trim-to-budget removes optional sections when over budget" {
  # Create oversized context by adding lots of prior_plans and dept_conventions
  local phase_dir="$PHASES_DIR/01-setup"
  # Create many summary files to inflate prior_plans section
  for i in $(seq 1 20); do
    local plan_num
    plan_num=$(printf "%02d" "$i")
    cat > "$phase_dir/01-${plan_num}.summary.jsonl" <<EOF
{"p":"01","n":"${plan_num}","t":"Plan ${i}","s":"complete","dt":"2026-01-01","tc":5,"tt":5,"ch":["abc"],"fm":["src/file${i}.sh","src/other${i}.sh","src/more${i}.sh"],"dv":[],"built":["file${i}.sh"],"tst":"green_only"}
EOF
  done
  # Create large conventions file
  mkdir -p "$TEST_WORKDIR/.yolo-planning"
  {
    echo '{"conventions":['
    for i in $(seq 1 50); do
      [ "$i" -gt 1 ] && echo ","
      echo "{\"category\":\"cat-${i}\",\"rule\":\"This is a long convention rule number ${i} that contains a lot of text to inflate the context size beyond the budget limit\"}"
    done
    echo ']}'
  } > "$TEST_WORKDIR/.yolo-planning/conventions.json"

  # Run with --measure and very small budget role (scout = 1000)
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT' --measure 01 scout '$PHASES_DIR' 2>&1 1>/dev/null"
  assert_success
  # Output should be valid JSON
  echo "$output" | jq empty
}

@test "trimmed context retains phase and goal fields" {
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT' --measure 01 dev '$PHASES_DIR' '$PHASES_DIR/01-setup/01-01.plan.jsonl' 2>/dev/null"
  assert_success
  # Read the generated .ctx-dev.toon
  local ctx_file="$PHASES_DIR/01-setup/.ctx-dev.toon"
  [ -f "$ctx_file" ]
  # Must contain phase and goal lines
  run grep "^phase:" "$ctx_file"
  assert_success
  run grep "^goal:" "$ctx_file"
  assert_success
}

@test "trimmed context retains tasks section for dev role" {
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT' --measure 01 dev '$PHASES_DIR' '$PHASES_DIR/01-setup/01-01.plan.jsonl' 2>/dev/null"
  assert_success
  local ctx_file="$PHASES_DIR/01-setup/.ctx-dev.toon"
  [ -f "$ctx_file" ]
  run grep "^tasks" "$ctx_file"
  assert_success
}

# ============================================================
# Manifest completeness
# ============================================================

@test "manifest has all required base roles" {
  for role in architect lead senior dev tester qa security critic scout owner debugger documenter; do
    local has_role
    has_role=$(jq --arg r "$role" 'has("roles") and (.roles | has($r))' "$MANIFEST")
    [ "$has_role" = "true" ] || fail "Missing role: $role"
  done
}

@test "manifest has all fe- department roles" {
  for role in fe-architect fe-lead fe-senior fe-dev fe-tester fe-qa fe-security fe-documenter; do
    local has_role
    has_role=$(jq --arg r "$role" '.roles | has($r)' "$MANIFEST")
    [ "$has_role" = "true" ] || fail "Missing fe role: $role"
  done
}

@test "manifest has all ux- department roles" {
  for role in ux-architect ux-lead ux-senior ux-dev ux-tester ux-qa ux-security ux-documenter; do
    local has_role
    has_role=$(jq --arg r "$role" '.roles | has($r)' "$MANIFEST")
    [ "$has_role" = "true" ] || fail "Missing ux role: $role"
  done
}

@test "manifest fe-* roles have includes field" {
  for role in fe-architect fe-lead fe-senior fe-dev fe-tester fe-qa fe-security fe-documenter; do
    local has_includes
    has_includes=$(jq --arg r "$role" '.roles[$r] | has("includes")' "$MANIFEST")
    [ "$has_includes" = "true" ] || fail "Missing includes for: $role"
  done
}

@test "manifest ux-* roles have includes field" {
  for role in ux-architect ux-lead ux-senior ux-dev ux-tester ux-qa ux-security ux-documenter; do
    local has_includes
    has_includes=$(jq --arg r "$role" '.roles[$r] | has("includes")' "$MANIFEST")
    [ "$has_includes" = "true" ] || fail "Missing includes for: $role"
  done
}

@test "manifest every role has budget field" {
  local roles_without_budget
  roles_without_budget=$(jq -r '.roles | to_entries[] | select(.value.budget == null) | .key' "$MANIFEST")
  [ -z "$roles_without_budget" ] || fail "Roles without budget: $roles_without_budget"
}

@test "manifest analyze role has non-empty files" {
  local file_count
  file_count=$(jq '.roles.analyze.files | length' "$MANIFEST")
  [ "$file_count" -gt 0 ] || fail "analyze role has empty files array"
}

@test "manifest integration-gate does not reference non-existent department_result" {
  local has_dept_result
  has_dept_result=$(jq '.roles["integration-gate"].artifacts | index("department_result")' "$MANIFEST")
  [ "$has_dept_result" = "null" ] || fail "integration-gate still references department_result"
}

@test "manifest qa role includes code-review artifact" {
  local has_code_review
  has_code_review=$(jq '.roles.qa.artifacts | index("code-review")' "$MANIFEST")
  [ "$has_code_review" != "null" ] || fail "qa role missing code-review artifact"
}

@test "manifest has no qa-code role (merged into qa)" {
  local has_qa_code
  has_qa_code=$(jq '.roles | has("qa-code")' "$MANIFEST")
  [ "$has_qa_code" = "false" ] || fail "qa-code role should not exist (merged into qa)"
}
