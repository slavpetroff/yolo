#!/usr/bin/env bats
# filter-agent-context.bats -- Unit tests for scripts/filter-agent-context.sh
# Role-based JSONL field filtering for agent context optimization (REQ-04).
# Usage: bats tests/unit/filter-agent-context.bats

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/filter-agent-context.sh"
  FIXTURE_DIR="$FIXTURES_DIR/filter-context"
}

# Helper: run the filter script
run_filter() {
  run bash "$SUT" "$@"
}

# --- Usage and error handling (4 tests) ---

@test 'exits 1 with usage when no args' {
  run_filter
  assert_failure
  assert_output --partial 'Usage'
}

@test 'exits 1 when artifact file missing' {
  run_filter --role dev --artifact /nonexistent/file.jsonl --type plan
  assert_failure
  assert_output --partial 'artifact not found'
}

@test 'exits 1 for unknown role' {
  run_filter --role unknown-role --artifact "$FIXTURE_DIR/sample-plan.jsonl" --type plan
  assert_failure
  assert_output --partial 'unknown role'
}

@test 'exits 1 for unknown artifact type' {
  run_filter --role dev --artifact "$FIXTURE_DIR/sample-plan.jsonl" --type unknown
  assert_failure
  assert_output --partial 'unknown artifact type'
}

# --- dev + plan.jsonl (3 tests) ---

@test 'dev+plan returns only task fields id,a,f,spec,ts,done' {
  run_filter --role dev --artifact "$FIXTURE_DIR/sample-plan.jsonl" --type plan
  assert_success
  # Output should have 2 lines (tasks only, no header)
  local line_count
  line_count=$(echo "$output" | wc -l | tr -d ' ')
  assert [ "$line_count" -eq 2 ]
  # First task should have id, a, f, spec, ts, done
  echo "$output" | head -1 | jq -e '.id == "T1"'
  echo "$output" | head -1 | jq -e '.spec == "Create src/foo.ts with default export"'
  echo "$output" | head -1 | jq -e '.ts == "Test foo.ts exports"'
  # Should NOT have v, tp fields
  echo "$output" | head -1 | jq -e 'has("v") | not'
  echo "$output" | head -1 | jq -e 'has("tp") | not'
}

@test 'dev+plan does not include header line' {
  run_filter --role dev --artifact "$FIXTURE_DIR/sample-plan.jsonl" --type plan
  assert_success
  # No output line should have 'obj' field (header field)
  refute_output --partial '"obj"'
}

@test 'fe-dev+plan returns same as dev (prefix stripping)' {
  run_filter --role fe-dev --artifact "$FIXTURE_DIR/sample-plan.jsonl" --type plan
  assert_success
  echo "$output" | head -1 | jq -e '.id == "T1"'
  echo "$output" | head -1 | jq -e 'has("v") | not'
}

# --- qa + plan.jsonl (2 tests) ---

@test 'qa+plan returns only header mh,obj' {
  run_filter --role qa --artifact "$FIXTURE_DIR/sample-plan.jsonl" --type plan
  assert_success
  # Should be 1 line (header only)
  local line_count
  line_count=$(echo "$output" | wc -l | tr -d ' ')
  assert [ "$line_count" -eq 1 ]
  echo "$output" | jq -e '.obj == "Test objective"'
  echo "$output" | jq -e '.mh.tr[0] == "test passes"'
  # Should NOT have p, n, t, w fields
  echo "$output" | jq -e 'has("p") | not'
}

@test 'qa+summary returns s,tc,tt,fm,dv,tst' {
  run_filter --role qa --artifact "$FIXTURE_DIR/sample-summary.jsonl" --type summary
  assert_success
  echo "$output" | jq -e '.s == "complete"'
  echo "$output" | jq -e '.tc == 2'
  echo "$output" | jq -e '.tst == "green_only"'
  # Should NOT have p, n, ch, built
  echo "$output" | jq -e 'has("ch") | not'
  echo "$output" | jq -e 'has("built") | not'
}

# --- security + summary.jsonl (1 test) ---

@test 'security+summary returns only fm' {
  run_filter --role security --artifact "$FIXTURE_DIR/sample-summary.jsonl" --type summary
  assert_success
  echo "$output" | jq -e '.fm[0] == "src/foo.ts"'
  echo "$output" | jq -e '.fm[1] == "src/bar.ts"'
  # Should NOT have s, tc, tt, etc.
  echo "$output" | jq -e 'has("s") | not'
  echo "$output" | jq -e 'has("tc") | not'
}

# --- architect + critique.jsonl (2 tests) ---

@test 'architect+critique returns all 7 critique fields' {
  run_filter --role architect --artifact "$FIXTURE_DIR/sample-critique.jsonl" --type critique
  assert_success
  # Should have 3 lines (all findings, no severity filter for architect)
  local line_count
  line_count=$(echo "$output" | wc -l | tr -d ' ')
  assert [ "$line_count" -eq 3 ]
  echo "$output" | head -1 | jq -e '.id == "C1"'
  echo "$output" | head -1 | jq -e '.sev == "critical"'
  echo "$output" | head -1 | jq -e '.sug == "Add express-jwt"'
}

@test 'architect+critique includes all severity levels' {
  run_filter --role architect --artifact "$FIXTURE_DIR/sample-critique.jsonl" --type critique
  assert_success
  assert_output --partial '"C3"'  # minor finding included for architect
}

# --- scout + critique.jsonl (2 tests) ---

