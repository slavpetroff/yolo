#!/usr/bin/env bats
# pre-push-hook.bats — Unit tests for scripts/pre-push-hook.sh
# Git pre-push hook: enforce version bump before push

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir
  mk_git_repo
  SUT="$SCRIPTS_DIR/pre-push-hook.sh"

  # Create version infrastructure in the test repo
  echo "1.0.0" > "$TEST_WORKDIR/VERSION"
  mkdir -p "$TEST_WORKDIR/.claude-plugin"
  echo '{"version":"1.0.0","name":"yolo"}' > "$TEST_WORKDIR/.claude-plugin/plugin.json"
  echo '{"plugins":[{"version":"1.0.0","name":"yolo"}]}' > "$TEST_WORKDIR/.claude-plugin/marketplace.json"
  echo '{"plugins":[{"version":"1.0.0","name":"yolo"}]}' > "$TEST_WORKDIR/marketplace.json"

  # Copy bump-version.sh so --verify works
  mkdir -p "$TEST_WORKDIR/scripts"
  cp "$SCRIPTS_DIR/bump-version.sh" "$TEST_WORKDIR/scripts/bump-version.sh"

  cd "$TEST_WORKDIR"
  git add -A && git commit -q -m "chore: add version files"
}

# Helper: simulate pre-push stdin (local_ref local_sha remote_ref remote_sha)
push_stdin() {
  local local_ref="$1" local_sha="$2" remote_ref="$3" remote_sha="$4"
  printf '%s %s %s %s\n' "$local_ref" "$local_sha" "$remote_ref" "$remote_sha"
}

# --- 1. Passes when VERSION is in changed files ---

@test "passes when VERSION is among changed files" {
  cd "$TEST_WORKDIR"
  echo "1.0.1" > VERSION
  jq '.version = "1.0.1"' .claude-plugin/plugin.json > tmp.json && mv tmp.json .claude-plugin/plugin.json
  jq '.plugins[0].version = "1.0.1"' .claude-plugin/marketplace.json > tmp.json && mv tmp.json .claude-plugin/marketplace.json
  jq '.plugins[0].version = "1.0.1"' marketplace.json > tmp.json && mv tmp.json marketplace.json
  echo "new feature" > feature.txt
  git add -A && git commit -q -m "feat: add feature with version bump"
  local head_sha
  head_sha=$(git rev-parse HEAD)
  local prev_sha
  prev_sha=$(git rev-parse HEAD~1)
  run bash -c "cd '$TEST_WORKDIR' && push_stdin() { printf '%s %s %s %s\n' 'refs/heads/main' '$head_sha' 'refs/heads/main' '$prev_sha'; }; push_stdin | bash '$SUT'"
  assert_success
}

# --- 2. Fails when VERSION is not in changed files ---

@test "fails when VERSION is not among changed files" {
  cd "$TEST_WORKDIR"
  echo "new code" > newfile.txt
  git add newfile.txt && git commit -q -m "feat: add code without version bump"
  local head_sha
  head_sha=$(git rev-parse HEAD)
  local prev_sha
  prev_sha=$(git rev-parse HEAD~1)
  run bash -c "cd '$TEST_WORKDIR' && printf 'refs/heads/main %s refs/heads/main %s\n' '$head_sha' '$prev_sha' | bash '$SUT'"
  assert_failure
  assert_output --partial "VERSION not updated"
}

# --- 3. Passes on tag pushes (skipped) ---

@test "passes when pushing a delete (zero sha)" {
  run bash -c "cd '$TEST_WORKDIR' && printf 'refs/heads/main 0000000000000000000000000000000000000000 refs/heads/main abc123\n' | bash '$SUT'"
  assert_success
}

# --- 4. Exits 0 when no VERSION and no bump-version.sh ---

@test "exits 0 when project has no VERSION file or bump script" {
  cd "$TEST_WORKDIR"
  rm -f VERSION
  rm -rf scripts
  git add -A && git commit -q -m "chore: remove version files"
  run bash -c "cd '$TEST_WORKDIR' && echo '' | bash '$SUT'"
  assert_success
}

# --- 5. Fails on version file mismatch ---

@test "fails when version files are out of sync" {
  cd "$TEST_WORKDIR"
  echo "1.0.2" > VERSION
  # Don't update the other files, so they're mismatched
  git add -A && git commit -q -m "chore: mismatched version"
  local head_sha
  head_sha=$(git rev-parse HEAD)
  local prev_sha
  prev_sha=$(git rev-parse HEAD~1)
  run bash -c "cd '$TEST_WORKDIR' && printf 'refs/heads/main %s refs/heads/main %s\n' '$head_sha' '$prev_sha' | bash '$SUT'"
  assert_failure
  assert_output --partial "version files are out of sync"
}

# --- 6. Exits 0 when not in a git repo ---

@test "exits 0 gracefully when not in a git repo" {
  local nogit_dir
  nogit_dir=$(mktemp -d "$BATS_TEST_TMPDIR/yolo-nogit-XXXXXX")
  run bash -c "cd '$nogit_dir' && echo '' | bash '$SUT'"
  assert_success
}
