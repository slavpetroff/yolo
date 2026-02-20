---
phase: 2
plan: 12
title: "Migrate routing scripts to native Rust (assess-plan-risk, resolve-gate-policy, smart-route, route-monorepo)"
wave: 2
depends_on: [1, 2]
must_haves:
  - "assess_plan_risk classifies plan risk as low/medium/high from metadata signals"
  - "resolve_gate_policy resolves validation gate policy from effort/risk/autonomy matrix"
  - "smart_route determines agent inclusion/skip based on effort level"
  - "route_monorepo detects monorepo packages and maps plan files to package roots"
  - "All pure Rust logic — no jq, no awk, no Command::new(bash)"
---

## Task 1: Implement assess_plan_risk module

**Files:** `yolo-mcp-server/src/commands/assess_plan_risk.rs` (new)

**Acceptance:** `assess_plan_risk::execute(plan_path) -> Result<(String, i32), String>`. Scoring: task_count>5 (+1), file_count>8 (+1), cross_phase_deps present (+1), must_haves>4 (+1). Count tasks from `## Task N:` headings. Count unique file paths from `**Files:**` lines. Check `cross_phase_deps:` in frontmatter. Count must_haves list items. Score 0-1=low, 2=medium, 3+=high. Fail-open: default "medium" on any error. Also expose CLI entry point.

## Task 2: Implement resolve_gate_policy module

**Files:** `yolo-mcp-server/src/commands/resolve_gate_policy.rs` (new)

**Acceptance:** `resolve_gate_policy::execute(effort, risk, autonomy) -> Result<(String, i32), String>`. Gate matrix: turbo -> skip QA/no approval/none comm. fast+low/medium -> quick QA/no approval/blockers. fast+high (cautious/standard) -> quick QA/approval/blockers/two_phase. balanced+low -> standard QA/no approval/blockers_findings. balanced+medium (cautious) -> approval. balanced+high (cautious/standard) -> approval/two_phase. thorough+any (cautious/standard) -> deep QA/approval/two_phase/full comm. Output JSON: `{qa_tier, approval_required, communication_level, two_phase}`. Also expose CLI entry point.

## Task 3: Implement smart_route module

**Files:** `yolo-mcp-server/src/commands/smart_route.rs` (new)

**Acceptance:** `smart_route::execute(agent_role, effort) -> Result<(String, i32), String>`. Check `v3_smart_routing` flag in config. Scout: skip for turbo/fast. Architect: include only for thorough. All others: always include. Emit `smart_route` metric via `collect_metrics::collect()`. Output JSON: `{agent, decision, reason}`. Also expose CLI entry point.

## Task 4: Implement route_monorepo module

**Files:** `yolo-mcp-server/src/commands/route_monorepo.rs` (new)

**Acceptance:** `route_monorepo::execute(phase_dir) -> Result<(String, i32), String>`. Check `v3_monorepo_routing` flag. Detect package root markers (package.json, Cargo.toml, go.mod, pyproject.toml) up to 4 levels deep, skip `node_modules/`, `.git/`, `.yolo-planning/`, skip root-level markers. Extract file paths from `**Files:**` lines in `*-PLAN.md` files. Match plan files to package roots (prefix matching). Output JSON array of relevant package paths. Use `std::fs::read_dir` recursively (max depth 4) and `walkdir` or manual traversal. Also expose CLI entry point.

## Task 5: Register CLI commands and add tests

**Files:** `yolo-mcp-server/src/commands/mod.rs`, `yolo-mcp-server/src/cli/router.rs`, `yolo-mcp-server/src/commands/assess_plan_risk.rs` (append tests), `yolo-mcp-server/src/commands/resolve_gate_policy.rs` (append tests), `yolo-mcp-server/src/commands/smart_route.rs` (append tests)

**Acceptance:** Register `yolo assess-risk`, `yolo gate-policy`, `yolo smart-route`, `yolo route-monorepo` in router. Tests cover: risk scoring (low/medium/high), gate matrix for all effort/autonomy combinations, smart route skip/include for each role+effort combo, monorepo detection with nested package markers, plan file to package root mapping. `cargo test` passes.
