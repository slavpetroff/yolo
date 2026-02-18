#!/usr/bin/env bats
# generate-agent-modes.bats -- Tests for mode-filtered agent prompt generation
# Plan 07-06 T5: verify --mode flag filters sections, reduces output, includes/excludes correct content

setup() {
  load '../test_helper/common'
  GENERATE="$SCRIPTS_DIR/generate-agent.sh"
}

# --- Token reduction tests ---

@test "--mode plan produces fewer lines than --mode full for dev/backend" {
  FULL=$(bash "$GENERATE" --role dev --dept backend --mode full --dry-run 2>/dev/null | wc -l)
  PLAN=$(bash "$GENERATE" --role dev --dept backend --mode plan --dry-run 2>/dev/null | wc -l)
  [ "$PLAN" -lt "$FULL" ]
}

@test "--mode plan produces at least 30% fewer lines than --mode full for dev/backend" {
  FULL=$(bash "$GENERATE" --role dev --dept backend --mode full --dry-run 2>/dev/null | wc -l)
  PLAN=$(bash "$GENERATE" --role dev --dept backend --mode plan --dry-run 2>/dev/null | wc -l)
  # Plan should be at most 70% of full
  THRESHOLD=$(( FULL * 70 / 100 ))
  [ "$PLAN" -le "$THRESHOLD" ]
}

@test "--mode review produces fewer lines than --mode full for senior/backend" {
  FULL=$(bash "$GENERATE" --role senior --dept backend --mode full --dry-run 2>/dev/null | wc -l)
  REVIEW=$(bash "$GENERATE" --role senior --dept backend --mode review --dry-run 2>/dev/null | wc -l)
  [ "$REVIEW" -lt "$FULL" ]
}

@test "--mode qa produces fewer lines than --mode full for qa-code/frontend" {
  FULL=$(bash "$GENERATE" --role qa-code --dept frontend --mode full --dry-run 2>/dev/null | wc -l)
  QA=$(bash "$GENERATE" --role qa-code --dept frontend --mode qa --dry-run 2>/dev/null | wc -l)
  [ "$QA" -lt "$FULL" ]
}

# --- Section inclusion tests ---

@test "--mode implement includes Execution Protocol section for dev" {
  run bash "$GENERATE" --role dev --dept backend --mode implement --dry-run
  assert_output --partial "## Execution Protocol"
}

@test "--mode implement includes Change Management section for dev" {
  run bash "$GENERATE" --role dev --dept backend --mode implement --dry-run
  assert_output --partial "## Change Management"
}

@test "--mode implement includes Teammate API section for dev" {
  run bash "$GENERATE" --role dev --dept backend --mode implement --dry-run
  assert_output --partial "## Teammate API"
}

@test "--mode review includes Execution Protocol for dev" {
  run bash "$GENERATE" --role dev --dept backend --mode review --dry-run
  assert_output --partial "## Execution Protocol"
}

@test "--mode review includes Code Review section for senior" {
  run bash "$GENERATE" --role senior --dept backend --mode review --dry-run
  assert_output --partial "## Mode 2: Code Review"
}

@test "--mode review includes Review Ownership for senior" {
  run bash "$GENERATE" --role senior --dept backend --mode review --dry-run
  assert_output --partial "## Review Ownership"
}

@test "--mode plan includes Planning Protocol for lead" {
  run bash "$GENERATE" --role lead --dept backend --mode plan --dry-run
  assert_output --partial "## Planning Protocol"
}

@test "--mode qa includes Verification Protocol for qa" {
  run bash "$GENERATE" --role qa --dept backend --mode qa --dry-run
  assert_output --partial "## Verification Protocol"
}

@test "--mode qa includes Audit Protocol for security" {
  run bash "$GENERATE" --role security --dept backend --mode qa --dry-run
  assert_output --partial "## Audit Protocol"
}

@test "--mode test includes Core Protocol for tester" {
  run bash "$GENERATE" --role tester --dept backend --mode test --dry-run
  assert_output --partial "## Core Protocol"
}

# --- Section exclusion tests ---

@test "--mode plan excludes Execution Protocol for dev" {
  run bash "$GENERATE" --role dev --dept backend --mode plan --dry-run
  refute_output --partial "## Execution Protocol"
}

