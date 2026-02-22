#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config

  # Create codebase files for tier testing
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning/codebase"
  echo "Convention rules here" > "$TEST_TEMP_DIR/.yolo-planning/codebase/CONVENTIONS.md"
  echo "Stack: Rust + TypeScript" > "$TEST_TEMP_DIR/.yolo-planning/codebase/STACK.md"
  echo "Architecture overview" > "$TEST_TEMP_DIR/.yolo-planning/codebase/ARCHITECTURE.md"
  echo "Roadmap content" > "$TEST_TEMP_DIR/.yolo-planning/codebase/ROADMAP.md"
  echo "Requirements list" > "$TEST_TEMP_DIR/.yolo-planning/codebase/REQUIREMENTS.md"

  # Create phases dir with a sample plan
  mkdir -p "$TEST_TEMP_DIR/phases"
  echo "Plan content for phase 1" > "$TEST_TEMP_DIR/phases/01-PLAN.md"
}

teardown() {
  teardown_temp_dir
}

# Helper: extract a tier section from compiled context file
# Usage: extract_tier <file> <tier_header_pattern>
extract_tier() {
  local file="$1" pattern="$2"
  awk "/$pattern/{found=1; next} /^--- TIER [0-9]|^--- END COMPILED/{if(found) exit} found{print}" "$file"
}

@test "compile-context output contains TIER 1 header" {
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" compile-context 1 dev "$TEST_TEMP_DIR/phases"
  [ "$status" -eq 0 ]

  local ctx_file="$TEST_TEMP_DIR/phases/.context-dev.md"
  [ -f "$ctx_file" ]
  grep -q "^--- TIER 1: SHARED BASE ---" "$ctx_file"
}

@test "compile-context output contains TIER 2 header with family" {
  cd "$TEST_TEMP_DIR"

  # dev is in "execution" family
  run "$YOLO_BIN" compile-context 1 dev "$TEST_TEMP_DIR/phases"
  [ "$status" -eq 0 ]
  grep -q "^--- TIER 2: ROLE FAMILY (execution) ---" "$TEST_TEMP_DIR/phases/.context-dev.md"

  # lead is in "planning" family
  run "$YOLO_BIN" compile-context 1 lead "$TEST_TEMP_DIR/phases"
  [ "$status" -eq 0 ]
  grep -q "^--- TIER 2: ROLE FAMILY (planning) ---" "$TEST_TEMP_DIR/phases/.context-lead.md"
}

@test "tier 1 is byte-identical across dev and architect" {
  cd "$TEST_TEMP_DIR"

  run "$YOLO_BIN" compile-context 1 dev "$TEST_TEMP_DIR/phases"
  [ "$status" -eq 0 ]
  run "$YOLO_BIN" compile-context 1 architect "$TEST_TEMP_DIR/phases"
  [ "$status" -eq 0 ]

  local tier1_dev tier1_arch
  tier1_dev="$(extract_tier "$TEST_TEMP_DIR/phases/.context-dev.md" "TIER 1: SHARED BASE")"
  tier1_arch="$(extract_tier "$TEST_TEMP_DIR/phases/.context-architect.md" "TIER 1: SHARED BASE")"

  [ "$tier1_dev" = "$tier1_arch" ]
}

@test "tier 2 is byte-identical for dev and qa (same family)" {
  cd "$TEST_TEMP_DIR"

  run "$YOLO_BIN" compile-context 1 dev "$TEST_TEMP_DIR/phases"
  [ "$status" -eq 0 ]
  run "$YOLO_BIN" compile-context 1 qa "$TEST_TEMP_DIR/phases"
  [ "$status" -eq 0 ]

  local tier2_dev tier2_qa
  tier2_dev="$(extract_tier "$TEST_TEMP_DIR/phases/.context-dev.md" "TIER 2: ROLE FAMILY")"
  tier2_qa="$(extract_tier "$TEST_TEMP_DIR/phases/.context-qa.md" "TIER 2: ROLE FAMILY")"

  [ "$tier2_dev" = "$tier2_qa" ]
}

