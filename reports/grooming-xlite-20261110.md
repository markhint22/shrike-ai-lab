# Grooming proposal — xlite — 2026-11-10 04:00

## Current Next Steps
```
- [x] [AUTO-SKIP after 5 no-op cycles — already-done, mis-targeted, or beyond the 27B; review] [EMERGENCY][T2] godot GUT suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing:   Failing         4;[31m---- 4 failing tests ---- ERROR: 12 RID allocations of type 'PN13RendererDummy14TextureStorage12DummyTextureE' were leaked at exit.;ERROR: 93 RID allocations of type 'PN18TextServerAdvanced22ShapedTextDataAdvancedE' were leaked at exit. ERROR: 1 RID allocations of type 'PN18TextServerAdvanced12FontAdvancedE' were leaked at exit.  <!-- superseded by recovery decomposition below -->
- [x] (dismissed 2026-10-07: diagnostic note, not a work item - the underlying work is tracked by the item lines with a VERIFY clause) [CLAUDE] this area has been recovered/decomposed 5 times (cap 2) without ever landing - the fleet keeps re-guessing at this same file with no real diagnosis; needs a human/Claude session to understand the actual blast radius (recovery:escalated)
```

## Proposed (LLM re-evaluation — review before applying)
1. Verify GUT suite is green and confirm the 4 previously failing tests pass without RID allocation leaks at exit
2. Add unit tests for `count_in_radius` to cover edge cases (zero radius, negative radius, empty grid)
3. Refactor `weighted_pick.gd` to extract weight normalization logic into a separate utility function for better testability
4. Create a shared `RigLoader` utility script to standardize loading of `rig_meta.json` and sprite paths for all units in `assets/sprites/rig_units/`
5. Implement a basic `UnitFactory` that uses the new `RigLoader` to instantiate enemy and player units from their respective directories
