#!/usr/bin/env bats
# security-filter.bats — Unit tests for scripts/security-filter.sh
# PreToolUse hook, fail-CLOSED (exit 2 on any error)

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir
  mk_planning_dir
  SUT="$SCRIPTS_DIR/security-filter.sh"
}

# --- Sensitive file blocking ---

@test "blocks .env file" {
  run bash -c "echo '{\"tool_input\":{\"file_path\":\".env\"}}' | bash '$SUT'"
  assert_failure 2
}

@test "blocks .env.local file" {
  run bash -c "echo '{\"tool_input\":{\"file_path\":\".env.local\"}}' | bash '$SUT'"
  assert_failure 2
}

@test "blocks .pem file" {
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"server.pem\"}}' | bash '$SUT'"
  assert_failure 2
}

@test "blocks .key file" {
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"private.key\"}}' | bash '$SUT'"
  assert_failure 2
}

@test "blocks .cert file" {
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"tls.cert\"}}' | bash '$SUT'"
  assert_failure 2
}

@test "blocks .p12 file" {
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"keystore.p12\"}}' | bash '$SUT'"
  assert_failure 2
}

@test "blocks .pfx file" {
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"cert.pfx\"}}' | bash '$SUT'"
  assert_failure 2
}

@test "blocks credentials.json" {
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"credentials.json\"}}' | bash '$SUT'"
  assert_failure 2
}

@test "blocks secrets.json" {
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"config/secrets.json\"}}' | bash '$SUT'"
  assert_failure 2
}

@test "blocks service-account JSON files" {
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"service-account-prod.json\"}}' | bash '$SUT'"
  assert_failure 2
}

@test "blocks node_modules/ path" {
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"node_modules/express/index.js\"}}' | bash '$SUT'"
  assert_failure 2
}

@test "blocks .git/ path" {
  run bash -c "echo '{\"tool_input\":{\"file_path\":\".git/config\"}}' | bash '$SUT'"
  assert_failure 2
}

@test "blocks dist/ and build/ paths" {
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"dist/bundle.js\"}}' | bash '$SUT'"
  assert_failure 2

  run bash -c "echo '{\"tool_input\":{\"file_path\":\"build/output.js\"}}' | bash '$SUT'"
  assert_failure 2
}

# --- Isolation: .planning/ blocked when YOLO markers present ---

@test "blocks .planning/ when .active-agent marker exists" {
  mk_active_agent
  run bash -c "echo '{\"tool_input\":{\"file_path\":\".planning/intel/map.json\"}}' | bash '$SUT'"
  assert_failure 2
}

@test "blocks .planning/ when .yolo-session marker exists" {
  mk_yolo_session
  run bash -c "echo '{\"tool_input\":{\"file_path\":\".planning/intel/map.json\"}}' | bash '$SUT'"
  assert_failure 2
}

# --- Isolation: .yolo-planning/ with GSD isolation ---

@test "blocks .yolo-planning/ when .gsd-isolation set and no YOLO markers" {
  mk_gsd_isolation
  run bash -c "echo '{\"tool_input\":{\"file_path\":\".yolo-planning/state.json\"}}' | bash '$SUT'"
  assert_failure 2
}

@test "allows .yolo-planning/ when .gsd-isolation AND .active-agent present" {
  mk_gsd_isolation
  mk_active_agent
  run bash -c "echo '{\"tool_input\":{\"file_path\":\".yolo-planning/state.json\"}}' | bash '$SUT'"
  assert_success
}

@test "allows .yolo-planning/ when .gsd-isolation AND .yolo-session present" {
  mk_gsd_isolation
  mk_yolo_session
  run bash -c "echo '{\"tool_input\":{\"file_path\":\".yolo-planning/state.json\"}}' | bash '$SUT'"
  assert_success
}

# --- Fail-closed on bad input ---

@test "exits 2 on empty stdin" {
  run bash -c "echo -n '' | bash '$SUT'"
  assert_failure 2
}

@test "exits 2 when file_path is missing from JSON" {
  run bash -c "echo '{\"tool_input\":{\"content\":\"hello\"}}' | bash '$SUT'"
  assert_failure 2
}

@test "exits 2 on malformed JSON" {
  run bash -c "echo 'not json at all' | bash '$SUT'"
  assert_failure 2
}

# --- Allow safe files ---

@test "allows normal source file" {
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"src/index.ts\"}}' | bash '$SUT'"
  assert_success
}
