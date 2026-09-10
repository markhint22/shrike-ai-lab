# AGENTS.md — xlite

Godot 4 (GDScript) isometric turn-based tactics game (XCOM-like: squad, cover, overwatch, tech tree,
roster, missions). MVP complete; work now is release-hardening (crash/save-corruption guards + test coverage).

**Stack:** Godot 4 + GDScript. Tests via the **GUT** framework, run headless. No backend/web.

## Repo map (where things live)
- `scripts/save/save_manager.gd` — save/load (`save_save`/`load_save`/`delete_save`/`list_saves`/`_migrate`); SAVE_VERSION.
- `scripts/roster/roster_manager.gd` — soldiers, credits/materials economy, recruit, ranks (`RosterEntry`, `rank_for_xp`, `create_unit_from_entry`).
- `scripts/tech/tech_manager.gd` — research tree (`research_tech`, `apply_tech_bonuses`).
- `scripts/mission/mission_data.gd` — mission definitions (`TerrainType`, `type_for_index`, grid/spawns).
- `scripts/units/{unit.gd, status_effects.gd}` — unit stats/archetypes; status effects (`apply`/`tick`/`refresh`/`to_dict`/`from_dict`).
- `scripts/grid/`, `scripts/ui/` — grid render / cover; UI helpers (safe-area, touch).
- `missions/mission_*.tres` — mission data resources (43+).
- `tests/*.gd` and `test/` — GUT unit tests (one per pure function/behavior; ~300+).

## Commands (exact)
- Tests are GUT, run headless by the fleet's verify (Godot binary on the server is `~/godot/godot4`).
  Typical: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gexit` (or the repo's `.ovn-verify.sh` if present).
- **After changing art/scenes/resources, an `--import` pass is needed** for changes to register.
- No compiler/typecheck step beyond Godot's parse; a parse error in one `.gd` fails that file.

## Conventions
- Write/extend **GUT tests** for pure/deterministic logic: damage/heal math, class-balance rules, state
  transitions, save/load serialization **round-trips**, bounds/null guards. `assert_eq`/`assert_true`/`assert_false`.
- **Coerce types from loaded/serialized data** (`int(v)`, `clampi`, `maxi`) — save files and rewind snapshots
  can carry String/float/negative values that crash later code. Guard them at the boundary.
- **Deep-copy** on snapshot/serialize (`to_dict`/`from_dict`, `TurnSnapshot`) so undo/rewind can't alias live state.
- Economy methods must reject negative amounts (a negative `spend_credits` would *grant* credits).
- Keep two arrays that must stay parallel (e.g. `obstacles` + `obstacle_types`) the SAME length.

## Gotchas
- **`scripts/battle/battle.gd` and `scripts/mission/mission_select.gd` are HARD-BANNED for the fleet**
  (Claude/human only — they need the running engine to verify and the int-vs-string bug class bit twice there).
  Never edit them from a queue item; wire pure predicates into them only via a Claude-owned task.
- **GUT exits 0 even on a parse error that drops a whole test file** — verify by checking the raw
  Passing/Tests totals, not just the exit code (a silent parse break can hide as "all passed").
- Mid-battle state save/restore is a Claude item (needs in-engine verification), not a fleet task.
- Sprites are placeholder; art is a separate gated track (`docs/ART_TODO.md`), not code work.
