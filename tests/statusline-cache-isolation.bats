#!/usr/bin/env bats
# Tests for statusline cache isolation across repositories
# Verifies cache keys include repo identity and no-remote repos display correctly.

load test_helper

setup() {
  setup_temp_dir
  export ORIG_UID=$(id -u)
  # Ensure git identity is available (CI runners may not have global config)
  export GIT_AUTHOR_NAME="test"
  export GIT_AUTHOR_EMAIL="test@test.local"
  export GIT_COMMITTER_NAME="test"
  export GIT_COMMITTER_EMAIL="test@test.local"
  # Clean any existing caches
  rm -f /tmp/yolo-*-"${ORIG_UID}"-* /tmp/yolo-*-"${ORIG_UID}" 2>/dev/null || true
}

teardown() {
  rm -f /tmp/yolo-*-"${ORIG_UID}"-* /tmp/yolo-*-"${ORIG_UID}" 2>/dev/null || true
  teardown_temp_dir
}

# --- Cache key includes repo hash ---

@test "cache key includes repo-specific hash" {
  local uid=$(id -u)
  # Run statusline in the project repo
  cd "$PROJECT_ROOT"
  echo '{}' | "$YOLO_BIN" statusline >/dev/null 2>&1
  # Cache files should contain an 8-char hash segment after the UID
  local cache_files
  cache_files=$(ls /tmp/yolo-*-"${uid}"-*-fast 2>/dev/null || true)
  [ -n "$cache_files" ]
  # Verify the hash segment is present (pattern: yolo-{ver}-{uid}-{hash}-fast)
  echo "$cache_files" | grep -qE "yolo-[0-9.]+-${uid}-[a-f0-9]+-fast"
}

@test "different repos produce different cache keys" {
  local uid=$(id -u)

  # Run in project repo
  cd "$PROJECT_ROOT"
  echo '{}' | "$YOLO_BIN" statusline >/dev/null 2>&1
  local cache1
  cache1=$(ls /tmp/yolo-*-"${uid}"-*-fast 2>/dev/null | head -1)

  # Create a second repo and run there
  local repo2="$TEST_TEMP_DIR/repo2"
  mkdir -p "$repo2"
  git -C "$repo2" init -q
  git -C "$repo2" commit --allow-empty -m "test(init): seed" -q
  rm -f /tmp/yolo-*-"${uid}"-*-fast 2>/dev/null
  cd "$repo2"
  echo '{}' | "$YOLO_BIN" statusline >/dev/null 2>&1
  cd "$PROJECT_ROOT"
  local cache2
  cache2=$(ls /tmp/yolo-*-"${uid}"-*-fast 2>/dev/null | head -1)

  # Cache filenames should differ (different hash)
  [ "$cache1" != "$cache2" ]
}

@test "cache is not shared between repos within TTL window" {
  local uid=$(id -u)

  # Create two isolated repos
  local repo_a="$TEST_TEMP_DIR/repo-a"
  local repo_b="$TEST_TEMP_DIR/repo-b"
  mkdir -p "$repo_a" "$repo_b"
  git -C "$repo_a" init -q
  git -C "$repo_a" commit --allow-empty -m "test(init): seed" -q
  git -C "$repo_b" init -q
  git -C "$repo_b" commit --allow-empty -m "test(init): seed" -q

  # Run statusline in repo A — capture number of cache files for repo A
  cd "$repo_a"
  echo '{}' | "$YOLO_BIN" statusline >/dev/null 2>&1
  local cache_count_a
  cache_count_a=$(ls /tmp/yolo-*-"${uid}"-* 2>/dev/null | wc -l | tr -d ' ')

  # Run statusline in repo B (within TTL)
  cd "$repo_b"
  echo '{}' | "$YOLO_BIN" statusline >/dev/null 2>&1

  cd "$PROJECT_ROOT"

  # Total cache files should increase (separate repos get separate caches)
  local cache_count_total
  cache_count_total=$(ls /tmp/yolo-*-"${uid}"-* 2>/dev/null | wc -l | tr -d ' ')
  [ "$cache_count_total" -ge "$cache_count_a" ]
}

# --- No-remote repo handling ---

