# Grooming proposal — xlite — 2026-10-19 04:00

## Current Next Steps
```
- [x] [AUTO-SKIP after 5 no-op cycles — already-done, mis-targeted, or beyond the 27B; review] [EMERGENCY][T2] godot GUT suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing:   Failing         4;[31m---- 4 failing tests ---- ERROR: 12 RID allocations of type 'PN13RendererDummy14TextureStorage12DummyTextureE' were leaked at exit.;ERROR: 93 RID allocations of type 'PN18TextServerAdvanced22ShapedTextDataAdvancedE' were leaked at exit. ERROR: 1 RID allocations of type 'PN18TextServerAdvanced12FontAdvancedE' were leaked at exit.  <!-- superseded by recovery decomposition below -->
- [x] (dismissed 2026-10-07: diagnostic note, not a work item - the underlying work is tracked by the item lines with a VERIFY clause) [CLAUDE] this area has been recovered/decomposed 5 times (cap 2) without ever landing - the fleet keeps re-guessing at this same file with no real diagnosis; needs a human/Claude session to understand the actual blast radius (recovery:escalated)
```

## Proposed (LLM re-evaluation — review before applying)
1. Triage GUT suite: Isolate and fix the 4 failing tests to achieve a green baseline (15 min)
2. Resolve RID leak warnings: Add explicit `free()` calls for DummyTexture and ShapedTextData in test teardowns (15 min)
3. Validate rig_meta.json consistency: Write a script to verify all sprite paths in assets/sprites/rig_units exist on disk (15 min)
4. Implement audio SFX loader: Create a utility to preload and play the 6 defined .ogg files from assets/audio/sfx (15 min)
5. Generate placeholder sprites for missing rig parts: Create simple colored rectangles for any missing arm/head assets in rig_units (15 min)
