#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir

  cd "$TEST_TEMP_DIR"
  git init -q
  git config user.name "YOLO Test"
  git config user.email "yolo-test@example.com"

  echo "seed" > README.md
  git add README.md
  git commit -q -m "chore(init): seed"
}

teardown() {
  teardown_temp_dir
}

@test "sync-ignore adds .yolo-planning to root gitignore when planning_tracking=ignore" {
  cat > .yolo-planning/config.json <<'EOF'
{
  "planning_tracking": "ignore",
  "auto_push": "never"
}
EOF

  run bash "$SCRIPTS_DIR/planning-git.sh" sync-ignore .yolo-planning/config.json
  [ "$status" -eq 0 ]

  run grep -qx '\.yolo-planning/' .gitignore
  [ "$status" -eq 0 ]
}

@test "sync-ignore removes root ignore and writes transient planning ignore when commit mode" {
  cat > .gitignore <<'EOF'
.yolo-planning/
EOF

  cat > .yolo-planning/config.json <<'EOF'
{
  "planning_tracking": "commit",
  "auto_push": "never"
}
EOF

  run bash "$SCRIPTS_DIR/planning-git.sh" sync-ignore .yolo-planning/config.json
  [ "$status" -eq 0 ]

  run grep -qx '\.yolo-planning/' .gitignore
  [ "$status" -ne 0 ]

  run grep -q '^\.execution-state\.json$' .yolo-planning/.gitignore
  [ "$status" -eq 0 ]

  run grep -q '^\.context-\*\.md$' .yolo-planning/.gitignore
  [ "$status" -eq 0 ]
}

@test "sync-ignore includes all transient runtime artifacts in commit mode" {
  cat > .yolo-planning/config.json <<'EOF'
{
  "planning_tracking": "commit",
  "auto_push": "never"
}
EOF

  run bash "$SCRIPTS_DIR/planning-git.sh" sync-ignore .yolo-planning/config.json
  [ "$status" -eq 0 ]

  expected_entries=(
    '.execution-state.json'
    '.execution-state.json.tmp'
    '.context-*.md'
    '.contracts/'
    '.locks/'
    '.token-state/'
    '.yolo-session'
    '.active-agent'
    '.active-agent-count'
    '.active-agent-count.lock/'
    '.agent-pids'
    '.task-verify-seen'
    '.metrics/'
    '.cost-ledger.json'
    '.cache/'
    '.artifacts/'
    '.events/'
    '.event-log.jsonl'
    '.snapshots/'
    '.hook-errors.log'
    '.compaction-marker'
    '.session-log.jsonl'
    '.session-log.jsonl.tmp'
    '.notification-log.jsonl'
    '.watchdog-pid'
    '.watchdog.log'
    '.claude-md-migrated'
    '.tmux-mode-patched'
    '.baselines/'
    'codebase/'
  )

  for entry in "${expected_entries[@]}"; do
    run grep -Fqx "$entry" .yolo-planning/.gitignore
    [ "$status" -eq 0 ]
  done

  actual_entries="$(grep -Ev '^(#|$)' .yolo-planning/.gitignore | sort)"
  expected_entries_sorted="$(printf '%s\n' "${expected_entries[@]}" | sort)"
  [ "$actual_entries" = "$expected_entries_sorted" ]
}

@test "commit-boundary excludes transient files from commit" {
  cat > .yolo-planning/config.json <<'EOF'
{
  "planning_tracking": "commit",
  "auto_push": "never"
}
EOF

  # Create a legitimate planning artifact
  cat > .yolo-planning/STATE.md <<'EOF'
# State
Updated
EOF

  # Create transient runtime files that should be excluded
  echo "12345" > .yolo-planning/.agent-pids
  echo "session-abc" > .yolo-planning/.yolo-session
  echo "lead" > .yolo-planning/.active-agent
  echo "migrated" > .yolo-planning/.claude-md-migrated
  echo "patched" > .yolo-planning/.tmux-mode-patched
  echo "99999" > .yolo-planning/.watchdog-pid
  echo "watchdog started" > .yolo-planning/.watchdog.log
  echo '{"type":"info"}' > .yolo-planning/.notification-log.jsonl
  echo '{"status":"running"}' > .yolo-planning/.execution-state.json.tmp
  mkdir -p .yolo-planning/.metrics
  echo '{}' > .yolo-planning/.metrics/run-metrics.jsonl
  mkdir -p .yolo-planning/.baselines
  echo '{"baseline":1}' > .yolo-planning/.baselines/token-baseline.json
  mkdir -p .yolo-planning/.active-agent-count.lock
  echo 'stale' > .yolo-planning/.active-agent-count.lock/stale.lock

  run bash "$SCRIPTS_DIR/planning-git.sh" commit-boundary "phase complete" .yolo-planning/config.json
  [ "$status" -eq 0 ]

  # STATE.md should be committed
  run git cat-file -e 'HEAD:.yolo-planning/STATE.md'
  [ "$status" -eq 0 ]

  # Transient files should NOT be committed
  transient_paths=(
    '.agent-pids'
    '.yolo-session'
    '.active-agent'
    '.claude-md-migrated'
    '.tmux-mode-patched'
    '.watchdog-pid'
    '.watchdog.log'
    '.notification-log.jsonl'
    '.execution-state.json.tmp'
    '.metrics/run-metrics.jsonl'
    '.baselines/token-baseline.json'
    '.active-agent-count.lock/stale.lock'
  )

  for path in "${transient_paths[@]}"; do
    run git cat-file -e "HEAD:.yolo-planning/$path"
    [ "$status" -ne 0 ]
  done
}

@test "commit-boundary creates planning artifacts commit in commit mode" {
  cat > .yolo-planning/config.json <<'EOF'
{
  "planning_tracking": "commit",
  "auto_push": "never"
}
EOF

  cat > .yolo-planning/STATE.md <<'EOF'
# State

Updated
EOF

  cat > CLAUDE.md <<'EOF'
# CLAUDE

Updated
EOF

  run bash "$SCRIPTS_DIR/planning-git.sh" commit-boundary "bootstrap project" .yolo-planning/config.json
  [ "$status" -eq 0 ]

  run git log -1 --pretty=%s
  [ "$status" -eq 0 ]
  [ "$output" = "chore(yolo): bootstrap project" ]
}

@test "commit-boundary is no-op in manual mode" {
  cat > .yolo-planning/config.json <<'EOF'
{
  "planning_tracking": "manual",
  "auto_push": "never"
}
EOF

  cat > .yolo-planning/STATE.md <<'EOF'
# State

Updated
EOF

  BEFORE=$(git rev-list --count HEAD)

  run bash "$SCRIPTS_DIR/planning-git.sh" commit-boundary "phase update" .yolo-planning/config.json
  [ "$status" -eq 0 ]

  AFTER=$(git rev-list --count HEAD)
  [ "$BEFORE" = "$AFTER" ]
}