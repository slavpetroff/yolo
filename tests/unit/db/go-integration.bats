#!/usr/bin/env bats
# go-integration.bats — Unit tests for SQLite wiring in go.md and execute-protocol.md
# Validates DB script references, backward compatibility, and artifact store integration

setup() {
  load '../../test_helper/common'
  GO_MD="$PROJECT_ROOT/commands/go.md"
  EXEC_PROTO="$PROJECT_ROOT/references/execute-protocol.md"
}

# --- T1: DB initialization in go.md ---

@test "go.md references init-db.sh for artifact store" {
  run grep 'init-db.sh' "$GO_MD"
  assert_success
}

@test "go.md sets db_available flag" {
  run grep 'db_available' "$GO_MD"
  assert_success
}

@test "go.md imports existing plan.jsonl via import-jsonl.sh" {
  run grep 'import-jsonl.sh' "$GO_MD"
  assert_success
}

@test "go.md backward compatible when init-db.sh not found" {
  run grep 'db_available=false' "$GO_MD"
  assert_success
}

# --- T2: Task queue in execute-protocol.md Step 7 ---

@test "execute-protocol.md references next-task.sh" {
  run grep 'next-task.sh' "$EXEC_PROTO"
  assert_success
}

@test "execute-protocol.md references complete-task.sh" {
  run grep 'complete-task.sh' "$EXEC_PROTO"
  assert_success
}

@test "execute-protocol.md references claim-task.sh" {
  run grep 'claim-task.sh' "$EXEC_PROTO"
  assert_success
}

@test "execute-protocol.md references insert-task.sh" {
  run grep 'insert-task.sh' "$EXEC_PROTO"
  assert_success
}

@test "execute-protocol.md preserves file-based path" {
  run grep '\[file\]' "$EXEC_PROTO"
  assert_success
}

# --- T3: Phase status in go.md ---

@test "go.md references check-phase-status.sh" {
  run grep 'check-phase-status.sh' "$GO_MD"
  assert_success
}

# --- T4: Artifact writes in execute-protocol.md ---

@test "execute-protocol.md references append-finding.sh" {
  run grep 'append-finding.sh' "$EXEC_PROTO"
  assert_success
}

@test "execute-protocol.md references import-jsonl.sh for dual-write" {
  run grep 'import-jsonl.sh' "$EXEC_PROTO"
  assert_success
}

# --- T5: Error recovery ---

@test "execute-protocol.md references release-task.sh" {
  run grep 'release-task.sh' "$EXEC_PROTO"
  assert_success
}

@test "execute-protocol.md documents orphan detection" {
  run grep -i 'orphan' "$EXEC_PROTO"
  assert_success
}

# --- Backward compatibility ---

@test "go.md db_available gates all DB operations" {
  # Every DB operation should be gated by db_available check
  local db_refs
  db_refs=$(grep -c 'db_available' "$GO_MD")
  # At minimum: initialization + status check + flag setting
  [[ "$db_refs" -ge 3 ]]
}

@test "execute-protocol.md preserves existing file-based workflow" {
  # The word "summary.jsonl" should still appear (file-based path)
  run grep 'summary.jsonl' "$EXEC_PROTO"
  assert_success
}
