#!/usr/bin/env bats
# validate-naming.bats -- Unit tests for scripts/validate-naming.sh
# Validates artifact naming conventions: plan headers, task keys, summaries, reqs.

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/validate-naming.sh"
}

# --- Helpers ---

mk_valid_named_plan() {
  local file="$1"
  cat > "$file" <<'JSONL'
{"p":"03","n":"01","t":"Test Plan","w":1,"d":[],"mh":{"tr":["test"],"ar":[],"kl":[]},"obj":"Test objective"}
{"id":"T1","tp":"auto","a":"Create file","f":["src/test.sh"],"v":"file exists","done":"Created"}
JSONL
}

mk_valid_summary() {
  local file="$1"
  echo '{"p":"01","n":"01","t":"Test","s":"complete","dt":"2026-02-17","tc":3,"tt":3,"ch":["abc123"],"fm":["src/a.sh"],"dv":[],"built":["feature"],"tst":"red_green"}' > "$file"
}

mk_turbo_plan() {
  local file="$1"
  cat > "$file" <<'JSONL'
{"p":"01","n":"01","t":"Quick fix","w":1,"d":[],"obj":"Fix bug","eff":"turbo"}
{"id":"T1","a":"Fix the bug","f":["src/fix.sh"],"v":"bug gone","done":"Fixed"}
JSONL
}

# ===== T1 scope: plan validation (tests 1-10) =====

@test "(1) valid canonical plan passes naming validation" {
  local file="$TEST_WORKDIR/03-01.plan.jsonl"
  mk_valid_named_plan "$file"
  run bash "$SUT" "$file"
  assert_success
  local valid
  valid=$(echo "$output" | jq -r '.valid')
  [ "$valid" = "true" ]
}

@test "(2) plan with compound p field fails" {
  local file="$TEST_WORKDIR/01-01.plan.jsonl"
  cat > "$file" <<'JSONL'
{"p":"01-01","n":"01","t":"Test Plan","w":1,"d":[],"mh":{"tr":["test"],"ar":[],"kl":[]},"obj":"Test"}
{"id":"T1","tp":"auto","a":"Create file","f":["src/test.sh"],"v":"ok","done":"ok"}
JSONL
  run bash "$SUT" "$file"
  assert_failure
  assert_output --partial 'compound'
}

@test "(3) plan with title string in n field fails" {
  local file="$TEST_WORKDIR/01-01.plan.jsonl"
  cat > "$file" <<'JSONL'
{"p":"01","n":"Create auth","t":"Test Plan","w":1,"d":[],"mh":{"tr":["test"],"ar":[],"kl":[]},"obj":"Test"}
{"id":"T1","tp":"auto","a":"test","f":["src/a.sh"],"v":"ok","done":"ok"}
JSONL
  run bash "$SUT" "$file"
  assert_failure
  assert_output --partial 'not a plan number'
}

@test "(4) plan with number in t field fails" {
  local file="$TEST_WORKDIR/01-01.plan.jsonl"
  cat > "$file" <<'JSONL'
{"p":"01","n":"01","t":"3","w":1,"d":[],"mh":{"tr":["test"],"ar":[],"kl":[]},"obj":"Test"}
{"id":"T1","tp":"auto","a":"test","f":["src/a.sh"],"v":"ok","done":"ok"}
JSONL
  run bash "$SUT" "$file"
  assert_failure
  assert_output --partial 'must be title string'
}

@test "(5) plan task missing tp key fails" {
  local file="$TEST_WORKDIR/01-01.plan.jsonl"
  cat > "$file" <<'JSONL'
{"p":"01","n":"01","t":"Test Plan","w":1,"d":[],"mh":{"tr":["test"],"ar":[],"kl":[]},"obj":"Test"}
{"id":"T1","a":"test","f":["src/a.sh"],"v":"ok","done":"ok"}
JSONL
  run bash "$SUT" "$file"
  assert_failure
  assert_output --partial 'missing required key: tp'
}

