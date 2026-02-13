#!/usr/bin/env bats
# convention-compliance.bats — Validate YOLO coding conventions

setup() {
  load '../test_helper/common'
}

@test "all scripts in scripts/ use bash shebang" {
  local fail=0
  # Check top-level scripts and bootstrap/ subdirectory
  while IFS= read -r script; do
    local first_line
    first_line=$(head -1 "$script")
    if [[ "$first_line" != "#!/usr/bin/env bash" ]] && [[ "$first_line" != "#!/bin/bash" ]]; then
      echo "FAIL: $script has shebang: $first_line" >&2
      fail=1
    fi
  done < <(find "$SCRIPTS_DIR" -name '*.sh' -type f)
  [ "$fail" -eq 0 ]
}

@test "all files in scripts/ are .sh files" {
  local fail=0
  while IFS= read -r file; do
    local basename
    basename=$(basename "$file")
    # Skip directories
    [ -d "$file" ] && continue
    if [[ "$basename" != *.sh ]]; then
      echo "FAIL: non-.sh file found: $file" >&2
      fail=1
    fi
  done < <(find "$SCRIPTS_DIR" -type f)
  [ "$fail" -eq 0 ]
}

@test "all commands are .md files in commands/" {
  local fail=0
  while IFS= read -r file; do
    local basename
    basename=$(basename "$file")
    if [[ "$basename" != *.md ]]; then
      echo "FAIL: non-.md file in commands/: $file" >&2
      fail=1
    fi
  done < <(find "$COMMANDS_DIR" -maxdepth 1 -type f)
  [ "$fail" -eq 0 ]
}

@test "all agents are named yolo-{role}.md in agents/" {
  local fail=0
  while IFS= read -r file; do
    local basename
    basename=$(basename "$file")
    if [[ "$basename" != yolo-*.md ]]; then
      echo "FAIL: agent not matching yolo-{role}.md pattern: $basename" >&2
      fail=1
    fi
  done < <(find "$AGENTS_DIR" -maxdepth 1 -type f -name '*.md')
  [ "$fail" -eq 0 ]
}

@test "phase directories follow NN-slug pattern" {
  local planning_dir="$PROJECT_ROOT/.yolo-planning"
  local phases_dir="$planning_dir/phases"
  if [ ! -d "$phases_dir" ]; then
    skip "No .yolo-planning/phases/ directory found"
  fi
  local fail=0
  while IFS= read -r dir; do
    local dirname
    dirname=$(basename "$dir")
    if ! [[ "$dirname" =~ ^[0-9]{2}-.+ ]]; then
      echo "FAIL: phase directory does not match NN-slug pattern: $dirname" >&2
      fail=1
    fi
  done < <(find "$phases_dir" -mindepth 1 -maxdepth 1 -type d)
  [ "$fail" -eq 0 ]
}

@test "no script parses JSON files with grep or sed instead of jq" {
  # Check for patterns like: grep <something> <file>.json or sed <something> <file>.json
  # These indicate reading/parsing JSON content directly — a convention violation.
  # Exclude path-matching patterns (grep -qE '\.json$' or echo | grep) which are
  # checking if a variable string ends in .json, not parsing JSON content.
  local fail=0
  while IFS= read -r script; do
    # Look for lines that read a .json file directly with grep/sed
    # Pattern: grep/sed with a literal .json file as argument (not piped string matching)
    # Match: grep "key" foo.json, sed 's/x/y/' config.json
    # Skip: echo "$x" | grep -q '.json' (path matching), grep -l pattern (file search)
    while IFS= read -r line; do
      # Skip lines that pipe into grep/sed (path matching on strings)
      [[ "$line" == *'echo'*'|'*'grep'* ]] && continue
      [[ "$line" == *'echo'*'|'*'sed'* ]] && continue
      # Skip lines that are comments
      [[ "$line" =~ ^[[:space:]]*# ]] && continue
      # Check for direct JSON file reading: grep/sed with a .json file argument at end
      if [[ "$line" =~ (grep|sed)[[:space:]].*[[:space:]][^|]*\.json[^a-zA-Z] ]] || \
         [[ "$line" =~ (grep|sed)[[:space:]].*[[:space:]][^|]*\.json$ ]]; then
        # Further filter: skip if the .json is in a quoted string pattern (path matching)
        [[ "$line" =~ \.json\$ ]] && continue
        [[ "$line" =~ \.json\| ]] && continue
        [[ "$line" =~ credentials\.json ]] && continue
        [[ "$line" =~ secrets\.json ]] && continue
        [[ "$line" =~ service-account ]] && continue
        echo "FAIL: $script uses grep/sed on JSON: $line" >&2
        fail=1
      fi
    done < <(cat "$script")
  done < <(find "$SCRIPTS_DIR" -name '*.sh' -type f)
  [ "$fail" -eq 0 ]
}

@test "critical scripts have set -u" {
  local critical_scripts=(
    "$SCRIPTS_DIR/security-filter.sh"
    "$SCRIPTS_DIR/file-guard.sh"
    "$SCRIPTS_DIR/qa-gate.sh"
    "$SCRIPTS_DIR/task-verify.sh"
  )
  local fail=0
  for script in "${critical_scripts[@]}"; do
    [ -f "$script" ] || { echo "FAIL: critical script not found: $script" >&2; fail=1; continue; }
    if ! grep -qE '^set -[a-zA-Z]*u' "$script"; then
      echo "FAIL: $script missing 'set -u'" >&2
      fail=1
    fi
  done
  [ "$fail" -eq 0 ]
}

@test "hook scripts document exit code semantics" {
  # Hook scripts that use exit 2 or exit 0 should document the meaning in comments.
  # Formats vary: "Exit 2 = block", "exit 2 only on", "exit 0 on any error", etc.
  local hook_scripts=(
    "$SCRIPTS_DIR/security-filter.sh"
    "$SCRIPTS_DIR/file-guard.sh"
    "$SCRIPTS_DIR/qa-gate.sh"
    "$SCRIPTS_DIR/task-verify.sh"
  )
  local fail=0
  for script in "${hook_scripts[@]}"; do
    [ -f "$script" ] || { echo "FAIL: hook script not found: $script" >&2; fail=1; continue; }
    # Must have comments documenting both exit 0 and exit 2 behavior
    if ! grep -qiE '#.*exit 0' "$script"; then
      echo "FAIL: $script missing exit 0 documentation" >&2
      fail=1
    fi
    if ! grep -qiE '#.*exit 2' "$script"; then
      echo "FAIL: $script missing exit 2 documentation" >&2
      fail=1
    fi
  done
  [ "$fail" -eq 0 ]
}