@test 'scout+critique returns only critical and major (not minor)' {
  run_filter --role scout --artifact "$FIXTURE_DIR/sample-critique.jsonl" --type critique
  assert_success
  # Should have 2 lines (critical + major, NOT minor)
  local line_count
  line_count=$(echo "$output" | wc -l | tr -d ' ')
  assert [ "$line_count" -eq 2 ]
  echo "$output" | head -1 | jq -e '.id == "C1"'
  echo "$output" | tail -1 | jq -e '.id == "C2"'
  refute_output --partial '"C3"'  # minor excluded
}

@test 'scout+critique returns only id,sev,q fields' {
  run_filter --role scout --artifact "$FIXTURE_DIR/sample-critique.jsonl" --type critique
  assert_success
  echo "$output" | head -1 | jq -e '.q == "Missing auth middleware"'
  echo "$output" | head -1 | jq -e 'has("cat") | not'
  echo "$output" | head -1 | jq -e 'has("ctx") | not'
  echo "$output" | head -1 | jq -e 'has("sug") | not'
}

# --- lead + plan.jsonl (1 test) ---

@test 'lead+plan returns header (all fields) plus filtered tasks' {
  run_filter --role lead --artifact "$FIXTURE_DIR/sample-plan.jsonl" --type plan
  assert_success
  # Should have 3 lines: 1 header + 2 tasks
  local line_count
  line_count=$(echo "$output" | wc -l | tr -d ' ')
  assert [ "$line_count" -eq 3 ]
  # Header line has all fields
  echo "$output" | head -1 | jq -e '.p == "01"'
  echo "$output" | head -1 | jq -e '.obj == "Test objective"'
  # Task lines have only id, a, f, done, v
  echo "$output" | sed -n '2p' | jq -e '.id == "T1"'
  echo "$output" | sed -n '2p' | jq -e '.v == "module exports"'
  echo "$output" | sed -n '2p' | jq -e 'has("spec") | not'
  echo "$output" | sed -n '2p' | jq -e 'has("ts") | not'
}

# --- senior + plan.jsonl (2 tests) ---

@test 'senior+plan design mode returns tasks with id,a,f,done,v' {
  run_filter --role senior --artifact "$FIXTURE_DIR/sample-plan.jsonl" --type plan
  assert_success
  echo "$output" | head -1 | jq -e '.id == "T1"'
  echo "$output" | head -1 | jq -e '.v == "module exports"'
  echo "$output" | head -1 | jq -e 'has("spec") | not'
}

@test 'senior+plan review mode returns tasks with id,a,f,spec,ts,done' {
  run_filter --role senior --artifact "$FIXTURE_DIR/sample-plan.jsonl" --type plan --mode review
  assert_success
  echo "$output" | head -1 | jq -e '.id == "T1"'
  echo "$output" | head -1 | jq -e '.spec == "Create src/foo.ts with default export"'
  echo "$output" | head -1 | jq -e 'has("v") | not'
}

# --- senior + critique.jsonl (1 test) ---

@test 'senior+critique returns only open findings with id,q,sug' {
  run_filter --role senior --artifact "$FIXTURE_DIR/sample-critique.jsonl" --type critique
  assert_success
  # Only C1 and C2 are st=open; C3 is st=addressed
  local line_count
  line_count=$(echo "$output" | wc -l | tr -d ' ')
  assert [ "$line_count" -eq 2 ]
  echo "$output" | head -1 | jq -e '.id == "C1"'
  echo "$output" | head -1 | jq -e 'has("sev") | not'  # only id, q, sug
  echo "$output" | head -1 | jq -e '.q == "Missing auth middleware"'  # verify value not null
  echo "$output" | head -1 | jq -e '.sug == "Add express-jwt"'  # verify value not null
}

# --- tester + plan.jsonl (1 test) ---

@test 'tester+plan returns tasks with id,a,f,ts,spec' {
  run_filter --role tester --artifact "$FIXTURE_DIR/sample-plan.jsonl" --type plan
  assert_success
  echo "$output" | head -1 | jq -e '.id == "T1"'
  echo "$output" | head -1 | jq -e '.ts == "Test foo.ts exports"'
  echo "$output" | head -1 | jq -e '.spec == "Create src/foo.ts with default export"'
  echo "$output" | head -1 | jq -e 'has("v") | not'
  echo "$output" | head -1 | jq -e 'has("done") | not'
}

# --- role + wrong artifact type (1 test) ---

@test 'dev+summary returns error (dev does not consume summary)' {
  run_filter --role dev --artifact "$FIXTURE_DIR/sample-summary.jsonl" --type summary
  assert_failure
  assert_output --partial 'does not consume'
}

# --- owner + plan.jsonl (1 test) ---

@test 'owner+plan returns only header (all fields)' {
  run_filter --role owner --artifact "$FIXTURE_DIR/sample-plan.jsonl" --type plan
  assert_success
  local line_count
  line_count=$(echo "$output" | wc -l | tr -d ' ')
  assert [ "$line_count" -eq 1 ]
  echo "$output" | jq -e '.p == "01"'
  echo "$output" | jq -e '.obj == "Test objective"'
}

# --- debugger + summary (1 test) ---

@test 'debugger+summary returns fm,ch,dv' {
  run_filter --role debugger --artifact "$FIXTURE_DIR/sample-summary.jsonl" --type summary
  assert_success
  echo "$output" | jq -e '.fm[0] == "src/foo.ts"'
  echo "$output" | jq -e '.ch[0] == "abc123"'
  echo "$output" | jq -e 'has("s") | not'
  echo "$output" | jq -e 'has("tc") | not'
}
