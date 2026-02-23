# Requirements

Defined: 2026-02-23

## Requirements

### REQ-01: Review gate must spawn actual yolo-reviewer agent for adversarial plan review (not just Rust CLI structural checks)
**Must-have**

### REQ-02: QA gate must spawn actual yolo-qa agent for verification (not just Rust CLI format checks)
**Must-have**

### REQ-03: Execution family (dev, qa, debugger) must receive ARCHITECTURE.md in tier2 context to prevent architectural drift
**Must-have**

### REQ-04: Execute protocol step headings must not use "(optional)" label when config gates are set to "always" — enforce gate activation unconditionally
**Must-have**

### REQ-05: Add step-ordering verification to prevent Claude from skipping or reordering workflow steps
**Must-have**

### REQ-06: Strengthen lead delegation mandate with explicit anti-takeover instructions that survive context compression
**Should-have**

### REQ-07: Add integration tests verifying reviewer agent spawn and QA agent spawn during execution
**Should-have**

### REQ-08: Validate that feedback loops (review reject → architect revise → re-review) actually trigger with real agent-quality review
**Should-have**

## Out of Scope
- New agent types beyond reviewer/QA
- Changes to the Rust CLI commands themselves (they remain as pre-checks)
- Milestone management or archive workflow changes