@test "tier 2 differs between dev and lead (different families)" {
  cd "$TEST_TEMP_DIR"

  run "$YOLO_BIN" compile-context 1 dev "$TEST_TEMP_DIR/phases"
  [ "$status" -eq 0 ]
  run "$YOLO_BIN" compile-context 1 lead "$TEST_TEMP_DIR/phases"
  [ "$status" -eq 0 ]

  local tier2_dev tier2_lead
  tier2_dev="$(extract_tier "$TEST_TEMP_DIR/phases/.context-dev.md" "TIER 2: ROLE FAMILY")"
  tier2_lead="$(extract_tier "$TEST_TEMP_DIR/phases/.context-lead.md" "TIER 2: ROLE FAMILY")"

  [ "$tier2_dev" != "$tier2_lead" ]
}

@test "tier 3 contains phase plan content" {
  cd "$TEST_TEMP_DIR"

  run "$YOLO_BIN" compile-context 1 dev "$TEST_TEMP_DIR/phases" "$TEST_TEMP_DIR/phases/01-PLAN.md"
  [ "$status" -eq 0 ]

  local ctx_file="$TEST_TEMP_DIR/phases/.context-dev.md"
  grep -q "^--- TIER 3: VOLATILE TAIL (phase=1) ---" "$ctx_file"
  grep -q "Plan content for phase 1" "$ctx_file"
}

@test "compile-context writes output file" {
  cd "$TEST_TEMP_DIR"

  run "$YOLO_BIN" compile-context 1 dev "$TEST_TEMP_DIR/phases"
  [ "$status" -eq 0 ]

  local ctx_file="$TEST_TEMP_DIR/phases/.context-dev.md"
  [ -f "$ctx_file" ]
  # File should contain all 3 tier headers and the end sentinel
  grep -q "TIER 1: SHARED BASE" "$ctx_file"
  grep -q "TIER 2: ROLE FAMILY" "$ctx_file"
  grep -q "TIER 3: VOLATILE TAIL" "$ctx_file"
  grep -q "END COMPILED CONTEXT" "$ctx_file"
}

# --- Researcher context injection tests ---

@test "researcher role gets planning family tier 2" {
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" compile-context 1 researcher "$TEST_TEMP_DIR/phases"
  [ "$status" -eq 0 ]

  local ctx_file="$TEST_TEMP_DIR/phases/.context-researcher.md"
  [ -f "$ctx_file" ]
  grep -q "TIER 2: ROLE FAMILY (planning)" "$ctx_file"
  grep -q "Architecture overview" "$ctx_file"
}

@test "tier 3 includes RESEARCH.md when present" {
  cd "$TEST_TEMP_DIR"
  mkdir -p "$TEST_TEMP_DIR/phases/03"
  echo "Research findings here" > "$TEST_TEMP_DIR/phases/03/RESEARCH.md"

  run "$YOLO_BIN" compile-context 3 dev "$TEST_TEMP_DIR/phases"
  [ "$status" -eq 0 ]

  local ctx_file="$TEST_TEMP_DIR/phases/.context-dev.md"
  grep -q "# Research: RESEARCH.md" "$ctx_file"
  grep -q "Research findings here" "$ctx_file"
}

@test "tier 3 excludes research when no RESEARCH.md" {
  cd "$TEST_TEMP_DIR"
  mkdir -p "$TEST_TEMP_DIR/phases/04"
  echo "Plan only" > "$TEST_TEMP_DIR/phases/04/01-PLAN.md"

  run "$YOLO_BIN" compile-context 4 dev "$TEST_TEMP_DIR/phases"
  [ "$status" -eq 0 ]

  local ctx_file="$TEST_TEMP_DIR/phases/.context-dev.md"
  ! grep -q "# Research:" "$ctx_file"
}

@test "researcher model resolves from profiles" {
  run "$YOLO_BIN" resolve-model researcher "$TEST_TEMP_DIR/.yolo-planning/config.json" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 0 ]
  [ "$output" = "sonnet" ]
}
