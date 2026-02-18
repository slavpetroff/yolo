#!/usr/bin/env bats
# test-escalation-jsonl-schema.bats — Static validation tests for escalation.jsonl format
# Tests: required fields, valid values, ID reuse, monotonic timestamps.

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir
}

# Helper: validate an escalation entry has all required fields
validate_entry() {
  local entry="$1"
  echo "$entry" | jq -e '
    has("id") and has("dt") and has("agent") and has("reason") and
    has("sb") and has("tgt") and has("sev") and has("st")
  ' > /dev/null 2>&1
}

# --- Valid open entry ---

@test "valid open entry parses with all required fields" {
  local entry='{"id":"ESC-04-05-T3","dt":"2026-02-18T14:30:00Z","agent":"dev","reason":"Spec unclear","sb":"Dev scope: implement within spec only","tgt":"senior","sev":"blocking","st":"open"}'
  run validate_entry "$entry"
  assert_success
}

# --- Valid resolved entry has res field ---

@test "valid resolved entry has res field" {
  local entry='{"id":"ESC-04-05-T3","dt":"2026-02-18T14:35:00Z","agent":"senior","reason":"Spec unclear","sb":"Senior scope: spec enrichment and code review","tgt":"lead","sev":"blocking","st":"resolved","res":"Clarified: use default config fallback"}'
  run bash -c "echo '$entry' | jq -e 'has(\"res\") and .st == \"resolved\"'"
  assert_success
}

# --- Invalid sev value ---

@test "invalid sev value is rejected" {
  local entry='{"id":"ESC-01","dt":"2026-02-18T14:30:00Z","agent":"dev","reason":"test","sb":"scope","tgt":"senior","sev":"low","st":"open"}'
  run bash -c "echo '$entry' | jq -e '.sev == \"blocking\" or .sev == \"major\" or .sev == \"minor\"'"
  assert_failure
}

# --- Invalid st value ---

@test "invalid st value is rejected" {
  local entry='{"id":"ESC-01","dt":"2026-02-18T14:30:00Z","agent":"dev","reason":"test","sb":"scope","tgt":"senior","sev":"blocking","st":"closed"}'
  run bash -c "echo '$entry' | jq -e '.st == \"open\" or .st == \"escalated\" or .st == \"resolved\"'"
  assert_failure
}

# --- Missing sb field ---

@test "missing sb field is rejected" {
  local entry='{"id":"ESC-01","dt":"2026-02-18T14:30:00Z","agent":"dev","reason":"test","tgt":"senior","sev":"blocking","st":"open"}'
  run bash -c "echo '$entry' | jq -e 'has(\"sb\")'"
  assert_failure
}

# --- ID reuse across entries (same escalation chain) ---

@test "ID reuse across entries is valid for escalation chain" {
  local file="$TEST_WORKDIR/escalation.jsonl"
  echo '{"id":"ESC-04-05-T3","dt":"2026-02-18T14:30:00Z","agent":"dev","reason":"Spec unclear","sb":"Dev scope: implement within spec only","tgt":"senior","sev":"blocking","st":"open"}' > "$file"
  echo '{"id":"ESC-04-05-T3","dt":"2026-02-18T14:35:00Z","agent":"senior","reason":"Spec unclear","sb":"Senior scope: spec enrichment","tgt":"lead","sev":"blocking","st":"escalated"}' >> "$file"
  echo '{"id":"ESC-04-05-T3","dt":"2026-02-18T14:40:00Z","agent":"lead","reason":"Spec unclear","sb":"Lead scope: coordination","tgt":"architect","sev":"blocking","st":"resolved","res":"Use default fallback"}' >> "$file"
  # All entries share same ID — valid chain
  local id_count
  id_count=$(jq -s '[.[].id] | unique | length' "$file")
  run bash -c "echo $id_count"
  assert_output "1"
}

# --- Monotonically increasing dt timestamps ---

@test "entries with same ID have monotonically increasing dt timestamps" {
  local file="$TEST_WORKDIR/escalation.jsonl"
  echo '{"id":"ESC-01","dt":"2026-02-18T14:30:00Z","agent":"dev","reason":"test","sb":"scope","tgt":"senior","sev":"blocking","st":"open"}' > "$file"
  echo '{"id":"ESC-01","dt":"2026-02-18T14:35:00Z","agent":"senior","reason":"test","sb":"scope","tgt":"lead","sev":"blocking","st":"escalated"}' >> "$file"
  # Check timestamps are sorted
  run bash -c "jq -s '[.[] | select(.id == \"ESC-01\")] | [.[].dt] | . as \$ts | [range(1; length)] | all(. as \$i | \$ts[\$i] > \$ts[\$i-1])' '$file'"
  assert_success
  assert_output "true"
}
