#!/usr/bin/env bats
# test-token-audit.bats — Unit tests for scripts/token-audit.sh
# Plan 06-04 T4: Ratio calculation, threshold PASS/FAIL, JSON validity, CLI flags

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/token-audit.sh"

  # Create mock config dir with known budgets
  MOCK_ROOT="$TEST_WORKDIR/plugin"
  mkdir -p "$MOCK_ROOT/config"

  # Mock manifest: known budgets for deterministic ratio testing
  # High path total: 100+200+300+400+500+600+700+800+900+1000+1100+1200+1300+1400+1500+1600+1700+1800 = 16200
  cat > "$MOCK_ROOT/config/context-manifest.json" <<'JSON'
{
  "roles": {
    "architect":        { "budget": 500,  "files": [], "artifacts": [], "fields": {} },
    "lead":             { "budget": 300,  "files": [], "artifacts": [], "fields": {} },
    "senior":           { "budget": 400,  "files": [], "artifacts": [], "fields": {} },
    "dev":              { "budget": 200,  "files": [], "artifacts": [], "fields": {} },
    "tester":           { "budget": 300,  "files": [], "artifacts": [], "fields": {} },
    "qa":               { "budget": 200,  "files": [], "artifacts": [], "fields": {} },
    "qa-code":          { "budget": 300,  "files": [], "artifacts": [], "fields": {} },
    "security":         { "budget": 300,  "files": [], "artifacts": [], "fields": {} },
    "critic":           { "budget": 400,  "files": [], "artifacts": [], "fields": {} },
    "scout":            { "budget": 100,  "files": [], "artifacts": [], "fields": {} },
    "owner":            { "budget": 300,  "files": [], "artifacts": [], "fields": {} },
    "debugger":         { "budget": 300,  "files": [], "artifacts": [], "fields": {} },
    "documenter":       { "budget": 200,  "files": [], "artifacts": [], "fields": {} },
    "fe-security":      { "budget": 300,  "files": [], "artifacts": [], "fields": {} },
    "ux-security":      { "budget": 200,  "files": [], "artifacts": [], "fields": {} },
    "fe-documenter":    { "budget": 200,  "files": [], "artifacts": [], "fields": {} },
    "ux-documenter":    { "budget": 200,  "files": [], "artifacts": [], "fields": {} },
    "integration-gate": { "budget": 300,  "files": [], "artifacts": [], "fields": {} },
    "po":               { "budget": 300,  "files": [], "artifacts": [], "fields": {} },
    "questionary":      { "budget": 200,  "files": [], "artifacts": [], "fields": {} },
    "roadmap":          { "budget": 200,  "files": [], "artifacts": [], "fields": {} }
  }
}
JSON
}

# Helper: run SUT with mock plugin root
run_audit() {
  CLAUDE_PLUGIN_ROOT="$MOCK_ROOT" run bash "$SUT" "$@"
}

# --- JSON validity ---

@test "token-audit outputs valid JSON" {
  run_audit
  assert_success
  run jq empty <<< "$output"
  assert_success
}

# --- High path total ---

@test "high_tokens sums all role budgets" {
  run_audit
  assert_success
  local high
  high=$(echo "$output" | jq '.high_tokens')
  # Sum: 500+300+400+200+300+200+300+300+400+100+300+300+200+300+200+200+200+300+300+200+200 = 5700
  [ "$high" -eq 5700 ]
}

# --- Trivial path ---

@test "trivial_tokens includes only senior, dev, owner, debugger" {
  run_audit
  assert_success
  local trivial
  trivial=$(echo "$output" | jq '.trivial_tokens')
  # senior(400) + dev(200) + owner(300) + debugger(300) = 1200
  [ "$trivial" -eq 1200 ]
}

# --- Medium path ---

@test "medium_tokens includes lead, senior, dev, owner, debugger" {
  run_audit
  assert_success
  local medium
  medium=$(echo "$output" | jq '.medium_tokens')
  # lead(300) + senior(400) + dev(200) + owner(300) + debugger(300) = 1500
  [ "$medium" -eq 1500 ]
}

# --- Ratio calculation ---

@test "trivial_ratio is trivial_tokens / high_tokens" {
  run_audit
  assert_success
  local ratio
  ratio=$(echo "$output" | jq '.trivial_ratio')
  # 1200 / 5700 = 0.2105...
  # Check it's between 0.20 and 0.22
  awk "BEGIN {exit !($ratio > 0.20 && $ratio < 0.22)}"
}

