#!/usr/bin/env bats
# agent-task-coordination.bats -- Static validation: Phase 3 task coordination sections in agent files

setup() {
  load '../test_helper/common'
  # No fixtures needed -- reads real agent files via $AGENTS_DIR from common.bash
}

# --- Dev agent: Task Self-Claiming ---

@test "yolo-dev.md contains ## Task Self-Claiming section" {
  run grep -c '## Task Self-Claiming' "$AGENTS_DIR/yolo-dev.md"
  assert_success
  [[ "$output" -ge 1 ]] || fail "Zero matches for ## Task Self-Claiming in yolo-dev.md"
}

@test "yolo-dev.md Task Self-Claiming has team_mode=teammate guard" {
  run grep -A5 'Task Self-Claiming' "$AGENTS_DIR/yolo-dev.md"
  assert_success
  assert_output --partial 'team_mode=teammate'
}

@test "yolo-dev.md references git-commit-serialized.sh" {
  run grep 'git-commit-serialized.sh' "$AGENTS_DIR/yolo-dev.md"
  assert_success
}

@test "yolo-dev.md Stage 3 Override skips summary.jsonl in teammate mode" {
  run grep -E 'SKIP.*Stage 3|Stage 3.*Override|skip.*summary.jsonl' "$AGENTS_DIR/yolo-dev.md"
  assert_success
}

# --- Lead agent: Summary Aggregation ---

@test "yolo-lead.md contains ## Summary Aggregation section" {
  run grep -c '## Summary Aggregation' "$AGENTS_DIR/yolo-lead.md"
  assert_success
  [[ "$output" -ge 1 ]] || fail "Zero matches for ## Summary Aggregation in yolo-lead.md"
}

@test "yolo-lead.md Summary Aggregation has team_mode=teammate guard" {
  run grep -A5 'Summary Aggregation' "$AGENTS_DIR/yolo-lead.md"
  assert_success
  assert_output --partial 'team_mode=teammate'
}

@test "yolo-lead.md documents claimed_files for file-overlap detection" {
  run grep 'claimed_files' "$AGENTS_DIR/yolo-lead.md"
  assert_success
}

# --- Senior agent: Parallel Review ---

@test "yolo-senior.md contains ## Parallel Review section" {
  run grep -c '## Parallel Review' "$AGENTS_DIR/yolo-senior.md"
  assert_success
  [[ "$output" -ge 1 ]] || fail "Zero matches for ## Parallel Review in yolo-senior.md"
}

@test "yolo-senior.md Parallel Review covers Step 4 and Step 7" {
  run grep -E 'Step 4|Design Review' "$AGENTS_DIR/yolo-senior.md"
  assert_success
  run grep -E 'Step 7|Code Review' "$AGENTS_DIR/yolo-senior.md"
  assert_success
}

# --- FE Senior: Parallel Review ---

@test "yolo-fe-senior.md contains ## Parallel Review section" {
  run grep -c '## Parallel Review' "$AGENTS_DIR/yolo-fe-senior.md"
  assert_success
  [[ "$output" -ge 1 ]] || fail "Zero matches for ## Parallel Review in yolo-fe-senior.md"
}

# --- UX Senior: Parallel Review ---

@test "yolo-ux-senior.md contains ## Parallel Review section" {
  run grep -c '## Parallel Review' "$AGENTS_DIR/yolo-ux-senior.md"
  assert_success
  [[ "$output" -ge 1 ]] || fail "Zero matches for ## Parallel Review in yolo-ux-senior.md"
}

# --- FE Dev: Task Self-Claiming ---

@test "yolo-fe-dev.md contains ## Task Self-Claiming section" {
  run grep -c '## Task Self-Claiming' "$AGENTS_DIR/yolo-fe-dev.md"
  assert_success
  [[ "$output" -ge 1 ]] || fail "Zero matches for ## Task Self-Claiming in yolo-fe-dev.md"
}

@test "yolo-fe-dev.md Task Self-Claiming references FE Senior" {
  run grep -A10 'Task Self-Claiming' "$AGENTS_DIR/yolo-fe-dev.md"
  assert_success
  assert_output --partial 'FE Senior'
}

# --- UX Dev: Task Self-Claiming ---

@test "yolo-ux-dev.md contains ## Task Self-Claiming section" {
  run grep -c '## Task Self-Claiming' "$AGENTS_DIR/yolo-ux-dev.md"
  assert_success
  [[ "$output" -ge 1 ]] || fail "Zero matches for ## Task Self-Claiming in yolo-ux-dev.md"
}

@test "yolo-ux-dev.md Task Self-Claiming references UX Senior" {
  run grep -A10 'Task Self-Claiming' "$AGENTS_DIR/yolo-ux-dev.md"
  assert_success
  assert_output --partial 'UX Senior'
}

# --- FE Lead: Summary Aggregation ---

@test "yolo-fe-lead.md contains ## Summary Aggregation section" {
  run grep -c '## Summary Aggregation' "$AGENTS_DIR/yolo-fe-lead.md"
  assert_success
  [[ "$output" -ge 1 ]] || fail "Zero matches for ## Summary Aggregation in yolo-fe-lead.md"
}

# --- UX Lead: Summary Aggregation ---

