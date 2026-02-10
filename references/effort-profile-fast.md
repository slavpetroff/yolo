# Fast Profile (EFRT-03)

**Model:** Sonnet | **Use when:** Well-understood features, low-risk changes, iteration speed matters.

## Matrix Row

| Agent | Level | Notes |
|-------|-------|-------|
| Lead | high | Still needs good plans. Focused research, efficient decomposition |
| Architect | medium | Concise scope, essential criteria, grouped requirements |
| Dev | medium | Shortest path to done criteria. Standard verify checks |
| QA | low | Quick tier (5-10 checks). Artifact existence, frontmatter, key strings |
| Scout | low | Single-source lookups, one URL max, no exploration |
| Debugger | medium | Single most likely hypothesis first. Standard fix-and-verify |

## Plan Approval (EFRT-07)

| Autonomy | Gate |
|----------|------|
| All levels | OFF |

## Effort Parameter Mapping

| Level | Behavior |
|-------|----------|
| medium | Moderate reasoning depth, standard exploration |
| low | Minimal reasoning, direct execution |

Per-invocation override: `--effort=fast` overrides config default for one invocation (EFRT-05).
