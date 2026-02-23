# Research: Hard Typification & Contract Enforcement

**Date**: 2026-02-23
**Scope**: Audit of type safety across MCP, CLI, hooks, config, inter-agent messaging, and planning artifacts

## Current State Summary

| System | Typing | Validation | Risk |
|--------|--------|------------|------|
| MCP Protocol | Strong (struct/enum) | Schema declared | LOW |
| CLI Commands | Weak (strings) | Arg count only | MEDIUM |
| Inter-Agent Msgs | Value + schema | Feature-gated (off) | MEDIUM |
| Hook Contracts | Enum + Value | Field extraction | HIGH |
| Config | No schema | None | CRITICAL |
| Planning Artifacts | Partial | Feature-gated (off) | MEDIUM |

## Critical Findings

### 1. Config is Schema-less (CRITICAL)
- `config/defaults.json` has 57 keys, zero validation
- Feature flags read via `.get("key").and_then(|v| v.as_bool()).unwrap_or(false)`
- String "true" silently becomes false (type mismatch ignored)
- Missing config.json silently disables ALL enforcement gates
- No migration validation after merge

### 2. Feature Flags Fail-Open (HIGH)
- `v2_hard_contracts`, `v2_typed_protocol`, `v3_schema_validation` all default false
- If config read fails, all flags silently become false
- No startup validation loop
- No warning logged when enforcement is disabled

### 3. CLI Uses String Dispatch (MEDIUM)
- 73+ commands routed via `match args[1].as_str()` in router.rs
- No command enum, no type-safe argument parsing
- Phase/task numbers stay as strings until last moment
- No clap or custom parser — manual `&args[N]` access

### 4. Hook Inputs Untyped (HIGH)
- HookInput wraps `serde_json::Value` (untyped)
- Handlers extract fields via `.get("field")` chains
- Missing fields silently ignored (fail-open)
- No formal schema for what each hook event receives

### 5. No Domain Newtypes (MEDIUM)
- `task_id`, `phase`, `wave`, `role` all plain String/u64
- Compiler cannot prevent `task_id` ↔ `phase` swaps
- 144 occurrences of `serde_json::Value` in 43 source files

### 6. Inter-Agent Messaging Optional (MEDIUM)
- `validate_message.rs` has full schema validation
- Gated by `v2_typed_protocol` (default false)
- Schema file loaded with fail-open fallback
- Well-designed but disabled by default

## Recommended Priority Order

1. Config JSON schema + validation at startup
2. Feature flag enum + startup enforcement check
3. Enable v2_typed_protocol, v3_schema_validation by default
4. CLI command enum (replace string routing)
5. Domain newtypes (TaskId, Phase, FilePath)
6. Typed hook inputs (selective, critical hooks first)
