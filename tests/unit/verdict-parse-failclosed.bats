#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="${BATS_TEST_DIRNAME}/../.."
  SKILL="$PROJECT_ROOT/skills/execute-protocol/SKILL.md"
}

# --- Reviewer verdict parse failure: fail-closed ---

@test "reviewer parse failure does NOT fall back to conditional" {
  # The fallback block must not set AGENT_VERDICT="conditional"
  run grep 'AGENT_VERDICT="conditional"' "$SKILL"
  [ "$status" -ne 0 ]
}

@test "reviewer parse failure sets VERDICT to reject" {
  # The fallback block must set VERDICT="reject"
  run grep 'VERDICT="reject"' "$SKILL"
  [ "$status" -eq 0 ]
}

# --- QA report parse failure: fail-closed ---

@test "QA parse failure does NOT fall back to CLI results" {
  # The fallback block must not say "using CLI results"
  run grep 'using CLI results' "$SKILL"
  [ "$status" -ne 0 ]
}

@test "QA parse failure sets passed to false in fallback report" {
  # The fallback block must contain a report with "passed": false
  run grep '"passed": false' "$SKILL"
  [ "$status" -eq 0 ]
}

# --- Both paths log diagnostic events ---

@test "reviewer parse failure logs review_parse_failure event" {
  run grep 'log-event review_parse_failure' "$SKILL"
  [ "$status" -eq 0 ]
}

@test "QA parse failure logs qa_parse_failure event" {
  run grep 'log-event qa_parse_failure' "$SKILL"
  [ "$status" -eq 0 ]
}
