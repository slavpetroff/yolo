#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
}

teardown() {
  teardown_temp_dir
}

@test "research-warn: ok when flag disabled" {
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" hard-gate research_warn "$TEST_TEMP_DIR/.yolo-planning"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "ok"'
  echo "$output" | jq -e '.reason == "research_persist disabled"'
}

@test "research-warn: ok when effort=turbo" {
  cd "$TEST_TEMP_DIR"
  jq '.v3_plan_research_persist = true | .effort = "turbo"' .yolo-planning/config.json > .yolo-planning/config.json.tmp \
    && mv .yolo-planning/config.json.tmp .yolo-planning/config.json
  run "$YOLO_BIN" hard-gate research_warn "$TEST_TEMP_DIR/.yolo-planning"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "ok"'
  echo "$output" | jq -e '.reason == "turbo effort: research skipped"'
}

@test "research-warn: warns when no RESEARCH.md" {
  cd "$TEST_TEMP_DIR"
  jq '.v3_plan_research_persist = true | .effort = "balanced"' .yolo-planning/config.json > .yolo-planning/config.json.tmp \
    && mv .yolo-planning/config.json.tmp .yolo-planning/config.json
  mkdir -p "$TEST_TEMP_DIR/phase-dir"
  run "$YOLO_BIN" hard-gate research_warn "$TEST_TEMP_DIR/phase-dir"
  [ "$status" -eq 0 ]
  # Extract first line (JSON) — stderr warning also captured by run
  JSON_LINE=$(echo "$output" | head -1)
  echo "$JSON_LINE" | jq -e '.result == "warn"'
  echo "$JSON_LINE" | jq -e '.reason | test("No RESEARCH.md")'
}

@test "research-warn: ok when RESEARCH.md exists" {
  cd "$TEST_TEMP_DIR"
  jq '.v3_plan_research_persist = true | .effort = "thorough"' .yolo-planning/config.json > .yolo-planning/config.json.tmp \
    && mv .yolo-planning/config.json.tmp .yolo-planning/config.json
  mkdir -p "$TEST_TEMP_DIR/phase-dir"
  echo "# Research" > "$TEST_TEMP_DIR/phase-dir/02-01-RESEARCH.md"
  run "$YOLO_BIN" hard-gate research_warn "$TEST_TEMP_DIR/phase-dir"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "ok"'
  echo "$output" | jq -e '.reason == "RESEARCH.md found"'
}
