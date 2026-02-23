# Concerns

## Technical Debt
- CI bats invocation should use explicit directory list to avoid hitting submodule test files
- Cargo.toml version (2.7.0) lags behind plugin VERSION (2.9.0)

## Security
- No secrets in repo (enforced by CLAUDE.md rules + commit hooks)
- Security filter hook (`src/hooks/security_filter.rs`) validates agent actions
- Pre-push hook prevents accidental pushes of sensitive data
- Plugin isolation enforced via `references/plugin-isolation.md`

## Scale Considerations
- 107 Rust source files — moderate-high complexity for a plugin
- 75 command modules — largest subsystem, growing per milestone
- Telemetry uses local SQLite (`rusqlite`) with event log — no external DB dependency
- MCP server is single-process, tokio-based async with retry logic

## Compatibility
- Shell scripts must be bash 3+ compatible (macOS default)
- No `declare -A`, no `${VAR,,}` — bash 4+ features avoided
- Plugin targets Claude Code marketplace ecosystem

## Test Health
- 68 bats test files covering unit, integration, contract, and QA verification
- Rust unit tests within `yolo-mcp-server/src/` modules
- No known test failures as of v2.9.0
