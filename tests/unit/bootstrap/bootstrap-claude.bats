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

# --- Department Architecture section ---

@test "generates Department Architecture section in fresh file" {
  bash "$SUT" "$TEST_WORKDIR/CLAUDE.md" "TestApp" "Core value"
  run cat "$TEST_WORKDIR/CLAUDE.md"
  assert_output --partial "## Department Architecture"
  assert_output --partial "26 agents across 4 departments"
}

@test "Department Architecture not duplicated when regenerating existing file" {
  # Create file with Department Architecture section
  cat > "$TEST_WORKDIR/existing.md" <<'EOF'
# MyProject

**Core value:** Build things

## Department Architecture

26 agents across 4 departments.

## Active Context

**Work:** Some milestone

## YOLO Rules

- Rule one
EOF
  bash "$SUT" "$TEST_WORKDIR/CLAUDE.md" "MyProject" "Build things" "$TEST_WORKDIR/existing.md"
  local count
  count=$(grep -c '## Department Architecture' "$TEST_WORKDIR/CLAUDE.md")
  [ "$count" -eq 1 ]
}

# --- Content duplication prevention ---

@test "content between heading and first ## is not duplicated" {
  cat > "$TEST_WORKDIR/existing.md" <<'EOF'
# MyProject

**Core value:** Build things

This is a description line that appears before any ## section.
Another description line.

## Custom Section

Custom content here.

## Active Context

**Work:** Old work
EOF
  bash "$SUT" "$TEST_WORKDIR/CLAUDE.md" "MyProject" "Build things" "$TEST_WORKDIR/existing.md"
  local desc_count
  desc_count=$(grep -c 'This is a description line' "$TEST_WORKDIR/CLAUDE.md" || true)
  [ "$desc_count" -eq 0 ]
}

# --- In-place regeneration ---

@test "in-place regeneration: same file for OUTPUT_PATH and EXISTING_PATH" {
  bash "$SUT" "$TEST_WORKDIR/CLAUDE.md" "First" "First value"
  # Add custom section to the generated file
  printf '\n## My Custom\n\nKeep this.\n' >> "$TEST_WORKDIR/CLAUDE.md"
  # Regenerate in-place
  bash "$SUT" "$TEST_WORKDIR/CLAUDE.md" "Second" "Second value" "$TEST_WORKDIR/CLAUDE.md"
  run cat "$TEST_WORKDIR/CLAUDE.md"
  assert_output --partial "# Second"
  assert_output --partial "**Core value:** Second value"
  assert_output --partial "## My Custom"
  assert_output --partial "Keep this."
  # Verify no corruption -- YOLO sections present exactly once
  local ac_count
  ac_count=$(grep -c '## Active Context' "$TEST_WORKDIR/CLAUDE.md")
  [ "$ac_count" -eq 1 ]
}

# --- Code block awareness ---

@test "code block with ## header is not treated as section boundary" {
  cat > "$TEST_WORKDIR/existing.md" <<'TESTEOF'
# Project

**Core value:** Value

## My Docs

Here is an example:

```markdown
## This Is Not A Real Section

Content inside code block.
```

More docs after the code block.

## Active Context

**Work:** Old
TESTEOF
  bash "$SUT" "$TEST_WORKDIR/CLAUDE.md" "Project" "Value" "$TEST_WORKDIR/existing.md"
  run cat "$TEST_WORKDIR/CLAUDE.md"
  assert_output --partial "## My Docs"
  assert_output --partial "## This Is Not A Real Section"
  assert_output --partial "Content inside code block."
  assert_output --partial "More docs after the code block."
}

# --- Collision detection ---

@test "no false-positive collision warning on normal operation" {
  cat > "$TEST_WORKDIR/existing.md" <<'EOF'
# Project

**Core value:** Value

## Active Context

User wrote their own Active Context section.

## My Section

Safe content.
EOF
  run bash -c "bash '$SUT' '$TEST_WORKDIR/CLAUDE.md' 'Project' 'Value' '$TEST_WORKDIR/existing.md' 2>&1"
  # Active Context is a managed section -- stripped before collision detection.
  # No false-positive warning should fire.
  refute_output --partial "WARNING:"
}

# --- Minimal flag ---

@test "--minimal flag generates only bootstrap-appropriate sections" {
  bash "$SUT" "$TEST_WORKDIR/CLAUDE.md" "InitProject" "Init value" --minimal
  run cat "$TEST_WORKDIR/CLAUDE.md"
  # Present in minimal:
  assert_output --partial "## YOLO Rules"
  assert_output --partial "## Project Conventions"
  assert_output --partial "## Commands"
  assert_output --partial "## Plugin Isolation"
  # NOT present in minimal:
  refute_output --partial "## Active Context"
  refute_output --partial "## Key Decisions"
  refute_output --partial "## Department Architecture"
  refute_output --partial "## Installed Skills"
}

# --- Verify flag ---

@test "--verify flag validates section registry and exits 0" {
  run bash "$SUT" /dev/null "Test" "Value" --verify
  assert_success
}

# --- Section count ---

@test "fresh file has exactly 8 YOLO sections" {
  bash "$SUT" "$TEST_WORKDIR/CLAUDE.md" "Test" "Value"
  local section_count
  section_count=$(grep -c '^## ' "$TEST_WORKDIR/CLAUDE.md")
  [ "$section_count" -eq 8 ]
}