@test "yolo-ux-lead.md contains ## Summary Aggregation section" {
  run grep -c '## Summary Aggregation' "$AGENTS_DIR/yolo-ux-lead.md"
  assert_success
  [[ "$output" -ge 1 ]] || fail "Zero matches for ## Summary Aggregation in yolo-ux-lead.md"
}

# --- FE Lead and UX Lead: claimed_files ---

@test "yolo-fe-lead.md Summary Aggregation documents claimed_files" {
  run grep 'claimed_files' "$AGENTS_DIR/yolo-fe-lead.md"
  assert_success
}

@test "yolo-ux-lead.md Summary Aggregation documents claimed_files" {
  run grep 'claimed_files' "$AGENTS_DIR/yolo-ux-lead.md"
  assert_success
}

# --- DB Script References (Phase 10 SQLite) ---

@test "dev agents reference get-task.sh" {
  for agent in yolo-dev.md yolo-fe-dev.md yolo-ux-dev.md; do
    run grep 'get-task.sh' "$AGENTS_DIR/$agent"
    [[ $status -eq 0 ]] || fail "Missing get-task.sh reference in $agent"
  done
}

@test "dev agents reference complete-task.sh" {
  for agent in yolo-dev.md yolo-fe-dev.md yolo-ux-dev.md; do
    run grep 'complete-task.sh' "$AGENTS_DIR/$agent"
    [[ $status -eq 0 ]] || fail "Missing complete-task.sh reference in $agent"
  done
}

@test "lead agents reference insert-task.sh" {
  for agent in yolo-lead.md yolo-fe-lead.md yolo-ux-lead.md; do
    run grep 'insert-task.sh' "$AGENTS_DIR/$agent"
    [[ $status -eq 0 ]] || fail "Missing insert-task.sh reference in $agent"
  done
}

@test "lead agents reference check-phase-status.sh" {
  for agent in yolo-lead.md yolo-fe-lead.md yolo-ux-lead.md; do
    run grep 'check-phase-status.sh' "$AGENTS_DIR/$agent"
    [[ $status -eq 0 ]] || fail "Missing check-phase-status.sh reference in $agent"
  done
}

@test "qa agents reference get-summaries.sh" {
  for agent in yolo-qa.md yolo-fe-qa.md yolo-ux-qa.md; do
    run grep 'get-summaries.sh' "$AGENTS_DIR/$agent"
    [[ $status -eq 0 ]] || fail "Missing get-summaries.sh reference in $agent"
  done
}

@test "tester agents reference get-task.sh with test_spec" {
  for agent in yolo-tester.md yolo-fe-tester.md yolo-ux-tester.md; do
    run grep 'get-task.sh' "$AGENTS_DIR/$agent"
    [[ $status -eq 0 ]] || fail "Missing get-task.sh reference in $agent"
    run grep 'test_spec' "$AGENTS_DIR/$agent"
    [[ $status -eq 0 ]] || fail "Missing test_spec reference in $agent"
  done
}

@test "architect agents reference get-phase.sh" {
  for agent in yolo-architect.md yolo-fe-architect.md yolo-ux-architect.md; do
    run grep 'get-phase.sh' "$AGENTS_DIR/$agent"
    [[ $status -eq 0 ]] || fail "Missing get-phase.sh reference in $agent"
  done
}

@test "scout references search-research.sh" {
  run grep 'search-research.sh' "$AGENTS_DIR/yolo-scout.md"
  assert_success
}

@test "critic references search-decisions.sh" {
  run grep 'search-decisions.sh' "$AGENTS_DIR/yolo-critic.md"
  assert_success
}

@test "all DB-aware agents have backward-compatible fallback" {
  local DB_AGENTS=(
    yolo-dev.md yolo-fe-dev.md yolo-ux-dev.md
    yolo-lead.md yolo-fe-lead.md yolo-ux-lead.md
    yolo-senior.md yolo-fe-senior.md yolo-ux-senior.md
    yolo-qa.md yolo-fe-qa.md yolo-ux-qa.md
    yolo-tester.md yolo-fe-tester.md yolo-ux-tester.md
    yolo-architect.md yolo-fe-architect.md yolo-ux-architect.md
  )
  for agent in "${DB_AGENTS[@]}"; do
    run grep -c '\[sqlite\]' "$AGENTS_DIR/$agent"
    [[ $status -eq 0 ]] || fail "Missing [sqlite] block in $agent"
    [[ "$output" -ge 1 ]] || fail "Zero [sqlite] blocks in $agent"
  done
}

# --- Cross-cutting: all task coordination agents reference teammate-api-patterns.md ---

@test "all task coordination sections reference teammate-api-patterns.md" {
  local COORD_AGENTS=(
    yolo-dev.md yolo-lead.md yolo-senior.md
    yolo-fe-dev.md yolo-fe-lead.md yolo-fe-senior.md
    yolo-ux-dev.md yolo-ux-lead.md yolo-ux-senior.md
  )
  for agent in "${COORD_AGENTS[@]}"; do
    run grep -c 'teammate-api-patterns.md' "$AGENTS_DIR/$agent"
    [[ $status -eq 0 ]] || fail "Missing teammate-api-patterns.md reference in $agent"
    [[ "$output" -ge 1 ]] || fail "Zero matches for teammate-api-patterns.md in $agent"
  done
}
