# Shipped: Type Safety & Self-Healing

**Date:** 2026-02-24
**Phases:** 2
**Plans:** 10
**Tasks:** 50
**Commits:** 42
**Deviations:** 0

## Phase 1: Hard Typification & Contract Enforcement

- Config JSON Schema (`config/config.schema.json`) with full validation at startup
- FeatureFlag enum replacing string-based config reads (22 variants)
- CLI Command enum for type-safe routing (66 variants, Levenshtein suggestions)
- Domain newtypes: TaskId, Phase, Wave, ResourceId
- Typed hook input structs: SecurityFilterInput, ContractValidationInput
- v2_typed_protocol and v3_schema_validation enabled by default

## Phase 2: Self-Healing Infrastructure

- MCP tool retry with exponential backoff (100ms base, 3 retries, jitter)
- Circuit breaker: disables tool after 5 consecutive failures, resets after 60s
- Atomic file writes with SHA256 checksum sidecars and backup restore
- Command execution timeouts (30s default, configurable via command_timeout_ms)
- Task lease TTL with auto-reassignment for crashed agents
- v3_event_recovery, v3_snapshot_resume, v3_lease_locks enabled by default
