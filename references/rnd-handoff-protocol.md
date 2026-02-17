# R&D Handoff Protocol

Formalizes the Critic->Scout->Architect pipeline (Steps 1-3) and the Architect->Lead stage-gate handoff (Step 3->4). Referenced by execute-protocol.md.

## Pipeline Overview

```
Step 1: Critic → critique.jsonl (gap analysis)
   │ critical/major findings
   ▼
Step 2: Scout → research.jsonl (targeted research)
   │ all findings (pre-critic + post-critic)
   ▼
Step 3: Architect → architecture.toon (system design)
   │ stage-gate
   ▼
Step 4: Lead → plan.jsonl (task decomposition)
```

## Step 1: Critic Output

Critic produces critique.jsonl with findings. Each finding has:
- `id`: C1, C2, etc.
- `sev`: critical, major, minor
- `st`: open (initially)

**Filtering for Scout:** Only critical and major findings feed into Scout research directives. Minor findings are advisory and do not generate research tasks.

## Step 2: Scout Research Directives

For each critical/major finding from critique.jsonl, the orchestrator (go.md) generates a research directive:
- `directive`: Research question derived from the critique finding
- `brief_for`: Critique ID (e.g., C1) linking research back to the finding

Scout produces research.jsonl entries with:
- `mode: "post-critic"` -- targeted research for specific critique findings
- `addresses: ["C1"]` -- links back to critique IDs
- `conf: "high" | "medium" | "low"` -- confidence in finding

**Pre-existing research:** research.jsonl may already contain `mode: "pre-critic"` entries from earlier research runs. These coexist with post-critic entries (append mode).

**Failure modes:**
- Scout finds nothing: Entry with `finding: "No relevant information found"` and `conf: "low"`. Architect proceeds with available information.
- Conflicting sources: Scout reports both positions with evidence. Architect makes the decision.

## Step 3: Architect Consumption

Architect reads research.jsonl and processes entries by mode:
1. `post-critic` (high priority): Targeted findings linked to critique. Use `brief_for` to cross-reference critique ID. High-confidence findings carry more weight.
2. `pre-critic` (context): General best-practices research. Use as background.
3. `standalone` (reference): Research from /yolo:research. General reference.

Architect addresses each critique finding (updates `st` field in critique.jsonl).

## Architect->Lead Stage-Gate (Go/Recycle/Kill)

### Entry Criteria (architecture.toon must contain)

Before Lead can plan against architecture.toon, it must meet this completeness checklist:
1. **tech_decisions**: At least one decision with rationale and alternatives
2. **components**: All requirements mapped to components
3. **integration_points**: Integration points defined between components
4. **risks**: Risks identified with impact and mitigation
5. **critique_disposition**: Every critique finding has a disposition (addressed/deferred/rejected)

### Gate Review

Lead validates architecture.toon completeness at Step 4 entry:
1. Read architecture.toon
2. Check completeness criteria above
3. Make gate decision:
   - **Go**: All criteria met. Proceed to planning.
   - **Recycle**: Criteria incomplete. Escalate to Architect with specific gaps. Architect reworks and resubmits.
   - **Kill**: Architecture reveals phase should be deferred. Escalate to Architect -> User for scope decision.

### Feedback Loop

If Lead discovers architecture.toon incomplete DURING planning (after initial Go):
1. Lead escalates to Architect via `escalation` schema with specific gaps
2. Architect addresses gaps, updates architecture.toon
3. Lead re-validates and continues planning
4. This does NOT restart the full gate -- it is a targeted rework.

## Handoff Artifact Summary

| Step | From | To | Artifact | Schema |
|------|------|-----|----------|--------|
| 1->2 | Critic | Scout (via orchestrator) | critique.jsonl (critical/major only) | See references/artifact-formats.md |
| 2->3 | Scout | Architect | research.jsonl (append mode) | See references/artifact-formats.md |
| 3->4 | Architect | Lead | architecture.toon | See references/artifact-formats.md |

## Failure Modes

| Scenario | Handling |
|----------|----------|
| Critic has no findings | Skip Scout (Step 2 guard: turbo). Architect proceeds without research. |
| Scout finds nothing useful | Architect proceeds with available info. Low-confidence entries noted. |
| Conflicting research sources | Scout reports both. Architect decides in tech_decisions with rationale. |
| Architecture incomplete at gate | Lead sends Recycle. Architect reworks specific gaps. |
| Architecture reveals scope problem | Lead sends Kill. Architect escalates to User for scope decision. |
