#!/usr/bin/env bats
# bootstrap-flow.bats — Integration tests: init -> bootstrap -> state flow
# Tests the full chain of bootstrap scripts producing correct artifacts.

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir
  mkdir -p "$TEST_WORKDIR/.yolo-planning/phases"
}

# --- bootstrap-project creates PROJECT.md ---

@test "bootstrap-project creates PROJECT.md with correct content" {
  local output_path="$TEST_WORKDIR/.yolo-planning/PROJECT.md"

  run bash "$BOOTSTRAP_DIR/bootstrap-project.sh" \
    "$output_path" "My Test Project" "A CLI tool for testing"
  assert_success

  assert_file_exists "$output_path"

  run grep "^# My Test Project" "$output_path"
  assert_success

  run grep "A CLI tool for testing" "$output_path"
  assert_success

  run grep "^## Requirements" "$output_path"
  assert_success

  run grep "^## Key Decisions" "$output_path"
  assert_success
}

# --- bootstrap-requirements generates REQUIREMENTS.md from discovery JSON ---

@test "bootstrap-requirements generates REQUIREMENTS.md from discovery JSON" {
  local discovery="$TEST_WORKDIR/discovery.json"
  cat > "$discovery" <<'EOF'
{
  "answered": [{"q": "What is the goal?", "a": "Build a CLI"}],
  "inferred": [
    {"text": "Support multiple output formats", "priority": "Must-have"},
    {"text": "Provide help command", "priority": "Should-have"}
  ]
}
EOF
  local output_path="$TEST_WORKDIR/.yolo-planning/REQUIREMENTS.md"

  run bash "$BOOTSTRAP_DIR/bootstrap-requirements.sh" "$output_path" "$discovery"
  assert_success

  assert_file_exists "$output_path"

  run grep "### REQ-01: Support multiple output formats" "$output_path"
  assert_success

  run grep "### REQ-02: Provide help command" "$output_path"
  assert_success

  run grep '^\*\*Must-have\*\*' "$output_path"
  assert_success

  run grep '^\*\*Should-have\*\*' "$output_path"
  assert_success
}

# --- bootstrap-state creates STATE.md with correct phase count ---

@test "bootstrap-state creates STATE.md with correct phase count" {
  local output_path="$TEST_WORKDIR/.yolo-planning/STATE.md"

  run bash "$BOOTSTRAP_DIR/bootstrap-state.sh" \
    "$output_path" "Test Project" "MVP Release" 3
  assert_success

  assert_file_exists "$output_path"

  run grep "^# YOLO State" "$output_path"
  assert_success

  run grep '^\*\*Milestone:\*\* MVP Release' "$output_path"
  assert_success

  run grep '^\- \*\*Phase 1:\*\* Pending planning' "$output_path"
  assert_success

  run grep '^\- \*\*Phase 2:\*\* Pending' "$output_path"
  assert_success

  run grep '^\- \*\*Phase 3:\*\* Pending' "$output_path"
  assert_success
}

# --- bootstrap-state-json creates valid state.json ---

@test "bootstrap-state-json creates valid state.json" {
  local output_path="$TEST_WORKDIR/.yolo-planning/state.json"

  run bash "$BOOTSTRAP_DIR/bootstrap-state-json.sh" \
    "$output_path" "MVP Release" 3
  assert_success

  assert_file_exists "$output_path"

  # Validate it is valid JSON
  run jq empty "$output_path"
  assert_success

  run jq -r '.ms' "$output_path"
  assert_output "MVP Release"

  run jq -r '.ph' "$output_path"
  assert_output "1"

  run jq -r '.tt' "$output_path"
  assert_output "3"

  run jq -r '.st' "$output_path"
  assert_output "planning"

  run jq -r '.pr' "$output_path"
  assert_output "0"
}

# --- bootstrap-reqs-jsonl converts REQUIREMENTS.md to reqs.jsonl ---

