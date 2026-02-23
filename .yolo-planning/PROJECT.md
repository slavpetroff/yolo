# Token Efficiency: Rust Offload & Instruction Compression

Maximize token efficiency by offloading all deterministic LLM work to the Rust binary, fixing failing tests, and compressing agent/command instructions to eliminate wasted tokens.

**Core value:** Every token spent on deterministic work (state parsing, file discovery, progress counting, frontmatter extraction, cost math) is a token wasted. Move it to Rust. Compress what remains.

## Requirements

### Validated

### Active

### Out of Scope

## Constraints
- All new Rust commands must follow existing CLI router pattern
- No breaking changes to existing command interfaces
- Tests must pass after each phase
- Agent instructions must remain functional after compression

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
