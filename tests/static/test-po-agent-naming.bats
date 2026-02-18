#!/usr/bin/env bats
# test-po-agent-naming.bats — Static naming validation for PO layer agents
# Validates: file existence, naming conventions, frontmatter, model-profiles entries.

setup() {
  load '../test_helper/common'
}

# --- File existence ---

@test "agents/yolo-po.md exists" {
  assert_file_exists "$AGENTS_DIR/yolo-po.md"
}

@test "agents/yolo-questionary.md exists" {
  assert_file_exists "$AGENTS_DIR/yolo-questionary.md"
}

@test "agents/yolo-roadmap.md exists" {
  assert_file_exists "$AGENTS_DIR/yolo-roadmap.md"
}

# --- Naming conventions ---

@test "yolo-po.md follows yolo-{role}.md naming convention" {
  local basename
  basename=$(basename "$AGENTS_DIR/yolo-po.md")
  [[ "$basename" =~ ^yolo-[a-z]+\.md$ ]]
}

@test "yolo-questionary.md follows yolo-{role}.md naming convention" {
  local basename
  basename=$(basename "$AGENTS_DIR/yolo-questionary.md")
  [[ "$basename" =~ ^yolo-[a-z]+\.md$ ]]
}

@test "yolo-roadmap.md follows yolo-{role}.md naming convention" {
  local basename
  basename=$(basename "$AGENTS_DIR/yolo-roadmap.md")
  [[ "$basename" =~ ^yolo-[a-z]+\.md$ ]]
}

# --- YAML frontmatter ---

@test "yolo-po.md has valid YAML frontmatter with name field" {
  local agent="$AGENTS_DIR/yolo-po.md"
  [ -f "$agent" ] || skip "yolo-po.md not yet created"
  local frontmatter
  frontmatter=$(sed -n '/^---$/,/^---$/p' "$agent" | sed '1d;$d')
  echo "$frontmatter" | grep -q '^name:' || fail "Missing name in frontmatter"
}

@test "yolo-questionary.md has valid YAML frontmatter with name field" {
  local agent="$AGENTS_DIR/yolo-questionary.md"
  [ -f "$agent" ] || skip "yolo-questionary.md not yet created"
  local frontmatter
  frontmatter=$(sed -n '/^---$/,/^---$/p' "$agent" | sed '1d;$d')
  echo "$frontmatter" | grep -q '^name:' || fail "Missing name in frontmatter"
}

@test "yolo-roadmap.md has valid YAML frontmatter with name field" {
  local agent="$AGENTS_DIR/yolo-roadmap.md"
  [ -f "$agent" ] || skip "yolo-roadmap.md not yet created"
  local frontmatter
  frontmatter=$(sed -n '/^---$/,/^---$/p' "$agent" | sed '1d;$d')
  echo "$frontmatter" | grep -q '^name:' || fail "Missing name in frontmatter"
}

# --- model-profiles.json entries ---

@test "po role exists in model-profiles.json for all profiles" {
  local profiles="$CONFIG_DIR/model-profiles.json"
  for profile in quality balanced budget; do
    run jq -e --arg p "$profile" '.[$p] | has("po")' "$profiles"
    assert_success
  done
}

@test "questionary role exists in model-profiles.json for all profiles" {
  local profiles="$CONFIG_DIR/model-profiles.json"
  for profile in quality balanced budget; do
    run jq -e --arg p "$profile" '.[$p] | has("questionary")' "$profiles"
    assert_success
  done
}

@test "roadmap role exists in model-profiles.json for all profiles" {
  local profiles="$CONFIG_DIR/model-profiles.json"
  for profile in quality balanced budget; do
    run jq -e --arg p "$profile" '.[$p] | has("roadmap")' "$profiles"
    assert_success
  done
}
