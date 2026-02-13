#!/usr/bin/env bats
# validate-frontmatter.bats — Unit tests for scripts/validate-frontmatter.sh
# PostToolUse on Write|Edit, non-blocking (always exit 0)

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/validate-frontmatter.sh"
}

# --- Ignores non-markdown files ---

@test "exits 0 for non-markdown file" {
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"src/foo.ts\"}}' | bash '$SUT'"
  assert_success
  refute_output --partial "hookSpecificOutput"
}

# --- Valid frontmatter ---

@test "valid single-line description passes" {
  local f="$TEST_WORKDIR/test.md"
  cat > "$f" <<'EOF'
---
description: A valid single-line description
title: Test
---
# Content
EOF

  run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash '$SUT'"
  assert_success
  refute_output --partial "hookSpecificOutput"
}

# --- Multi-line description detection ---

@test "block scalar pipe description warns" {
  local f="$TEST_WORKDIR/test.md"
  cat > "$f" <<'EOF'
---
description: |
  This is a multi-line
  description
title: Test
---
# Content
EOF

  run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash '$SUT'"
  assert_success
  assert_output --partial "hookSpecificOutput"
  assert_output --partial "must be a single line"
}

@test "block scalar folded description warns" {
  local f="$TEST_WORKDIR/test.md"
  cat > "$f" <<'EOF'
---
description: >
  This is a folded
  description
title: Test
---
# Content
EOF

  run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash '$SUT'"
  assert_success
  assert_output --partial "hookSpecificOutput"
  assert_output --partial "must be a single line"
}

@test "empty description with indented continuation warns multi-line" {
  local f="$TEST_WORKDIR/test.md"
  cat > "$f" <<'EOF'
---
description:
  This is indented continuation
title: Test
---
# Content
EOF

  run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash '$SUT'"
  assert_success
  assert_output --partial "hookSpecificOutput"
  assert_output --partial "must be a single line"
}

@test "empty description without continuation warns empty" {
  local f="$TEST_WORKDIR/test.md"
  cat > "$f" <<'EOF'
---
description:
title: Test
---
# Content
EOF

  run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash '$SUT'"
  assert_success
  assert_output --partial "hookSpecificOutput"
  assert_output --partial "is empty"
}

# --- No description field ---

@test "markdown without description field exits 0 silently" {
  local f="$TEST_WORKDIR/test.md"
  cat > "$f" <<'EOF'
---
title: No description here
---
# Content
EOF

  run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash '$SUT'"
  assert_success
  refute_output --partial "hookSpecificOutput"
}

# --- No frontmatter ---

@test "markdown without frontmatter exits 0 silently" {
  local f="$TEST_WORKDIR/test.md"
  cat > "$f" <<'EOF'
# Just a plain markdown file
No frontmatter here.
EOF

  run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash '$SUT'"
  assert_success
  refute_output --partial "hookSpecificOutput"
}

# --- Always exits 0 ---

@test "exits 0 on empty stdin" {
  run bash -c "echo -n '' | bash '$SUT'"
  assert_success
}
