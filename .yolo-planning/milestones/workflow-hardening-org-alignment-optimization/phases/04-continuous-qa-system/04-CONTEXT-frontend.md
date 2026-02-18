# Phase 4 Frontend Context: Continuous QA System

## Vision
Transform QA from phase-end-only to continuous. Ensure QA gate configuration and reporting integrates with the plugin interface patterns.

## Department Requirements
- QA gate configuration: new config.json fields for gate enable/disable per level
- QA gate reporting: structured JSONL output for gate results (parseable by other tools)
- Plugin hook integration: QA gates fire at correct hook points in the plugin lifecycle
- Config schema updates: document new QA-related config options in config.md

## Constraints
- This is a Claude Code plugin, not a web frontend
- "Frontend" = plugin interface, config schema, command interface
- No npm, no build step, no package.json
- Config changes backward-compatible (new fields have defaults)

## Integration Points
- config.json schema: new QA gate configuration fields
- commands/config.md: expose QA gate settings
- Plugin hooks: QA gates as PreToolUse/PostToolUse hooks where applicable
- JSONL output schemas: gate result formats in artifact-formats.md
