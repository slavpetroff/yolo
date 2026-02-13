# Codebase Mapping Metadata

mapped_at: 2026-02-13T22:45:00Z
git_hash: 498cc5465e15b203162408d79e95e691914ac080
file_count: 99
mode: full
monorepo: false
mapping_tier: solo

## Documents

| Document | Description |
|----------|-------------|
| STACK.md | Tech stack analysis (bash, shell scripts, markdown, jq, JSON) |
| DEPENDENCIES.md | External dependencies (jq, git, bash, curl, npx, Claude Code platform) |
| ARCHITECTURE.md | Architecture overview (6 layers: plugin registration, command dispatch, agent system, hook pipeline, state management, context compilation) |
| STRUCTURE.md | Directory/file structure map (20 commands, 6 agents, 35 scripts, 7 templates) |
| CONVENTIONS.md | Code conventions (naming, shell standards, commits, JSON handling, hooks, output formatting) |
| TESTING.md | Test infrastructure (no formal tests; multi-layered hook-based verification system) |
| CONCERNS.md | Technical debt and risks (no tests, shell complexity, security assumptions, race conditions) |
| PATTERNS.md | 14 recurring patterns (hook wrapper, cache resolution, atomic JSON, fail-open/closed, state detection, etc.) |
| INDEX.md | Cross-referenced index of key files, commands, hooks, and themes |
