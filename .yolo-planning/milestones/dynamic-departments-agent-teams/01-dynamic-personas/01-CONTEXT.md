# Phase 1 Context: Project Type Detection & Persona Templates

## User Vision
Make departments (Backend, Frontend, UI/UX) dynamically adapt to any project type. A shell-scripts project should get Bash/BATS conventions, not TypeScript/React. The framework must be generic across web apps, APIs, CLI tools, libraries, mobile apps, and monorepos.

## Essential Features
- detect-stack.sh enhanced to output a `project_type` classification
- New `config/project-types.json` with extensible type definitions (start with 6: web-app, api-service, cli-tool, library, mobile-app, monorepo)
- New `scripts/generate-department-toons.sh` that creates department TOON files from project type + templates
- UX department dynamically maps to project interface type:
  - web-app → UI design, component specs, design tokens
  - cli-tool → help text quality, error output formatting, progress indicators, user prompts
  - api-service → API documentation, OpenAPI specs, developer experience
  - library → API surface design, examples, README quality
  - mobile-app → UI design, gesture interactions, platform conventions
  - monorepo → per-package type detection, shared design system

## Technical Preferences
- Type definitions stored in JSON config (`config/project-types.json`) — users can add custom types
- TOON generation happens at init time (/yolo:init or /yolo:map), stored in `.yolo-planning/departments/`
- Refresh mechanism: if detect-stack.sh output changes (new framework detected), regenerate TOONs
- All generation done by shell scripts (not LLM), following zero-dependency design

## Boundaries
- Do NOT modify agent YAML files in this phase (that's Phase 3)
- Do NOT touch Teammate API (that's Phase 2)
- Do NOT change execute-protocol.md or go.md routing logic
- Only create the generation pipeline: detect → classify → template → TOON output

## Acceptance Criteria
- detect-stack.sh outputs `project_type` field in its JSON output
- config/project-types.json defines 6 types with department mappings
- generate-department-toons.sh produces valid TOON files for all 3 departments
- compile-context.sh reads generated TOONs instead of static references/departments/*.toon
- Running on YOLO project itself produces correct shell-project personas (Bash, BATS, Markdown/prompt engineering)

## Decisions Made
- Extensible config: 6 types in JSON, users can add custom types
- Hybrid generation: generate at init, refresh if stack detection changes
- UX maps to CLI output quality for shell projects
