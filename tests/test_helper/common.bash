#!/usr/bin/env bash
# common.bash — Shared setup loaded by every test file

# Resolve test_helper directory (where this file lives)
_HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_TESTS_DIR="$(cd "$_HELPER_DIR/.." && pwd)"

# Resolved paths
PROJECT_ROOT="$(cd "$_TESTS_DIR/.." && pwd)"
SCRIPTS_DIR="$PROJECT_ROOT/scripts"
BOOTSTRAP_DIR="$PROJECT_ROOT/scripts/bootstrap"
AGENTS_DIR="$PROJECT_ROOT/agents"
COMMANDS_DIR="$PROJECT_ROOT/commands"
CONFIG_DIR="$PROJECT_ROOT/config"
HOOKS_JSON="$PROJECT_ROOT/hooks/hooks.json"
FIXTURES_DIR="$_TESTS_DIR/fixtures"

# Load bats helpers using absolute paths
load "$_HELPER_DIR/bats-support/load"
load "$_HELPER_DIR/bats-assert/load"
load "$_HELPER_DIR/bats-file/load"
