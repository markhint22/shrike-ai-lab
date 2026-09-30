# Grooming proposal — xlite — 2026-09-30 04:00

## Current Next Steps
```
- [x] [AUTO-SKIP after 5 no-op cycles — already-done, mis-targeted, or beyond the 27B; review] [EMERGENCY][T2] godot GUT suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing:   Failing         4;[31m---- 4 failing tests ---- ERROR: 12 RID allocations of type 'PN13RendererDummy14TextureStorage12DummyTextureE' were leaked at exit.;ERROR: 93 RID allocations of type 'PN18TextServerAdvanced22ShapedTextDataAdvancedE' were leaked at exit. ERROR: 1 RID allocations of type 'PN18TextServerAdvanced12FontAdvancedE' were leaked at exit.  <!-- superseded by recovery decomposition below -->
- [ ] [CLAUDE] this area has been recovered/decomposed 5 times (cap 2) without ever landing - the fleet keeps re-guessing at this same file with no real diagnosis; needs a human/Claude session to understand the actual blast radius (recovery:escalated)
```

## Proposed (LLM re-evaluation — review before applying)
1. Triage and fix the 4 failing GUT tests by isolating whether the code logic or test assertions are incorrect, ensuring the suite passes without introducing new failures.
2. Resolve RID allocation leaks for `RendererDummyTextureStorage` and `TextServerAdvanced` by adding explicit resource freeing in test teardown or fixing lifecycle management in the affected scenes.
3. Update `OVERNIGHT_PROGRESS.md` to reflect the latest green test status and reconcile any stale entries against the current `develop` branch state.
4. Add a unit test for the newly implemented machine and mutant completionist achievements to verify state transitions and reward triggers.
5. Verify that `test_mark_faction_seen_updates_state` in the codex manager tests correctly handles edge cases where faction data is missing or corrupted.
