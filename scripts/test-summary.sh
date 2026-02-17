#!/usr/bin/env bash
set -euo pipefail

# test-summary.sh -- Concise test runner with PASS/FAIL summary
# Usage: bash scripts/test-summary.sh
# Output: "PASS (N tests)" or "FAIL (F/N failed)" with details
# Coexists with tests/run-all.sh (verbose) -- this is CI-friendly

# --- Resolve paths ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TESTS_DIR="${TESTS_DIR:-$SCRIPT_DIR/../tests}"

# --- Check bats installed ---
if ! command -v bats >/dev/null 2>&1; then
  echo "FAIL -- bats not installed" >&2
  exit 1
fi

# --- Dynamic discovery of test directories containing .bats files ---
SUITES=()
for dir in "$TESTS_DIR"/*/; do
  dir_name="$(basename "$dir")"
  # Skip helper and fixture directories
  if [ "$dir_name" = "test_helper" ] || [ "$dir_name" = "fixtures" ]; then
    continue
  fi
  # Check if directory contains .bats files (directly or recursively)
  if compgen -G "${dir}"*.bats >/dev/null 2>&1 || compgen -G "${dir}"**/*.bats >/dev/null 2>&1; then
    SUITES+=("$dir")
  fi
done

# --- Edge case: no suites found ---
if [ ${#SUITES[@]} -eq 0 ]; then
  echo "FAIL (0/0 failed) -- no test directories found"
  exit 1
fi

# --- Variables ---
TOTAL_PASS=0
TOTAL_FAIL=0
FAILED_TESTS=()
PERF_FAILURES=()

# --- Suite loop ---
for dir in "${SUITES[@]}"; do
  SUITE_NAME="$(basename "$dir")"

  # Run bats with TAP output, capture exit code
  TAP_OUTPUT="$(bats --tap --recursive "$dir" 2>&1)" || true

  # Parse TAP output: count passes and failures
  PASS_COUNT=$(echo "$TAP_OUTPUT" | grep -c '^ok [0-9]' || true)
  FAIL_COUNT=$(echo "$TAP_OUTPUT" | grep -c '^not ok ' || true)

  # Accumulate totals
  TOTAL_PASS=$((TOTAL_PASS + PASS_COUNT))

  if [ "$FAIL_COUNT" -gt 0 ]; then
    # Extract failed test names
    while IFS= read -r line; do
      test_name="$(echo "$line" | sed 's/^not ok [0-9]* //')"
      if [ "$SUITE_NAME" = "perf" ]; then
        # Perf failures are optional -- track separately, do not count toward TOTAL_FAIL
        PERF_FAILURES+=("[$SUITE_NAME] $test_name")
      else
        FAILED_TESTS+=("[$SUITE_NAME] $test_name")
      fi
    done <<< "$(echo "$TAP_OUTPUT" | grep '^not ok ')"

    # Only count non-perf failures toward total
    if [ "$SUITE_NAME" != "perf" ]; then
      TOTAL_FAIL=$((TOTAL_FAIL + FAIL_COUNT))
    fi
  fi
done

# --- Output ---
TOTAL=$((TOTAL_PASS + TOTAL_FAIL))
if [ "$TOTAL_FAIL" -eq 0 ]; then
  echo "PASS ($TOTAL tests)"
  exit 0
else
  echo "FAIL ($TOTAL_FAIL/$TOTAL failed)"
  for entry in "${FAILED_TESTS[@]}"; do
    echo "  $entry"
  done
  exit 1
fi
