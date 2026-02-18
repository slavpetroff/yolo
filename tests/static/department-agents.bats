#!/usr/bin/env bats
# department-agents.bats — Validate all 30 agent files have correct YAML frontmatter
# Checks: file exists, has name/description/tools, single-line description, escalation table

setup() {
  load '../test_helper/common'
}

# Helper: validate agent frontmatter has required fields
assert_agent_frontmatter() {
  local agent_file="$AGENTS_DIR/$1"
  [ -f "$agent_file" ] || { echo "Missing: $agent_file" >&2; return 1; }
  # Has name field
  run grep '^name:' "$agent_file"
  assert_success
  # Has description field (single line)
  run grep '^description:' "$agent_file"
  assert_success
  # Has tools field
  run grep '^tools:' "$agent_file"
  assert_success
}

# Helper: validate agent has escalation table
assert_has_escalation() {
  local agent_file="$AGENTS_DIR/$1"
  run grep -c "Escalation Table" "$agent_file"
  assert_success
  [ "$output" -ge 1 ]
}

# --- Backend agents (existing) ---

@test "yolo-architect.md has valid frontmatter" {
  assert_agent_frontmatter "yolo-architect.md"
}

@test "yolo-lead.md has valid frontmatter" {
  assert_agent_frontmatter "yolo-lead.md"
}

@test "yolo-senior.md has valid frontmatter" {
  assert_agent_frontmatter "yolo-senior.md"
}

@test "yolo-dev.md has valid frontmatter" {
  assert_agent_frontmatter "yolo-dev.md"
}

@test "yolo-tester.md has valid frontmatter" {
  assert_agent_frontmatter "yolo-tester.md"
}

@test "yolo-qa.md has valid frontmatter" {
  assert_agent_frontmatter "yolo-qa.md"
}

@test "yolo-qa-code.md has valid frontmatter" {
  assert_agent_frontmatter "yolo-qa-code.md"
}

# --- Shared agents ---

@test "yolo-owner.md has valid frontmatter" {
  assert_agent_frontmatter "yolo-owner.md"
}

@test "yolo-owner.md is read-only (disallowedTools)" {
  run grep 'disallowedTools:.*Edit.*Write.*Bash' "$AGENTS_DIR/yolo-owner.md"
  assert_success
}

@test "yolo-critic.md has valid frontmatter" {
  assert_agent_frontmatter "yolo-critic.md"
}

@test "yolo-scout.md has valid frontmatter" {
  assert_agent_frontmatter "yolo-scout.md"
}

@test "yolo-debugger.md has valid frontmatter" {
  assert_agent_frontmatter "yolo-debugger.md"
}

@test "yolo-security.md has valid frontmatter" {
  assert_agent_frontmatter "yolo-security.md"
}

# --- Frontend agents ---

@test "yolo-fe-architect.md has valid frontmatter" {
  assert_agent_frontmatter "yolo-fe-architect.md"
}

@test "yolo-fe-lead.md has valid frontmatter" {
  assert_agent_frontmatter "yolo-fe-lead.md"
}

@test "yolo-fe-senior.md has valid frontmatter" {
  assert_agent_frontmatter "yolo-fe-senior.md"
}

@test "yolo-fe-dev.md has valid frontmatter" {
  assert_agent_frontmatter "yolo-fe-dev.md"
}

@test "yolo-fe-tester.md has valid frontmatter" {
  assert_agent_frontmatter "yolo-fe-tester.md"
}

@test "yolo-fe-qa.md has valid frontmatter" {
  assert_agent_frontmatter "yolo-fe-qa.md"
}

@test "yolo-fe-qa-code.md has valid frontmatter" {
  assert_agent_frontmatter "yolo-fe-qa-code.md"
}

# --- UI/UX agents ---

@test "yolo-ux-architect.md has valid frontmatter" {
  assert_agent_frontmatter "yolo-ux-architect.md"
}

@test "yolo-ux-lead.md has valid frontmatter" {
  assert_agent_frontmatter "yolo-ux-lead.md"
}

@test "yolo-ux-senior.md has valid frontmatter" {
  assert_agent_frontmatter "yolo-ux-senior.md"
}

@test "yolo-ux-dev.md has valid frontmatter" {
  assert_agent_frontmatter "yolo-ux-dev.md"
}

@test "yolo-ux-tester.md has valid frontmatter" {
  assert_agent_frontmatter "yolo-ux-tester.md"
}

@test "yolo-ux-qa.md has valid frontmatter" {
  assert_agent_frontmatter "yolo-ux-qa.md"
}

@test "yolo-ux-qa-code.md has valid frontmatter" {
  assert_agent_frontmatter "yolo-ux-qa-code.md"
}

# --- Escalation table presence ---

@test "all 26 agents have escalation tables" {
  local agents=(
    yolo-architect yolo-lead yolo-senior yolo-dev yolo-tester yolo-qa yolo-qa-code
    yolo-owner yolo-critic yolo-scout yolo-debugger yolo-security
    yolo-fe-architect yolo-fe-lead yolo-fe-senior yolo-fe-dev yolo-fe-tester yolo-fe-qa yolo-fe-qa-code
    yolo-ux-architect yolo-ux-lead yolo-ux-senior yolo-ux-dev yolo-ux-tester yolo-ux-qa yolo-ux-qa-code
  )
  for agent in "${agents[@]}"; do
    assert_has_escalation "${agent}.md"
  done
}

# --- Agent count ---

@test "exactly 30 agent files exist" {
  local count
  count=$(ls -1 "$AGENTS_DIR"/yolo-*.md 2>/dev/null | wc -l | tr -d ' ')
  [ "$count" -eq 30 ]
}

# --- Frontend agents reference frontend department protocol ---

@test "frontend agents reference frontend department protocol" {
  for agent in fe-architect fe-lead fe-senior fe-dev fe-tester fe-qa fe-qa-code; do
    run grep "departments/frontend.toon" "$AGENTS_DIR/yolo-${agent}.md"
    assert_success
  done
}

# --- UI/UX agents reference uiux department protocol ---

@test "uiux agents reference uiux department protocol" {
  for agent in ux-architect ux-lead ux-senior ux-dev ux-tester ux-qa ux-qa-code; do
    run grep "departments/uiux.toon" "$AGENTS_DIR/yolo-${agent}.md"
    assert_success
  done
}
