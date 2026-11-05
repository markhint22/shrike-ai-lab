# Grooming proposal — xlite — 2026-11-05 04:00

## Current Next Steps
```
- [x] [AUTO-SKIP after 5 no-op cycles — already-done, mis-targeted, or beyond the 27B; review] [EMERGENCY][T2] godot GUT suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing:   Failing         4;[31m---- 4 failing tests ---- ERROR: 12 RID allocations of type 'PN13RendererDummy14TextureStorage12DummyTextureE' were leaked at exit.;ERROR: 93 RID allocations of type 'PN18TextServerAdvanced22ShapedTextDataAdvancedE' were leaked at exit. ERROR: 1 RID allocations of type 'PN18TextServerAdvanced12FontAdvancedE' were leaked at exit.  <!-- superseded by recovery decomposition below -->
- [x] (dismissed 2026-10-07: diagnostic note, not a work item - the underlying work is tracked by the item lines with a VERIFY clause) [CLAUDE] this area has been recovered/decomposed 5 times (cap 2) without ever landing - the fleet keeps re-guessing at this same file with no real diagnosis; needs a human/Claude session to understand the actual blast radius (recovery:escalated)
```

## Proposed (LLM re-evaluation — review before applying)
1. Verify GUT test suite is green and confirm RID leak errors are resolved by running the full test suite locally.
2. Refactor `scripts/tools/mission_editor.gd` to extract `_on_save_pressed` logic into a dedicated save handler class or function for better maintainability.
3. Implement unit tests for the new reset logic in `_defend_until`, `_directive`, and `_patrol_b` to ensure state resets correctly.
4. Add missing arm sprites for `enemy_boss`, `enemy_brute`, `enemy_elite`, `enemy_grunt`, `enemy_minigunner`, `enemy_raider`, `enemy_shield`, `enemy_shotgunner`, `player_heavy`, and `player_medic` to match the `rig_test/grunt` structure.
5. Create a `scripts/autoload/audio_manager.gd` to centralize SFX playback for `attack_hit`, `attack_miss`, `confirm`, `error`, `grenade_explosion`, and `unit_select`.
6. Add a `scripts/ui/hub_menu.gd` script to handle navigation between the hub, battle, and title screens using the existing background assets.
