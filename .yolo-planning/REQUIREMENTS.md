# Requirements

Defined: 2026-02-23

## Requirements

### REQ-01: Fix all failing tests (3 failures in validate-commit.bats and vibe-mode-split.bats)
**Must-have**

### REQ-02: Audit Rust CLI commands and arguments for completeness — ensure no LLM calls needed for deterministic operations
**Must-have**

### REQ-03: Create new Rust commands for deterministic work currently done in MD (frontmatter parsing, progress compilation, git state, plugin root resolution)
**Must-have**

### REQ-04: Enhance existing Rust commands with additional flags to avoid LLM reasoning (phase-detect --suggest-route, resolve-model --with-cost)
**Must-have**

### REQ-05: Compress agent instruction files to eliminate verbose boilerplate and redundant protocol descriptions
**Should-have**

### REQ-06: Revise command markdown files to call Rust CLI instead of inline shell/jq patterns
**Should-have**

### REQ-07: Consolidate repeated patterns across 23+ command files (plugin root, model resolution, phase progress)
**Should-have**

## Out of Scope
- New features unrelated to token efficiency
- Changes to MCP server protocol
- UI/UX redesign of output formats