@test "bootstrap-reqs-jsonl converts REQUIREMENTS.md to reqs.jsonl" {
  # First create a REQUIREMENTS.md with known content
  local reqs_md="$TEST_WORKDIR/.yolo-planning/REQUIREMENTS.md"
  cat > "$reqs_md" <<'EOF'
# Requirements

## Requirements

### REQ-01: Support output formats
**Must-have**

### REQ-02: Provide help command
**Should-have**

### REQ-03: Add color support
**Nice-to-have**

## Out of Scope
EOF

  local output_path="$TEST_WORKDIR/.yolo-planning/reqs.jsonl"

  run bash "$BOOTSTRAP_DIR/bootstrap-reqs-jsonl.sh" "$reqs_md" "$output_path"
  assert_success

  assert_file_exists "$output_path"

  # Should have 3 lines (one per requirement)
  local line_count
  line_count=$(wc -l < "$output_path" | tr -d ' ')
  [ "$line_count" -eq 3 ]

  # Validate first line
  run bash -c "head -1 '$output_path' | jq -r '.id'"
  assert_output "REQ-01"

  run bash -c "head -1 '$output_path' | jq -r '.pri'"
  assert_output "must"

  # Validate third line has nice priority
  run bash -c "sed -n '3p' '$output_path' | jq -r '.pri'"
  assert_output "nice"
}

# --- bootstrap-claude generates CLAUDE.md with YOLO sections ---

@test "bootstrap-claude generates CLAUDE.md with YOLO sections" {
  local output_path="$TEST_WORKDIR/CLAUDE.md"

  run bash "$BOOTSTRAP_DIR/bootstrap-claude.sh" \
    "$output_path" "Test Project" "Replace ad-hoc coding with workflows"
  assert_success

  assert_file_exists "$output_path"

  run grep "^# Test Project" "$output_path"
  assert_success

  run grep '^\*\*Core value:\*\* Replace ad-hoc coding with workflows' "$output_path"
  assert_success

  # All YOLO sections should be present
  run grep "^## Active Context" "$output_path"
  assert_success

  run grep "^## YOLO Rules" "$output_path"
  assert_success

  run grep "^## Key Decisions" "$output_path"
  assert_success

  run grep "^## Plugin Isolation" "$output_path"
  assert_success

  run grep "^## Commands" "$output_path"
  assert_success
}

# --- bootstrap-claude preserves non-YOLO content from existing file ---

@test "bootstrap-claude preserves non-YOLO content from existing file" {
  local existing="$TEST_WORKDIR/existing-CLAUDE.md"
  cat > "$existing" <<'EOF'
# Old Project

**Core value:** Old value

## Custom Section

This is my custom documentation that should be preserved.

## Active Context

**Work:** Old milestone
**Last shipped:** Something

## Another Custom Section

More custom content here.

## YOLO Rules

- Old rules that should be replaced
EOF

  local output_path="$TEST_WORKDIR/CLAUDE.md"

  run bash "$BOOTSTRAP_DIR/bootstrap-claude.sh" \
    "$output_path" "New Project" "New core value" "$existing"
  assert_success

  assert_file_exists "$output_path"

  # New header and core value
  run grep "^# New Project" "$output_path"
  assert_success

  run grep '^\*\*Core value:\*\* New core value' "$output_path"
  assert_success

  # Custom sections preserved
  run grep "^## Custom Section" "$output_path"
  assert_success

  run grep "This is my custom documentation that should be preserved." "$output_path"
  assert_success

  run grep "^## Another Custom Section" "$output_path"
  assert_success

  run grep "More custom content here." "$output_path"
  assert_success

  # YOLO sections regenerated (not old content)
  run grep "Old rules that should be replaced" "$output_path"
  assert_failure
}

# --- bootstrap-roadmap creates ROADMAP.md and phase directories ---

@test "bootstrap-roadmap creates ROADMAP.md and phase directories" {
  local phases_json="$FIXTURES_DIR/phases/valid-phases.json"
  local output_path="$TEST_WORKDIR/.yolo-planning/ROADMAP.md"

  run bash "$BOOTSTRAP_DIR/bootstrap-roadmap.sh" \
    "$output_path" "Test Project" "$phases_json"
  assert_success

  assert_file_exists "$output_path"

  # Header and scope
  run grep "^# Test Project Roadmap" "$output_path"
  assert_success

  run grep '^\*\*Scope:\*\* 2 phases' "$output_path"
  assert_success

  # Progress table with both phases
  run grep "| 1 | Pending | 0 | 0 | 0 |" "$output_path"
  assert_success

  run grep "| 2 | Pending | 0 | 0 | 0 |" "$output_path"
  assert_success

  # Phase detail sections
  run grep "^## Phase 1: Setup" "$output_path"
  assert_success

  run grep "^## Phase 2: Build Core" "$output_path"
  assert_success

  # Phase directories created
  assert_dir_exists "$TEST_WORKDIR/.yolo-planning/phases/01-setup"
  assert_dir_exists "$TEST_WORKDIR/.yolo-planning/phases/02-build-core"
}
