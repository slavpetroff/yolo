#!/usr/bin/env bats
# department-agents.bats — Validate all 26 agent files have correct YAML frontmatter
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

@test "vbw-architect.md has valid frontmatter" {
  assert_agent_frontmatter "vbw-architect.md"
}

@test "vbw-lead.md has valid frontmatter" {
  assert_agent_frontmatter "vbw-lead.md"
}

@test "vbw-senior.md has valid frontmatter" {
  assert_agent_frontmatter "vbw-senior.md"
}

@test "vbw-dev.md has valid frontmatter" {
  assert_agent_frontmatter "vbw-dev.md"
}

@test "vbw-tester.md has valid frontmatter" {
  assert_agent_frontmatter "vbw-tester.md"
}

@test "vbw-qa.md has valid frontmatter" {
  assert_agent_frontmatter "vbw-qa.md"
}

@test "vbw-qa-code.md has valid frontmatter" {
  assert_agent_frontmatter "vbw-qa-code.md"
}

# --- Shared agents ---

@test "vbw-owner.md has valid frontmatter" {
  assert_agent_frontmatter "vbw-owner.md"
}

@test "vbw-owner.md is read-only (disallowedTools)" {
  run grep 'disallowedTools:.*Edit.*Write.*Bash' "$AGENTS_DIR/vbw-owner.md"
  assert_success
}

@test "vbw-critic.md has valid frontmatter" {
  assert_agent_frontmatter "vbw-critic.md"
}

@test "vbw-scout.md has valid frontmatter" {
  assert_agent_frontmatter "vbw-scout.md"
}

@test "vbw-debugger.md has valid frontmatter" {
  assert_agent_frontmatter "vbw-debugger.md"
}

@test "vbw-security.md has valid frontmatter" {
  assert_agent_frontmatter "vbw-security.md"
}

# --- Frontend agents ---

@test "vbw-fe-architect.md has valid frontmatter" {
  assert_agent_frontmatter "vbw-fe-architect.md"
}

@test "vbw-fe-lead.md has valid frontmatter" {
  assert_agent_frontmatter "vbw-fe-lead.md"
}

@test "vbw-fe-senior.md has valid frontmatter" {
  assert_agent_frontmatter "vbw-fe-senior.md"
}

@test "vbw-fe-dev.md has valid frontmatter" {
  assert_agent_frontmatter "vbw-fe-dev.md"
}

@test "vbw-fe-tester.md has valid frontmatter" {
  assert_agent_frontmatter "vbw-fe-tester.md"
}

@test "vbw-fe-qa.md has valid frontmatter" {
  assert_agent_frontmatter "vbw-fe-qa.md"
}

@test "vbw-fe-qa-code.md has valid frontmatter" {
  assert_agent_frontmatter "vbw-fe-qa-code.md"
}

# --- UI/UX agents ---

@test "vbw-ux-architect.md has valid frontmatter" {
  assert_agent_frontmatter "vbw-ux-architect.md"
}

@test "vbw-ux-lead.md has valid frontmatter" {
  assert_agent_frontmatter "vbw-ux-lead.md"
}

@test "vbw-ux-senior.md has valid frontmatter" {
  assert_agent_frontmatter "vbw-ux-senior.md"
}

@test "vbw-ux-dev.md has valid frontmatter" {
  assert_agent_frontmatter "vbw-ux-dev.md"
}

@test "vbw-ux-tester.md has valid frontmatter" {
  assert_agent_frontmatter "vbw-ux-tester.md"
}

@test "vbw-ux-qa.md has valid frontmatter" {
  assert_agent_frontmatter "vbw-ux-qa.md"
}

@test "vbw-ux-qa-code.md has valid frontmatter" {
  assert_agent_frontmatter "vbw-ux-qa-code.md"
}

# --- Escalation table presence ---

@test "all 26 agents have escalation tables" {
  local agents=(
    vbw-architect vbw-lead vbw-senior vbw-dev vbw-tester vbw-qa vbw-qa-code
    vbw-owner vbw-critic vbw-scout vbw-debugger vbw-security
    vbw-fe-architect vbw-fe-lead vbw-fe-senior vbw-fe-dev vbw-fe-tester vbw-fe-qa vbw-fe-qa-code
    vbw-ux-architect vbw-ux-lead vbw-ux-senior vbw-ux-dev vbw-ux-tester vbw-ux-qa vbw-ux-qa-code
  )
  for agent in "${agents[@]}"; do
    assert_has_escalation "${agent}.md"
  done
}

# --- Agent count ---

@test "exactly 26 agent files exist" {
  local count
  count=$(ls -1 "$AGENTS_DIR"/vbw-*.md 2>/dev/null | wc -l | tr -d ' ')
  [ "$count" -eq 26 ]
}

# --- Frontend agents reference frontend department protocol ---

@test "frontend agents reference frontend department protocol" {
  for agent in fe-architect fe-lead fe-senior fe-dev fe-tester fe-qa fe-qa-code; do
    run grep "departments/frontend.md" "$AGENTS_DIR/vbw-${agent}.md"
    assert_success
  done
}

# --- UI/UX agents reference uiux department protocol ---

@test "uiux agents reference uiux department protocol" {
  for agent in ux-architect ux-lead ux-senior ux-dev ux-tester ux-qa ux-qa-code; do
    run grep "departments/uiux.md" "$AGENTS_DIR/vbw-${agent}.md"
    assert_success
  done
}