@test "medium_ratio is medium_tokens / high_tokens" {
  run_audit
  assert_success
  local ratio
  ratio=$(echo "$output" | jq '.medium_ratio')
  # 1500 / 5700 = 0.2631...
  # Check it's between 0.26 and 0.27
  awk "BEGIN {exit !($ratio > 0.26 && $ratio < 0.27)}"
}

# --- Threshold PASS ---

@test "trivial_pass is true when ratio < 0.30" {
  run_audit
  assert_success
  local pass
  pass=$(echo "$output" | jq '.trivial_pass')
  [ "$pass" = "true" ]
}

@test "medium_pass is true when ratio < 0.60" {
  run_audit
  assert_success
  local pass
  pass=$(echo "$output" | jq '.medium_pass')
  [ "$pass" = "true" ]
}

@test "overall is PASS when both thresholds met" {
  run_audit
  assert_success
  local overall
  overall=$(echo "$output" | jq -r '.overall')
  [ "$overall" = "PASS" ]
}

@test "exit code is 0 when overall PASS" {
  run_audit
  assert_success
}

# --- Threshold FAIL ---

@test "trivial_pass is false when trivial budget is too high" {
  # Override manifest: make trivial roles (senior, dev, owner, debugger) dominate
  cat > "$MOCK_ROOT/config/context-manifest.json" <<'JSON'
{
  "roles": {
    "architect":        { "budget": 10, "files": [], "artifacts": [], "fields": {} },
    "lead":             { "budget": 10, "files": [], "artifacts": [], "fields": {} },
    "senior":           { "budget": 5000, "files": [], "artifacts": [], "fields": {} },
    "dev":              { "budget": 5000, "files": [], "artifacts": [], "fields": {} },
    "tester":           { "budget": 10, "files": [], "artifacts": [], "fields": {} },
    "qa":               { "budget": 10, "files": [], "artifacts": [], "fields": {} },
    "qa-code":          { "budget": 10, "files": [], "artifacts": [], "fields": {} },
    "security":         { "budget": 10, "files": [], "artifacts": [], "fields": {} },
    "critic":           { "budget": 10, "files": [], "artifacts": [], "fields": {} },
    "scout":            { "budget": 10, "files": [], "artifacts": [], "fields": {} },
    "owner":            { "budget": 5000, "files": [], "artifacts": [], "fields": {} },
    "debugger":         { "budget": 5000, "files": [], "artifacts": [], "fields": {} },
    "documenter":       { "budget": 10, "files": [], "artifacts": [], "fields": {} },
    "fe-security":      { "budget": 10, "files": [], "artifacts": [], "fields": {} },
    "ux-security":      { "budget": 10, "files": [], "artifacts": [], "fields": {} },
    "fe-documenter":    { "budget": 10, "files": [], "artifacts": [], "fields": {} },
    "ux-documenter":    { "budget": 10, "files": [], "artifacts": [], "fields": {} },
    "integration-gate": { "budget": 10, "files": [], "artifacts": [], "fields": {} },
    "po":               { "budget": 10, "files": [], "artifacts": [], "fields": {} },
    "questionary":      { "budget": 10, "files": [], "artifacts": [], "fields": {} },
    "roadmap":          { "budget": 10, "files": [], "artifacts": [], "fields": {} }
  }
}
JSON
  # trivial roles: senior(5000)+dev(5000)+owner(5000)+debugger(5000)=20000
  # high total: 20000+170=20170
  # trivial ratio: 20000/20170 = 0.9916 > 0.30 → FAIL
  run_audit
  assert_failure
  local trivial_pass
  trivial_pass=$(echo "$output" | jq '.trivial_pass')
  [ "$trivial_pass" = "false" ]
}

