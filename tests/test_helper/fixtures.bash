#!/usr/bin/env bash
# fixtures.bash — Temp directory and fixture factories for YOLO tests

# Create isolated temp working directory (auto-cleaned by bats)
mk_test_workdir() {
  export TEST_WORKDIR="$(mktemp -d "$BATS_TEST_TMPDIR/yolo-test-XXXXXX")"
  cd "$TEST_WORKDIR"
}

# Create .yolo-planning/ skeleton with config.json
mk_planning_dir() {
  mkdir -p "$TEST_WORKDIR/.yolo-planning/phases"
  cp "$FIXTURES_DIR/config/balanced-config.json" "$TEST_WORKDIR/.yolo-planning/config.json"
}

# Create a phase directory with plan/summary files
# Usage: mk_phase <num> <slug> [plans] [summaries]
mk_phase() {
  local num="$1" slug="$2" plans="${3:-0}" summaries="${4:-0}"
  local dir="$TEST_WORKDIR/.yolo-planning/phases/$(printf '%02d' "$num")-${slug}"
  mkdir -p "$dir"
  local i
  for ((i = 1; i <= plans; i++)); do
    cp "$FIXTURES_DIR/plans/valid-plan.jsonl" "$dir/$(printf '%02d-%02d' "$num" "$i").plan.jsonl"
  done
  for ((i = 1; i <= summaries; i++)); do
    cp "$FIXTURES_DIR/summaries/valid-summary.jsonl" "$dir/$(printf '%02d-%02d' "$num" "$i").summary.jsonl"
  done
  echo "$dir"
}

# Create a minimal git repo for commit-dependent tests
mk_git_repo() {
  cd "$TEST_WORKDIR"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "init" > README.md
  git add README.md && git commit -q -m "chore(init): initial commit"
}

# Create a recent commit with optional age offset
# Usage: mk_recent_commit "feat(01-01): add auth" [age_seconds]
mk_recent_commit() {
  local msg="$1" age_seconds="${2:-0}"
  cd "$TEST_WORKDIR"
  if [ "$age_seconds" -gt 0 ]; then
    local ts
    # macOS date
    ts=$(date -v-${age_seconds}S +"%Y-%m-%dT%H:%M:%S" 2>/dev/null) || \
    # Linux date fallback
    ts=$(date -d "-${age_seconds} seconds" +"%Y-%m-%dT%H:%M:%S" 2>/dev/null) || \
    ts=$(date +"%Y-%m-%dT%H:%M:%S")
    GIT_COMMITTER_DATE="$ts" GIT_AUTHOR_DATE="$ts" \
      git commit --allow-empty -q -m "$msg"
  else
    git commit --allow-empty -q -m "$msg"
  fi
}

# Create active-agent marker
mk_active_agent() {
  echo "${1:-yolo-dev}" > "$TEST_WORKDIR/.yolo-planning/.active-agent"
}

# Create YOLO session marker
mk_yolo_session() {
  echo "session" > "$TEST_WORKDIR/.yolo-planning/.yolo-session"
}

# Create GSD isolation flag
mk_gsd_isolation() {
  touch "$TEST_WORKDIR/.yolo-planning/.gsd-isolation"
}

# Create state.json
mk_state_json() {
  local phase="${1:-1}" total="${2:-2}" status="${3:-executing}"
  jq -n --argjson ph "$phase" --argjson tt "$total" --arg st "$status" \
    '{ms:"test",ph:$ph,tt:$tt,st:$st,step:"plan",pr:0,started:"2026-01-01"}' \
    > "$TEST_WORKDIR/.yolo-planning/state.json"
}

# Create STATE.md with standard format
mk_state_md() {
  local phase="${1:-1}" total="${2:-2}"
  cat > "$TEST_WORKDIR/.yolo-planning/STATE.md" <<EOF
# Test Milestone

Phase: ${phase} of ${total} (Test Phase)
Status: active
Plans: 0/0
Progress: 0%

## Codebase Profile
- **Language:** Bash
- **Test Coverage:** None
EOF
}

# Create ROADMAP.md with standard format
mk_roadmap() {
  cat > "$TEST_WORKDIR/.yolo-planning/ROADMAP.md" <<'EOF'
# Test Roadmap

## Progress
| Phase | Status | Plans | Tasks | Commits |
|-------|--------|-------|-------|---------|
| 1 | Pending | 0 | 0 | 0 |
| 2 | Pending | 0 | 0 | 0 |

---

## Phase List
- [ ] Phase 1: Setup
- [ ] Phase 2: Build

---
EOF
}

# Create .execution-state.json
mk_execution_state() {
  local phase="${1:-01}" plan="${2:-01-01}"
  jq -n --arg p "$phase" --arg n "$plan" \
    '{phases:{($p):{($n):{status:"pending"}}}}' \
    > "$TEST_WORKDIR/.yolo-planning/.execution-state.json"
}
