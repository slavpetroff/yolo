#!/usr/bin/env bats
# test-dept-security-agent-naming.bats — Static naming validation for per-department security agents
# Validates: file existence, naming conventions, frontmatter, disallowedTools, model-profiles entries.

setup() {
  load '../test_helper/common'
}

# --- File existence ---

@test "agents/yolo-security.md exists" {
  assert_file_exists "$AGENTS_DIR/yolo-security.md"
}

@test "agents/yolo-fe-security.md exists" {
  assert_file_exists "$AGENTS_DIR/yolo-fe-security.md"
}

@test "agents/yolo-ux-security.md exists" {
  assert_file_exists "$AGENTS_DIR/yolo-ux-security.md"
}

# --- Naming conventions ---

@test "yolo-fe-security.md follows yolo-{dept}-{role}.md naming" {
  local basename
  basename=$(basename "$AGENTS_DIR/yolo-fe-security.md")
  [[ "$basename" =~ ^yolo-fe-[a-z]+\.md$ ]]
}

@test "yolo-ux-security.md follows yolo-{dept}-{role}.md naming" {
  local basename
  basename=$(basename "$AGENTS_DIR/yolo-ux-security.md")
  [[ "$basename" =~ ^yolo-ux-[a-z]+\.md$ ]]
}

# --- YAML frontmatter ---

@test "yolo-security.md has name: yolo-security in frontmatter" {
  run grep '^name: yolo-security' "$AGENTS_DIR/yolo-security.md"
  assert_success
}

@test "yolo-fe-security.md has name: yolo-fe-security in frontmatter" {
  run grep '^name: yolo-fe-security' "$AGENTS_DIR/yolo-fe-security.md"
  assert_success
}

@test "yolo-ux-security.md has name: yolo-ux-security in frontmatter" {
  run grep '^name: yolo-ux-security' "$AGENTS_DIR/yolo-ux-security.md"
  assert_success
}

@test "all 3 security agents have model field in frontmatter" {
  for agent in yolo-security yolo-fe-security yolo-ux-security; do
    run grep '^model:' "$AGENTS_DIR/${agent}.md"
    assert_success
  done
}

# --- disallowedTools ---

@test "all 3 security agents disallow Write and Edit" {
  for agent in yolo-security yolo-fe-security yolo-ux-security; do
    run grep '^disallowedTools:' "$AGENTS_DIR/${agent}.md"
    assert_success
    assert_output --partial "Write"
    assert_output --partial "Edit"
  done
}

# --- Department scoping ---

@test "yolo-security.md references Department: Backend" {
  run grep 'Department.*Backend' "$AGENTS_DIR/yolo-security.md"
  assert_success
}

@test "yolo-fe-security.md references Department: Frontend" {
  run grep 'Department.*Frontend' "$AGENTS_DIR/yolo-fe-security.md"
  assert_success
}

@test "yolo-ux-security.md references Department: UI/UX" {
  run grep 'Department.*UI/UX' "$AGENTS_DIR/yolo-ux-security.md"
  assert_success
}

# --- model-profiles.json entries ---

@test "fe-security role exists in model-profiles.json for all profiles" {
  local profiles="$CONFIG_DIR/model-profiles.json"
  for profile in quality balanced budget; do
    run jq -e --arg p "$profile" '.[$p] | has("fe-security")' "$profiles"
    assert_success
  done
}

@test "ux-security role exists in model-profiles.json for all profiles" {
  local profiles="$CONFIG_DIR/model-profiles.json"
  for profile in quality balanced budget; do
    run jq -e --arg p "$profile" '.[$p] | has("ux-security")' "$profiles"
    assert_success
  done
}
