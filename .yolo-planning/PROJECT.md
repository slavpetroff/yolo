# Workflow Integrity Enforcement

Fix fundamental workflow integrity gaps where review gates, QA gates, context injection, and step ordering are defined in agent specs but never enforced during execution.

**Core value:** Every quality gate described in agent definitions must actually run and have blocking power during execution.

## Requirements

### Validated

### Active

### Out of Scope
- New workflow features not related to fixing existing gaps
- Changing the plugin's command interface
- MCP server protocol changes

## Constraints
- Fixes must be backward-compatible (no breaking changes to config schema)
- Tests must pass after each phase
- Execute protocol changes must work with all effort levels (thorough/balanced/fast/turbo)
- Agent definitions must remain usable as standalone subagent_types

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
