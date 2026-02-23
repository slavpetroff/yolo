# Requirements

Defined: 2026-02-23

## Requirements

### REQ-01: Audit all 79 Rust command modules for code quality issues (dead code, unreachable branches, error handling, naming)
**Must-have**

### REQ-02: Audit all 24 Rust hook modules for logic issues, redundant checks, and correctness
**Must-have**

### REQ-03: Audit all 23 command markdown files for token waste (verbose instructions, repeated boilerplate, inline shell/jq that should be Rust)
**Must-have**

### REQ-04: Audit 8 agent definition files for token efficiency and protocol redundancy
**Must-have**

### REQ-05: Identify deterministic LLM work still done in markdown that should be offloaded to Rust CLI
**Must-have**

### REQ-06: Identify redundant or overlapping commands (commands doing similar things, unused commands)
**Must-have**

### REQ-07: Audit skills (execute-protocol 942 LOC, discussion-engine 181 LOC, etc.) for verbosity and logic issues
**Should-have**

### REQ-08: Audit reference documents for accuracy, freshness, and token waste
**Should-have**

### REQ-09: Audit config files and schemas for consistency with actual code behavior
**Should-have**

### REQ-10: Audit test coverage gaps — untested Rust commands, missing edge cases
**Should-have**

### REQ-11: Remediate critical findings from audit phases
**Must-have**

## Out of Scope
- New features unrelated to audit findings
- Changes to MCP server JSON-RPC protocol
- UI/UX redesign of output formats
