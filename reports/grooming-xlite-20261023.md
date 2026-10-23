# Grooming proposal — xlite — 2026-10-23 04:00

## Current Next Steps
```
- [x] [AUTO-SKIP after 5 no-op cycles — already-done, mis-targeted, or beyond the 27B; review] [EMERGENCY][T2] godot GUT suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing:   Failing         4;[31m---- 4 failing tests ---- ERROR: 12 RID allocations of type 'PN13RendererDummy14TextureStorage12DummyTextureE' were leaked at exit.;ERROR: 93 RID allocations of type 'PN18TextServerAdvanced22ShapedTextDataAdvancedE' were leaked at exit. ERROR: 1 RID allocations of type 'PN18TextServerAdvanced12FontAdvancedE' were leaked at exit.  <!-- superseded by recovery decomposition below -->
- [x] (dismissed 2026-10-07: diagnostic note, not a work item - the underlying work is tracked by the item lines with a VERIFY clause) [CLAUDE] this area has been recovered/decomposed 5 times (cap 2) without ever landing - the fleet keeps re-guessing at this same file with no real diagnosis; needs a human/Claude session to understand the actual blast radius (recovery:escalated)
```

## Proposed (LLM re-evaluation — review before applying)
1. Verify `grid_distance.gd` logic and ensure all related unit tests pass without flakiness.
2. Confirm the idempotency check in `mark_faction_seen` prevents duplicate state updates under concurrent load.
3. Validate that `faction codex` data structures correctly handle edge cases for unseen factions.
4. Add a lightweight integration test for the `rig_meta.json` parsing logic to ensure sprite rigging data loads correctly.
5. Create a utility script to validate audio asset file paths in `assets/audio/sfx/` against the codebase references.
6. Implement a basic health check endpoint or log entry that verifies the presence of critical background images (`bg_battle.png`, etc.).
