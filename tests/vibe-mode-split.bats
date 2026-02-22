#!/usr/bin/env bats

load test_helper

# Mode files that should exist under skills/vibe-modes/
MODE_FILES=(bootstrap scope plan phase-mutation archive assumptions)

setup() {
  export VIBE_ROUTER="${PROJECT_ROOT}/commands/vibe.md"
  export MODES_DIR="${PROJECT_ROOT}/skills/vibe-modes"
}

# --- Test 1: All 6 new mode files exist ---

@test "vibe-mode-split: all mode files exist under skills/vibe-modes/" {
  for mode in "${MODE_FILES[@]}"; do
    [ -f "${MODES_DIR}/${mode}.md" ]
  done
}

# --- Test 2: Router is under 120 lines ---

@test "vibe-mode-split: router vibe.md is under 120 lines" {
  local lines
  lines=$(wc -l < "$VIBE_ROUTER")
  [ "$lines" -lt 120 ]
}

# --- Test 3: Router contains Read references for all mode files ---

@test "vibe-mode-split: router contains Read references for all mode files" {
  for mode in "${MODE_FILES[@]}"; do
    grep -q "skills/vibe-modes/${mode}.md" "$VIBE_ROUTER"
  done
}

# --- Test 4: Each mode file contains a Guard section ---

@test "vibe-mode-split: each mode file contains Guard section" {
  for mode in "${MODE_FILES[@]}"; do
    grep -qi "guard" "${MODES_DIR}/${mode}.md"
  done
}

# --- Test 5: No mode file contains YAML frontmatter ---

@test "vibe-mode-split: no mode file contains frontmatter" {
  for mode in "${MODE_FILES[@]}"; do
    local first_line
    first_line=$(head -1 "${MODES_DIR}/${mode}.md")
    [ "$first_line" != "---" ]
  done
}

# --- Test 6: Router still contains frontmatter with yolo:vibe ---

@test "vibe-mode-split: router contains frontmatter with yolo:vibe" {
  head -8 "$VIBE_ROUTER" | grep -q "name: yolo:vibe"
}

# --- Test 7: All mode files contain Steps header ---

@test "vibe-mode-split: all mode files contain Steps header" {
  for mode in "${MODE_FILES[@]}"; do
    grep -qE "^##?#? ?(Steps|Step)" "${MODES_DIR}/${mode}.md" || \
    grep -q "\*\*Steps:\*\*" "${MODES_DIR}/${mode}.md"
  done
}

# --- Test 8: Router contains references to existing delegated modes ---

@test "vibe-mode-split: router references execute-protocol and discussion-engine" {
  grep -q "skills/execute-protocol/SKILL.md" "$VIBE_ROUTER"
  grep -q "skills/discussion-engine/SKILL.md" "$VIBE_ROUTER"
  grep -q "commands/verify.md" "$VIBE_ROUTER"
}

# --- Test 9: Mode files are non-empty ---

@test "vibe-mode-split: all mode files are non-empty" {
  for mode in "${MODE_FILES[@]}"; do
    [ -s "${MODES_DIR}/${mode}.md" ]
  done
}
