#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  cd "$TEST_TEMP_DIR"
  git init --quiet
  git config user.email "test@test.com"
  git config user.name "Test"
  touch dummy && git add dummy && git commit -m "init" --quiet

  # Copy stack-mappings.json for detect-stack
  mkdir -p "$TEST_TEMP_DIR/config"
  cp "$CONFIG_DIR/stack-mappings.json" "$TEST_TEMP_DIR/config/"
}

teardown() {
  cd "$PROJECT_ROOT"
  teardown_temp_dir
}

@test "detect-stack --brownfield: true in git repo with files" {
  run "$YOLO_BIN" detect-stack "$TEST_TEMP_DIR" --brownfield
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.brownfield == true' >/dev/null
}

@test "detect-stack without --brownfield: no brownfield key" {
  run "$YOLO_BIN" detect-stack "$TEST_TEMP_DIR"
  [ "$status" -eq 0 ]
  local bf
  bf=$(echo "$output" | jq 'has("brownfield")')
  [ "$bf" = "false" ]
}

@test "detect-stack --brownfield: false in empty git repo" {
  local empty_dir
  empty_dir=$(mktemp -d)
  mkdir -p "$empty_dir/config"
  cp "$CONFIG_DIR/stack-mappings.json" "$empty_dir/config/"
  cd "$empty_dir"
  git init --quiet
  git config user.email "test@test.com"
  git config user.name "Test"
  run "$YOLO_BIN" detect-stack "$empty_dir" --brownfield
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.brownfield == false' >/dev/null
  rm -rf "$empty_dir"
}
