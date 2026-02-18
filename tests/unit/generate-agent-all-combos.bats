#!/usr/bin/env bats
# generate-agent-all-combos.bats -- Tests for all 27 role+dept agent generation combinations
# Plan 08-06: BATS tests for template generation pipeline

setup() {
  load '../test_helper/common'
  GENERATE="$SCRIPTS_DIR/generate-agent.sh"
  ROLES=(architect lead senior dev tester qa qa-code security documenter)
  DEPTS=(backend frontend uiux)
}

# --- Basic generation tests (all 27 combos) ---

@test "generate-agent.sh exits 0 for all 27 combinations" {
  for dept in "${DEPTS[@]}"; do
    for role in "${ROLES[@]}"; do
      run bash "$GENERATE" --role "$role" --dept "$dept" --dry-run
      [ "$status" -eq 0 ] || {
        echo "FAIL: ${dept}/${role} exited with $status"
        return 1
      }
    done
  done
}

@test "generate-agent.sh produces non-empty output for all 27 combinations" {
  for dept in "${DEPTS[@]}"; do
    for role in "${ROLES[@]}"; do
      run bash "$GENERATE" --role "$role" --dept "$dept" --dry-run
      [ -n "$output" ] || {
        echo "FAIL: ${dept}/${role} produced empty output"
        return 1
      }
    done
  done
}

@test "no unreplaced {{PLACEHOLDER}} patterns in any of 27 combinations" {
  for dept in "${DEPTS[@]}"; do
    for role in "${ROLES[@]}"; do
      OUTPUT=$(bash "$GENERATE" --role "$role" --dept "$dept" --dry-run 2>/dev/null)
      UNREPLACED=$(echo "$OUTPUT" | grep -oE '\{\{[A-Z_]+\}\}' || true)
      [ -z "$UNREPLACED" ] || {
        echo "FAIL: ${dept}/${role} has unreplaced: $UNREPLACED"
        return 1
      }
    done
  done
}

@test "all 27 combinations contain YAML frontmatter" {
  for dept in "${DEPTS[@]}"; do
    for role in "${ROLES[@]}"; do
      OUTPUT=$(bash "$GENERATE" --role "$role" --dept "$dept" --dry-run 2>/dev/null)
      echo "$OUTPUT" | grep -q "^---$" || {
        echo "FAIL: ${dept}/${role} missing YAML frontmatter delimiter"
        return 1
      }
    done
  done
}

@test "all 27 combinations contain expected name field in frontmatter" {
  for dept in "${DEPTS[@]}"; do
    for role in "${ROLES[@]}"; do
      OUTPUT=$(bash "$GENERATE" --role "$role" --dept "$dept" --dry-run 2>/dev/null)
      echo "$OUTPUT" | grep -q "^name: yolo-" || {
        echo "FAIL: ${dept}/${role} missing name field"
        return 1
      }
    done
  done
}

@test "all 27 combinations contain H1 heading" {
  for dept in "${DEPTS[@]}"; do
    for role in "${ROLES[@]}"; do
      OUTPUT=$(bash "$GENERATE" --role "$role" --dept "$dept" --dry-run 2>/dev/null)
      echo "$OUTPUT" | grep -q "^# YOLO" || {
        echo "FAIL: ${dept}/${role} missing H1 heading"
        return 1
      }
    done
  done
}

# --- No stderr warnings (all 27) ---

@test "no unreplaced placeholder warnings on stderr for any combination" {
  for dept in "${DEPTS[@]}"; do
    for role in "${ROLES[@]}"; do
      STDERR=$(bash "$GENERATE" --role "$role" --dept "$dept" --dry-run 2>&1 >/dev/null)
      WARNINGS=$(echo "$STDERR" | grep -i "warning\|unreplaced" || true)
      [ -z "$WARNINGS" ] || {
        echo "FAIL: ${dept}/${role} stderr warning: $WARNINGS"
        return 1
      }
    done
  done
}

# --- Dept prefix correctness ---

@test "backend agents have no dept prefix in name field" {
  for role in "${ROLES[@]}"; do
    OUTPUT=$(bash "$GENERATE" --role "$role" --dept backend --dry-run 2>/dev/null)
    echo "$OUTPUT" | grep -q "^name: yolo-${role}$" || {
      echo "FAIL: backend/${role} wrong name field"
      return 1
    }
  done
}

@test "frontend agents have fe- prefix in name field" {
  for role in "${ROLES[@]}"; do
    OUTPUT=$(bash "$GENERATE" --role "$role" --dept frontend --dry-run 2>/dev/null)
    echo "$OUTPUT" | grep -q "^name: yolo-fe-${role}$" || {
      echo "FAIL: frontend/${role} wrong name field"
      return 1
    }
  done
}

@test "uiux agents have ux- prefix in name field" {
  for role in "${ROLES[@]}"; do
    OUTPUT=$(bash "$GENERATE" --role "$role" --dept uiux --dry-run 2>/dev/null)
    echo "$OUTPUT" | grep -q "^name: yolo-ux-${role}$" || {
      echo "FAIL: uiux/${role} wrong name field"
      return 1
    }
  done
}

# --- Validation edge cases ---

@test "invalid role is rejected" {
  run bash "$GENERATE" --role invalid --dept backend --dry-run
  assert_failure
  assert_output --partial "invalid role"
}

@test "invalid dept is rejected" {
  run bash "$GENERATE" --role dev --dept invalid --dry-run
  assert_failure
  assert_output --partial "invalid dept"
}

@test "missing --role is rejected" {
  run bash "$GENERATE" --dept backend --dry-run
  assert_failure
  assert_output --partial "--role is required"
}

@test "missing --dept is rejected" {
  run bash "$GENERATE" --role dev --dry-run
  assert_failure
  assert_output --partial "--dept is required"
}