@test "(6) plan task using legacy key n instead of a fails" {
  local file="$TEST_WORKDIR/01-01.plan.jsonl"
  cat > "$file" <<'JSONL'
{"p":"01","n":"01","t":"Test Plan","w":1,"d":[],"mh":{"tr":["test"],"ar":[],"kl":[]},"obj":"Test"}
{"id":"T1","tp":"auto","n":"action","f":["src/a.sh"],"v":"ok","done":"ok"}
JSONL
  run bash "$SUT" "$file"
  assert_failure
  assert_output --partial 'legacy key'
}

@test "(7) file name vs header mismatch detected" {
  local file="$TEST_WORKDIR/02-01.plan.jsonl"
  cat > "$file" <<'JSONL'
{"p":"03","n":"01","t":"Test Plan","w":1,"d":[],"mh":{"tr":["test"],"ar":[],"kl":[]},"obj":"Test"}
{"id":"T1","tp":"auto","a":"test","f":["src/a.sh"],"v":"ok","done":"ok"}
JSONL
  run bash "$SUT" "$file"
  assert_failure
  assert_output --partial 'does not match'
}

@test "(8) turbo plan without mh passes with --turbo flag" {
  local file="$TEST_WORKDIR/01-01.plan.jsonl"
  cat > "$file" <<'JSONL'
{"p":"01","n":"01","t":"Quick fix","w":1,"d":[],"obj":"Fix bug","eff":"turbo"}
{"id":"T1","a":"Fix the bug","f":["src/fix.sh"],"v":"bug gone","done":"Fixed"}
JSONL
  run bash "$SUT" "$file" --turbo
  assert_success
}

@test "(9) turbo auto-detection works when eff:turbo in header" {
  local file="$TEST_WORKDIR/01-01.plan.jsonl"
  mk_turbo_plan "$file"
  run bash "$SUT" "$file"
  assert_success
}

@test "(10) absolute path in task f field fails" {
  local file="$TEST_WORKDIR/01-01.plan.jsonl"
  cat > "$file" <<'JSONL'
{"p":"01","n":"01","t":"Test Plan","w":1,"d":[],"mh":{"tr":["test"],"ar":[],"kl":[]},"obj":"Test"}
{"id":"T1","tp":"auto","a":"test","f":["/usr/local/bin/foo"],"v":"ok","done":"ok"}
JSONL
  run bash "$SUT" "$file"
  assert_failure
  assert_output --partial 'absolute path'
}

# ===== T2 scope: summary + reqs validation (tests 11-20) =====

@test "(11) valid canonical summary passes" {
  local file="$TEST_WORKDIR/01-01.summary.jsonl"
  mk_valid_summary "$file"
  run bash "$SUT" "$file"
  assert_success
}

@test "(12) summary with legacy commits key fails" {
  local file="$TEST_WORKDIR/01-01.summary.jsonl"
  echo '{"p":"01","n":"01","t":"Test","s":"complete","dt":"2026-02-17","tc":3,"tt":3,"commits":["abc123"],"fm":["src/a.sh"],"dv":[],"built":["feature"],"tst":"red_green"}' > "$file"
  run bash "$SUT" "$file"
  assert_failure
  assert_output --partial "legacy key 'commits'"
}

@test "(13) summary with legacy tasks key fails" {
  local file="$TEST_WORKDIR/01-01.summary.jsonl"
  echo '{"p":"01","n":"01","t":"Test","s":"complete","dt":"2026-02-17","tasks":3,"tt":3,"ch":["abc123"],"fm":["src/a.sh"],"dv":[],"built":["feature"],"tst":"red_green"}' > "$file"
  run bash "$SUT" "$file"
  assert_failure
  assert_output --partial "legacy key 'tasks'"
}

@test "(14) summary with legacy dev key fails" {
  local file="$TEST_WORKDIR/01-01.summary.jsonl"
  echo '{"p":"01","n":"01","t":"Test","s":"complete","dt":"2026-02-17","tc":3,"tt":3,"ch":["abc123"],"fm":["src/a.sh"],"dev":[],"built":["feature"],"tst":"red_green"}' > "$file"
  run bash "$SUT" "$file"
  assert_failure
  assert_output --partial "legacy key 'dev'"
}

