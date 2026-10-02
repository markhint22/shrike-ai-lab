# Grooming proposal — xlite — 2026-10-02 04:00

## Current Next Steps
```
- [x] [AUTO-SKIP after 5 no-op cycles — already-done, mis-targeted, or beyond the 27B; review] [EMERGENCY][T2] godot GUT suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing:   Failing         4;[31m---- 4 failing tests ---- ERROR: 12 RID allocations of type 'PN13RendererDummy14TextureStorage12DummyTextureE' were leaked at exit.;ERROR: 93 RID allocations of type 'PN18TextServerAdvanced22ShapedTextDataAdvancedE' were leaked at exit. ERROR: 1 RID allocations of type 'PN18TextServerAdvanced12FontAdvancedE' were leaked at exit.  <!-- superseded by recovery decomposition below -->
- [ ] [CLAUDE] this area has been recovered/decomposed 5 times (cap 2) without ever landing - the fleet keeps re-guessing at this same file with no real diagnosis; needs a human/Claude session to understand the actual blast radius (recovery:escalated)
```

## Proposed (LLM re-evaluation — review before applying)
1. Triage GUT suite: Isolate and fix the 4 failing tests by verifying if `scripts/battle/battle.gd` logic is incorrect or if test expectations are stale, ensuring the suite passes locally before pushing.
2. Resolve RID memory leaks: Add explicit `free()` calls for `DummyTexture`, `ShapedTextData`, and `Font` resources in the battle scene teardown to eliminate the 106 leaked allocations reported at exit.
3. Implement patrol route JSON validator: Create a unit test that validates the structure of the new patrol route JSON files against the schema defined in `scripts/battle/battle.gd` usage.
4. Add battle resume state persistence: Implement save/load logic for the battle resume feature to ensure game state is correctly serialized and restored, complementing the existing validator.
5. Refactor rig unit loading: Create a utility script to dynamically load `rig_meta.json` and associated sprites for `enemy_boss`, `enemy_brute`, and other units to reduce code duplication in scene setup.
