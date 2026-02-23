---
phase: 1
plan: 04
status: complete
---
## Summary
Routed 6 previously unroutable CLI commands through the router and fixed glob wildcard pattern matching in detect-stack so that patterns like `*.csproj` and `*.sln` correctly detect dotnet/kotlin stacks.

## What Was Built
- CLI routes for clean-stale-teams, tmux-watchdog, verify-init-todo, verify-vibe, verify-claude-bootstrap, and pre-push
- Glob wildcard matching in detect-stack's check_pattern function (glob_matches helper + directory scanning)
- Unit tests for all new routes and glob pattern matching scenarios

## Files Modified
- `yolo-mcp-server/src/cli/router.rs` — added 6 match arms and imports for unrouted modules; added route verification test
- `yolo-mcp-server/src/commands/detect_stack.rs` — added glob_matches() helper and glob branch in check_pattern(); added 3 glob detection tests

## Tasks
- Task 1: Add missing CLI routes for 6 unrouted modules — complete
- Task 2: Fix detect-stack glob pattern matching for wildcards — complete
- Task 3: Add unit tests for new routes and glob detection — complete

## Commits
- 11d01d1: feat(router): add CLI routes for 6 unrouted modules
- 89858ee: fix(detect-stack): handle glob wildcard patterns in stack detection
- 915ca5e: test(router,detect-stack): add tests for new routes and glob detection

## Deviations
None
