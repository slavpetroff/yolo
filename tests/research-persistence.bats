#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
}

teardown() {
  teardown_temp_dir
}

@test "research-persistence: validates Phase 1 RESEARCH.md sections" {
  RESEARCH_FILE="$PROJECT_ROOT/.vbw-planning/phases/01-config-migration/01-RESEARCH.md"

  # Verify file exists
  [ -f "$RESEARCH_FILE" ]

  # Count the 4 required section headers
  FINDINGS_COUNT=$(grep -c "^## Findings$" "$RESEARCH_FILE" || echo 0)
  PATTERNS_COUNT=$(grep -c "^## Relevant Patterns$" "$RESEARCH_FILE" || echo 0)
  RISKS_COUNT=$(grep -c "^## Risks$" "$RESEARCH_FILE" || echo 0)
  RECOMMENDATIONS_COUNT=$(grep -c "^## Recommendations$" "$RESEARCH_FILE" || echo 0)

  # All 4 sections must be present exactly once
  [ "$FINDINGS_COUNT" -eq 1 ]
  [ "$PATTERNS_COUNT" -eq 1 ]
  [ "$RISKS_COUNT" -eq 1 ]
  [ "$RECOMMENDATIONS_COUNT" -eq 1 ]
}
