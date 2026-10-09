# Grooming proposal — xlite — 2026-10-05 04:00

## Current Next Steps
```
- [x] [AUTO-SKIP after 5 no-op cycles — already-done, mis-targeted, or beyond the 27B; review] [EMERGENCY][T2] godot GUT suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing:   Failing         4;[31m---- 4 failing tests ---- ERROR: 12 RID allocations of type 'PN13RendererDummy14TextureStorage12DummyTextureE' were leaked at exit.;ERROR: 93 RID allocations of type 'PN18TextServerAdvanced22ShapedTextDataAdvancedE' were leaked at exit. ERROR: 1 RID allocations of type 'PN18TextServerAdvanced12FontAdvancedE' were leaked at exit.  <!-- superseded by recovery decomposition below -->
- [ ] [CLAUDE] this area has been recovered/decomposed 5 times (cap 2) without ever landing - the fleet keeps re-guessing at this same file with no real diagnosis; needs a human/Claude session to understand the actual blast radius (recovery:escalated)
```

## Proposed (LLM re-evaluation — review before applying)
1. Triage and fix the 4 failing GUT tests by isolating the specific test cases causing RID allocation leaks (TextureStorage, ShapedTextData, Font) and applying targeted fixes to either the code or test setup.
2. Investigate the root cause of the recurring recovery/decomposition failures in the escalated area by analyzing the last 5 failed attempts to identify the specific file or logic pattern causing the loop.
3. Verify that the `GridDistance` preload fix in `overwatch.gd` has not introduced new runtime errors by running a quick smoke test on the grid movement logic.
4. Audit the `assets/sprites/rig_units/` directory to ensure all `rig_meta.json` files correctly reference existing sprite assets and contain valid JSON structure.
5. Check the `.queue-hard-banned-files` list to confirm no currently active code references any banned files, preventing future build failures.