@test "--mode plan excludes Teammate API for dev" {
  run bash "$GENERATE" --role dev --dept backend --mode plan --dry-run
  refute_output --partial "## Teammate API"
}

@test "--mode plan excludes Change Management for dev" {
  run bash "$GENERATE" --role dev --dept backend --mode plan --dry-run
  refute_output --partial "## Change Management"
}

@test "--mode review excludes Teammate API for dev" {
  run bash "$GENERATE" --role dev --dept backend --mode review --dry-run
  refute_output --partial "## Teammate API"
}

@test "--mode review excludes Design Review for senior" {
  run bash "$GENERATE" --role senior --dept backend --mode review --dry-run
  refute_output --partial "## Mode 1: Design Review"
}

@test "--mode qa excludes Planning Protocol for lead" {
  run bash "$GENERATE" --role lead --dept backend --mode qa --dry-run
  refute_output --partial "## Planning Protocol"
}

@test "--mode test excludes Teammate API for tester" {
  run bash "$GENERATE" --role tester --dept backend --mode test --dry-run
  refute_output --partial "## Teammate API"
}

# --- Mode marker cleanup tests ---

@test "mode markers are stripped from output in full mode" {
  OUTPUT=$(bash "$GENERATE" --role dev --dept backend --mode full --dry-run 2>/dev/null)
  [[ ! "$OUTPUT" =~ "<!-- mode:" ]]
  [[ ! "$OUTPUT" =~ "<!-- /mode -->" ]]
}

@test "mode markers are stripped from output when no --mode specified" {
  OUTPUT=$(bash "$GENERATE" --role dev --dept backend --dry-run 2>/dev/null)
  [[ ! "$OUTPUT" =~ "<!-- mode:" ]]
  [[ ! "$OUTPUT" =~ "<!-- /mode -->" ]]
}

@test "mode markers are stripped from filtered output" {
  OUTPUT=$(bash "$GENERATE" --role dev --dept backend --mode plan --dry-run 2>/dev/null)
  [[ ! "$OUTPUT" =~ "<!-- mode:" ]]
  [[ ! "$OUTPUT" =~ "<!-- /mode -->" ]]
}

# --- Backward compatibility tests ---

@test "--mode full produces same line count as no --mode" {
  FULL=$(bash "$GENERATE" --role dev --dept backend --mode full --dry-run 2>/dev/null | wc -l)
  NOMODE=$(bash "$GENERATE" --role dev --dept backend --dry-run 2>/dev/null | wc -l)
  [ "$FULL" -eq "$NOMODE" ]
}

@test "all modes always include Hierarchy section" {
  for mode in plan implement review qa test; do
    OUTPUT=$(bash "$GENERATE" --role dev --dept backend --mode "$mode" --dry-run 2>/dev/null)
    echo "$OUTPUT" | grep -q "## Hierarchy" || {
      echo "Mode $mode missing Hierarchy section"
      return 1
    }
  done
}

@test "all modes always include Persona section" {
  for mode in plan implement review qa test; do
    OUTPUT=$(bash "$GENERATE" --role dev --dept backend --mode "$mode" --dry-run 2>/dev/null)
    echo "$OUTPUT" | grep -q "## Persona & Voice" || {
      echo "Mode $mode missing Persona section"
      return 1
    }
  done
}

@test "all modes always include Context section" {
  for mode in plan implement review qa test; do
    OUTPUT=$(bash "$GENERATE" --role dev --dept backend --mode "$mode" --dry-run 2>/dev/null)
    echo "$OUTPUT" | grep -q "## Context" || {
      echo "Mode $mode missing Context section"
      return 1
    }
  done
}

# --- Validation tests ---

@test "invalid mode is rejected" {
  run bash "$GENERATE" --role dev --dept backend --mode invalid
  assert_failure
  assert_output --partial "invalid mode"
}

@test "mode-profiles.json is valid JSON" {
  run jq empty "$PROJECT_ROOT/config/mode-profiles.json"
  assert_success
}

@test "mode-profiles.json defines all 6 modes" {
  COUNT=$(jq '.modes | keys | length' "$PROJECT_ROOT/config/mode-profiles.json")
  [ "$COUNT" -eq 6 ]
}

@test "mode-profiles.json plan mode has sections array" {
  run jq -e '.modes.plan.sections | length > 0' "$PROJECT_ROOT/config/mode-profiles.json"
  assert_success
}
