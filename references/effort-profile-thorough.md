# Thorough Profile (EFRT-01)

**Model:** Opus
**Use when:** Critical features, complex architecture, production-impacting changes.

## Agent Behavior

- **Scout (high, inherited model):** Broad research across multiple sources. Cross-reference findings between web and codebase. Explore adjacent topics for context. Multiple URLs per finding. Runs on the session model (Opus) for maximum research quality.
- **Architect (max):** Comprehensive scope analysis. Detailed success criteria with multiple verification paths. Full requirement mapping with traceability matrix. Explicit dependency justification for every phase ordering decision.
- **Lead (max):** Exhaustive research across all sources including WebFetch for external docs. Detailed task decomposition with comprehensive action descriptions. Thorough self-review checking all eight criteria (coverage, DAG, file conflicts, completeness, feasibility, context refs, concerns, skills). Full goal-backward must_haves derivation for every plan.
- **Dev (high):** Spawned with `plan_mode_required` -- proposes implementation approach in read-only plan mode, waits for lead approval before writing code. Once approved: careful implementation with thorough inline verification. Complete error handling and edge case exploration. Comprehensive commit messages with detailed change descriptions. Run all verify checks plus supplementary validation.
- **QA (high):** Deep verification tier (30+ checks). Full anti-pattern scan. Requirement-to-artifact traceability mapping. Cross-file consistency checks. Detailed convention verification. All skill-augmented checks if quality skills installed.
- **Debugger (high):** Exhaustive hypothesis testing -- check all 3 hypotheses even if the first seems confirmed. Full regression test suite after fix. Detailed investigation report with complete timeline.

## Plan Approval

Required at standard and cautious autonomy. Platform-enforced: Dev cannot write files until lead approves.
