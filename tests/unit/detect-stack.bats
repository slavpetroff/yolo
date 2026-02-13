#!/usr/bin/env bats
# detect-stack.bats — Unit tests for scripts/detect-stack.sh
# Stack detection for /yolo:init.
# Usage: detect-stack.sh [project-dir]
# Outputs JSON with detected_stack, installed, recommended_skills, suggestions.

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/detect-stack.sh"

  # Override CLAUDE_CONFIG_DIR to avoid picking up real installed skills
  export CLAUDE_CONFIG_DIR="$TEST_WORKDIR/mock-claude"
  mkdir -p "$CLAUDE_CONFIG_DIR/skills"
}

# Helper: run detect-stack against test project dir
run_detect() {
  run bash -c "cd '$TEST_WORKDIR' && CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' bash '$SUT' '$TEST_WORKDIR'"
}

# --- Detects from package.json dependency ---

@test "detects react from package.json dependency" {
  cat > "$TEST_WORKDIR/package.json" <<'EOF'
{
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0"
  }
}
EOF
  run_detect
  assert_success
  echo "$output" | jq -e '.detected_stack | index("react")'
}

# --- Detects from file existence ---

@test "detects next.js from next.config.js file" {
  touch "$TEST_WORKDIR/next.config.js"
  # Also need package.json with react for the react detection
  run_detect
  assert_success
  echo "$output" | jq -e '.detected_stack | index("next")'
}

# --- Handles empty project ---

@test "handles empty project with no stack detected" {
  run_detect
  assert_success
  local count
  count=$(echo "$output" | jq '.detected_stack | length')
  [ "$count" -eq 0 ]
}

# --- Outputs valid JSON ---

@test "outputs valid JSON" {
  run_detect
  assert_success
  echo "$output" | jq . >/dev/null 2>&1
}

# --- Exits 1 on no jq ---

@test "exits 1 when jq is not available" {
  run bash -c "PATH=/usr/bin:/bin && hash -r && command -v jq >/dev/null 2>&1 && skip 'cannot remove jq from PATH' || CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' bash '$SUT' '$TEST_WORKDIR'"
  # If jq IS on the restricted path, the test would skip.
  # If jq is NOT available, it should fail.
  # We simulate by creating a wrapper that hides jq
  local fake_bin="$TEST_WORKDIR/fake-bin"
  mkdir -p "$fake_bin"
  # Copy common utils but not jq
  for cmd in bash cat ls grep sed awk find wc tr cut head tail sort paste mkdir cp rm mv touch chmod printf echo test mktemp dirname basename cd pwd id date; do
    local real
    real=$(which "$cmd" 2>/dev/null) || true
    if [ -n "$real" ] && [ -f "$real" ]; then
      ln -sf "$real" "$fake_bin/$cmd"
    fi
  done
  run bash -c "export PATH='$fake_bin' && CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' bash '$SUT' '$TEST_WORKDIR'"
  assert_failure
}

# --- Exits 1 on no stack-mappings.json ---

@test "exits 1 when stack-mappings.json is missing" {
  # Run the script from a temp copy with missing config
  local fake_scripts="$TEST_WORKDIR/fake-scripts"
  mkdir -p "$fake_scripts"
  cp "$SUT" "$fake_scripts/detect-stack.sh"
  # The script looks for ../config/stack-mappings.json relative to itself
  # Since there is no config/ dir next to fake-scripts/, it will fail
  run bash -c "CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' bash '$fake_scripts/detect-stack.sh' '$TEST_WORKDIR'"
  assert_failure
}

# --- Identifies installed skills ---

@test "identifies installed global skills" {
  mkdir -p "$CLAUDE_CONFIG_DIR/skills/react-skill"
  touch "$TEST_WORKDIR/package.json"
  echo '{"dependencies":{"react":"^18"}}' > "$TEST_WORKDIR/package.json"
  run_detect
  assert_success
  echo "$output" | jq -e '.installed.global | index("react-skill")'
}

# --- Computes suggestions (recommended minus installed) ---

@test "computes suggestions as recommended minus installed" {
  echo '{"dependencies":{"react":"^18"}}' > "$TEST_WORKDIR/package.json"
  # react maps to react-skill — do NOT install it
  run_detect
  assert_success
  echo "$output" | jq -e '.suggestions | index("react-skill")'
}

@test "suggestions exclude already-installed skills" {
  echo '{"dependencies":{"react":"^18"}}' > "$TEST_WORKDIR/package.json"
  # Install the react skill
  mkdir -p "$CLAUDE_CONFIG_DIR/skills/react-skill"
  run_detect
  assert_success
  # react-skill should NOT be in suggestions since it's installed
  local count
  count=$(echo "$output" | jq '[.suggestions[] | select(. == "react-skill")] | length')
  [ "$count" -eq 0 ]
}

# --- Detects multiple stacks ---

@test "detects multiple stacks simultaneously" {
  cat > "$TEST_WORKDIR/package.json" <<'EOF'
{
  "dependencies": {
    "react": "^18",
    "express": "^4"
  }
}
EOF
  touch "$TEST_WORKDIR/tsconfig.json"
  run_detect
  assert_success
  echo "$output" | jq -e '.detected_stack | index("react")'
  echo "$output" | jq -e '.detected_stack | index("express")'
  echo "$output" | jq -e '.detected_stack | index("typescript")'
}