@test "(15) summary missing required key dt fails" {
  local file="$TEST_WORKDIR/01-01.summary.jsonl"
  echo '{"p":"01","n":"01","t":"Test","s":"complete","tc":3,"tt":3,"ch":["abc123"],"fm":["src/a.sh"],"dv":[],"built":["feature"],"tst":"red_green"}' > "$file"
  run bash "$SUT" "$file"
  assert_failure
  assert_output --partial 'missing required key: dt'
}

@test "(16) summary with invalid tst enum fails" {
  local file="$TEST_WORKDIR/01-01.summary.jsonl"
  echo '{"p":"01","n":"01","t":"Test","s":"complete","dt":"2026-02-17","tc":3,"tt":3,"ch":["abc123"],"fm":["src/a.sh"],"dv":[],"built":["feature"],"tst":"manual"}' > "$file"
  run bash "$SUT" "$file"
  assert_failure
  assert_output --partial 'not valid'
}

@test "(17) summary with compound p field fails" {
  local file="$TEST_WORKDIR/01-01.summary.jsonl"
  echo '{"p":"01-01","n":"01","t":"Test","s":"complete","dt":"2026-02-17","tc":3,"tt":3,"ch":["abc123"],"fm":["src/a.sh"],"dv":[],"built":["feature"],"tst":"red_green"}' > "$file"
  run bash "$SUT" "$file"
  assert_failure
  assert_output --partial 'compound'
}

@test "(18) summary file name mismatch detected" {
  local file="$TEST_WORKDIR/02-01.summary.jsonl"
  echo '{"p":"01","n":"01","t":"Test","s":"complete","dt":"2026-02-17","tc":3,"tt":3,"ch":["abc123"],"fm":["src/a.sh"],"dv":[],"built":["feature"],"tst":"red_green"}' > "$file"
  run bash "$SUT" "$file"
  assert_failure
  assert_output --partial 'does not match'
}

@test "(19) reqs with legacy p key instead of pri fails" {
  local file="$TEST_WORKDIR/reqs.jsonl"
  echo '{"id":"REQ-01","t":"test","p":"must"}' > "$file"
  run bash "$SUT" "$file" --type=reqs
  assert_failure
  assert_output --partial "legacy key 'p'"
}

@test "(20) valid reqs passes" {
  local file="$TEST_WORKDIR/reqs.jsonl"
  echo '{"id":"REQ-01","t":"test","pri":"must","st":"open","ac":"criteria"}' > "$file"
  run bash "$SUT" "$file"
  assert_success
}

# ===== Additional tests: scope, turbo, drift (tests 21-26) =====

@test "(21) directory mode validates all plan files" {
  local dir="$TEST_WORKDIR/phase-dir"
  mkdir -p "$dir"
  # One valid plan
  mk_valid_named_plan "$dir/03-01.plan.jsonl"
  # One plan with compound p
  cat > "$dir/01-01.plan.jsonl" <<'JSONL'
{"p":"01-01","n":"01","t":"Bad Plan","w":1,"d":[],"mh":{"tr":["test"],"ar":[],"kl":[]},"obj":"Test"}
{"id":"T1","tp":"auto","a":"test","f":["src/a.sh"],"v":"ok","done":"ok"}
JSONL
  run bash "$SUT" "$dir"
  assert_failure
}

@test "(22) --scope=active skips milestones directory" {
  local dir="$TEST_WORKDIR/.yolo-planning/phases/01-test"
  mkdir -p "$dir"
  mk_valid_named_plan "$dir/01-01.plan.jsonl"
  # Fix header to match filename
  cat > "$dir/01-01.plan.jsonl" <<'JSONL'
{"p":"01","n":"01","t":"Test Plan","w":1,"d":[],"mh":{"tr":["test"],"ar":[],"kl":[]},"obj":"Test"}
{"id":"T1","tp":"auto","a":"Create file","f":["src/test.sh"],"v":"file exists","done":"Created"}
JSONL
  # Create milestones with legacy naming
  local ms_dir="$TEST_WORKDIR/.yolo-planning/milestones/old/01-old"
  mkdir -p "$ms_dir"
  cat > "$ms_dir/01-01.plan.jsonl" <<'JSONL'
{"p":"01-01","n":"Legacy","t":"3","w":1,"d":[],"mh":{},"obj":"Test"}
{"id":"T1","n":"test","f":["src/a.sh"],"d":"desc","ac":"ok"}
JSONL
  run bash "$SUT" "$dir" --scope=active
  assert_success
}

