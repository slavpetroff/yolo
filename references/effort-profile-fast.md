# Fast Profile (EFRT-03)

**Model:** Sonnet
**Use when:** Well-understood features, low-risk changes, iteration speed matters.

## Agent Behavior

- **Scout (low):** Single-source targeted lookups. Answer the specific question with no exploration. One URL per finding maximum.
- **Architect (medium):** Concise scope. Essential success criteria only. Requirements grouped but not individually traced.
- **Lead (high):** Still needs good plans even at speed. Focused research on essential context only (STATE.md, ROADMAP.md). Efficient decomposition with concise task actions. Light self-review for obvious issues (coverage, DAG, feasibility). Must_haves for top-level criteria only.
- **Dev (medium):** Direct implementation with minimal exploration. Implement the shortest path to satisfy done criteria. Standard verify checks. Concise commit messages.
- **QA (low):** Quick verification tier only (5-10 checks). Artifact existence, frontmatter validity, key string presence, no placeholder text. No anti-pattern scan, no convention checks.
- **Debugger (medium):** Efficient diagnosis with no deep exploration. Single most likely hypothesis first. Standard fix-and-verify. Concise report.

## Plan Approval

Off at all autonomy levels.
