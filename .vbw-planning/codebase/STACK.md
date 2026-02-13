# Tech Stack

## Primary Language

- **Bash** (100% of logic) -- All scripts target bash, not POSIX sh. Scripts use `set -u` minimum, `set -euo pipefail` for critical scripts.

## Configuration & Data

- **JSON** -- All structured data: config.json, model-profiles.json, stack-mappings.json, discovery.json, execution-state.json, cost-ledger.json, conventions.json
- **YAML frontmatter** -- Structured metadata in PLAN.md, SUMMARY.md, VERIFICATION.md templates. Parsed with awk/sed in hooks and jq when available.
- **Markdown** -- Commands (commands/*.md), agents (agents/*.md), references (references/*.md), templates (templates/*.md). Markdown IS the application logic -- Claude Code interprets these as instructions.

## Runtime Dependencies

- **jq** -- Required. Used for all JSON parsing. Guards exist in every script that uses it. Without jq, all 17 quality gates are disabled.
- **git** -- Required for brownfield detection, commit validation, version tracking, hook installation, branch management, pre-push hooks.
- **bash** -- Required. All scripts and hook-wrapper.sh target bash explicitly.
- **curl** -- Used for update checks (GitHub raw content fetch) and Anthropic API usage fetching in statusline.
- **npx** -- Optional. Used for skills installation (`npx skills add ...`).
- **sed/awk/grep** -- Standard Unix tools used throughout for text processing.
- **date/stat/wc/sort** -- Standard Unix utilities for timestamps, file stats, counting, sorting.

## Platform

- **Claude Code Plugin System** -- The entire application runs as a Claude Code plugin. Hooks, commands, and agents are declared in hooks.json and discovered via the plugin cache system.
- **macOS + Linux** -- Platform-aware code (stat flags differ between Darwin and GNU), security credential access via macOS Keychain (security command).

## Build System

- **None** -- Zero-dependency design. No package.json, npm, or build step. No compilation. Plugin is distributed via git clone and cached by Claude Code's plugin system.

## Version Management

- Single `VERSION` file at root (currently 1.10.18)
- `scripts/bump-version.sh` syncs version across VERSION, plugin.json, marketplace.json, CHANGELOG.md

## Python (Peripheral)

- `.python-version`, `pyproject.toml`, `uv.lock`, `main.py`, `.venv/` exist at root but are NOT part of the YOLO plugin. These appear to be for a separate/experimental purpose (FastAPI/uvicorn/httpx/pydantic in .venv).
