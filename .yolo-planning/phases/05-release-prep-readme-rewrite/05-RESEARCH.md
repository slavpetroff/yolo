# Phase 5 Research: Release Prep & README Rewrite

## VBW Remnants in Active Code

Only 2 files reference VBW outside .vbw-planning/:
1. **CLAUDE.md** (line 17): `VBW-specific:` rule about .vbw-planning/
2. **references/plugin-isolation.md**: VBW plugin isolation protocol

## Current README Analysis

- 996 lines, heavily detailed
- Token efficiency table shows v1.x analysis reports (stale — now at v2.4.0)
- Missing: concise "what you get" summary
- Missing: actual before/after comparison showing real workflow difference
- Overly long feature descriptions (good detail but buries the quick-start)
- Some stale references: "852 tests" (now 951+), v1.21.30 analysis reports

## Performance Data Available

5 token analysis docs in docs/, latest is v1.21.30. Key metrics:
- 86% reduction in coordination overhead (87,100 → 12,100 tokens)
- 50% cost reduction per phase ($2.78 → $1.40)
- 17% per-request overhead drop while codebase grew 64%
- vibe.md split: 7,220 → ~1,500 tokens per invocation (79% saving)

## Release Checklist

- VERSION: 2.4.0 (current), needs bump to 2.4.1
- 4 version files: VERSION, .claude-plugin/plugin.json, .claude-plugin/marketplace.json, marketplace.json
- CHANGELOG.md: has [Unreleased] section? Need to check
- Git tag: v2.4.0 exists, next will be v2.4.1
- GitHub release: via `gh release create`