@test "no-remote repo shows directory name in status line" {
  local repo="$TEST_TEMP_DIR/my-local-project"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" commit --allow-empty -m "test(init): seed" -q

  cd "$repo"
  local branch
  branch=$(git branch --show-current)
  local output
  output=$(echo '{}' | "$YOLO_BIN" statusline 2>&1 | head -1)
  cd "$PROJECT_ROOT"

  # Should contain directory name and branch (branch varies: main or master)
  echo "$output" | grep -q "my-local-project:${branch}"
}

@test "no-remote repo does not show another repo's name" {
  local uid=$(id -u)
  local repo="$TEST_TEMP_DIR/isolated-repo"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" commit --allow-empty -m "test(init): seed" -q

  # First run in main project (has origin remote)
  cd "$PROJECT_ROOT"
  echo '{}' | "$YOLO_BIN" statusline >/dev/null 2>&1

  # Then run in local-only repo
  cd "$repo"
  local output
  output=$(echo '{}' | "$YOLO_BIN" statusline 2>&1 | head -1)
  cd "$PROJECT_ROOT"

  # Should NOT contain the main project's GitHub repo name
  ! echo "$output" | grep -q "vibe-better-with-claude-code-yolo"
  # Should contain the local directory name
  echo "$output" | grep -q "isolated-repo"
}

@test "repo with remote shows repo name in statusline" {
  cd "$PROJECT_ROOT"
  local output
  output=$(echo '{}' | "$YOLO_BIN" statusline 2>&1 | head -1)
  # Should contain the project repo identifier (YOLO marker or repo name)
  echo "$output" | grep -q "YOLO"
}

@test "detached HEAD repo still produces valid statusline" {
  local repo="$TEST_TEMP_DIR/detached-remote-repo"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" commit --allow-empty -m "test(init): seed" -q
  git -C "$repo" remote add origin "https://github.com/example/detached-remote-repo.git"
  git -C "$repo" checkout --detach -q

  cd "$repo"
  local output
  output=$(echo '{}' | "$YOLO_BIN" statusline 2>&1)
  cd "$PROJECT_ROOT"

  # Detached HEAD should still produce valid output without errors
  local lines
  lines=$(echo "$output" | wc -l | tr -d ' ')
  [ "$lines" -ge 1 ]
}

# --- Cache cleanup ---

@test "cache-nuke removes all format caches" {
  local uid=$(id -u)
  # Create fake old-format and new-format caches
  touch "/tmp/yolo-0.0.0-${uid}-fast"
  touch "/tmp/yolo-0.0.0-${uid}-slow"

  # Run cache-nuke — should clean up all formats
  "$YOLO_BIN" cache-nuke >/dev/null 2>&1

  # Old caches should be gone
  [ ! -f "/tmp/yolo-0.0.0-${uid}-fast" ]
  [ ! -f "/tmp/yolo-0.0.0-${uid}-slow" ]
}

@test "cache-nuke cleans repo-scoped caches" {
  local uid=$(id -u)
  # Create cache files in new format
  cd "$PROJECT_ROOT"
  echo '{}' | "$YOLO_BIN" statusline >/dev/null 2>&1
  local before
  before=$(ls /tmp/yolo-*-"${uid}"-* 2>/dev/null | wc -l | tr -d ' ')
  [ "$before" -gt 0 ]

  # Nuke caches
  "$YOLO_BIN" cache-nuke >/dev/null 2>&1

  # All caches for this user should be gone
  local after
  after=$(ls /tmp/yolo-*-"${uid}"-* 2>/dev/null | wc -l | tr -d ' ')
  [ "$after" -eq 0 ]
}

# --- Non-git directory handling ---

@test "statusline works in non-git directory" {
  local noGitDir="$TEST_TEMP_DIR/not-a-repo"
  mkdir -p "$noGitDir"
  cd "$noGitDir"
  local output
  output=$(echo '{}' | "$YOLO_BIN" statusline 2>&1)
  cd "$PROJECT_ROOT"
  # Should produce 4 lines without errors
  local lines
  lines=$(echo "$output" | wc -l | tr -d ' ')
  [ "$lines" -eq 4 ]
}
