# Grooming proposal — xlite — 2026-10-20 04:00

## Current Next Steps
```
- [x] [AUTO-SKIP after 5 no-op cycles — already-done, mis-targeted, or beyond the 27B; review] [EMERGENCY][T2] godot GUT suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing:   Failing         4;[31m---- 4 failing tests ---- ERROR: 12 RID allocations of type 'PN13RendererDummy14TextureStorage12DummyTextureE' were leaked at exit.;ERROR: 93 RID allocations of type 'PN18TextServerAdvanced22ShapedTextDataAdvancedE' were leaked at exit. ERROR: 1 RID allocations of type 'PN18TextServerAdvanced12FontAdvancedE' were leaked at exit.  <!-- superseded by recovery decomposition below -->
- [x] (dismissed 2026-10-07: diagnostic note, not a work item - the underlying work is tracked by the item lines with a VERIFY clause) [CLAUDE] this area has been recovered/decomposed 5 times (cap 2) without ever landing - the fleet keeps re-guessing at this same file with no real diagnosis; needs a human/Claude session to understand the actual blast radius (recovery:escalated)
```

## Proposed (LLM re-evaluation — review before applying)
1. Triage and fix the 4 failing GUT tests by isolating whether the code logic or test assertions are incorrect, ensuring the suite passes without modifying unrelated systems.
2. Resolve the 12 leaked `RendererDummyTextureStorage` RID allocations by adding explicit resource freeing logic in the relevant scene cleanup or `_exit_tree` methods.
3. Resolve the 94 leaked `TextServerAdvanced` RID allocations (ShapedTextData and Font) by ensuring text resources are properly released when UI elements or labels are destroyed.
4. Implement a basic unit selection interaction handler using the existing `assets/audio/sfx/unit_select.ogg` asset to provide immediate audio feedback on click.
5. Create a minimal `RigLoader` utility script that parses `rig_meta.json` files from `assets/sprites/rig_units/` to validate sprite path integrity for all enemy and player units.