@test "overall is FAIL when a threshold is breached" {
  # Use same high-trivial manifest from previous test
  cat > "$MOCK_ROOT/config/context-manifest.json" <<'JSON'
{
  "roles": {
    "architect":        { "budget": 10, "files": [], "artifacts": [], "fields": {} },
    "lead":             { "budget": 10, "files": [], "artifacts": [], "fields": {} },
    "senior":           { "budget": 5000, "files": [], "artifacts": [], "fields": {} },
    "dev":              { "budget": 5000, "files": [], "artifacts": [], "fields": {} },
    "tester":           { "budget": 10, "files": [], "artifacts": [], "fields": {} },
    "qa":               { "budget": 10, "files": [], "artifacts": [], "fields": {} },
    "qa-code":          { "budget": 10, "files": [], "artifacts": [], "fields": {} },
    "security":         { "budget": 10, "files": [], "artifacts": [], "fields": {} },
    "critic":           { "budget": 10, "files": [], "artifacts": [], "fields": {} },
    "scout":            { "budget": 10, "files": [], "artifacts": [], "fields": {} },
    "owner":            { "budget": 5000, "files": [], "artifacts": [], "fields": {} },
    "debugger":         { "budget": 5000, "files": [], "artifacts": [], "fields": {} },
    "documenter":       { "budget": 10, "files": [], "artifacts": [], "fields": {} },
    "fe-security":      { "budget": 10, "files": [], "artifacts": [], "fields": {} },
    "ux-security":      { "budget": 10, "files": [], "artifacts": [], "fields": {} },
    "fe-documenter":    { "budget": 10, "files": [], "artifacts": [], "fields": {} },
    "ux-documenter":    { "budget": 10, "files": [], "artifacts": [], "fields": {} },
    "integration-gate": { "budget": 10, "files": [], "artifacts": [], "fields": {} },
    "po":               { "budget": 10, "files": [], "artifacts": [], "fields": {} },
    "questionary":      { "budget": 10, "files": [], "artifacts": [], "fields": {} },
    "roadmap":          { "budget": 10, "files": [], "artifacts": [], "fields": {} }
  }
}
JSON
  run_audit
  assert_failure
  local overall
  overall=$(echo "$output" | jq -r '.overall')
  [ "$overall" = "FAIL" ]
}

@test "exit code is 1 when overall FAIL" {
  cat > "$MOCK_ROOT/config/context-manifest.json" <<'JSON'
{
  "roles": {
    "architect":        { "budget": 10, "files": [], "artifacts": [], "fields": {} },
    "lead":             { "budget": 10, "files": [], "artifacts": [], "fields": {} },
    "senior":           { "budget": 5000, "files": [], "artifacts": [], "fields": {} },
    "dev":              { "budget": 5000, "files": [], "artifacts": [], "fields": {} },
    "tester":           { "budget": 10, "files": [], "artifacts": [], "fields": {} },
    "qa":               { "budget": 10, "files": [], "artifacts": [], "fields": {} },
    "qa-code":          { "budget": 10, "files": [], "artifacts": [], "fields": {} },
    "security":         { "budget": 10, "files": [], "artifacts": [], "fields": {} },
    "critic":           { "budget": 10, "files": [], "artifacts": [], "fields": {} },
    "scout":            { "budget": 10, "files": [], "artifacts": [], "fields": {} },
    "owner":            { "budget": 5000, "files": [], "artifacts": [], "fields": {} },
    "debugger":         { "budget": 5000, "files": [], "artifacts": [], "fields": {} },
    "documenter":       { "budget": 10, "files": [], "artifacts": [], "fields": {} },
    "fe-security":      { "budget": 10, "files": [], "artifacts": [], "fields": {} },
    "ux-security":      { "budget": 10, "files": [], "artifacts": [], "fields": {} },
    "fe-documenter":    { "budget": 10, "files": [], "artifacts": [], "fields": {} },
    "ux-documenter":    { "budget": 10, "files": [], "artifacts": [], "fields": {} },
    "integration-gate": { "budget": 10, "files": [], "artifacts": [], "fields": {} },
    "po":               { "budget": 10, "files": [], "artifacts": [], "fields": {} },
    "questionary":      { "budget": 10, "files": [], "artifacts": [], "fields": {} },
    "roadmap":          { "budget": 10, "files": [], "artifacts": [], "fields": {} }
  }
}
JSON
  run_audit
  [ "$status" -eq 1 ]
}

# --- CLI flags ---

@test "--phase flag is reflected in output" {
  run_audit --phase 06
  assert_success
  local phase
  phase=$(echo "$output" | jq -r '.phase')
  [ "$phase" = "06" ]
}

@test "--dry-run prints result without writing" {
  run_audit --dry-run
  assert_success
  assert_output --partial "[dry-run]"
  assert_output --partial "trivial_tokens"
}

@test "--output writes to file" {
  local outfile="$TEST_WORKDIR/audit-result.json"
  run_audit --output "$outfile"
  assert_success
  [ -f "$outfile" ]
  run jq empty "$outfile"
  assert_success
}

@test "--help exits 0 with usage" {
  run_audit --help
  assert_success
  assert_output --partial "Usage:"
}

# --- Error handling ---

@test "exits 2 when manifest not found" {
  CLAUDE_PLUGIN_ROOT="$TEST_WORKDIR/nonexistent" run bash "$SUT"
  [ "$status" -eq 2 ]
}

@test "unknown arg exits 2" {
  run_audit --bogus
  [ "$status" -eq 2 ]
}

# --- Real manifest validation ---

@test "real context-manifest.json passes thresholds" {
  run bash "$SUT"
  assert_success
  local overall
  overall=$(echo "$output" | jq -r '.overall')
  [ "$overall" = "PASS" ]
}
