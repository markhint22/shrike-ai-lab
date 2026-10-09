# Grooming proposal — xlite — 2026-10-09 04:00

## Current Next Steps
```
- [x] [AUTO-SKIP after 5 no-op cycles — already-done, mis-targeted, or beyond the 27B; review] [EMERGENCY][T2] godot GUT suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing:   Failing         4;[31m---- 4 failing tests ---- ERROR: 12 RID allocations of type 'PN13RendererDummy14TextureStorage12DummyTextureE' were leaked at exit.;ERROR: 93 RID allocations of type 'PN18TextServerAdvanced22ShapedTextDataAdvancedE' were leaked at exit. ERROR: 1 RID allocations of type 'PN18TextServerAdvanced12FontAdvancedE' were leaked at exit.  <!-- superseded by recovery decomposition below -->
- [x] (dismissed 2026-10-07: diagnostic note, not a work item - the underlying work is tracked by the item lines with a VERIFY clause) [CLAUDE] this area has been recovered/decomposed 5 times (cap 2) without ever landing - the fleet keeps re-guessing at this same file with no real diagnosis; needs a human/Claude session to understand the actual blast radius (recovery:escalated)
```

## Proposed (LLM re-evaluation — review before applying)
1. Verify GUT test suite is green and confirm zero RID allocation leaks at exit (RendererDummy, TextServerAdvanced)
2. Audit `assets/sprites/rig_units/` for missing arm sprites (arm_l.png, arm_r.png) in enemy/player units and generate placeholders or flag asset pipeline gap
3. Update `ROADMAP.md` to reflect the removal of `BattleResumeValidator` and mark related battle resume features as deprecated or pending re-implementation
4. Add unit tests for `rig_meta.json` parsing logic to ensure sprite rig metadata is validated correctly during load
