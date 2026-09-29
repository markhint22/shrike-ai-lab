# Grooming proposal — xlite — 2026-09-29 04:00

## Current Next Steps
```
- [x] [AUTO-SKIP after 5 no-op cycles — already-done, mis-targeted, or beyond the 27B; review] [EMERGENCY][T2] godot GUT suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing:   Failing         4;[31m---- 4 failing tests ---- ERROR: 12 RID allocations of type 'PN13RendererDummy14TextureStorage12DummyTextureE' were leaked at exit.;ERROR: 93 RID allocations of type 'PN18TextServerAdvanced22ShapedTextDataAdvancedE' were leaked at exit. ERROR: 1 RID allocations of type 'PN18TextServerAdvanced12FontAdvancedE' were leaked at exit.  <!-- superseded by recovery decomposition below -->
- [ ] [CLAUDE] this area has been recovered/decomposed 5 times (cap 2) without ever landing - the fleet keeps re-guessing at this same file with no real diagnosis; needs a human/Claude session to understand the actual blast radius (recovery:escalated)
```

## Proposed (LLM re-evaluation — review before applying)
1. Triage GUT suite: Identify and fix the 4 failing tests causing RID allocation leaks (RendererDummy, TextServerAdvanced) to restore green status.
2. Resolve escalated recovery loop: Conduct a human/Claude session to diagnose the root cause of the 5 failed recovery attempts on the target file.
3. Add GUT tests for `SpiralCells.count_in_radius` edge cases (e.g., radius 0, negative values) to complement recent commits.
4. Implement out-of-range validation logic in `scripts/battle/battle.gd` to support the newly added catapult test.
5. Create a unit test suite for `rig_meta.json` parsing to ensure sprite rig data integrity across all enemy and player units.
