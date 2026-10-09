# Grooming proposal — xlite — 2026-10-08 04:00

## Current Next Steps
```
- [x] [AUTO-SKIP after 5 no-op cycles — already-done, mis-targeted, or beyond the 27B; review] [EMERGENCY][T2] godot GUT suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing:   Failing         4;[31m---- 4 failing tests ---- ERROR: 12 RID allocations of type 'PN13RendererDummy14TextureStorage12DummyTextureE' were leaked at exit.;ERROR: 93 RID allocations of type 'PN18TextServerAdvanced22ShapedTextDataAdvancedE' were leaked at exit. ERROR: 1 RID allocations of type 'PN18TextServerAdvanced12FontAdvancedE' were leaked at exit.  <!-- superseded by recovery decomposition below -->
- [x] (dismissed 2026-10-07: diagnostic note, not a work item - the underlying work is tracked by the item lines with a VERIFY clause) [CLAUDE] this area has been recovered/decomposed 5 times (cap 2) without ever landing - the fleet keeps re-guessing at this same file with no real diagnosis; needs a human/Claude session to understand the actual blast radius (recovery:escalated)
```

## Proposed (LLM re-evaluation — review before applying)
1. Verify GUT suite is green by running the full test suite and confirming zero failing tests, specifically checking that the previously reported RID allocation leaks (DummyTexture, ShapedTextData, Font) no longer appear in the exit logs.
2. Update `OVERNIGHT_PROGRESS.md` to reflect the successful reconciliation of the overnight/feature branch into develop, marking the branch-hygiene task as complete and noting the green test gate status.
3. Create a minimal `test_rig_loading.gd` GUT test that iterates through all `rig_meta.json` files in `assets/sprites/rig_units/` to verify JSON structure validity and ensure all referenced sprite paths (body, leg_l, leg_r) exist on disk.
