#!/usr/bin/env bats
# map-staleness.bats — Unit tests for scripts/map-staleness.sh
# SessionStart hook for codebase map freshness detection

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir
  mk_git_repo
  SUT="$SCRIPTS_DIR/map-staleness.sh"
}

# --- 1. Reports no_map when META.md is missing ---

@test "reports no_map when META.md does not exist" {
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT'"
  assert_success
  assert_output --partial "status: no_map"
}

# --- 2. Reports fresh when no files changed ---

@test "reports fresh when no files changed since map" {
  local head_hash
  head_hash=$(cd "$TEST_WORKDIR" && git rev-parse HEAD)
  mkdir -p "$TEST_WORKDIR/.yolo-planning/codebase"
  cat > "$TEST_WORKDIR/.yolo-planning/codebase/META.md" <<EOF
git_hash: $head_hash
file_count: 10
mapped_at: 2026-01-01
EOF
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT'"
  assert_success
  assert_output --partial "status: fresh"
  assert_output --partial "staleness: 0%"
}

# --- 3. Reports stale when many files changed ---

@test "reports stale when >30% files changed" {
  local head_hash
  head_hash=$(cd "$TEST_WORKDIR" && git rev-parse HEAD)
  mkdir -p "$TEST_WORKDIR/.yolo-planning/codebase"
  # Map was created at HEAD, claim file_count of 3
  cat > "$TEST_WORKDIR/.yolo-planning/codebase/META.md" <<EOF
git_hash: $head_hash
file_count: 3
mapped_at: 2026-01-01
EOF
  # Add 2 new files (2/3 = 66% > 30%)
  cd "$TEST_WORKDIR"
  echo "a" > file_a.txt
  echo "b" > file_b.txt
  git add file_a.txt file_b.txt
  git commit -q -m "add files"
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT'"
  assert_success
  assert_output --partial "status: stale"
}

# --- 4. Reports no_map when file_count is 0 ---

@test "reports no_map when file_count is 0" {
  local head_hash
  head_hash=$(cd "$TEST_WORKDIR" && git rev-parse HEAD)
  mkdir -p "$TEST_WORKDIR/.yolo-planning/codebase"
  cat > "$TEST_WORKDIR/.yolo-planning/codebase/META.md" <<EOF
git_hash: $head_hash
file_count: 0
mapped_at: 2026-01-01
EOF
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT'"
  assert_success
  assert_output --partial "status: no_map"
}

# --- 5. Reports stale when git_hash is missing/invalid ---

@test "reports stale when stored git_hash does not exist in repo" {
  mkdir -p "$TEST_WORKDIR/.yolo-planning/codebase"
  cat > "$TEST_WORKDIR/.yolo-planning/codebase/META.md" <<EOF
git_hash: 0000000000000000000000000000000000000000
file_count: 10
mapped_at: 2026-01-01
EOF
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT'"
  assert_success
  assert_output --partial "status: stale"
  assert_output --partial "staleness: 100%"
}

# --- 6. Reports no_git when not in a git repo ---

@test "reports no_git when not in a git repo" {
  # Create a workdir outside the git repo
  local nogit_dir
  nogit_dir=$(mktemp -d "$BATS_TEST_TMPDIR/yolo-nogit-XXXXXX")
  mkdir -p "$nogit_dir/.yolo-planning/codebase"
  cat > "$nogit_dir/.yolo-planning/codebase/META.md" <<EOF
git_hash: abc123
file_count: 10
mapped_at: 2026-01-01
EOF
  run bash -c "cd '$nogit_dir' && bash '$SUT'"
  assert_success
  assert_output --partial "status: no_git"
}

# --- 7. Includes changed count and total ---

@test "includes changed and total counts in output" {
  local head_hash
  head_hash=$(cd "$TEST_WORKDIR" && git rev-parse HEAD)
  mkdir -p "$TEST_WORKDIR/.yolo-planning/codebase"
  cat > "$TEST_WORKDIR/.yolo-planning/codebase/META.md" <<EOF
git_hash: $head_hash
file_count: 50
mapped_at: 2026-01-01
EOF
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT'"
  assert_success
  assert_output --partial "changed: 0"
  assert_output --partial "total: 50"
}

# --- 8. Includes since timestamp ---

@test "includes since timestamp from META.md" {
  local head_hash
  head_hash=$(cd "$TEST_WORKDIR" && git rev-parse HEAD)
  mkdir -p "$TEST_WORKDIR/.yolo-planning/codebase"
  cat > "$TEST_WORKDIR/.yolo-planning/codebase/META.md" <<EOF
git_hash: $head_hash
file_count: 10
mapped_at: 2026-02-10
EOF
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT'"
  assert_success
  assert_output --partial "since: 2026-02-10"
}

# --- 9. Handles Markdown bold format from actual map output ---

@test "parses Markdown bold format META.md from map command" {
  local head_hash
  head_hash=$(cd "$TEST_WORKDIR" && git rev-parse HEAD)
  mkdir -p "$TEST_WORKDIR/.yolo-planning/codebase"
  cat > "$TEST_WORKDIR/.yolo-planning/codebase/META.md" <<EOF
# Mapping Metadata

- **mapped_at**: 2026-02-13
- **git_hash**: $head_hash
- **file_count**: 50
- **documents**: STACK.md, DEPENDENCIES.md
- **mode**: full
- **monorepo**: false
- **mapping_tier**: solo
EOF
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT'"
  assert_success
  assert_output --partial "status: fresh"
  assert_output --partial "total: 50"
  assert_output --partial "since: 2026-02-13"
}
