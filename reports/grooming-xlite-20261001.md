# Grooming proposal — xlite — 2026-10-01 04:00

## Current Next Steps
```
- [x] [AUTO-SKIP after 5 no-op cycles — already-done, mis-targeted, or beyond the 27B; review] [EMERGENCY][T2] godot GUT suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing:   Failing         4;[31m---- 4 failing tests ---- ERROR: 12 RID allocations of type 'PN13RendererDummy14TextureStorage12DummyTextureE' were leaked at exit.;ERROR: 93 RID allocations of type 'PN18TextServerAdvanced22ShapedTextDataAdvancedE' were leaked at exit. ERROR: 1 RID allocations of type 'PN18TextServerAdvanced12FontAdvancedE' were leaked at exit.  <!-- superseded by recovery decomposition below -->
- [ ] [CLAUDE] this area has been recovered/decomposed 5 times (cap 2) without ever landing - the fleet keeps re-guessing at this same file with no real diagnosis; needs a human/Claude session to understand the actual blast radius (recovery:escalated)
```

## Proposed (LLM re-evaluation — review before applying)
1. Fix GUT suite RID leaks: Add `queue_free()` or explicit release calls for `DummyTexture` and `ShapedTextData` in test teardown to clear the 4 failing tests.
2. Implement `SaveManager.save_game()` method to persist current game state using the existing `file_exists_for` and `quarantine` utilities.
3. Add unit tests for `SaveManager._is_valid_save_name` covering edge cases (special characters, length limits) to ensure validation logic is robust.
4. Create a basic `BattleScene` integration test that verifies `sync_from_battle` correctly handles fallen units without re-adding them, leveraging the recent commit changes.
5. Document the `rig_meta.json` schema in `README.md` or a new `ASSETS.md` to clarify how sprite rigging data is structured for future asset additions.
