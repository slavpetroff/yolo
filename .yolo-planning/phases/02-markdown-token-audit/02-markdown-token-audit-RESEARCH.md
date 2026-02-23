# Research: Phase 2 — Markdown & Token Efficiency Audit

## Findings

### P0 — Highest Impact

1. **Plugin root boilerplate in 17/23 commands** — 118-char shell expression repeated verbatim. Replace with `yolo plugin-root` or SessionStart hook injection. Savings: HIGH.

2. **Circuit Breaker duplicated in all 8 agents** — Same 3-line text in every agent file, already exists in `references/agent-base-protocols.md`. Remove per-agent copies. Savings: HIGH (~150 tokens per agent spawn).

3. **16 `<!-- v3: -->` dead comment markers in execute-protocol/SKILL.md** — Zero operational value in default path. File preamble already handles v3 flag loading. Remove all 16. Savings: HIGH.

4. **Tier 1/2/3 documentation block repeated twice in execute-protocol** — L352-356 and L367-380 are identical. Remove duplicate. Savings: HIGH (13 lines).

5. **Execution-state jq update pattern 8× in execute-protocol** — `jq ... > tmp && mv tmp` blocks. Replace with `yolo update-exec-state <plan> <key> <val>`. Savings: HIGH.

6. **log-event calls interleaved 8+ times in execute-protocol** — Internalize into `yolo update-exec-state`. Savings: HIGH.

7. **resolve-model + resolve-turns paired block in 7+ files** — 6-line block duplicated in execute-protocol (4×), plan.md, fix.md, debug.md, research.md. Replace with `yolo spawn-params <role> <effort>`. Savings: HIGH.

8. **"Discovered Issues" protocol copied 4×** — Nearly identical 15-line block in verify.md, debug.md, fix.md, execute-protocol/SKILL.md. Extract to reference. Savings: HIGH.

### P1 — High Impact

9. **config.md jq-tmp-mv pattern 8×** — Replace with `yolo config-set`. Savings: HIGH.
10. **Shutdown Handling duplicated in 4 agents** — Already in agent-base-protocols.md. Savings: MEDIUM.
11. **Context Injection duplicated in 3 agents** — Already in agent-base-protocols.md. Savings: MEDIUM.
12. **Effort footer duplicated in 5 agents** — Move to agent-base-protocols.md. Savings: MEDIUM.
13. **scout_findings schema missing from handoff-schemas.md** — BUG, not savings.
14. **Codebase size + tier selection in map.md** — `yolo size-codebase` Rust offload. Savings: HIGH.
15. **Scenario detection in init.md Step 5** — `yolo detect-scenario` Rust offload. Savings: HIGH.
16. **Delta findings jq in execute-protocol L135-156** — `yolo diff-findings` Rust offload. Savings: HIGH.
17. **Model cost calc in config.md (2×)** — `yolo estimate-cost` Rust offload. Savings: HIGH.
18. **Feature flags listing in config.md** — `yolo config-list-flags` Rust offload. Savings: MEDIUM.

### P2 — Medium Impact

19. **Plan Approval tables repeated 4× in effort-profiles.md** — Consolidate to 1 table. Savings: MEDIUM.
20. **Three agent tables in model-profiles.md** — Merge into 1 comparison table. Savings: MEDIUM.
21. **debug.md model resolution duplicated for Path A/B** — Deduplicate. Savings: MEDIUM.
22. **init.md: Timing rationale prose (14 lines)** — Remove developer docs. Savings: MEDIUM.
23. **init.md: INDEX.json field list (9 lines)** — Remove. Savings: MEDIUM.
24. **status.md progress computation** — Extend `yolo phase-detect` with progress field. Savings: MEDIUM.
25. **status.md economy section** — `yolo status-economy`. Savings: MEDIUM.
26. **release.md git commit parsing + README staleness** — `yolo release-audit`. Savings: MEDIUM.

### P3 — Low Impact

27. **discussion-engine Design Principles + Entry Points** — 14 lines, removable.
28. **verification-protocol Continuous Verification Hooks** — 8 lines, removable.
29. **todo.md vs list-todos.md STATE.md write overlap** — Low priority.

## Relevant Patterns
- Plugin root resolution is the single most-repeated boilerplate across all commands
- Agent files duplicate 4 patterns from agent-base-protocols.md (Circuit Breaker, Shutdown, Context Injection, Effort)
- execute-protocol/SKILL.md has the most token waste: dead v3 comments, duplicated docs, repeated jq patterns
- Config mutation (jq tmp-mv) pattern appears 8× in config.md alone
- Model resolution (resolve-model + resolve-turns) appears in 7+ files

## Risks
- Removing agent-level protocol duplication requires verifying compile-context injects agent-base-protocols.md
- Extracting "Discovered Issues" to a reference needs all 4 consuming files updated
- Rust offload commands (spawn-params, update-exec-state, diff-findings) need to be built before markdown can reference them

## Recommendations
- Split into: (1) markdown dedup/compression (no new Rust needed), (2) agent protocol consolidation, (3) Rust offload inventory (reference doc, no code)
- Phase 2 should produce FINDINGS + targeted fixes for pure markdown cleanup
- Rust offload candidates should be catalogued for a future milestone (not built in this audit)
