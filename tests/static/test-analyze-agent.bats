#!/usr/bin/env bats
# test-analyze-agent.bats — Static validation for agents/yolo-analyze.md
# Plan 01-04 T4: File existence, frontmatter, naming, profile, hierarchy

setup() {
  load '../test_helper/common'
}

@test "agents/yolo-analyze.md exists" {
  assert_file_exists "$AGENTS_DIR/yolo-analyze.md"
}

@test "yolo-analyze.md has valid YAML frontmatter with required fields" {
  local agent="$AGENTS_DIR/yolo-analyze.md"
  # Extract frontmatter (between first two --- lines)
  local frontmatter
  frontmatter=$(sed -n '/^---$/,/^---$/p' "$agent" | sed '1d;$d')

  # Check required fields exist
  echo "$frontmatter" | grep -q '^name:' || fail "Missing name in frontmatter"
  echo "$frontmatter" | grep -q '^description:' || fail "Missing description in frontmatter"
  echo "$frontmatter" | grep -q 'tools' || fail "Missing tools in frontmatter"
  echo "$frontmatter" | grep -q '^model:' || fail "Missing model in frontmatter"
}

@test "yolo-analyze.md has model: opus" {
  local agent="$AGENTS_DIR/yolo-analyze.md"
  local frontmatter
  frontmatter=$(sed -n '/^---$/,/^---$/p' "$agent" | sed '1d;$d')
  local model
  model=$(echo "$frontmatter" | grep '^model:' | sed 's/^model:[[:space:]]*//')
  [ "$model" = "opus" ] || fail "Expected model: opus, got model: $model"
}

@test "yolo-analyze.md follows yolo-{role}.md naming convention" {
  local basename
  basename=$(basename "$AGENTS_DIR/yolo-analyze.md")
  [[ "$basename" =~ ^yolo-[a-z]+\.md$ ]] || fail "Name $basename does not match yolo-{role}.md pattern"
}

@test "analyze role exists in model-profiles.json for all profiles" {
  local profiles="$CONFIG_DIR/model-profiles.json"
  for profile in quality balanced budget; do
    run jq -e --arg p "$profile" '.[$p] | has("analyze")' "$profiles"
    assert_success
  done
}

@test "analyze role exists in company-hierarchy.md Agent Roster" {
  local hierarchy="$PROJECT_ROOT/references/company-hierarchy.md"
  run grep 'yolo-analyze' "$hierarchy"
  assert_success
}
