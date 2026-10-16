# Grooming proposal — xlite — 2026-10-16 04:00

## Current Next Steps
```
- [x] [AUTO-SKIP after 5 no-op cycles — already-done, mis-targeted, or beyond the 27B; review] [EMERGENCY][T2] godot GUT suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing:   Failing         4;[31m---- 4 failing tests ---- ERROR: 12 RID allocations of type 'PN13RendererDummy14TextureStorage12DummyTextureE' were leaked at exit.;ERROR: 93 RID allocations of type 'PN18TextServerAdvanced22ShapedTextDataAdvancedE' were leaked at exit. ERROR: 1 RID allocations of type 'PN18TextServerAdvanced12FontAdvancedE' were leaked at exit.  <!-- superseded by recovery decomposition below -->
- [x] (dismissed 2026-10-07: diagnostic note, not a work item - the underlying work is tracked by the item lines with a VERIFY clause) [CLAUDE] this area has been recovered/decomposed 5 times (cap 2) without ever landing - the fleet keeps re-guessing at this same file with no real diagnosis; needs a human/Claude session to understand the actual blast radius (recovery:escalated)
```

## Proposed (LLM re-evaluation — review before applying)
1. Verify GUT suite is green by running the full test suite and confirming zero failing tests or RID leak errors.
2. Add docstrings to all public functions in `test_directive_sweep.gd` to match recent documentation standards.
3. Refactor `aggro.gd` to remove any remaining references to `bonus_enemy_count` and verify unit tests pass.
4. Create a new GUT test file for `mission_data.gd` to cover edge cases in mission loading logic.
5. Add a smoke test for the `rig_meta.json` parsing logic to ensure sprite rig data loads correctly.
6. Update `README.md` to document the current status of the autonomous coding queue and recent changes.
