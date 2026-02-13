#!/usr/bin/env bats
# bootstrap-claude.bats — Unit tests for scripts/bootstrap/bootstrap-claude.sh
# Generates or updates CLAUDE.md with YOLO-managed sections.

setup() {
  load '../../test_helper/common'
  load '../../test_helper/fixtures'
  load '../../test_helper/mock_stdin'
  mk_test_workdir
  SUT="$BOOTSTRAP_DIR/bootstrap-claude.sh"
}

# --- Argument validation ---

@test "exits 1 with usage when fewer than 3 args" {
  run bash "$SUT"
  assert_failure
  assert_output --partial "Usage:"

  run bash "$SUT" "$TEST_WORKDIR/CLAUDE.md" "Project"
  assert_failure
  assert_output --partial "Usage:"
}

@test "exits 0 with correct 3 args (new file)" {
  run bash "$SUT" "$TEST_WORKDIR/CLAUDE.md" "TestProject" "Build great things"
  assert_success
}

# --- New file generation ---

@test "generates CLAUDE.md with project heading, core value, and all YOLO sections" {
  bash "$SUT" "$TEST_WORKDIR/CLAUDE.md" "MyApp" "Ship fast, ship safe"
  run cat "$TEST_WORKDIR/CLAUDE.md"
  assert_output --partial "# MyApp"
  assert_output --partial "**Core value:** Ship fast, ship safe"
  assert_output --partial "## Active Context"
  assert_output --partial "## YOLO Rules"
  assert_output --partial "## Key Decisions"
  assert_output --partial "## Installed Skills"
  assert_output --partial "## Project Conventions"
  assert_output --partial "## Commands"
  assert_output --partial "## Plugin Isolation"
  assert_output --partial "### Context Isolation"
}

@test "creates parent directories for output path" {
  local nested="$TEST_WORKDIR/deep/nested/CLAUDE.md"
  run bash "$SUT" "$nested" "TestProject" "Core value"
  assert_success
  assert_file_exist "$nested"
}

# --- Existing file preservation ---

@test "preserves non-YOLO sections from existing CLAUDE.md" {
  cat > "$TEST_WORKDIR/existing.md" <<'EOF'
# OldProject

**Core value:** Old value

## Custom Section

This is custom user content that should be preserved.

## Active Context

**Work:** Old active context (should be replaced)

## Another Custom

More custom content.
EOF
  bash "$SUT" "$TEST_WORKDIR/CLAUDE.md" "NewProject" "New value" "$TEST_WORKDIR/existing.md"
  run cat "$TEST_WORKDIR/CLAUDE.md"
  # New header and core value
  assert_output --partial "# NewProject"
  assert_output --partial "**Core value:** New value"
  # Preserved custom sections
  assert_output --partial "## Custom Section"
  assert_output --partial "This is custom user content that should be preserved."
  assert_output --partial "## Another Custom"
  assert_output --partial "More custom content."
  # Regenerated YOLO sections (not old content)
  assert_output --partial "## Active Context"
  refute_output --partial "Old active context (should be replaced)"
}

@test "strips GSD sections from existing CLAUDE.md" {
  cat > "$TEST_WORKDIR/existing.md" <<'EOF'
# Project

## Codebase Intelligence

GSD-specific intelligence data that should be stripped.

## Custom Section

Keep this content.

## GSD Rules

GSD-specific rules that should be stripped.
EOF
  bash "$SUT" "$TEST_WORKDIR/CLAUDE.md" "Clean" "No GSD" "$TEST_WORKDIR/existing.md"
  run cat "$TEST_WORKDIR/CLAUDE.md"
  assert_output --partial "## Custom Section"
  assert_output --partial "Keep this content."
  refute_output --partial "GSD-specific intelligence data"
  refute_output --partial "GSD-specific rules"
}

# --- Idempotency ---

@test "re-running on same output path overwrites YOLO sections cleanly" {
  bash "$SUT" "$TEST_WORKDIR/CLAUDE.md" "First" "First value"
  bash "$SUT" "$TEST_WORKDIR/CLAUDE.md" "Second" "Second value" "$TEST_WORKDIR/CLAUDE.md"
  run cat "$TEST_WORKDIR/CLAUDE.md"
  assert_output --partial "# Second"
  assert_output --partial "**Core value:** Second value"
  # YOLO sections still present
  assert_output --partial "## Active Context"
  assert_output --partial "## Plugin Isolation"
}

@test "new file includes Plugin Isolation with correct isolation rules" {
  bash "$SUT" "$TEST_WORKDIR/CLAUDE.md" "TestProject" "Core value"
  run cat "$TEST_WORKDIR/CLAUDE.md"
  assert_output --partial "GSD agents and commands MUST NOT read, write, glob, grep, or reference any files in"
  assert_output --partial "YOLO agents and commands MUST NOT read, write, glob, grep, or reference any files in"
  assert_output --partial "Context Isolation"
}
