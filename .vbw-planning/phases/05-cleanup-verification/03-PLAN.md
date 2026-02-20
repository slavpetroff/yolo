---
phase: 5
plan: 03
title: "Clean up Rust source files that still reference .sh scripts"
wave: 1
depends_on: []
must_haves:
  - "All 10 Rust source files with .sh references are cleaned up"
  - "No Rust file shells out to a .sh script or references scripts/ paths for runtime use"
  - "Comments referencing .sh as historical context are updated to past tense or removed"
  - "Usage strings and error messages no longer reference .sh scripts"
  - "cargo build and cargo test pass"
---

## Task 1: Clean up pre_push_hook.rs and install_hooks.rs

**Files:** `yolo-mcp-server/src/commands/pre_push_hook.rs`, `yolo-mcp-server/src/commands/install_hooks.rs`

**Acceptance:** In pre_push_hook.rs: Guard checking `scripts/bump-version.sh` existence replaced with check for `yolo` binary availability or Cargo.toml presence (appropriate marker for a YOLO repo). In install_hooks.rs: The pre-push hook content that references `pre-push-hook.sh` path is updated to invoke `yolo pre-push-hook` instead. Test fixtures using `pre-push-hook.sh` and `other-hook.sh` filenames updated. `cargo test --lib -- pre_push_hook` passes. `cargo test --lib -- install_hooks` passes.

## Task 2: Clean up session_start.rs and bootstrap_claude.rs

**Files:** `yolo-mcp-server/src/commands/session_start.rs`, `yolo-mcp-server/src/commands/bootstrap_claude.rs`

**Acceptance:** In session_start.rs: The bash command constructing a path to `yolo-statusline.sh` replaced with `yolo statusline` invocation. In bootstrap_claude.rs: Any .sh references in generated CLAUDE.md content or setup instructions updated to reference Rust CLI. `cargo test --lib -- session_start` and `cargo test --lib -- bootstrap_claude` pass. No `.sh` substring remains in either file.

## Task 3: Clean up infer_project_context.rs, token_baseline.rs, hard_gate.rs

**Files:** `yolo-mcp-server/src/commands/infer_project_context.rs`, `yolo-mcp-server/src/commands/token_baseline.rs`, `yolo-mcp-server/src/commands/hard_gate.rs`

**Acceptance:** In infer_project_context.rs: Usage string `infer-project-context.sh` changed to `yolo infer-project-context`. In token_baseline.rs: Message `token-baseline.sh measure --save` changed to `yolo token-baseline measure --save`. In hard_gate.rs: Comments `replaces log-event.sh` and `replaces collect-metrics.sh` either removed (code is self-evident now) or updated to past tense without .sh. `cargo test` passes for all three modules.

## Task 4: Clean up hooks/ Rust files (utils.rs, skill_hook_dispatch.rs, compaction_instructions.rs)

**Files:** `yolo-mcp-server/src/hooks/utils.rs`, `yolo-mcp-server/src/hooks/skill_hook_dispatch.rs`, `yolo-mcp-server/src/hooks/compaction_instructions.rs`

**Acceptance:** In utils.rs: Test fixture strings like `"test-hook.sh"` and `"hook-{}.sh"` are fine in test code (they simulate external hook file names that may still use .sh). In skill_hook_dispatch.rs: The `format!("{}-hook.sh")` pattern for finding skill hook scripts — if skills still use .sh hooks, leave as-is; if skills are also migrated to Rust, update accordingly. In compaction_instructions.rs: Comment `mirrors bash snapshot-resume.sh save` updated to remove .sh reference. `cargo test` passes for all three modules.

## Task 5: Final Rust .sh reference audit and cargo check

**Files:** All `yolo-mcp-server/src/**/*.rs` (audit)

**Acceptance:** `grep -r '\.sh' yolo-mcp-server/src/ --include='*.rs'` returns only: (a) test fixtures simulating external file names, (b) skill hook dispatch looking for user-provided .sh scripts (if applicable). Zero references to `scripts/` directory paths. Zero references to `bash ` followed by a script invocation. `cargo build --release` succeeds. `cargo test` passes with 0 failures. Single atomic commit: `refactor(rust): remove all obsolete .sh script references from Rust source`.
