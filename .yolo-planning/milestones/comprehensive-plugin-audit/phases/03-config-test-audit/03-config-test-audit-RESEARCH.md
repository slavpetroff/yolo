# Research: Phase 3 — Config, Schema & Test Coverage Audit

## Findings

### P0 — Highest Impact

1. **Schema `effort` enum wrong** — Schema allows `["minimal", "balanced", "thorough"]` but code uses `"fast"` and `"turbo"` extensively (effort-profiles.md, execute-protocol). Actual valid values: `["thorough", "balanced", "fast", "turbo"]`. Schema is 75% wrong.

2. **Schema `autonomy` enum wrong** — Schema allows `["minimal", "standard", "full"]` but code uses `"cautious"`, `"standard"`, `"confident"`, `"pure-vibe"`. Schema has 2/4 wrong values.

3. **Schema `planning_tracking` enum wrong** — Schema allows `["manual", "auto"]` but code uses `"commit"`, `"manual"`, `"ignore"`. The `"auto"` value doesn't exist in code; `"commit"` and `"ignore"` are missing from schema.

4. **Schema `review_gate`/`qa_gate` enum wrong** — Schema allows `["off", "on_request", "always"]` but code uses `"never"` not `"off"`. Defaults.json uses `"on_request"` (valid) but execute-protocol references `"never"`.

5. **Schema `model_profile` enum mismatched** — Schema allows `["quality", "balanced", "speed"]` but `model-profiles.json` has keys `"quality"`, `"balanced"`, `"budget"`. The `"speed"` value doesn't exist; `"budget"` is missing.

6. **Schema `prefer_teams` enum incomplete** — Schema allows `["never", "auto", "always"]` but code also uses `"when_parallel"`. Missing from schema.

### P1 — High Impact

7. **Schema missing keys used in code** — At least these keys appear in runtime configs but not in schema: `compaction_threshold`. Schema has `additionalProperties: false` which means any unlisted key would fail validation.

8. **Token budgets references phantom roles** — `config/token-budgets.json` lists `"senior"` and `"security"` in `role_families.execution` but neither role exists in `model-profiles.json` or `agent_max_turns`. These were likely department-architecture remnants.

9. **Defaults.json has different v3 flag defaults than typical configs** — `defaults.json` sets `v3_schema_validation: true`, `v3_snapshot_resume: true`, `v3_lease_locks: true`, `v3_event_recovery: true` but these advanced features are typically false in user configs. The defaults may cause unexpected behavior for new users.

10. **No test for config schema validation itself** — While `schema-validation.bats` exists, the schema enum mismatches (findings 1-6) suggest the tests may not exercise the actual runtime values. The schema is likely not being validated against real configs in CI.

### P2 — Medium Impact

11. **Test coverage: 72 bats files vs 23 commands** — Strong test coverage overall but coverage is concentrated on Rust CLI commands and infrastructure, not on markdown command behavior. Commands like `pause.md`, `resume.md`, `teach.md`, `whats-new.md`, `uninstall.md`, `doctor.md` have no dedicated test files.

12. **Stack-mappings.json references non-existent skills** — Skills like `"python-skill"`, `"rust-skill"`, `"go-skill"`, etc. are generic placeholders not matching actual installed skill names (e.g., actual skills use names like `python-backend`, `rust-best-practices`).

13. **Model-profiles "budget" vs schema "speed"** — The model-profiles.json third tier is named `"budget"` but references in `model-profiles.md` reference file and schema call it `"speed"`. Inconsistent naming across config, schema, and documentation.

14. **Defaults.json sets `v2_typed_protocol: true`** — This is an advanced V2 feature that adds message validation overhead. Having it on by default seems aggressive for new projects.

## Relevant Patterns
- Schema was likely written early and not updated as enum values evolved
- The schema's `additionalProperties: false` means it's actively wrong — would reject valid configs
- Token budgets file references a department architecture that was likely simplified (senior, security roles removed from agents but not from budgets)
- Stack mappings use generic placeholder skill names rather than real marketplace skill IDs

## Risks
- Fixing schema enums could break existing validation in CI or Rust code that reads the schema
- Removing phantom roles from token-budgets.json needs checking if any Rust code references them
- Stack-mappings skill name fix requires knowing the actual skill marketplace IDs

## Recommendations
- Split into: (1) Schema enum fixes (highest priority, clear correctness issues), (2) Config consistency fixes (phantom roles, missing keys), (3) Test coverage gap inventory (documentation, not new tests)
- The schema fixes are pure correctness — the current schema would reject valid configs
- Stack-mappings and defaults adjustments are lower priority and could be deferred
