# Grooming proposal — xlite — 2026-10-04 04:00

## Current Next Steps
```
- [x] [AUTO-SKIP after 5 no-op cycles — already-done, mis-targeted, or beyond the 27B; review] [EMERGENCY][T2] godot GUT suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing:   Failing         4;[31m---- 4 failing tests ---- ERROR: 12 RID allocations of type 'PN13RendererDummy14TextureStorage12DummyTextureE' were leaked at exit.;ERROR: 93 RID allocations of type 'PN18TextServerAdvanced22ShapedTextDataAdvancedE' were leaked at exit. ERROR: 1 RID allocations of type 'PN18TextServerAdvanced12FontAdvancedE' were leaked at exit.  <!-- superseded by recovery decomposition below -->
- [ ] [CLAUDE] this area has been recovered/decomposed 5 times (cap 2) without ever landing - the fleet keeps re-guessing at this same file with no real diagnosis; needs a human/Claude session to understand the actual blast radius (recovery:escalated)
```

## Proposed (LLM re-evaluation — review before applying)
1. Triage GUT suite: isolate and fix the 4 failing tests by verifying if code logic is incorrect or test expectations are stale, ensuring a green baseline.
2. Resolve RID memory leaks: implement proper cleanup for `RendererDummy` texture allocations in the dummy renderer backend to eliminate exit-time errors.
3. Resolve RID memory leaks: add disposal logic for `TextServerAdvanced` shaped text and font resources to prevent the 94 reported allocation leaks.
4. Diagnose recurring recovery failures: conduct a focused review of the file that has failed decomposition 5 times to identify the root cause preventing stable implementation.
5. Validate rig metadata consistency: write a script or test to verify that all `rig_meta.json` files in `assets/sprites/rig_units/` correctly reference existing sprite assets and valid joint definitions.
6. Implement unit selection SFX integration: wire up `assets/audio/sfx/unit_select.ogg` to the player's unit selection interaction logic to provide immediate audio feedback.
7. Create asset integrity check: add a CI or pre-commit hook that verifies all `.png` files in `assets/sprites/` are non-empty and match their corresponding `rig_meta.json` dimensions.
