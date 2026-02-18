#!/usr/bin/env bats
# test-documenter-agent-naming.bats — Static naming validation for documenter agents
# Validates: file existence, naming conventions, frontmatter, model: haiku, docs.jsonl output, model-profiles entries.

setup() {
  load '../test_helper/common'
}

# --- File existence ---

@test "agents/yolo-documenter.md exists" {
  assert_file_exists "$AGENTS_DIR/yolo-documenter.md"
}

@test "agents/yolo-fe-documenter.md exists" {
  assert_file_exists "$AGENTS_DIR/yolo-fe-documenter.md"
}

@test "agents/yolo-ux-documenter.md exists" {
  assert_file_exists "$AGENTS_DIR/yolo-ux-documenter.md"
}

# --- Naming conventions ---

@test "yolo-documenter.md follows yolo-{role}.md naming" {
  local basename
  basename=$(basename "$AGENTS_DIR/yolo-documenter.md")
  [[ "$basename" =~ ^yolo-[a-z]+\.md$ ]]
}

@test "yolo-fe-documenter.md follows yolo-{dept}-{role}.md naming" {
  local basename
  basename=$(basename "$AGENTS_DIR/yolo-fe-documenter.md")
  [[ "$basename" =~ ^yolo-fe-[a-z]+\.md$ ]]
}

@test "yolo-ux-documenter.md follows yolo-{dept}-{role}.md naming" {
  local basename
  basename=$(basename "$AGENTS_DIR/yolo-ux-documenter.md")
  [[ "$basename" =~ ^yolo-ux-[a-z]+\.md$ ]]
}

# --- YAML frontmatter: name field ---

@test "yolo-documenter.md has name: yolo-documenter in frontmatter" {
  run grep '^name: yolo-documenter' "$AGENTS_DIR/yolo-documenter.md"
  assert_success
}

@test "yolo-fe-documenter.md has name: yolo-fe-documenter in frontmatter" {
  run grep '^name: yolo-fe-documenter' "$AGENTS_DIR/yolo-fe-documenter.md"
  assert_success
}

@test "yolo-ux-documenter.md has name: yolo-ux-documenter in frontmatter" {
  run grep '^name: yolo-ux-documenter' "$AGENTS_DIR/yolo-ux-documenter.md"
  assert_success
}

# --- model: haiku ---

@test "all 3 documenter agents have model: haiku" {
  for agent in yolo-documenter yolo-fe-documenter yolo-ux-documenter; do
    run grep '^model: haiku' "$AGENTS_DIR/${agent}.md"
    assert_success
  done
}

# --- docs.jsonl output reference ---

@test "all 3 documenter agents mention docs.jsonl" {
  for agent in yolo-documenter yolo-fe-documenter yolo-ux-documenter; do
    run grep 'docs\.jsonl' "$AGENTS_DIR/${agent}.md"
    assert_success
  done
}

# --- Config Gate section ---

@test "all 3 documenter agents have Config Gate section" {
  for agent in yolo-documenter yolo-fe-documenter yolo-ux-documenter; do
    run grep '## Config Gate' "$AGENTS_DIR/${agent}.md"
    assert_success
  done
}

# --- model-profiles.json entries ---

@test "documenter role exists in model-profiles.json for all profiles" {
  local profiles="$CONFIG_DIR/model-profiles.json"
  for profile in quality balanced budget; do
    run jq -e --arg p "$profile" '.[$p] | has("documenter")' "$profiles"
    assert_success
  done
}

@test "fe-documenter role exists in model-profiles.json for all profiles" {
  local profiles="$CONFIG_DIR/model-profiles.json"
  for profile in quality balanced budget; do
    run jq -e --arg p "$profile" '.[$p] | has("fe-documenter")' "$profiles"
    assert_success
  done
}

@test "ux-documenter role exists in model-profiles.json for all profiles" {
  local profiles="$CONFIG_DIR/model-profiles.json"
  for profile in quality balanced budget; do
    run jq -e --arg p "$profile" '.[$p] | has("ux-documenter")' "$profiles"
    assert_success
  done
}
