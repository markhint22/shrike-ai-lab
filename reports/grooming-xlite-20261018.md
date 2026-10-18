# Grooming proposal — xlite — 2026-10-18 04:00

## Current Next Steps
```
- [x] [AUTO-SKIP after 5 no-op cycles — already-done, mis-targeted, or beyond the 27B; review] [EMERGENCY][T2] godot GUT suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing:   Failing         4;[31m---- 4 failing tests ---- ERROR: 12 RID allocations of type 'PN13RendererDummy14TextureStorage12DummyTextureE' were leaked at exit.;ERROR: 93 RID allocations of type 'PN18TextServerAdvanced22ShapedTextDataAdvancedE' were leaked at exit. ERROR: 1 RID allocations of type 'PN18TextServerAdvanced12FontAdvancedE' were leaked at exit.  <!-- superseded by recovery decomposition below -->
- [x] (dismissed 2026-10-07: diagnostic note, not a work item - the underlying work is tracked by the item lines with a VERIFY clause) [CLAUDE] this area has been recovered/decomposed 5 times (cap 2) without ever landing - the fleet keeps re-guessing at this same file with no real diagnosis; needs a human/Claude session to understand the actual blast radius (recovery:escalated)
```

## Proposed (LLM re-evaluation — review before applying)
1. Verify `has_line_of_sight` removal in `overwatch.gd` by running the full GUT suite to ensure no regression tests fail due to the deleted function.
2. Add unit tests for `hit_percent_needed` clamping and range validation to lock in the recent fix and prevent future regressions.
3. Implement basic audio playback integration for `assets/audio/sfx/confirm.ogg` and `assets/audio/sfx/error.ogg` in the UI interaction handlers.
4. Create a `RigLoader` utility script to parse `rig_meta.json` files from `assets/sprites/rig_units/` and instantiate corresponding sprite nodes.
5. Add a `README.md` section documenting the directory structure for `assets/sprites/rig_test/` vs `assets/sprites/rig_units/` to clarify asset organization for contributors.
