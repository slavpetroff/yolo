---
phase: 1
plan: 03
title: "Migrate 4 bootstrap scripts to Rust CLI subcommands"
wave: 2
depends_on: [1]
must_haves:
  - "`yolo bootstrap project <output> <name> <description> [core_value]` replaces bootstrap-project.sh"
  - "`yolo bootstrap requirements <output> <discovery_json> [research_file]` replaces bootstrap-requirements.sh"
  - "`yolo bootstrap roadmap <output> <project_name> <phases_json>` replaces bootstrap-roadmap.sh"
  - "`yolo bootstrap state <output> <project_name> <milestone_name> <phase_count>` replaces bootstrap-state.sh"
  - "Existing `yolo bootstrap` (CLAUDE.md) remains at `yolo bootstrap claude` or top-level"
---

## Task 1: Implement bootstrap project subcommand

**Files:** `yolo-mcp-server/src/commands/bootstrap_project.rs`

**Acceptance:** `yolo bootstrap project .yolo-planning/PROJECT.md "MyApp" "A task manager" "Simplify task management"` produces identical PROJECT.md output to bootstrap-project.sh.

Implement `pub fn execute(args: &[String], _cwd: &Path) -> Result<(String, i32), String>`:

1. Parse args: output_path, name, description, optional core_value (defaults to description)
2. Ensure parent directory exists (`fs::create_dir_all`)
3. Write PROJECT.md template: heading, description, core value, Requirements (Validated/Active/Out of Scope), Constraints, Key Decisions table
4. Output matches the bash heredoc exactly

Include unit tests: basic generation, core_value override, missing args error.

## Task 2: Implement bootstrap requirements subcommand

**Files:** `yolo-mcp-server/src/commands/bootstrap_requirements.rs`

**Acceptance:** `yolo bootstrap requirements .yolo-planning/REQUIREMENTS.md .yolo-planning/discovery.json` produces REQUIREMENTS.md and updates discovery.json with research metadata, matching bash behavior.

Implement the full requirements generation:

1. Parse args: output_path, discovery_json_path, optional research_file
2. Validate discovery JSON exists and is valid
3. Extract `inferred[]` array, generate REQ-NN entries with text and priority
4. Write REQUIREMENTS.md: heading, date, requirements list, Out of Scope section
5. Update discovery.json with `research_summary` field (available=true with domain/date if research file exists, available=false otherwise)

Include unit tests: with inferred requirements, empty inferred, with research file, invalid JSON error.

## Task 3: Implement bootstrap roadmap subcommand

**Files:** `yolo-mcp-server/src/commands/bootstrap_roadmap.rs`

**Acceptance:** `yolo bootstrap roadmap .yolo-planning/ROADMAP.md "MyApp" .yolo-planning/phases.json` produces ROADMAP.md and creates phase directories, matching bash behavior.

Implement the full roadmap generation:

1. Parse args: output_path, project_name, phases_json_path
2. Validate phases JSON exists, is valid, has >= 1 phase
3. Generate ROADMAP.md: heading, goal, scope, progress table (all Pending), phase list with checkbox links, phase details (goal, requirements, success criteria, dependencies)
4. Create phase directories: `{phases_dir}/{NN}-{slug}/` where slug = lowercase name with non-alphanumeric replaced by hyphens
5. Derive phases_dir from output_path parent + "phases"

Include unit tests: single phase, multiple phases, slug generation, empty phases error.

## Task 4: Implement bootstrap state subcommand

**Files:** `yolo-mcp-server/src/commands/bootstrap_state.rs`

**Acceptance:** `yolo bootstrap state .yolo-planning/STATE.md "MyApp" "Initial Release" 3` produces STATE.md matching bash behavior, preserving existing Todos and Decisions sections.

Implement the full state generation:

1. Parse args: output_path, project_name, milestone_name, phase_count
2. Get today's date (`chrono::Local::now().format("%Y-%m-%d")`)
3. If output file already exists, extract existing Todos and Key Decisions sections (awk-like parsing)
4. Write STATE.md: heading, project/milestone/phase/status/started/progress fields, phase status list (Phase 1 = "Pending planning", rest = "Pending"), Key Decisions table (preserved or default), Todos (preserved or "None."), Recent Activity

Include unit tests: fresh generation, preserve existing todos, preserve existing decisions, missing args error.

## Task 5: Wire bootstrap subcommands into CLI router

**Files:** `yolo-mcp-server/src/commands/mod.rs`, `yolo-mcp-server/src/cli/router.rs`

**Acceptance:** `yolo bootstrap project|requirements|roadmap|state` all route correctly. Existing `yolo bootstrap <output> <name> <value> [existing]` (CLAUDE.md) continues to work. `cargo test` and `cargo build` pass.

1. Add `pub mod bootstrap_project;`, `pub mod bootstrap_requirements;`, `pub mod bootstrap_roadmap;`, `pub mod bootstrap_state;` to `commands/mod.rs`
2. Modify the `"bootstrap"` match arm in router.rs to dispatch:
   - If `args[2]` is "project" -> `bootstrap_project::execute(&args[2..], &cwd)`
   - If `args[2]` is "requirements" -> `bootstrap_requirements::execute(&args[2..], &cwd)`
   - If `args[2]` is "roadmap" -> `bootstrap_roadmap::execute(&args[2..], &cwd)`
   - If `args[2]` is "state" -> `bootstrap_state::execute(&args[2..], &cwd)`
   - Otherwise (existing behavior) -> `bootstrap_claude::execute(&args, &cwd)` (CLAUDE.md bootstrap)
3. This preserves backward compatibility: `yolo bootstrap CLAUDE.md "Name" "Value"` still works because the first arg after "bootstrap" is a file path, not a known subcommand
4. Run `cargo test` and `cargo build`
