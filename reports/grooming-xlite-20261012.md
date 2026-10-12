# Grooming proposal — xlite — 2026-10-12 04:00

## Current Next Steps
```
- [x] [AUTO-SKIP after 5 no-op cycles — already-done, mis-targeted, or beyond the 27B; review] [EMERGENCY][T2] godot GUT suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing:   Failing         4;[31m---- 4 failing tests ---- ERROR: 12 RID allocations of type 'PN13RendererDummy14TextureStorage12DummyTextureE' were leaked at exit.;ERROR: 93 RID allocations of type 'PN18TextServerAdvanced22ShapedTextDataAdvancedE' were leaked at exit. ERROR: 1 RID allocations of type 'PN18TextServerAdvanced12FontAdvancedE' were leaked at exit.  <!-- superseded by recovery decomposition below -->
- [x] (dismissed 2026-10-07: diagnostic note, not a work item - the underlying work is tracked by the item lines with a VERIFY clause) [CLAUDE] this area has been recovered/decomposed 5 times (cap 2) without ever landing - the fleet keeps re-guessing at this same file with no real diagnosis; needs a human/Claude session to understand the actual blast radius (recovery:escalated)
```

## Proposed (LLM re-evaluation — review before applying)
1. Verify GUT test suite is green and resolve remaining RID allocation leaks (TextureStorage, ShapedTextData, Font) by adding explicit resource cleanup in test teardown or game exit hooks.
2. Implement visual feedback for faction codex completion triggers using existing SFX assets (confirm.ogg) and UI updates to confirm the recent achievement registry changes.
3. Add unit tests for the new faction codex update handler to ensure achievement triggers fire correctly under various game state conditions.
4. Refactor damage.gd to remove any remaining dead code or unused variables following the recent removal of simulate_single_load and coerce_to_array.
5. Create a basic integration test for the rig_test grunt sprite loading to verify rig_meta.json parsing and asset path resolution.
