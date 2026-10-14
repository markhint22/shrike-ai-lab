# Grooming proposal — xlite — 2026-10-14 04:00

## Current Next Steps
```
- [x] [AUTO-SKIP after 5 no-op cycles — already-done, mis-targeted, or beyond the 27B; review] [EMERGENCY][T2] godot GUT suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing:   Failing         4;[31m---- 4 failing tests ---- ERROR: 12 RID allocations of type 'PN13RendererDummy14TextureStorage12DummyTextureE' were leaked at exit.;ERROR: 93 RID allocations of type 'PN18TextServerAdvanced22ShapedTextDataAdvancedE' were leaked at exit. ERROR: 1 RID allocations of type 'PN18TextServerAdvanced12FontAdvancedE' were leaked at exit.  <!-- superseded by recovery decomposition below -->
- [x] (dismissed 2026-10-07: diagnostic note, not a work item - the underlying work is tracked by the item lines with a VERIFY clause) [CLAUDE] this area has been recovered/decomposed 5 times (cap 2) without ever landing - the fleet keeps re-guessing at this same file with no real diagnosis; needs a human/Claude session to understand the actual blast radius (recovery:escalated)
```

## Proposed (LLM re-evaluation — review before applying)
1. Fix GUT suite RID leaks: Add `free()` calls for DummyTexture and ShapedTextData in test teardown to clear the 4 failing tests.
2. Verify boss display name logic: Confirm `unit.gd` returns "Warlord" internally while UI displays "Boss" per recent revert, ensuring no regression in `test/unit_test.gd`.
3. Implement global codex save exclusion: Update save slot naming logic to exclude global codex data from local slot saves, verifying with the new test case.
4. Add missing arm sprites for enemy_brute: Create `arm_l.png` and `arm_r.png` in `assets/sprites/rig_units/enemy_brute/` to match the rig structure of other units like `enemy_grunt`.
5. Add missing arm sprites for enemy_elite: Create `arm_l.png` and `arm_r.png` in `assets/sprites/rig_units/enemy_elite/` to complete the sprite set for animation rigging.
6. Add missing arm sprites for enemy_minigunner: Create `arm_l.png` and `arm_r.png` in `assets/sprites/rig_units/enemy_minigunner/` to ensure consistent rig metadata across all enemy units.
