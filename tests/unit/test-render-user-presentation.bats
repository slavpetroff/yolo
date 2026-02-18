#!/usr/bin/env bats
# test-render-user-presentation.bats — Unit tests for scripts/render-user-presentation.sh
# Validates rendering: basic output, empty options, missing fields, invalid JSON.

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/render-user-presentation.sh"
}

# Helper: create a user_presentation JSON file
mk_presentation() {
  local file="$TEST_WORKDIR/presentation.json"
  cat > "$file"
  echo "$file"
}

@test "render-user-presentation.sh exists and is executable" {
  [ -f "$SUT" ] || skip "render-user-presentation.sh not yet created"
  [ -x "$SUT" ] || skip "render-user-presentation.sh not executable"
}

@test "basic rendering: content and options produce formatted markdown" {
  [ -x "$SUT" ] || skip "render-user-presentation.sh not yet created"
  local pres
  pres=$(mk_presentation <<'JSON'
{
  "content": "What is the project scope?",
  "context": "Gathering requirements for milestone planning",
  "options": [
    {"label": "A", "description": "Full rewrite"},
    {"label": "B", "description": "Incremental migration"}
  ]
}
JSON
  )
  run bash "$SUT" "$pres"
  assert_success
  assert_output --partial "project scope"
  assert_output --partial "Full rewrite"
  assert_output --partial "Incremental migration"
}

@test "empty options: renders content without options section" {
  [ -x "$SUT" ] || skip "render-user-presentation.sh not yet created"
  local pres
  pres=$(mk_presentation <<'JSON'
{
  "content": "No choices needed",
  "context": "Informational only",
  "options": []
}
JSON
  )
  run bash "$SUT" "$pres"
  assert_success
  assert_output --partial "No choices needed"
}

@test "missing fields: graceful handling when context is absent" {
  [ -x "$SUT" ] || skip "render-user-presentation.sh not yet created"
  local pres
  pres=$(mk_presentation <<'JSON'
{
  "content": "Simple question",
  "options": [{"label": "Yes", "description": "Confirm"}]
}
JSON
  )
  run bash "$SUT" "$pres"
  assert_success
  assert_output --partial "Simple question"
}

@test "invalid JSON input exits non-zero" {
  [ -x "$SUT" ] || skip "render-user-presentation.sh not yet created"
  local file="$TEST_WORKDIR/bad.json"
  echo "this is not json {{{" > "$file"
  run bash "$SUT" "$file"
  assert_failure
}
