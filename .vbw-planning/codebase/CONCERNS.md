# Technical Debt, Risks, and Concerns

## High Priority

### No Automated Tests
There are no unit tests, integration tests, or shell script tests for any of the 35 scripts. All verification is done at the semantic level by LLM agents. A regression in hook behavior (e.g., security-filter.sh failing to block) would not be caught until a user encounters it. The 4445 lines of shell code have no test coverage.

### Shell Script Complexity
`yolo-statusline.sh` (427 lines) and `session-start.sh` (330 lines) are large shell scripts with complex state management, caching, API calls, and platform-specific logic. These are difficult to debug and maintain without tests. The statusline script in particular handles OAuth token extraction from macOS Keychain, multi-tier caching (5s/60s TTL), cost attribution, and progress bar rendering.

### Security Model Assumptions
`security-filter.sh` uses pattern matching on file paths to block sensitive files. This can be bypassed via symlinks, path traversal, or encoding tricks. The fail-closed design (exit 2 on errors) is correct, but the pattern list is hardcoded and may miss new sensitive file patterns. The GSD isolation check depends on marker files that could be manipulated.

## Medium Priority

### Plugin Cache Resolution Fragility
Every hook command uses the same pattern to resolve script paths from the plugin cache:
```bash
ls -1 "$HOME"/.claude/plugins/cache/yolo-marketplace/yolo/*/scripts/hook-wrapper.sh | sort -V | tail -1
```
This depends on the cache directory structure matching expectations. `sort -V` is not available on all systems (fallback exists but adds complexity). The 16 hook entries in hooks.json each repeat this full resolution pattern.

### State File Race Conditions
Multiple hooks may fire concurrently on the same Write/Edit event. `state-updater.sh` uses `sed` with temp files for atomic updates, but there is no file locking. Concurrent SUMMARY.md writes from parallel Dev agents could cause state corruption in `.execution-state.json`, `STATE.md`, or `ROADMAP.md`.

### jq as Single Point of Failure
jq is required for all JSON operations. When jq is unavailable, all 17 quality gates are disabled (per session-start.sh warning). The fallback grep-based JSON parsing in phase-detect.sh is fragile. There is no graceful degradation path for individual features -- it is all-or-nothing.

### Large Command Files
`commands/go.md` (334 lines) and `commands/init.md` (483 lines) are very large prompt documents. The entire go.md is loaded into context for every `/yolo:go` invocation. This consumes significant tokens and makes the commands harder to maintain. The execute-protocol.md extraction helps but only covers one mode.

### Python Files at Root
`main.py`, `pyproject.toml`, `uv.lock`, `.python-version`, and `.venv/` exist at the project root but are not part of the YOLO plugin. This creates confusion about the project's actual stack. These should be clearly documented or moved.

## Low Priority

### Hardcoded Configuration
Several values are hardcoded in scripts rather than configurable:
- Hook error log max entries: 50 (hook-wrapper.sh)
- Update check interval: 86400 seconds (session-start.sh)
- Cache TTL: 5s fast, 60s slow (yolo-statusline.sh)
- Cost weights: opus=100, sonnet=20, haiku=2 (config.md)
- Max conventions: 15 auto-detected (teach.md)

### sed/awk for Structured Data
Several scripts use sed/awk to parse YAML frontmatter and markdown structure (compile-context.sh, state-updater.sh, file-guard.sh). While jq handles JSON, YAML parsing is ad-hoc and brittle. Malformed frontmatter could cause silent failures.

### No CI/CD
No GitHub Actions workflows exist. Version bumps, releases, and quality checks are manual. The pre-push hook provides some gate, but there is no automated pipeline for the plugin itself.

### Duplicate Version Sources
Version appears in 4 places: VERSION, .claude-plugin/plugin.json, marketplace.json, CHANGELOG.md. While bump-version.sh syncs them, manual edits could cause drift. The validate-commit.sh hook warns about mismatches but only during YOLO self-development.

### Platform-Specific Code
macOS-specific code (Keychain access via `security`, `stat -f %m`) is in the statusline script. While the statusline is optional, feature parity between macOS and Linux differs (no Keychain access on Linux means no usage limits display).

## Architectural Observations

### Prompt-as-Code Risk
The entire application logic lives in markdown files interpreted by an LLM. Model behavior changes (via updates or prompt sensitivity) could alter YOLO's behavior without any code changes. There is no way to pin model behavior for reproducibility.

### Token Cost
Every `/yolo:go` invocation loads go.md (~334 lines) plus phase-detect.sh output plus config. Heavy commands like init.md (~483 lines) consume substantial prompt tokens before any work begins. The context compiler helps but adds its own overhead.

### Single Maintainer
The plugin.json and marketplace.json list a single author. The architecture's reliance on prompt engineering and LLM behavior creates a high knowledge barrier for contributors.
