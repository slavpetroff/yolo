---
phase: "03b"
plan: "01"
title: "Introduce enums for stringly-typed state machines"
wave: 1
depends_on: []
must_haves:
  - "StepStatus enum in session_start.rs replaces &str status field"
  - "PhaseState and Route enums in phase_detect.rs replace string comparisons"
  - "AgentRole and Model enums in resolve_model.rs replace VALID_AGENTS/VALID_MODELS"
  - "cost_weight is a method on Model enum"
  - "All existing tests pass with enum-based code"
---

# Plan 03b-01: Introduce enums for stringly-typed state machines

## Summary

Replace the 3 most critical string-based state machines with proper Rust enums using serde derive macros, match arms, and compile-time exhaustiveness checking.

## Task 1: StepStatus enum in session_start.rs

**File:** `yolo-mcp-server/src/commands/session_start.rs`

**Changes:**
1. Add enum before `StepResult` struct:
   ```rust
   #[derive(Clone, Copy)]
   enum StepStatus {
       Ok,
       Skip,
       Warn,
       Error,
   }

   impl StepStatus {
       fn as_str(&self) -> &'static str {
           match self {
               StepStatus::Ok => "ok",
               StepStatus::Skip => "skip",
               StepStatus::Warn => "warn",
               StepStatus::Error => "error",
           }
       }
   }
   ```
2. Change `StepResult.status` from `&'static str` to `StepStatus`
3. Update all `status: "ok"` to `status: StepStatus::Ok`, etc.
4. In the JSON serialization, use `step.status.as_str()`

**Note:** Keep the JSON output identical — `"ok"`, `"skip"`, `"warn"`, `"error"` strings in output.

## Task 2: PhaseState and Route enums in phase_detect.rs

**File:** `yolo-mcp-server/src/commands/phase_detect.rs`

**Changes:**
1. Add enums:
   ```rust
   enum PhaseState {
       NoPhases,
       NeedsPlanAndExecute,
       NeedsExecute,
       AllDone,
   }

   impl PhaseState {
       fn as_str(&self) -> &'static str {
           match self {
               PhaseState::NoPhases => "no_phases",
               PhaseState::NeedsPlanAndExecute => "needs_plan_and_execute",
               PhaseState::NeedsExecute => "needs_execute",
               PhaseState::AllDone => "all_done",
           }
       }
   }

   enum Route {
       Init, Bootstrap, Resume, Plan, Execute, Archive,
   }

   impl Route {
       fn as_str(&self) -> &'static str {
           match self {
               Route::Init => "init",
               Route::Bootstrap => "bootstrap",
               Route::Resume => "resume",
               Route::Plan => "plan",
               Route::Execute => "execute",
               Route::Archive => "archive",
           }
       }
   }
   ```
2. Replace the mutable `next_phase_state: String` with `PhaseState` enum assignments
3. Replace `suggest_route_mode` if-else chain with match on `PhaseState`
4. Use `state.as_str()` and `route.as_str()` for output strings

**Note:** Keep the output format identical — `next_phase_state=all_done`, `suggested_route=archive`.

## Task 3: AgentRole and Model enums in resolve_model.rs

**File:** `yolo-mcp-server/src/commands/resolve_model.rs`

**Changes:**
1. Replace `VALID_AGENTS` and `VALID_MODELS` with enums:
   ```rust
   #[derive(Clone, Copy)]
   enum AgentRole {
       Lead, Dev, Qa, Scout, Debugger, Architect, Docs, Researcher, Reviewer,
   }

   impl AgentRole {
       fn from_str(s: &str) -> Option<AgentRole> {
           match s {
               "lead" => Some(AgentRole::Lead),
               "dev" => Some(AgentRole::Dev),
               // ... all 9
               _ => None,
           }
       }
       fn as_str(&self) -> &'static str {
           match self {
               AgentRole::Lead => "lead",
               // ... all 9
           }
       }
       fn all() -> &'static [AgentRole] {
           &[AgentRole::Lead, AgentRole::Dev, AgentRole::Qa, AgentRole::Scout,
             AgentRole::Debugger, AgentRole::Architect, AgentRole::Docs,
             AgentRole::Researcher, AgentRole::Reviewer]
       }
   }

   #[derive(Clone, Copy)]
   enum Model {
       Opus, Sonnet, Haiku,
   }

   impl Model {
       fn as_str(&self) -> &'static str {
           match self { Model::Opus => "opus", Model::Sonnet => "sonnet", Model::Haiku => "haiku" }
       }
       fn cost_weight(&self) -> u32 {
           match self { Model::Opus => 100, Model::Sonnet => 20, Model::Haiku => 2 }
       }
       fn from_str(s: &str) -> Option<Model> {
           match s { "opus" => Some(Model::Opus), "sonnet" => Some(Model::Sonnet), "haiku" => Some(Model::Haiku), _ => None }
       }
   }
   ```
2. Replace `VALID_AGENTS.contains()` with `AgentRole::from_str().is_some()`
3. Replace `VALID_MODELS.contains()` with `Model::from_str().is_some()`
4. Replace standalone `cost_weight()` function with `Model::cost_weight()` method
5. Use `AgentRole::all()` iterator for `--all` mode

**Note:** Keep output format identical.

## Task 4: Update existing unit tests for enum changes

**File:** Same 3 files (in `mod tests` blocks)

**Changes:**
1. Fix any test that references the old string-based API
2. Add tests for `from_str` conversions (valid + invalid)
3. Verify all JSON output unchanged

## Task 5: Verify backward compatibility

Run full test suites:
- `cargo test -p yolo --release`
- `bats tests/phase-detect.bats`
- `bats tests/resolve-agent-model.bats`
- `bats tests/sessionstart-compact-hooks.bats`

Verify no output format changes.
