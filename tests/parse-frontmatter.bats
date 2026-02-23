#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
}

teardown() {
  teardown_temp_dir
}

@test "parses standard frontmatter" {
  cat > "$TEST_TEMP_DIR/test.md" <<'EOF'
---
phase: "01"
plan: "02"
title: "Test Plan"
---
# Body
EOF
  run "$YOLO_BIN" parse-frontmatter "$TEST_TEMP_DIR/test.md"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.ok == true'
  echo "$output" | jq -e '.has_frontmatter == true'
  echo "$output" | jq -e '.frontmatter.phase == "01"'
  echo "$output" | jq -e '.frontmatter.plan == "02"'
  echo "$output" | jq -e '.frontmatter.title == "Test Plan"'
}

@test "returns has_frontmatter false for no frontmatter" {
  cat > "$TEST_TEMP_DIR/plain.md" <<'EOF'
# Just a heading
Some text.
EOF
  run "$YOLO_BIN" parse-frontmatter "$TEST_TEMP_DIR/plain.md"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.has_frontmatter == false'
  echo "$output" | jq -e '.frontmatter == {}'
}

@test "handles array values" {
  cat > "$TEST_TEMP_DIR/array.md" <<'EOF'
---
must_haves:
  - "item1"
  - "item2"
---
EOF
  run "$YOLO_BIN" parse-frontmatter "$TEST_TEMP_DIR/array.md"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.frontmatter.must_haves | length == 2'
  echo "$output" | jq -e '.frontmatter.must_haves[0] == "item1"'
  echo "$output" | jq -e '.frontmatter.must_haves[1] == "item2"'
}

@test "errors on missing file" {
  run "$YOLO_BIN" parse-frontmatter "/nonexistent/file.md"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.error | test("file not found")'
}

@test "handles empty frontmatter" {
  printf -- '---\n---\n# Content\n' > "$TEST_TEMP_DIR/empty.md"
  run "$YOLO_BIN" parse-frontmatter "$TEST_TEMP_DIR/empty.md"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.has_frontmatter == true'
  echo "$output" | jq -e '.frontmatter == {}'
}

@test "handles inline array values" {
  cat > "$TEST_TEMP_DIR/inline.md" <<'EOF'
---
depends_on: [01, 02]
title: "test"
---
EOF
  run "$YOLO_BIN" parse-frontmatter "$TEST_TEMP_DIR/inline.md"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.frontmatter.depends_on | length == 2'
  echo "$output" | jq -e '.frontmatter.depends_on[0] == "01"'
  echo "$output" | jq -e '.frontmatter.depends_on[1] == "02"'
}
