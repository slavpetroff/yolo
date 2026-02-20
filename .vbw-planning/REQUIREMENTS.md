# Requirements

Defined: 2026-02-20

## Requirements

### REQ-01: Core CLI commands (resolve-agent-model, resolve-agent-max-turns, planning-git) are highest priority — called most frequently from commands
**Must-have**

### REQ-02: Bootstrap scripts (4x bootstrap-*.sh) are critical for init and vibe workflows
**Must-have**

### REQ-03: Hook scripts (validate-summary, validate-frontmatter, agent-start/stop) run on every tool use — performance-critical
**Must-have**

### REQ-04: Feature/v3 scripts (lock-lite, lease-lock, validate-contract, etc.) can be lower priority
**Should-have**

### REQ-05: Telemetry scripts (log-event, collect-metrics) are side-effects — migrate last
**Nice-to-have**

## Out of Scope

_(To be defined)_

