# Model Profiles: "budget" vs "speed" naming

## Decision

The canonical name for the third (cheapest) effort tier in `config/model-profiles.json` is **`budget`**.

## History

- The original schema (`config/schemas/model-profiles.schema.json`) referenced this tier as `"speed"`.
- The actual data file (`config/model-profiles.json`) has always used `"budget"` as the key name.
- Plan 03-01 aligns the schema to match the data, changing the schema enum from `"speed"` to `"budget"`.

## Rationale

`"budget"` better describes the intent: minimize cost. `"speed"` was a misnomer since the tier does not affect execution speed -- it routes agents to cheaper models.

## Action Required

None. The data file already uses `"budget"`. The schema is being updated to match. Any future references should use `"budget"`, never `"speed"`.
