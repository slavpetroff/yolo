#!/usr/bin/env bats
# command-frontmatter.bats — Validate YAML frontmatter for all 20 command files

setup() {
  load '../test_helper/common'
}

# Helper: extract frontmatter block (between first and second ---)
extract_frontmatter() {
  local file="$1"
  sed -n '2,/^---$/p' "$file" | sed '$d'
}

# Helper: validate command frontmatter has required fields
validate_command_frontmatter() {
  local cmd_file="$COMMANDS_DIR/$1"
  local cmd_name="$1"

  # File exists
  [ -f "$cmd_file" ] || { echo "File not found: $cmd_file"; return 1; }

  # First line is YAML frontmatter delimiter
  local first_line
  first_line=$(head -1 "$cmd_file")
  [ "$first_line" = "---" ] || { echo "$cmd_name: first line is not '---'"; return 1; }

  # Extract frontmatter
  local fm
  fm=$(extract_frontmatter "$cmd_file")

  # Has name: field
  echo "$fm" | grep -qE '^name:' || { echo "$cmd_name: missing 'name:' field"; return 1; }

  # Has description: field (single line, not block scalar like > or |)
  echo "$fm" | grep -qE '^description:' || { echo "$cmd_name: missing 'description:' field"; return 1; }
  # Verify description is single-line (not a block scalar indicator)
  local desc_line
  desc_line=$(echo "$fm" | grep '^description:')
  [[ "$desc_line" != "description: >" ]] && [[ "$desc_line" != "description: |" ]] || {
    echo "$cmd_name: description uses block scalar (must be single-line)"
    return 1
  }
}

@test "config.md has valid frontmatter" {
  run validate_command_frontmatter "config.md"
  assert_success
}

@test "debug.md has valid frontmatter" {
  run validate_command_frontmatter "debug.md"
  assert_success
}

@test "fix.md has valid frontmatter" {
  run validate_command_frontmatter "fix.md"
  assert_success
}

@test "help.md has valid frontmatter" {
  run validate_command_frontmatter "help.md"
  assert_success
}

@test "init.md has valid frontmatter" {
  run validate_command_frontmatter "init.md"
  assert_success
}

@test "map.md has valid frontmatter" {
  run validate_command_frontmatter "map.md"
  assert_success
}

@test "pause.md has valid frontmatter" {
  run validate_command_frontmatter "pause.md"
  assert_success
}

@test "profile.md has valid frontmatter" {
  run validate_command_frontmatter "profile.md"
  assert_success
}

@test "qa.md has valid frontmatter" {
  run validate_command_frontmatter "qa.md"
  assert_success
}

@test "release.md has valid frontmatter" {
  run validate_command_frontmatter "release.md"
  assert_success
}

@test "research.md has valid frontmatter" {
  run validate_command_frontmatter "research.md"
  assert_success
}

@test "resume.md has valid frontmatter" {
  run validate_command_frontmatter "resume.md"
  assert_success
}

@test "skills.md has valid frontmatter" {
  run validate_command_frontmatter "skills.md"
  assert_success
}

@test "status.md has valid frontmatter" {
  run validate_command_frontmatter "status.md"
  assert_success
}

@test "teach.md has valid frontmatter" {
  run validate_command_frontmatter "teach.md"
  assert_success
}

@test "todo.md has valid frontmatter" {
  run validate_command_frontmatter "todo.md"
  assert_success
}

@test "uninstall.md has valid frontmatter" {
  run validate_command_frontmatter "uninstall.md"
  assert_success
}

@test "update.md has valid frontmatter" {
  run validate_command_frontmatter "update.md"
  assert_success
}

@test "go.md has valid frontmatter" {
  run validate_command_frontmatter "go.md"
  assert_success
}

@test "whats-new.md has valid frontmatter" {
  run validate_command_frontmatter "whats-new.md"
  assert_success
}
