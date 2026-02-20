# YOLO Plugin

A Claude Code plugin that adds structured development workflows using specialized agent teams. Currently migrating from bash scripts to a Rust CLI and MCP server for better performance, reliability, and token efficiency.

**Core value:** Replace ad-hoc AI coding with repeatable, phased workflows.

## Requirements

### Validated

### Active

### Out of Scope

## Constraints
- **Rust CLI + MCP**: All logic migrating from bash scripts to Rust binary and MCP server tools
- **No npm/node**: Plugin uses Rust binary (`yolo`) for all operations
- **Backward compat**: Commands must work during migration (scripts → Rust)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
