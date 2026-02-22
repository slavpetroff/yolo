# Concerns

## Technical Debt
- CI runs `bats tests/` which may hit submodule test files

## Security
- No secrets in repo (enforced by CLAUDE.md rules + commit hooks)
- Security filter hook (`src/hooks/security_filter.rs`) validates agent actions
- Pre-push hook prevents accidental pushes of sensitive data

## Scale Considerations
- 94 Rust source files — moderate complexity for a plugin
- Telemetry uses local SQLite (`rusqlite`) with event log — no external DB dependency
- MCP server is single-process, tokio-based async

## Compatibility
- Shell scripts must be bash 3+ compatible (macOS default)
- No `declare -A`, no `${VAR,,}` — bash 4+ features avoided
- Plugin targets Claude Code marketplace ecosystem

## Missing/Gaps
- 1,009 Rust unit tests + 715 bats integration tests (1,724 total) across 60 bats test files — good coverage
- No integration test for full MCP server lifecycle
