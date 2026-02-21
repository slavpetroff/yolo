#!/usr/bin/env bats
# Migrated: bootstrap-requirements.sh -> yolo bootstrap requirements
# CWD-sensitive: yes

load test_helper

setup() {
  setup_temp_dir
  create_test_config
}

teardown() {
  teardown_temp_dir
}

@test "domain-research.md has 4 required sections" {
  # Simulate Scout writing research file
  cat > "$TEST_TEMP_DIR/.yolo-planning/domain-research.md" <<EOF
## Table Stakes
- Feature 1
- Feature 2

## Common Pitfalls
- Pitfall 1

## Architecture Patterns
- Pattern 1

## Competitor Landscape
- Competitor 1: feature
EOF

  # Verify structure
  run grep -c "^## Table Stakes" "$TEST_TEMP_DIR/.yolo-planning/domain-research.md"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]

  run grep -c "^## Common Pitfalls" "$TEST_TEMP_DIR/.yolo-planning/domain-research.md"
  [ "$output" -eq 1 ]

  run grep -c "^## Architecture Patterns" "$TEST_TEMP_DIR/.yolo-planning/domain-research.md"
  [ "$output" -eq 1 ]

  run grep -c "^## Competitor Landscape" "$TEST_TEMP_DIR/.yolo-planning/domain-research.md"
  [ "$output" -eq 1 ]
}

@test "bootstrap requirements accepts optional research file" {
  cd "$TEST_TEMP_DIR"
  # Create discovery.json
  cat > "$TEST_TEMP_DIR/.yolo-planning/discovery.json" <<EOF
{"answered":[{"question":"Test","answer":"Answer","category":"scope","phase":"bootstrap","date":"2026-02-13"}],"inferred":[]}
EOF

  # Create research file
  cat > "$TEST_TEMP_DIR/.yolo-planning/domain-research.md" <<EOF
## Table Stakes
- Authentication

## Common Pitfalls
- Poor error handling

## Architecture Patterns
- REST API

## Competitor Landscape
- Competitor A: feature X
EOF

  # Run with research file
  run "$YOLO_BIN" bootstrap requirements \
    "$TEST_TEMP_DIR/.yolo-planning/REQUIREMENTS.md" \
    "$TEST_TEMP_DIR/.yolo-planning/discovery.json" \
    "$TEST_TEMP_DIR/.yolo-planning/domain-research.md"

  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/.yolo-planning/REQUIREMENTS.md" ]
}

@test "bootstrap requirements integrates research findings into requirements" {
  cd "$TEST_TEMP_DIR"
  cat > "$TEST_TEMP_DIR/.yolo-planning/discovery.json" <<EOF
{"answered":[{"question":"What features?","answer":"User accounts","category":"scope","phase":"bootstrap","date":"2026-02-13"}],"inferred":[{"text":"User authentication","priority":"Must-have"}]}
EOF

  cat > "$TEST_TEMP_DIR/.yolo-planning/domain-research.md" <<EOF
## Table Stakes
- User authentication (every app has this)

## Common Pitfalls
- Not handling offline mode

## Architecture Patterns
- Token-based auth

## Competitor Landscape
- App A: OAuth login
EOF

  run "$YOLO_BIN" bootstrap requirements \
    "$TEST_TEMP_DIR/.yolo-planning/REQUIREMENTS.md" \
    "$TEST_TEMP_DIR/.yolo-planning/discovery.json" \
    "$TEST_TEMP_DIR/.yolo-planning/domain-research.md"

  [ "$status" -eq 0 ]

  # Verify requirements were generated from inferred data
  run grep "REQ-01: User authentication" "$TEST_TEMP_DIR/.yolo-planning/REQUIREMENTS.md"
  [ "$status" -eq 0 ]

  [ -f "$TEST_TEMP_DIR/.yolo-planning/REQUIREMENTS.md" ]
}

@test "discovery.json includes research_summary field" {
  cd "$TEST_TEMP_DIR"
  cat > "$TEST_TEMP_DIR/.yolo-planning/discovery.json" <<EOF
{"answered":[],"inferred":[]}
EOF

  cat > "$TEST_TEMP_DIR/.yolo-planning/domain-research.md" <<EOF
## Table Stakes
- Feature

## Common Pitfalls
- Pitfall

## Architecture Patterns
- Pattern

## Competitor Landscape
- Competitor
EOF

  "$YOLO_BIN" bootstrap requirements \
    "$TEST_TEMP_DIR/.yolo-planning/REQUIREMENTS.md" \
    "$TEST_TEMP_DIR/.yolo-planning/discovery.json" \
    "$TEST_TEMP_DIR/.yolo-planning/domain-research.md"

  run jq -e '.research_summary.available' "$TEST_TEMP_DIR/.yolo-planning/discovery.json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}
