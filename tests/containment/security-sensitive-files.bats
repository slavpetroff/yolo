#!/usr/bin/env bats
# security-sensitive-files.bats — Exhaustive sensitive file pattern testing for security-filter.sh

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir
}

# --- Every pattern from security-filter.sh line 23 must be blocked ---

@test "blocks .env" {
  run_with_json '{"tool_input":{"file_path":".env"}}' "$SCRIPTS_DIR/security-filter.sh"
  assert_failure 2
}

@test "blocks .env.local" {
  run_with_json '{"tool_input":{"file_path":".env.local"}}' "$SCRIPTS_DIR/security-filter.sh"
  assert_failure 2
}

@test "blocks .env.production" {
  run_with_json '{"tool_input":{"file_path":".env.production"}}' "$SCRIPTS_DIR/security-filter.sh"
  assert_failure 2
}

@test "blocks server.pem" {
  run_with_json '{"tool_input":{"file_path":"certs/server.pem"}}' "$SCRIPTS_DIR/security-filter.sh"
  assert_failure 2
}

@test "blocks private.key" {
  run_with_json '{"tool_input":{"file_path":"ssl/private.key"}}' "$SCRIPTS_DIR/security-filter.sh"
  assert_failure 2
}

@test "blocks server.cert" {
  run_with_json '{"tool_input":{"file_path":"tls/server.cert"}}' "$SCRIPTS_DIR/security-filter.sh"
  assert_failure 2
}

@test "blocks keystore.p12" {
  run_with_json '{"tool_input":{"file_path":"keys/keystore.p12"}}' "$SCRIPTS_DIR/security-filter.sh"
  assert_failure 2
}

@test "blocks keystore.pfx" {
  run_with_json '{"tool_input":{"file_path":"keys/keystore.pfx"}}' "$SCRIPTS_DIR/security-filter.sh"
  assert_failure 2
}

@test "blocks credentials.json" {
  run_with_json '{"tool_input":{"file_path":"config/credentials.json"}}' "$SCRIPTS_DIR/security-filter.sh"
  assert_failure 2
}

@test "blocks secrets.json" {
  run_with_json '{"tool_input":{"file_path":"config/secrets.json"}}' "$SCRIPTS_DIR/security-filter.sh"
  assert_failure 2
}

@test "blocks service-account-prod.json" {
  run_with_json '{"tool_input":{"file_path":"gcp/service-account-prod.json"}}' "$SCRIPTS_DIR/security-filter.sh"
  assert_failure 2
}

@test "blocks node_modules/" {
  run_with_json '{"tool_input":{"file_path":"node_modules/foo/index.js"}}' "$SCRIPTS_DIR/security-filter.sh"
  assert_failure 2
}

@test "blocks .git/config" {
  run_with_json '{"tool_input":{"file_path":".git/config"}}' "$SCRIPTS_DIR/security-filter.sh"
  assert_failure 2
}

@test "blocks dist/bundle.js" {
  run_with_json '{"tool_input":{"file_path":"dist/bundle.js"}}' "$SCRIPTS_DIR/security-filter.sh"
  assert_failure 2
}

@test "blocks build/output.js" {
  run_with_json '{"tool_input":{"file_path":"build/output.js"}}' "$SCRIPTS_DIR/security-filter.sh"
  assert_failure 2
}

# --- Similar but non-matching paths must be ALLOWED ---

@test "allows environment.ts (not .env)" {
  run_with_json '{"tool_input":{"file_path":"src/environment.ts"}}' "$SCRIPTS_DIR/security-filter.sh"
  assert_success
}

@test "allows package.json (not credentials.json)" {
  run_with_json '{"tool_input":{"file_path":"package.json"}}' "$SCRIPTS_DIR/security-filter.sh"
  assert_success
}

@test "allows src/dist-utils.ts (not dist/)" {
  run_with_json '{"tool_input":{"file_path":"src/dist-utils.ts"}}' "$SCRIPTS_DIR/security-filter.sh"
  assert_success
}