@test "(23) --scope=all includes milestones as warnings" {
  # Set up: .yolo-planning/phases/01-test/ (scan target)
  #         .yolo-planning/milestones/old/ (milestone files)
  local dir="$TEST_WORKDIR/.yolo-planning/phases/01-test"
  mkdir -p "$dir"
  cat > "$dir/01-01.plan.jsonl" <<'JSONL'
{"p":"01","n":"01","t":"Test Plan","w":1,"d":[],"mh":{"tr":["test"],"ar":[],"kl":[]},"obj":"Test"}
{"id":"T1","tp":"auto","a":"Create file","f":["src/test.sh"],"v":"file exists","done":"Created"}
JSONL
  # Create milestones dir at .yolo-planning/milestones/ (../../milestones from phase dir)
  local ms_dir="$TEST_WORKDIR/.yolo-planning/milestones/old"
  mkdir -p "$ms_dir"
  cat > "$ms_dir/01-01.plan.jsonl" <<'JSONL'
{"p":"01-01","n":"Legacy","t":"3","w":1,"d":[],"mh":{},"obj":"Test"}
{"id":"T1","n":"test","f":["src/a.sh"],"d":"desc","ac":"ok"}
JSONL
  run bash "$SUT" "$dir" --scope=all
  # Should succeed (milestones are warnings, not errors)
  assert_success
  # Check that warnings were produced
  local warnings_count
  warnings_count=$(echo "$output" | jq '.warnings | length')
  [ "$warnings_count" -gt 0 ]
}

@test "(24) drift detection: naming-conventions.md sections have corresponding validation" {
  # Meta-test: verify validate-naming.sh covers main naming-conventions.md sections
  local naming_file="$PROJECT_ROOT/references/naming-conventions.md"
  local script_file="$SUT"

  # Sections 2 (plan header), 3 (plan task), 4 (summary), 5 (reqs) must each
  # have a corresponding validate_ function
  # Section 2: Plan Header -> validate_plan_naming
  run grep -c 'validate_plan_naming' "$script_file"
  [ "$output" -ge 2 ]  # at least function def + call

  # Section 3: Plan Task -> validate_plan_naming (tasks are validated within plan)
  run grep -c 'required_keys.*id.*tp\|required_keys.*id.*a' "$script_file"
  [ "$output" -ge 1 ]

  # Section 4: Summary -> validate_summary_naming
  run grep -c 'validate_summary_naming' "$script_file"
  [ "$output" -ge 2 ]

  # Section 5: Reqs -> validate_reqs_naming
  run grep -c 'validate_reqs_naming' "$script_file"
  [ "$output" -ge 2 ]

  # Count main naming sections (2-5) in naming-conventions.md
  run grep -c '^## [2-5]\.' "$naming_file"
  local section_count="$output"
  [ "$section_count" -ge 4 ]

  # Count validate_ functions in script
  run grep -c '^validate_.*_naming' "$script_file"
  local func_count="$output"
  # func_count should be >= section_count minus sections that are future-scope
  # Sections 2-5 = 4 required sections. We have 3 functions (plan covers sections 2+3)
  [ "$func_count" -ge 3 ]
}

@test "(25) --type flag overrides auto-detection" {
  local file="$TEST_WORKDIR/custom.jsonl"
  cat > "$file" <<'JSONL'
{"p":"01","n":"01","t":"Test Plan","w":1,"d":[],"mh":{"tr":["test"],"ar":[],"kl":[]},"obj":"Test"}
{"id":"T1","tp":"auto","a":"Create file","f":["src/test.sh"],"v":"file exists","done":"Created"}
JSONL
  run bash "$SUT" "$file" --type=plan
  assert_success
}

@test "(26) unknown file type produces warning not error" {
  local file="$TEST_WORKDIR/random.jsonl"
  echo '{"key":"value"}' > "$file"
  run bash "$SUT" "$file"
  assert_success
  local warnings_count
  warnings_count=$(echo "$output" | jq '.warnings | length')
  [ "$warnings_count" -gt 0 ]
}
