#!/usr/bin/env bats
# agent-teammate-sections.bats -- Static validation: all 23 agents have Teammate API sections

setup() {
  load '../test_helper/common'
  # No fixtures needed -- reads real agent files via $AGENTS_DIR from common.bash
}

# All 23 agent filenames that must have ## Teammate API sections
AGENTS=(
  yolo-lead.md yolo-senior.md yolo-dev.md yolo-architect.md
  yolo-tester.md yolo-fe-tester.md yolo-ux-tester.md
  yolo-qa.md yolo-fe-qa.md yolo-ux-qa.md
  yolo-qa-code.md yolo-fe-qa-code.md yolo-ux-qa-code.md
  yolo-security.md yolo-owner.md
  yolo-fe-lead.md yolo-fe-senior.md yolo-fe-dev.md yolo-fe-architect.md
  yolo-ux-lead.md yolo-ux-senior.md yolo-ux-dev.md yolo-ux-architect.md
)

@test "exactly 23 agents require Teammate API sections" {
  assert_equal "${#AGENTS[@]}" "23"
}

@test "all 23 agent files exist" {
  for agent in "${AGENTS[@]}"; do
    assert_file_exists "$AGENTS_DIR/$agent"
  done
}

@test "all 23 agents contain ## Teammate API section" {
  for agent in "${AGENTS[@]}"; do
    run grep -c '## Teammate API' "$AGENTS_DIR/$agent"
    [[ $status -eq 0 ]] || fail "Missing ## Teammate API in $agent"
    [[ "$output" -ge 1 ]] || fail "Zero matches for ## Teammate API in $agent"
  done
}

@test "all 23 agents contain team_mode=teammate guard" {
  for agent in "${AGENTS[@]}"; do
    run grep -c 'team_mode=teammate' "$AGENTS_DIR/$agent"
    [[ $status -eq 0 ]] || fail "Missing team_mode=teammate guard in $agent"
    [[ "$output" -ge 1 ]] || fail "Zero matches for team_mode=teammate in $agent"
  done
}

@test "all 23 agents reference @references/teammate-api-patterns.md" {
  for agent in "${AGENTS[@]}"; do
    run grep '@references/teammate-api-patterns.md' "$AGENTS_DIR/$agent"
    [[ $status -eq 0 ]] || fail "Missing @references/teammate-api-patterns.md in $agent"
  done
}

@test "owner agent documents file-based rationale" {
  run grep -c 'file-based' "$AGENTS_DIR/yolo-owner.md"
  assert_success
  [[ "$output" -ge 1 ]] || fail "yolo-owner.md missing file-based rationale"
}

@test "shared agents (critic, scout, debugger) do NOT have Teammate API section" {
  local EXCLUDED=(yolo-critic.md yolo-scout.md yolo-debugger.md)
  for agent in "${EXCLUDED[@]}"; do
    run grep '## Teammate API' "$AGENTS_DIR/$agent"
    assert_failure "Expected $agent to NOT have ## Teammate API section"
  done
}

@test "no agent files with Teammate API section are missing from test list" {
  # Find all agent files that have ## Teammate API section
  local found_agents=()
  for f in "$AGENTS_DIR"/yolo-*.md; do
    if grep -q '## Teammate API' "$f" 2>/dev/null; then
      found_agents+=("$(basename "$f")")
    fi
  done

  # Verify every found agent is in AGENTS array
  for found in "${found_agents[@]}"; do
    local in_list=false
    for listed in "${AGENTS[@]}"; do
      if [ "$found" = "$listed" ]; then
        in_list=true
        break
      fi
    done
    [[ "$in_list" = true ]] || fail "Agent $found has ## Teammate API section but is not in test list"
  done
}
