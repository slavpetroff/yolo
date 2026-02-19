#!/usr/bin/env bats
# validate-plan.bats — Unit tests for validate.sh --type plan
# Validates plan.jsonl structure: header keys, task keys, circular deps, paths.
# Note: validate-plan.sh was consolidated into validate.sh --type plan

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/validate.sh"
}

# Helper: create a valid plan.jsonl with header + 2 tasks
mk_valid_plan() {
  local file="$TEST_WORKDIR/valid-plan.jsonl"
  cat > "$file" <<'JSONL'
{"p":"03","n":"01","t":"Test Plan","w":1,"d":[],"mh":{"tr":["test"],"ar":[],"kl":[]},"obj":"Test objective","sk":["commit"],"fm":["src/test.sh"],"auto":true}
{"id":"T1","tp":"auto","a":"Create file","f":["src/test.sh"],"v":"file exists","done":"File created","spec":"Create src/test.sh"}
{"id":"T2","tp":"auto","a":"Update file","f":["src/test.sh"],"v":"updated","done":"File updated","spec":"Update src/test.sh"}
JSONL
  echo "$file"
}

@test "valid plan passes validation" {
  local plan_file
  plan_file=$(mk_valid_plan)
  run bash "$SUT" --type plan "$plan_file"
  assert_success
  local valid
  valid=$(echo "$output" | jq -r '.valid')
  [ "$valid" = "true" ]
  local err_count
  err_count=$(echo "$output" | jq '.errors | length')
  [ "$err_count" -eq 0 ]
}

@test "missing header key p fails" {
  local file="$TEST_WORKDIR/missing-p.jsonl"
  cat > "$file" <<'JSONL'
{"n":"01","t":"Test","w":1,"d":[],"mh":{},"obj":"Test"}
{"id":"T1","tp":"auto","a":"test","f":["src/a.sh"],"v":"ok","done":"ok"}
JSONL
  run bash "$SUT" --type plan "$file"
  assert_failure
  assert_output --partial "missing required key"
}

@test "missing task key id fails" {
  local file="$TEST_WORKDIR/missing-id.jsonl"
  cat > "$file" <<'JSONL'
{"p":"03","n":"01","t":"Test","w":1,"d":[],"mh":{},"obj":"Test"}
{"tp":"auto","a":"test","f":["src/a.sh"],"v":"ok","done":"ok"}
JSONL
  run bash "$SUT" --type plan "$file"
  assert_failure
  assert_output --partial "missing required key: id"
}

@test "circular self-dependency detected" {
  local file="$TEST_WORKDIR/circular.jsonl"
  cat > "$file" <<'JSONL'
{"p":"03","n":"01","t":"Test","w":1,"d":["03-01"],"mh":{},"obj":"Test"}
{"id":"T1","tp":"auto","a":"test","f":["src/a.sh"],"v":"ok","done":"ok"}
JSONL
  run bash "$SUT" --type plan "$file"
  assert_failure
  assert_output --partial "Circular dependency"
}

@test "absolute path in task f field fails" {
  local file="$TEST_WORKDIR/abspath.jsonl"
  cat > "$file" <<'JSONL'
{"p":"03","n":"01","t":"Test","w":1,"d":[],"mh":{},"obj":"Test"}
{"id":"T1","tp":"auto","a":"test","f":["/usr/local/bin/foo"],"v":"ok","done":"ok"}
JSONL
  run bash "$SUT" --type plan "$file"
  assert_failure
  assert_output --partial "absolute path"
}

@test "empty file fails" {
  local file="$TEST_WORKDIR/empty.jsonl"
  touch "$file"
  run bash "$SUT" --type plan "$file"
  assert_failure
}

@test "non-JSON content fails" {
  local file="$TEST_WORKDIR/nonjson.jsonl"
  echo "this is not json" > "$file"
  run bash "$SUT" --type plan "$file"
  assert_failure
}

@test "header-only plan (no tasks) passes" {
  local file="$TEST_WORKDIR/header-only.jsonl"
  cat > "$file" <<'JSONL'
{"p":"03","n":"01","t":"Test","w":1,"d":[],"mh":{},"obj":"Test"}
JSONL
  run bash "$SUT" --type plan "$file"
  assert_success
  local valid
  valid=$(echo "$output" | jq -r '.valid')
  [ "$valid" = "true" ]
}

# --- Integration tests: validate.sh --type plan + naming validation ---

@test "validate.sh --type plan still passes valid plan after naming integration" {
  local plan_file
  plan_file=$(mk_valid_plan)
  run bash "$SUT" --type plan "$plan_file"
  assert_success
}

@test "validate.sh --type plan catches compound p field via naming validation" {
  local file="$TEST_WORKDIR/01-01.plan.jsonl"
  cat > "$file" <<'JSONL'
{"p":"01-01","n":"01","t":"Test Plan","w":1,"d":[],"mh":{"tr":["test"],"ar":[],"kl":[]},"obj":"Test"}
{"id":"T1","tp":"auto","a":"test","f":["src/a.sh"],"v":"ok","done":"ok"}
JSONL
  run bash "$SUT" --type plan "$file"
  assert_failure
  assert_output --partial 'Naming:'
  assert_output --partial 'compound'
}

@test "validate.sh --type plan catches title in n field via naming validation" {
  local file="$TEST_WORKDIR/01-01.plan.jsonl"
  cat > "$file" <<'JSONL'
{"p":"01","n":"Create auth","t":"Test Plan","w":1,"d":[],"mh":{"tr":["test"],"ar":[],"kl":[]},"obj":"Test"}
{"id":"T1","tp":"auto","a":"test","f":["src/a.sh"],"v":"ok","done":"ok"}
JSONL
  run bash "$SUT" --type plan "$file"
  assert_failure
  assert_output --partial 'Naming:'
}

@test "validate.sh --type plan includes naming validation by default" {
  # Naming validation is now bundled in validate.sh (no separate script)
  # Verify a valid plan passes both structural and naming checks
  local plan_file
  plan_file=$(mk_valid_plan)
  run bash "$SUT" --type plan "$plan_file"
  assert_success
  local valid
  valid=$(echo "$output" | jq -r '.valid')
  [ "$valid" = "true" ]
}
