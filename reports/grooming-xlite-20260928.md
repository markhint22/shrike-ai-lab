# Grooming proposal — xlite — 2026-09-28 04:00

## Current Next Steps
```
- [x] [AUTO-SKIP after 5 no-op cycles — already-done, mis-targeted, or beyond the 27B; review] [EMERGENCY][T2] godot GUT suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing:   Failing         4;[31m---- 4 failing tests ---- ERROR: 12 RID allocations of type 'PN13RendererDummy14TextureStorage12DummyTextureE' were leaked at exit.;ERROR: 93 RID allocations of type 'PN18TextServerAdvanced22ShapedTextDataAdvancedE' were leaked at exit. ERROR: 1 RID allocations of type 'PN18TextServerAdvanced12FontAdvancedE' were leaked at exit.  <!-- superseded by recovery decomposition below -->
- [ ] [CLAUDE] this area has been recovered/decomposed 5 times (cap 2) without ever landing - the fleet keeps re-guessing at this same file with no real diagnosis; needs a human/Claude session to understand the actual blast radius (recovery:escalated)
```

## Proposed (LLM re-evaluation — review before applying)
1. Triage GUT suite: Isolate and fix the 4 failing tests by verifying if they are stale assertions or actual code bugs in `scripts/battle/battle.gd`.
2. Resolve RID memory leaks: Add explicit `free()` calls for `DummyTexture` and `ShapedTextData` resources in the test teardown or scene exit logic to clear the 106 leaked allocations.
3. Validate rig metadata consistency: Write a script to verify that all `rig_meta.json` files in `assets/sprites/rig_units/` correctly reference existing PNG assets (body, leg_l, leg_r).
4. Implement unit selection SFX: Integrate `assets/audio/sfx/unit_select.ogg` into the player input handler in `scripts/battle/battle.gd` to provide audio feedback on unit selection.
5. Update OVERNIGHT_PROGRESS.md: Sync the current status of the GUT suite fixes and memory leak resolution with the actual code state to prevent future queue mis-targeting.
