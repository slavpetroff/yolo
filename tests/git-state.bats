#!/usr/bin/env bats
# Tests for: yolo git-state
# CLI signature: yolo git-state
# CWD-sensitive: yes

load test_helper

setup() {
  setup_temp_dir
  cd "$TEST_TEMP_DIR"
}

teardown() {
  teardown_temp_dir
}

@test "returns is_git_repo false for non-git dir" {
  # Remove .yolo-planning so it's a plain temp dir
  rm -rf "$TEST_TEMP_DIR/.yolo-planning"

  run bash -c "cd '$TEST_TEMP_DIR' && '$YOLO_BIN' git-state"
  [ "$status" -eq 0 ]

  echo "$output" | jq -e '.ok == true'
  echo "$output" | jq -e '.is_git_repo == false'
  echo "$output" | jq -e '.branch == null'
}

@test "returns branch name" {
  git init -q
  git config user.name "Test"
  git config user.email "test@test.com"
  echo "init" > README.md
  git add README.md
  git commit -q -m "initial"

  run bash -c "cd '$TEST_TEMP_DIR' && '$YOLO_BIN' git-state"
  [ "$status" -eq 0 ]

  echo "$output" | jq -e '.is_git_repo == true'
  # Branch should be "main" or "master"
  local branch
  branch=$(echo "$output" | jq -r '.branch')
  [[ "$branch" == "main" || "$branch" == "master" ]]
}

@test "detects clean state" {
  git init -q
  git config user.name "Test"
  git config user.email "test@test.com"
  echo "init" > README.md
  git add README.md
  git commit -q -m "initial"

  run bash -c "cd '$TEST_TEMP_DIR' && '$YOLO_BIN' git-state"
  [ "$status" -eq 0 ]

  echo "$output" | jq -e '.dirty == false'
  echo "$output" | jq -e '.dirty_files == 0'
}

@test "detects dirty state" {
  git init -q
  git config user.name "Test"
  git config user.email "test@test.com"
  echo "init" > README.md
  git add README.md
  git commit -q -m "initial"

  echo "uncommitted" > new-file.txt

  run bash -c "cd '$TEST_TEMP_DIR' && '$YOLO_BIN' git-state"
  [ "$status" -eq 0 ]

  echo "$output" | jq -e '.dirty == true'
  echo "$output" | jq -e '.dirty_files > 0'
}

@test "returns head sha and message" {
  git init -q
  git config user.name "Test"
  git config user.email "test@test.com"
  echo "init" > README.md
  git add README.md
  git commit -q -m "my test commit message"

  run bash -c "cd '$TEST_TEMP_DIR' && '$YOLO_BIN' git-state"
  [ "$status" -eq 0 ]

  echo "$output" | jq -e '.head_message == "my test commit message"'
  # SHA should be non-null string
  echo "$output" | jq -e '.head_sha != null'
  echo "$output" | jq -e '.head_short != null'
}

@test "returns last tag and commits since" {
  git init -q
  git config user.name "Test"
  git config user.email "test@test.com"
  echo "init" > README.md
  git add README.md
  git commit -q -m "initial"

  git tag v1.0.0

  echo "a" > a.txt
  git add a.txt
  git commit -q -m "second"

  echo "b" > b.txt
  git add b.txt
  git commit -q -m "third"

  run bash -c "cd '$TEST_TEMP_DIR' && '$YOLO_BIN' git-state"
  [ "$status" -eq 0 ]

  echo "$output" | jq -e '.last_tag == "v1.0.0"'
  echo "$output" | jq -e '.commits_since_tag == 2'
}
