# Grooming proposal — iptv_apps — 2026-08-29 04:00

## Current Next Steps
```
- [ ] [HUMAN-ONLY BLOCKED ITEM — auto-skipped after 3 failed cycles; needs a human] Add `iptv-web/src/views/__tests__/AnalyticsView.accessibility.test.ts` mirroring the existing `GuideView.accessibility.test.ts` (assert a main landmark, a descriptive heading, all inputs have labels, and interactive elements have accessible names). New test file only.
- [ ] [HUMAN-ONLY BLOCKED ITEM — auto-skipped after 3 failed cycles; needs a human] Add `iptv-web/src/views/__tests__/DiscoverView.accessibility.test.ts` the same way. New test file only.
- [ ] [HUMAN-ONLY BLOCKED ITEM — auto-skipped after 3 failed cycles; needs a human] Add `iptv-web/src/views/__tests__/HomeView.accessibility.test.ts` the same way. New test file only.
- [ ] [HUMAN-ONLY BLOCKED ITEM — auto-skipped after 3 failed cycles; needs a human] Add `iptv-web/src/views/__tests__/SettingsView.accessibility.test.ts` the same way. New test file only.
```

## Proposed (LLM re-evaluation — review before applying)
1. Add `iptv-web/src/views/__tests__/AnalyticsView.accessibility.test.ts` mirroring `GuideView.accessibility.test.ts` (assert main landmark, descriptive heading, labeled inputs, and accessible names for interactive elements).
2. Add `iptv-web/src/views/__tests__/DiscoverView.accessibility.test.ts` mirroring `GuideView.accessibility.test.ts` (assert main landmark, descriptive heading, labeled inputs, and accessible names for interactive elements).
3. Add `iptv-web/src/views/__tests__/HomeView.accessibility.test.ts` mirroring `GuideView.accessibility.test.ts` (assert main landmark, descriptive heading, labeled inputs, and accessible names for interactive elements).
4. Add `iptv-web/src/views/__tests__/SettingsView.accessibility.test.ts` mirroring `GuideView.accessibility.test.ts` (assert main landmark, descriptive heading, labeled inputs, and accessible names for interactive elements).
5. Add unit tests for the new `/version` endpoint to verify correct response structure and version string retrieval.
6. Add unit tests for the `/metrics` endpoint to ensure the updated docstring and timezone-aware datetime logic are correctly reflected in the output.
7. Add integration tests for the `classify_label` function in normalization to cover the new edge cases added in recent commits.
