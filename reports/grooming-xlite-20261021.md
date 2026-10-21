# Grooming proposal — xlite — 2026-10-21 04:00

## Current Next Steps
```
- [x] [AUTO-SKIP after 5 no-op cycles — already-done, mis-targeted, or beyond the 27B; review] [EMERGENCY][T2] godot GUT suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing:   Failing         4;[31m---- 4 failing tests ---- ERROR: 12 RID allocations of type 'PN13RendererDummy14TextureStorage12DummyTextureE' were leaked at exit.;ERROR: 93 RID allocations of type 'PN18TextServerAdvanced22ShapedTextDataAdvancedE' were leaked at exit. ERROR: 1 RID allocations of type 'PN18TextServerAdvanced12FontAdvancedE' were leaked at exit.  <!-- superseded by recovery decomposition below -->
- [x] (dismissed 2026-10-07: diagnostic note, not a work item - the underlying work is tracked by the item lines with a VERIFY clause) [CLAUDE] this area has been recovered/decomposed 5 times (cap 2) without ever landing - the fleet keeps re-guessing at this same file with no real diagnosis; needs a human/Claude session to understand the actual blast radius (recovery:escalated)
```

## Proposed (LLM re-evaluation — review before applying)
1. Verify GUT test suite is green and confirm RID leak errors are resolved by running the full test suite locally
2. Add unit tests for the `faction_for` function to cover all unmapped enemy types and ensure "unknown" default behavior
3. Create a script to validate `rig_meta.json` files against existing sprite assets in `assets/sprites/rig_units/` to detect missing or orphaned files
4. Implement a CI check that fails if any `.ogg` audio file in `assets/audio/sfx/` is not referenced in the codebase
5. Document the rigging pipeline in `README.md` using the structure of `assets/sprites/rig_test/grunt/` as the reference example
