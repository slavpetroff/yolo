## Findings

### Mutex::lock().unwrap() (REQ-07)
- `telemetry/db.rs`: Lines 21, 67, 86, 147 (4 production + 1 test at line 193)
- `mcp/tools.rs`: Lines 170, 230, 247 (3 production, 1 test at 382 with poison recovery)
- telemetry/db.rs is synchronous rusqlite::Connection, NOT in async context
- mcp/tools.rs locks are in async handler context (ToolState uses std::sync::Mutex)

### Regex::new() without caching (REQ-08)
- `commands/phase_detect.rs:147` — in loop, `.unwrap()`
- `commands/generate_contract.rs:98,123` — 2 instances, `.unwrap()`
- `hooks/security_filter.rs:48` — single call, error-checked (lower priority)
- `commands/tier_context.rs:136,151` — 2 instances
- `commands/commit_lint.rs:40` — 1 instance
- `commands/list_todos.rs:160,242` — 2 instances
- Also in: bootstrap_claude.rs, hard_gate.rs, diff_against_plan.rs, verify_plan_completion.rs
- No OnceLock or lazy_static usage found

### Duplicated frontmatter parsing (REQ-09)
- `hooks/validate_frontmatter.rs:74` — `extract_frontmatter()` returns raw YAML
- `commands/parse_frontmatter.rs:53` — `parse_frontmatter_content()` returns JSON Map
- `commands/generate_contract.rs:10` — `split_frontmatter()` + `fm_scalar()`/`fm_list()`
- 8+ consumer files reference frontmatter parsing

### Manual JSON parsing vs YoloConfig (REQ-10)
- `YoloConfig` defined at `commands/utils.rs:5-25` with `load_config()` at lines 49-54
- Already using: resolve_model.rs, skill_hook_dispatch.rs
- Manual parsing: phase_detect.rs (lines 222-233)
- Other files likely doing manual parsing: need further survey

### unsafe libc::getuid() — NOT FOUND
- Zero unsafe blocks in codebase
- libc 0.2 is a dependency but no unsafe usage detected
- This success criterion is already met

## Relevant Patterns
- `std::sync::OnceLock` available in Rust std (no external crate needed)
- `unwrap_or_else(|e| e.into_inner())` pattern already used in test code for poison recovery
- `commands/utils.rs` already exists as the shared utility module

## Risks
- Changing Mutex types could affect ToolState lifetime requirements
- Regex caching with OnceLock requires &'static Regex references
- Frontmatter consolidation touches many consumer files

## Recommendations
1. Regex caching: Use `std::sync::OnceLock<Regex>` statics in each module (highest ROI)
2. Mutex: Replace `.unwrap()` with `.map_err()` or `.unwrap_or_else()` for poison recovery
3. Frontmatter: Consolidate into `commands/utils.rs` with unified API
4. Config: Migrate phase_detect.rs + survey for others
5. Skip unsafe libc — already clean
