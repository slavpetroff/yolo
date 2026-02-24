---
phase: 02
plan: 05
title: "Router and mod.rs registration"
wave: 2
depends_on: [1, 2, 3, 4]
must_haves:
  - "All 4 facade commands registered in router.rs"
  - "All 4 modules declared in mod.rs"
  - "Commands routable via CLI: qa-suite, resolve-agent, release-suite, bootstrap-all"
  - "Cargo clippy clean"
---

# Plan 05: Router and mod.rs registration

**Files modified:** `yolo-mcp-server/src/commands/mod.rs`, `yolo-mcp-server/src/cli/router.rs`

Registers all 4 new facade commands in the CLI router and module declarations.

## Task 1: Add module declarations to mod.rs

**Files:** `yolo-mcp-server/src/commands/mod.rs`

**What to do:**
1. Add 4 new `pub mod` declarations to `yolo-mcp-server/src/commands/mod.rs`:
   - `pub mod qa_suite;`
   - `pub mod resolve_agent;`
   - `pub mod release_suite;`
   - `pub mod bootstrap_all;`
2. Place them alphabetically among existing declarations

## Task 2: Add enum variants and from_arg cases to router.rs

**Files:** `yolo-mcp-server/src/cli/router.rs`

**What to do:**
1. Add to the `use crate::commands::{...}` import line: `qa_suite, resolve_agent, release_suite, bootstrap_all`
2. Add 4 enum variants to `Command`:
   - `QaSuite`
   - `ResolveAgent`
   - `ReleaseSuite`
   - `BootstrapAll`
3. Add `from_arg()` match cases:
   - `"qa-suite" => Some(Command::QaSuite)`
   - `"resolve-agent" => Some(Command::ResolveAgent)`
   - `"release-suite" => Some(Command::ReleaseSuite)`
   - `"bootstrap-all" => Some(Command::BootstrapAll)`
4. Add `name()` match cases returning the CLI names

## Task 3: Add dispatch arms and all_names entry

**Files:** `yolo-mcp-server/src/cli/router.rs`

**What to do:**
1. Add dispatch arms in `run_cli()` following the standard pattern:
```rust
Some(Command::QaSuite) => {
    let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    qa_suite::execute(&args, &cwd)
}
Some(Command::ResolveAgent) => {
    let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    resolve_agent::execute(&args, &cwd)
}
Some(Command::ReleaseSuite) => {
    let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    release_suite::execute(&args, &cwd)
}
Some(Command::BootstrapAll) => {
    let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    bootstrap_all::execute(&args, &cwd)
}
```
2. Add all 4 names to `all_names()`: `"qa-suite"`, `"resolve-agent"`, `"release-suite"`, `"bootstrap-all"`
3. Add routing test: verify these 4 commands are recognized (not "Unknown command")

**Commit:** `feat(yolo): register 4 facade commands in router`
