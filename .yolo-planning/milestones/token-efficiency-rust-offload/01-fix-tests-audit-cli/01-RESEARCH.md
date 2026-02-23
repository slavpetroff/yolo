# Phase 1 Research: Fix Tests & Audit Rust CLI Coverage

## Findings

### Test Failures (3)

**validate-commit.bats #716 & #717:** Tests assert `exit 2` but the hook returns exit 0 with JSON `permissionDecision: "deny"`. The Rust `security_filter.rs` `deny()` method prints message to stderr and returns `HookOutput::block(json)` with exit code 2. However tests check `$output` for stderr message — the actual stdout contains JSON deny payload. Fix: update assertions to check JSON deny output format.

**vibe-mode-split.bats #725:** Expects `name: yolo:vibe` in `commands/vibe.md` frontmatter, but that field doesn't exist. Current frontmatter has description, argument-hint, allowed-tools, disable-model-invocation. Fix: add `name: yolo:vibe` to frontmatter.

### Rust CLI Audit: 59 Subcommands

Current commands in router.rs cover: bootstrap, detect-stack, infer, phase-detect, resolve-model, resolve-turns, planning-git, compile-context, verify, review-plan, check-regression, commit-lint, diff-against-plan, validate-requirements, verify-plan-completion, session-start, statusline, token-baseline, delta-files, compress-context, feature-flags, validate-plan, prune-completed, and 36 more.

### Deterministic Gaps (No Rust Equivalent)

1. **Cost calculation** — inline bash arithmetic in config.md (opus=100, sonnet=20, haiku=2)
2. **Phase progress counting** — glob + count in status.md (PLANs vs SUMMARYs)
3. **Brownfield detection** — git ls-files in init.md
4. **Git state checks** — dirty tree, last release hash, commits-since in release.md
5. **Plugin root resolution** — shell glob in 23+ command files
6. **Frontmatter extraction** — manual grep/sed across 50+ instances in skills

## Relevant Patterns

- `resolve-model` already handles model lookup — needs `--with-cost` flag
- `phase-detect` already computes state — needs `--suggest-route` flag
- `detect-stack` exists but doesn't cover brownfield boolean
- `verify-plan-completion` verifies but doesn't aggregate progress

## Risks

- Test fixes are trivial but must preserve hook security validation intent
- Adding frontmatter field must not break other command discovery mechanisms
- Audit scope should be bounded to actionable items for Phase 2-3

## Recommendations

1. Fix 3 tests (trivial: update assertions + add frontmatter field)
2. Produce audit document mapping every MD deterministic pattern to Rust status
3. Prioritize gaps by token savings: plugin-root (23x), frontmatter (50x), progress, cost, git-state
