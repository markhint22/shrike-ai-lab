# Grooming proposal — xlite — 2026-11-03 04:00

## Current Next Steps
```
- [x] [AUTO-SKIP after 5 no-op cycles — already-done, mis-targeted, or beyond the 27B; review] [EMERGENCY][T2] godot GUT suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing:   Failing         4;[31m---- 4 failing tests ---- ERROR: 12 RID allocations of type 'PN13RendererDummy14TextureStorage12DummyTextureE' were leaked at exit.;ERROR: 93 RID allocations of type 'PN18TextServerAdvanced22ShapedTextDataAdvancedE' were leaked at exit. ERROR: 1 RID allocations of type 'PN18TextServerAdvanced12FontAdvancedE' were leaked at exit.  <!-- superseded by recovery decomposition below -->
- [x] (dismissed 2026-10-07: diagnostic note, not a work item - the underlying work is tracked by the item lines with a VERIFY clause) [CLAUDE] this area has been recovered/decomposed 5 times (cap 2) without ever landing - the fleet keeps re-guessing at this same file with no real diagnosis; needs a human/Claude session to understand the actual blast radius (recovery:escalated)
```

## Proposed (LLM re-evaluation — review before applying)
1. Fix GUT suite: Resolve the 4 failing tests by triaging whether code logic or test assertions are incorrect, ensuring a green baseline.
2. Debug RID leaks: Investigate and fix the 12 DummyTexture, 93 ShapedTextData, and 1 FontAdvanced RID allocations leaked at exit.
3. Verify mission_24 spawn logic: Confirm that the recent GUT test asserting clear obstacle spawns for mission_24 passes in the current develop branch.
4. Implement enemy_boss rig animation: Wire up the existing `assets/sprites/rig_units/enemy_boss` assets into the game's unit rendering pipeline.
5. Implement player_medic rig animation: Integrate the `assets/sprites/rig_units/player_medic` assets to support medic-specific visual states.
6. Add SFX integration for unit_select: Hook up `assets/audio/sfx/unit_select.ogg` to the player's unit selection interaction handler.
