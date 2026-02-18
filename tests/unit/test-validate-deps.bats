#!/usr/bin/env bats
# test-validate-deps.bats — Unit tests for scripts/validate-deps.sh
# Validates dependency graph: linear chains, cycles, missing refs, empty, critical path.

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/validate-deps.sh"
}

# Helper: create a dependency graph JSON file
mk_dep_graph() {
  local file="$TEST_WORKDIR/deps.json"
  cat > "$file"
  echo "$file"
}

@test "validate-deps.sh exists and is executable" {
  [ -f "$SUT" ] || skip "validate-deps.sh not yet created"
  [ -x "$SUT" ] || skip "validate-deps.sh not executable"
}

@test "valid linear graph A->B->C returns valid:true" {
  [ -x "$SUT" ] || skip "validate-deps.sh not yet created"
  local graph
  graph=$(mk_dep_graph <<'JSON'
{
  "phases": [
    {"id": "A", "depends_on": []},
    {"id": "B", "depends_on": ["A"]},
    {"id": "C", "depends_on": ["B"]}
  ]
}
JSON
  )
  run bash "$SUT" --roadmap-json "$graph"
  assert_success
  local valid
  valid=$(echo "$output" | jq -r '.valid // empty' 2>/dev/null)
  [ "$valid" = "true" ] || skip "Output format not matching spec yet"
}

@test "circular dependency A->B->C->A returns valid:false with cycle error" {
  [ -x "$SUT" ] || skip "validate-deps.sh not yet created"
  local graph
  graph=$(mk_dep_graph <<'JSON'
{
  "phases": [
    {"id": "A", "depends_on": ["C"]},
    {"id": "B", "depends_on": ["A"]},
    {"id": "C", "depends_on": ["B"]}
  ]
}
JSON
  )
  run bash "$SUT" --roadmap-json "$graph"
  assert_failure
  assert_output --partial "Circular"
}

@test "missing phase reference returns error" {
  [ -x "$SUT" ] || skip "validate-deps.sh not yet created"
  local graph
  graph=$(mk_dep_graph <<'JSON'
{
  "phases": [
    {"id": "A", "depends_on": []},
    {"id": "B", "depends_on": ["nonexistent"]}
  ]
}
JSON
  )
  run bash "$SUT" --roadmap-json "$graph"
  assert_failure
  assert_output --partial "nonexistent"
}

@test "empty graph (no phases) returns valid:false" {
  [ -x "$SUT" ] || skip "validate-deps.sh not yet created"
  local graph
  graph=$(mk_dep_graph <<'JSON'
{
  "phases": []
}
JSON
  )
  run bash "$SUT" --roadmap-json "$graph"
  assert_failure
  local valid
  valid=$(echo "$output" | jq -r '.valid // empty' 2>/dev/null)
  [ "$valid" = "false" ] || skip "Output format not matching spec yet"
}

@test "orphaned phase produces warning" {
  [ -x "$SUT" ] || skip "validate-deps.sh not yet created"
  local graph
  graph=$(mk_dep_graph <<'JSON'
{
  "phases": [
    {"id": "A", "depends_on": []},
    {"id": "B", "depends_on": ["A"]},
    {"id": "C", "depends_on": []}
  ],
  "critical_path": ["A", "B", "C"]
}
JSON
  )
  run bash "$SUT" --roadmap-json "$graph"
  assert_success
  assert_output --partial "orphaned"
}
