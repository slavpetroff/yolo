# Domain Research: LLM Token Efficiency & Cache Architecture

## Table Stakes
- Prompt prefix stability — content ordering (tools → system → messages) must be deterministic for cache hits
- Minimum cacheable thresholds: 1024 tokens (Sonnet), 4096 tokens (Opus/Haiku)
- 5-minute TTL default, refreshed on each hit. 1-hour TTL available at 2x write cost
- Cache hits cost 10% of base input price (90% savings). Writes cost 25% more
- Up to 4 explicit cache breakpoints per request
- 20-block lookback window — changes beyond 20 blocks from breakpoint require additional breakpoints

## Common Pitfalls
- Volatile content mixed into stable prefix → constant cache misses
- CLAUDE.md bloat → instructions ignored, context wasted on low-value text
- Subagent context pollution → reading many files without scoping fills context
- Tool definition changes invalidate entire cache chain (tools are highest in hierarchy)
- Thinking block parameters changes invalidate message cache
- Non-tool-result user messages strip all previous thinking blocks from cache

## Architecture Patterns
- **Stable/volatile split**: Separate never-changing references from phase-specific content
- **Prefix-first injection**: Compiled context at TOP of agent prompts (before task instructions)
- **Layered cache breakpoints**: Tools (rarely change) → system instructions → conversation history
- **Subagent isolation**: Research in separate context windows, only summary returned to main
- **Skills over CLAUDE.md**: Domain knowledge loaded on-demand vs. always-loaded
- **Automatic caching**: Single top-level cache_control for multi-turn conversations

## Competitor Landscape
- OpenAI: No equivalent prompt caching mechanism
- Google Vertex AI: Supports Claude prompt caching via partner models
- Amazon Bedrock: Supports prompt caching with same API structure
- OpenRouter: Proxy-level caching across providers

## Key Metrics
- Anthropic reports up to 90% cost reduction and 85% latency improvement with prompt caching
- Claude Code achieves ~92% prefix reuse in typical sessions
- Cache read tokens don't count against ITPM rate limits on Claude Sonnet 3.7+
