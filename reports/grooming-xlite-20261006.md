# Grooming proposal — xlite — 2026-10-06 04:00

## Current Next Steps
```
- [x] [AUTO-SKIP after 5 no-op cycles — already-done, mis-targeted, or beyond the 27B; review] [EMERGENCY][T2] godot GUT suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing:   Failing         4;[31m---- 4 failing tests ---- ERROR: 12 RID allocations of type 'PN13RendererDummy14TextureStorage12DummyTextureE' were leaked at exit.;ERROR: 93 RID allocations of type 'PN18TextServerAdvanced22ShapedTextDataAdvancedE' were leaked at exit. ERROR: 1 RID allocations of type 'PN18TextServerAdvanced12FontAdvancedE' were leaked at exit.  <!-- superseded by recovery decomposition below -->
- [ ] [CLAUDE] this area has been recovered/decomposed 5 times (cap 2) without ever landing - the fleet keeps re-guessing at this same file with no real diagnosis; needs a human/Claude session to understand the actual blast radius (recovery:escalated)
```

## Proposed (LLM re-evaluation — review before applying)
1. Triage GUT suite: isolate the 4 failing tests and determine if they are code bugs or stale assertions
2. Fix GUT suite: update test expectations or patch code to resolve the 4 failures
3. Investigate RID leaks: add cleanup calls for RendererDummy TextureStorage and TextServerAdvanced allocations
4. Verify rig_meta.json consistency: ensure all enemy/player unit sprite folders have valid JSON metadata
5. Update ROADMAP.md: reflect current sprint status and remove completed milestones
