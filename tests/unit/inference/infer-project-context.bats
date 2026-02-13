#!/usr/bin/env bats
# infer-project-context.bats — Unit tests for scripts/infer-project-context.sh
# Extracts project context from codebase mapping files with source attribution.

setup() {
  load '../../test_helper/common'
  load '../../test_helper/fixtures'
  load '../../test_helper/mock_stdin'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/infer-project-context.sh"
}

# --- Argument validation ---

@test "exits 1 when no args provided" {
  run bash "$SUT"
  assert_failure
  assert_output --partial "CODEBASE_DIR is required"
}

@test "exits 1 when CODEBASE_DIR does not exist" {
  run bash "$SUT" "$TEST_WORKDIR/nonexistent"
  assert_failure
  assert_output --partial "does not exist"
}

@test "shows help with --help flag" {
  run bash "$SUT" --help
  assert_success
  assert_output --partial "Usage:"
  assert_output --partial "CODEBASE_DIR"
}

# --- Minimal output with empty codebase dir ---

@test "produces valid JSON with null fields for empty codebase dir" {
  mkdir -p "$TEST_WORKDIR/codebase"
  run bash "$SUT" "$TEST_WORKDIR/codebase" "$TEST_WORKDIR"
  assert_success
  local result="$output"
  # Should be valid JSON
  run bash -c "echo '$result' | jq empty"
  assert_success
  # Name should fall back to directory name
  run bash -c "echo '$result' | jq -r '.name.source'"
  assert_output "directory"
  # Other fields should be null
  run bash -c "echo '$result' | jq -r '.tech_stack.value'"
  assert_output "null"
  run bash -c "echo '$result' | jq -r '.architecture.value'"
  assert_output "null"
}

# --- Tech stack extraction from STACK.md ---

@test "extracts tech stack from STACK.md languages and key technologies" {
  mkdir -p "$TEST_WORKDIR/codebase"
  cat > "$TEST_WORKDIR/codebase/STACK.md" <<'EOF'
# Stack

## Languages
| Language | Files | % |
|----------|-------|---|
| Bash | 45 | 60 |
| Markdown | 30 | 40 |

## Key Technologies
- **bats-core**: Testing framework
- **jq**: JSON processor
EOF
  run bash "$SUT" "$TEST_WORKDIR/codebase" "$TEST_WORKDIR"
  assert_success
  local result="$output"
  run bash -c "echo '$result' | jq -r '.tech_stack.source'"
  assert_output "STACK.md"
  run bash -c "echo '$result' | jq -r '.tech_stack.value[]'"
  assert_line --index 0 "Bash"
  assert_line --index 1 "Markdown"
  assert_line --index 2 "bats-core"
  assert_line --index 3 "jq"
}

# --- Architecture extraction from ARCHITECTURE.md ---

@test "extracts architecture overview from ARCHITECTURE.md" {
  mkdir -p "$TEST_WORKDIR/codebase"
  cat > "$TEST_WORKDIR/codebase/ARCHITECTURE.md" <<'EOF'
# Architecture

## Overview
Plugin-based CLI architecture with hook system.
All logic in shell scripts.

## Components
- Hooks
- Scripts
EOF
  run bash "$SUT" "$TEST_WORKDIR/codebase" "$TEST_WORKDIR"
  assert_success
  local result="$output"
  run bash -c "echo '$result' | jq -r '.architecture.source'"
  assert_output "ARCHITECTURE.md"
  run bash -c "echo '$result' | jq -r '.architecture.value'"
  assert_output --partial "Plugin-based CLI architecture"
  assert_output --partial "All logic in shell scripts"
}
