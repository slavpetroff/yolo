#!/usr/bin/env bats
# agent-review-ownership.bats -- Static validation: all 16 reviewing agents have ## Review Ownership sections

setup() {
  load '../test_helper/common'
  # No fixtures needed -- reads real agent files via $AGENTS_DIR from common.bash
}

# All 16 reviewing agent filenames that must have ## Review Ownership sections
# Per D1: Senior, Lead, Architect, Owner, QA, QA-Code across 3 departments
REVIEWING_AGENTS=(
  yolo-senior.md yolo-lead.md yolo-architect.md yolo-owner.md yolo-qa.md yolo-qa-code.md
  yolo-fe-senior.md yolo-fe-lead.md yolo-fe-architect.md yolo-fe-qa.md yolo-fe-qa-code.md
  yolo-ux-senior.md yolo-ux-lead.md yolo-ux-architect.md yolo-ux-qa.md yolo-ux-qa-code.md
)

# Non-reviewing agents that should NOT have ## Review Ownership
EXCLUDED_AGENTS=(
  yolo-dev.md yolo-fe-dev.md yolo-ux-dev.md
  yolo-tester.md yolo-fe-tester.md yolo-ux-tester.md
  yolo-critic.md yolo-scout.md yolo-debugger.md yolo-security.md
)

@test "exactly 16 reviewing agents require Review Ownership sections" {
  assert_equal "${#REVIEWING_AGENTS[@]}" "16"
}

@test "all 16 reviewing agent files exist" {
  for agent in "${REVIEWING_AGENTS[@]}"; do
    assert_file_exists "$AGENTS_DIR/$agent"
  done
}

@test "all 16 reviewing agents contain ## Review Ownership section" {
  for agent in "${REVIEWING_AGENTS[@]}"; do
    run grep -c '## Review Ownership' "$AGENTS_DIR/$agent"
    [[ $status -eq 0 ]] || fail "Missing ## Review Ownership in $agent"
    [[ "$output" -ge 1 ]] || fail "Zero matches for ## Review Ownership in $agent"
  done
}

@test "all 16 reviewing agents reference review-ownership-patterns.md" {
  for agent in "${REVIEWING_AGENTS[@]}"; do
    run grep 'review-ownership-patterns.md' "$AGENTS_DIR/$agent"
    [[ $status -eq 0 ]] || fail "Missing review-ownership-patterns.md reference in $agent"
  done
}

@test "all 16 reviewing agents contain ownership language (must analyze)" {
  for agent in "${REVIEWING_AGENTS[@]}"; do
    run grep -i 'must analyze\|ownership means\|own.*quality\|own.*thoroughness\|own.*accuracy\|own.*decisions\|own.*assessment' "$AGENTS_DIR/$agent"
    [[ $status -eq 0 ]] || fail "Missing ownership language in $agent"
  done
}

@test "excluded agents do NOT have ## Review Ownership section" {
  for agent in "${EXCLUDED_AGENTS[@]}"; do
    if [ -f "$AGENTS_DIR/$agent" ]; then
      run grep '## Review Ownership' "$AGENTS_DIR/$agent"
      assert_failure "Expected $agent to NOT have ## Review Ownership section"
    fi
  done
}

@test "review-ownership-patterns.md reference doc exists" {
  local REFS_DIR="$PROJECT_ROOT/references"
  assert_file_exists "$REFS_DIR/review-ownership-patterns.md"
}

@test "review-ownership-patterns.md contains OWNERSHIP_MATRIX" {
  local REFS_DIR="$PROJECT_ROOT/references"
  run grep 'OWNERSHIP_MATRIX_START' "$REFS_DIR/review-ownership-patterns.md"
  assert_success
}

@test "no reviewing agent files with Review Ownership section are missing from test list" {
  local found_agents=()
  for f in "$AGENTS_DIR"/yolo-*.md; do
    if grep -q '## Review Ownership' "$f" 2>/dev/null; then
      found_agents+=("$(basename "$f")")
    fi
  done

  for found in "${found_agents[@]}"; do
    local in_list=false
    for listed in "${REVIEWING_AGENTS[@]}"; do
      if [ "$found" = "$listed" ]; then
        in_list=true
        break
      fi
    done
    [[ "$in_list" = true ]] || fail "Agent $found has ## Review Ownership section but is not in test list"
  done
}
