# Grooming proposal — xlite — 2026-11-13 04:00

## Current Next Steps
```
- [ ] [CLAUDE] [unworkable: hard-banned file scripts/battle/battle.gd] [T3] scripts/battle/battle.gd — Manual-test bug (reported by Mark, flow cover-and-flank-change-odds, 2026-11-11): This is difficult to test because there's no clear indicator that an enemy is considered fully covered, half-covered, flanked etc. Please consider adding this to help a player learn that flanking helps and cover reduces hit chance. Also look at: scripts/grid/grid_renderer.gd, scripts/battle/aim_modifiers.gd. First write a failing test that reproduces this, then fix it; if the cause is not in this file, say so. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`. (cat:bugfix; multifile:yes; src:manual) [feat:xlite-20261111-manual-d957b547]
- [x] [AUTO-SKIP after 5 no-op cycles — already-done, mis-targeted, or beyond the 27B; review] [EMERGENCY][T2] godot GUT suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing:   Failing         4;[31m---- 4 failing tests ---- ERROR: 12 RID allocations of type 'PN13RendererDummy14TextureStorage12DummyTextureE' were leaked at exit.;ERROR: 93 RID allocations of type 'PN18TextServerAdvanced22ShapedTextDataAdvancedE' were leaked at exit. ERROR: 1 RID allocations of type 'PN18TextServerAdvanced12FontAdvancedE' were leaked at exit.  <!-- superseded by recovery decomposition below -->
- [x] (dismissed 2026-10-07: diagnostic note, not a work item - the underlying work is tracked by the item lines with a VERIFY clause) [CLAUDE] this area has been recovered/decomposed 5 times (cap 2) without ever landing - the fleet keeps re-guessing at this same file with no real diagnosis; needs a human/Claude session to understand the actual blast radius (recovery:escalated)
```

## Proposed (LLM re-evaluation — review before applying)
1. Add visual indicators for cover and flanking states in `scripts/grid/grid_renderer.gd` to help players understand tactical positioning (split: UI layer only).
2. Implement unit-specific hit-chance modifiers based on cover/flank status in `scripts/battle/aim_modifiers.gd` (split: logic layer only).
3. Write a failing GUT test for the cover-and-flank interaction in `tests/test_aim_modifiers.gd` to verify the new logic before integration.
4. Add a "Tactical Status" HUD element to display current unit's effective hit chance and modifier breakdowns (new: high-value UX win).
5. Create a `scripts/battle/tactical_debug.gd` utility to log detailed cover/flank calculations for manual testing (new: diagnostic tool).
6. Refactor `scripts/grid/grid_renderer.gd` to decouple rendering logic from tactical state queries, improving testability (new: code quality).
