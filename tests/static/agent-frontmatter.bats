#!/usr/bin/env bats
# agent-frontmatter.bats — Validate YAML frontmatter for all 11 agent files

setup() {
  load '../test_helper/common'
}

# Helper: extract frontmatter block (between first and second ---)
extract_frontmatter() {
  local file="$1"
  sed -n '2,/^---$/p' "$file" | sed '$d'
}

# Helper: validate agent frontmatter has required fields
validate_agent_frontmatter() {
  local agent_file="$AGENTS_DIR/$1"
  local agent_name="$1"

  # File exists
  [ -f "$agent_file" ] || { echo "File not found: $agent_file"; return 1; }

  # First line is YAML frontmatter delimiter
  local first_line
  first_line=$(head -1 "$agent_file")
  [ "$first_line" = "---" ] || { echo "$agent_name: first line is not '---'"; return 1; }

  # Extract frontmatter
  local fm
  fm=$(extract_frontmatter "$agent_file")

  # Has name: field
  echo "$fm" | grep -qE '^name:' || { echo "$agent_name: missing 'name:' field"; return 1; }

  # Has description: field (single line, not block scalar like > or |)
  echo "$fm" | grep -qE '^description:' || { echo "$agent_name: missing 'description:' field"; return 1; }
  # Verify description is single-line (not a block scalar indicator)
  local desc_line
  desc_line=$(echo "$fm" | grep '^description:')
  [[ "$desc_line" != "description: >" ]] && [[ "$desc_line" != "description: |" ]] || {
    echo "$agent_name: description uses block scalar (must be single-line)"
    return 1
  }

  # Has tools: field
  echo "$fm" | grep -qE '^tools:' || { echo "$agent_name: missing 'tools:' field"; return 1; }

  # Has model: field
  echo "$fm" | grep -qE '^model:' || { echo "$agent_name: missing 'model:' field"; return 1; }
}

@test "yolo-architect.md has valid frontmatter" {
  run validate_agent_frontmatter "yolo-architect.md"
  assert_success
}

@test "yolo-lead.md has valid frontmatter" {
  run validate_agent_frontmatter "yolo-lead.md"
  assert_success
}

@test "yolo-senior.md has valid frontmatter" {
  run validate_agent_frontmatter "yolo-senior.md"
  assert_success
}

@test "yolo-dev.md has valid frontmatter" {
  run validate_agent_frontmatter "yolo-dev.md"
  assert_success
}

@test "yolo-qa.md has valid frontmatter" {
  run validate_agent_frontmatter "yolo-qa.md"
  assert_success
}

@test "yolo-qa-code.md has valid frontmatter" {
  run validate_agent_frontmatter "yolo-qa-code.md"
  assert_success
}

@test "yolo-scout.md has valid frontmatter" {
  run validate_agent_frontmatter "yolo-scout.md"
  assert_success
}

@test "yolo-debugger.md has valid frontmatter" {
  run validate_agent_frontmatter "yolo-debugger.md"
  assert_success
}

@test "yolo-security.md has valid frontmatter" {
  run validate_agent_frontmatter "yolo-security.md"
  assert_success
}

@test "yolo-critic.md has valid frontmatter" {
  run validate_agent_frontmatter "yolo-critic.md"
  assert_success
}

@test "yolo-tester.md has valid frontmatter" {
  run validate_agent_frontmatter "yolo-tester.md"
  assert_success
}
