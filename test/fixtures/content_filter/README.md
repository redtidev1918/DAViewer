# Platform AI flag evidence

Captured on 2026-10-17 from a live unauthenticated HTTP 200 response to
https://www.deviantart.com/tag/aiart using a Mozilla/5.0 user agent.
`platform_ai_flags.json` contains only selected fields from two actual entries
in `window.__INITIAL_STATE__` → `@@entities` → `deviation` (all values retained
verbatim). The capture was decoded using DAKit's existing JavaScript-literal
decoder; no parser test fixture was inferred from the implementation.

Both samples have `isAiUseDisallowed: true`, but their `isAiGenerated` values
differ. Training permission is not evidence that an artwork was AI generated.
Missing flags remain unknown and are not blocked by the AI-only preference.
Raw HTML is intentionally excluded because it contains unrelated session data.
