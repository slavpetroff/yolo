#!/usr/bin/env bats
# task-coordination-patterns.bats -- Unit tests for Phase 3 documentation in reference files

setup() {
  load '../test_helper/common'
  PATTERNS_FILE="$PROJECT_ROOT/references/teammate-api-patterns.md"
  SCHEMAS_FILE="$PROJECT_ROOT/references/handoff-schemas.md"
  FORMATS_FILE="$PROJECT_ROOT/references/artifact-formats.md"
}

# --- teammate-api-patterns.md: Task Coordination section ---

@test "teammate-api-patterns.md contains ## Task Coordination section" {
  run grep '## Task Coordination' "$PATTERNS_FILE"
  assert_success
}

@test "Task Coordination contains TaskCreate subsection" {
  run grep -E 'TaskCreate' "$PATTERNS_FILE"
  assert_success
}

@test "Task Coordination contains TaskList subsection" {
  run grep 'TaskList' "$PATTERNS_FILE"
  assert_success
}

@test "Task Coordination contains TaskUpdate subsection" {
  run grep 'TaskUpdate' "$PATTERNS_FILE"
  assert_success
}

@test "Task Coordination documents file-overlap algorithm" {
  run grep -E 'claimed_files|file.overlap' "$PATTERNS_FILE"
  assert_success
}

# --- teammate-api-patterns.md: Dynamic Dev Scaling section ---

@test "teammate-api-patterns.md contains ## Dynamic Dev Scaling section" {
  run grep '## Dynamic Dev Scaling' "$PATTERNS_FILE"
  assert_success
}

@test "Dynamic Dev Scaling contains min formula" {
  run grep -E 'min.*available.*5|min\(available' "$PATTERNS_FILE"
  assert_success
}

@test "Dynamic Dev Scaling references compute-dev-count.sh" {
  run grep 'compute-dev-count.sh' "$PATTERNS_FILE"
  assert_success
}

# --- teammate-api-patterns.md: Task-Level Blocking section ---

@test "teammate-api-patterns.md contains ## Task-Level Blocking section" {
  run grep '## Task-Level Blocking' "$PATTERNS_FILE"
  assert_success
}

@test "Task-Level Blocking documents td field" {
  run grep -E 'td|task_depends' "$PATTERNS_FILE"
  assert_success
}

# --- handoff-schemas.md: task coordination schemas ---

@test "handoff-schemas.md contains task_claim schema" {
  run grep 'task_claim' "$SCHEMAS_FILE"
  assert_success
}

@test "handoff-schemas.md contains task_complete schema" {
  run grep 'task_complete' "$SCHEMAS_FILE"
  assert_success
}

@test "handoff-schemas.md contains summary_aggregation schema" {
  run grep 'summary_aggregation' "$SCHEMAS_FILE"
  assert_success
}

# --- artifact-formats.md: td field in Plan Task table ---

@test "artifact-formats.md contains td field in Plan Task table" {
  run grep -E 'td.*task_depends|`td`' "$FORMATS_FILE"
  assert_success
}
