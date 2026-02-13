#!/usr/bin/env bash
# mock_stdin.bash — Stdin piping helpers for hook script testing

# Pipe a fixture JSON file to a script's stdin
# Usage: run_with_stdin <fixture_file> <script_path> [args...]
run_with_stdin() {
  local stdin_file="$1"; shift
  run bash -c "cat '$stdin_file' | bash '$@'"
}

# Pipe inline JSON string to a script's stdin
# Usage: run_with_json '{"key":"val"}' <script_path> [args...]
run_with_json() {
  local json="$1"; shift
  run bash -c "printf '%s' '$json' | bash '$@'"
}

# Pipe inline string to a script's stdin (for non-JSON)
# Usage: run_with_input "some text" <script_path> [args...]
run_with_input() {
  local input="$1"; shift
  run bash -c "printf '%s' '$input' | bash '$@'"
}
