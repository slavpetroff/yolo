#!/usr/bin/env bats
# build-reference-packages.bats — Unit tests for scripts/build-reference-packages.sh
# Validates the sync-checker script AND verifies package content correctness.
# Drift detection per architecture decision R1.

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/build-reference-packages.sh"
}

# --- Helper: create mock packages with required keywords ---
setup_mock_packages() {
  mkdir -p "$TEST_WORKDIR/scripts"
  cp "$SUT" "$TEST_WORKDIR/scripts/build-reference-packages.sh"
  mkdir -p "$TEST_WORKDIR/references/packages"

  cat > "$TEST_WORKDIR/references/packages/architect.toon" <<'TOON'
role: architect
step: Step 2 Architecture
architecture.toon output
critique.jsonl input
tech_decisions section
TOON

  cat > "$TEST_WORKDIR/references/packages/lead.toon" <<'TOON'
role: lead
step: Step 3 Load Plans
step: Step 10 Sign-off
plan.jsonl artifacts
wave ordering
execution-state tracking
TOON

  cat > "$TEST_WORKDIR/references/packages/senior.toon" <<'TOON'
role: senior
step: Step 4 Design Review
step: Step 7 Code Review
spec enrichment
code-review.jsonl output
design_review protocol
TOON

  cat > "$TEST_WORKDIR/references/packages/dev.toon" <<'TOON'
role: dev
step: Step 6 Implementation
summary.jsonl output
commit format
escalation to Senior
TDD red green
TOON

  cat > "$TEST_WORKDIR/references/packages/tester.toon" <<'TOON'
role: tester
step: Step 5 Test Authoring
test-plan.jsonl output
RED phase confirmation
red check all fail
TOON

  cat > "$TEST_WORKDIR/references/packages/qa.toon" <<'TOON'
role: qa
step: Step 8 QA Plan-level
verification.jsonl output
tier resolution
must_have checks
TOON

  cat > "$TEST_WORKDIR/references/packages/qa-code.toon" <<'TOON'
role: qa-code
step: Step 8 QA Code-level
qa-code.jsonl output
TDD compliance
lint check
TOON

  cat > "$TEST_WORKDIR/references/packages/critic.toon" <<'TOON'
role: critic
step: Step 1 Critique
critique.jsonl output
gap identification
finding analysis
TOON

  cat > "$TEST_WORKDIR/references/packages/security.toon" <<'TOON'
role: security
step: Step 9 Security Audit
security-audit.jsonl output
vulnerability scan
FAIL hard stop
TOON
}

# Helper: run checker from mock workdir
run_checker() {
  run bash "$TEST_WORKDIR/scripts/build-reference-packages.sh" "$@"
}

# ============================================================
# MOCK-BASED TESTS (use TEST_WORKDIR)
# ============================================================

@test "outputs valid JSON when all packages present" {
  setup_mock_packages
  run_checker
  assert_success
  echo "$output" | jq . >/dev/null 2>&1
  assert [ $? -eq 0 ]
}

@test "reports valid:true when all packages have keywords" {
  setup_mock_packages
  run_checker
  assert_success
  local valid
  valid=$(echo "$output" | jq -r '.valid')
  assert [ "$valid" = "true" ]
}

@test "reports missing role when package file absent" {
  setup_mock_packages
  rm "$TEST_WORKDIR/references/packages/dev.toon"
  run_checker
  assert_failure
  local has_dev
  has_dev=$(echo "$output" | jq '.missing | index("dev")')
  assert [ "$has_dev" != "null" ]
}

@test "reports stale when keyword missing from package" {
  setup_mock_packages
  # Overwrite architect.toon without 'Step 2'
  echo "role: architect" > "$TEST_WORKDIR/references/packages/architect.toon"
  echo "architecture.toon output" >> "$TEST_WORKDIR/references/packages/architect.toon"
  echo "critique.jsonl input" >> "$TEST_WORKDIR/references/packages/architect.toon"
  echo "tech_decisions section" >> "$TEST_WORKDIR/references/packages/architect.toon"
  run_checker
  assert_failure
  echo "$output" | jq -e '.stale[] | select(startswith("architect"))'
}

@test "reports multiple missing roles" {
  setup_mock_packages
  rm "$TEST_WORKDIR/references/packages/dev.toon"
  rm "$TEST_WORKDIR/references/packages/qa.toon"
  run_checker
  assert_failure
  local count
  count=$(echo "$output" | jq '.missing | length')
  assert [ "$count" -eq 2 ]
}

@test "--help flag prints usage" {
  setup_mock_packages
  run_checker --help
  assert_success
  assert_output --partial "Usage"
}

@test "--quiet flag suppresses stdout" {
  setup_mock_packages
  run_checker --quiet
  assert_success
  assert [ -z "$output" ]
}

# ============================================================
# REAL-PACKAGE TESTS (use $PROJECT_ROOT/references/packages/)
# ============================================================

@test "actual packages pass sync check" {
  run bash "$SCRIPTS_DIR/build-reference-packages.sh"
  assert_success
}

@test "dev package contains Step 6 but not Step 2 or Step 4" {
  run grep "Step 6" "$PROJECT_ROOT/references/packages/dev.toon"
  assert_success
  run grep "Step 2" "$PROJECT_ROOT/references/packages/dev.toon"
  assert_failure
  run grep "Step 4" "$PROJECT_ROOT/references/packages/dev.toon"
  assert_failure
}

@test "senior package contains Step 4 and Step 7" {
  run grep "Step 4" "$PROJECT_ROOT/references/packages/senior.toon"
  assert_success
  run grep "Step 7" "$PROJECT_ROOT/references/packages/senior.toon"
  assert_success
}

@test "each package is under 3KB" {
  for f in "$PROJECT_ROOT"/references/packages/*.toon; do
    local size
    size=$(wc -c < "$f")
    assert [ "$size" -lt 3072 ]
  done
}

@test "qa package contains verification.jsonl reference" {
  run grep "verification.jsonl" "$PROJECT_ROOT/references/packages/qa.toon"
  assert_success
}

@test "security package contains FAIL handling" {
  run grep "FAIL" "$PROJECT_ROOT/references/packages/security.toon"
  assert_success
}

@test "all 9 package files exist" {
  local roles="architect lead senior dev tester qa qa-code critic security"
  for role in $roles; do
    assert [ -f "$PROJECT_ROOT/references/packages/${role}.toon" ]
  done
}
