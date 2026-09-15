# xlite — RELEASE-READINESS backlog (27B-friendly GDScript/GUT), release-blockers FIRST
# TOP blockers: crash guards (corrupt save_version) + economy bugs (negative spend grants credits)
# + soft-lock guards. battle.gd and mission_select.gd are HARD-BANNED for the fleet (Claude only).

# --- next-year roadmap decomposition (2026-09-05): tutorial + content expansion + release ---

# --- platform-completion pure-logic (2026-09-05): desktop/mobile/steam helpers + tests ---

# --- refill (2026-09-05): pure-logic coverage + new testable helper modules (not battle.gd/mission_select.gd) ---

# --- refill 2026-09-06: new self-contained pure GDScript modules + GUT tests (landable) ---

# --- refill 2026-09-06: more pure GDScript modules + GUT tests (self-verifying) ---

# --- COMPETITIVE 2026-09-06: xlite vs Into the Breach — telegraphed enemy intents (their signature) + no-pay-to-wait ---
# Full-information / telegraphed enemy moves — the defining Into the Breach feature xlite lacks



# --- 27B-decomposed from roadmap [2026-09-07]: Telegraphed enemy intents (Into-the-Breach signature): planned target, threat overlay, int (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-07]: Wire pure combat predicates into battle.gd (suppression, overwatch, flanking, friendly-fir (review + tweak) ---
- [ ] [T2] test/battle/test_overwatch.gd — Write unit test for `overwatch.gd` verifying true when LOS is clear and range valid, false when blocked. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test/battle/test_overwatch.gd`. (cat:test; multifile:no)

# --- 27B-decomposed from roadmap [2026-09-08]: Save/load hardening + settings + UX polish {cat: game; size: M; multifile: yes; research:  (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-10]: Fog-of-war follow-through (base is done, this is the remainder): (1) land the patrol-enemy (review + tweak) ---
# NOTE (2026-09-10): the planner decomposed this from the SERVER's overnight/feature clone, which didn't
# yet have the patrol-AI work that already shipped on claude/feature -> develop (_enemy_can_see_a_player/
# _patrol_step in battle.gd, MissionData.enemy_patrol_routes, tests/test_battle_patrol.gd,
# tests/test_mission_data_patrol_route.gd - all real and tested). Removed 7 duplicate items that would
# have rebuilt the same feature as new patrol_ai.gd/enemy_sight-adjacent files once overnight/feature
# catches up to develop. Kept only the genuinely still-open piece: per-archetype sight range - but split
# so the fleet only gets the standalone-file half; battle.gd is in .queue-hard-banned-files (mechanical
# enforcement in run_overnight.sh discards the WHOLE cycle if a commit touches it), so wiring
# EnemySight.get_range into battle.gd's actual usage site is Claude-only, noted in OVERNIGHT_PROGRESS.md's
# hard-ban section instead of left here where the fleet would burn a guaranteed-discarded cycle on it.

# --- 27B-decomposed from roadmap [2026-09-10]: Mission variety + campaign arc — Adopt Into the Breach's model: a small fixed set of ~6 ob (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-10]: Roster depth: classes, abilities, synergy, upgrades — Ship 4-6 mechanically distinct class (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-10]: Desktop release (Steam/itch) prep — Steam: create Steamworks account, pay the $100 Steam D (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-10]: Mobile port (Android first) — touch controls, safe-area — Remap desktop trackpad pinch-zoo (review + tweak) ---
- [x] (implemented via manual staged-pipeline test 2026-09-14, see scripts/battle/touch_move.gd) [T1] scripts/battle/touch_move.gd — Add static function `validate_move_target(cell: Vector2i, unit_pos: Vector2i, move_range: int, obstacles: Array[Vector2i]) -> bool` that checks if a tapped cell is within range and not blocked, for tap-to-move logic. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit/test_touch_move.gd -gexit` passes with grid pathfinding edge cases. (cat:godot; multifile:no)

# --- 27B-decomposed from roadmap [2026-09-13]: Ability synergy/combo tags — pure two-ability combo detection for the roster-depth epic: n (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-13]: Per-class perk/upgrade tier data — new scripts/roster/class_perks.gd (class_name ClassPerk (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-13]: Partial-success degraded reward calc — new scripts/battle/partial_success_reward.gd (class (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-13]: Objective failure predicate — new scripts/mission/objective_failure.gd (class_name Objecti (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-13]: Campaign branch-point resolver — new scripts/mission/campaign_branch.gd (class_name Campai (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Extract misplaced Steam/UI helpers out of accuracy_curve.gd — scripts/battle/accuracy_curv (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: New difficulty_scaling.gd (Easy/Normal/Hard multiplier, pure calc) — verified via read tha (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Achievement registry: add milestones for systems that already exist but aren't tracked — s (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: New itch_readiness_check.gd (fills a verified asymmetry with the Steam release checklist)  (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: New player_stats_validator.gd (mirrors the existing EnemyStatsValidator/AbilityStatsValida (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Mission validator: terrain theme + turn-limit checks — scripts/mission/mission_validator.g (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Injury recovery: progress percentage — scripts/roster/injury_recovery.gd (verified via rea (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Input remapper: detect duplicate key bindings — scripts/settings/input_remapper.gd (verifi (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Codex: tech entries missing their reveal key/wrapper — scripts/codex/codex_data.gd (verifi (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Loot tier: minimum-level lookup (inverse of loot_tier) — scripts/battle/loot_tier.gd (veri (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Shield absorb: remaining shield after a hit — scripts/battle/shield_absorb.gd (verified vi (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Cooldown: turns-remaining counter — scripts/units/cooldown.gd (verified via read, 5 lines) (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: TieBreaker highest-id tie-break helper — scripts/battle/tie_breaker.gd (verified via read, (review + tweak) ---
- [ ] [T2] tests/test_tie_breaker_highest_id.gd — Add `test_multiple_elements_returns_max` asserting TieBreaker.highest_id([1, 5, 3, 9]) == 9. VERIFY: godot --headless --script addons/gut/gut_cmdln.gd -gdir=tests/test_tie_breaker_highest_id.gd (cat:test; multifile:no)
- [ ] [T2] tests/test_tie_breaker_highest_id.gd — Add `test_negative_numbers_returns_max` asserting TieBreaker.highest_id([-10, -5, -1]) == -1. VERIFY: godot --headless --script addons/gut/gut_cmdln.gd -gdir=tests/test_tie_breaker_highest_id.gd (cat:test; multifile:no)
- [ ] [T2] tests/test_tie_breaker_highest_id.gd — Add `test_duplicates_returns_max` asserting TieBreaker.highest_id([7, 7, 7]) == 7. VERIFY: godot --headless --script addons/gut/gut_cmdln.gd -gdir=tests/test_tie_breaker_highest_id.gd (cat:test; multifile:no)

# --- 27B-decomposed from roadmap [2026-09-14]: RageMeter UI progress percent — scripts/battle/rage_meter.gd (verified via read, 11 lines) (review + tweak) ---
- [ ] [T1] scripts/battle/rage_meter.gd — Add `static func progress_percent(current: int, threshold: int) -> int` that returns 100 if threshold <= 0, else `clampi(current * 100 / threshold, 0, 100)`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_rage_meter_progress_percent.gd -gexit` passes. (cat:godot; multifile:no)
- [ ] [T2] tests/test_rage_meter_progress_percent.gd — Create new GUT test file asserting `RageMeter.progress_percent(50, 100)` returns 50, `RageMeter.progress_percent(150, 100)` returns 100, `RageMeter.progress_percent(0, 100)` returns 0, and `RageMeter.progress_percent(10, 0)` returns 100. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_rage_meter_progress_percent.gd -gexit` passes. (cat:test; multifile:no)
- [ ] [T3] scripts/battle/rage_meter.gd — Ensure `progress_percent` handles negative `current` values by clamping to 0, consistent with `clampi` behavior in `percent_util.gd`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_rage_meter_progress_percent.gd -gexit` passes. (cat:godot; multifile:no)
- [ ] [T4] tests/test_rage_meter_progress_percent.gd — Add test case for `RageMeter.progress_percent(-10, 100)` returning 0 to verify negative input clamping. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_rage_meter_progress_percent.gd -gexit` passes. (cat:test; multifile:no)
- [ ] [T5] scripts/battle/rage_meter.gd — Add doc comment to `progress_percent` explaining it returns 0-100 fill percentage for UI binding, referencing `percent_util.gd` clamp style. VERIFY: `grep -q "fill percentage" scripts/battle/rage_meter.gd`. (cat:docs; multifile:no)

# --- 27B-decomposed from roadmap [2026-09-14]: GrenadeArc remaining-reach indicator — scripts/battle/grenade_arc.gd (verified via read, 7 (review + tweak) ---
- [ ] [T1] scripts/battle/grenade_arc.gd — Add `static func remaining_reach(dist: int, max_range: int) -> int` returning `maxi(max_range - dist, 0)` VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_grenade_arc_remaining_reach.gd -gexit` (cat:godot; multifile:no)
- [ ] [T2] tests/test_grenade_arc_remaining_reach.gd — Create new test file inheriting `GutTest` with `test_remaining_reach_positive` asserting `GrenadeArc.remaining_reach(3, 10) == 7` VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_grenade_arc_remaining_reach.gd -gexit` (cat:test; multifile:no)
- [ ] [T2] tests/test_grenade_arc_remaining_reach.gd — Add `test_remaining_reach_zero` asserting `GrenadeArc.remaining_reach(10, 10) == 0` VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_grenade_arc_remaining_reach.gd -gexit` (cat:test; multifile:no)
- [ ] [T2] tests/test_grenade_arc_remaining_reach.gd — Add `test_remaining_reach_negative_clamped` asserting `GrenadeArc.remaining_reach(15, 10) == 0` VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_grenade_arc_remaining_reach.gd -gexit` (cat:test; multifile:no)
- [ ] [T2] tests/test_grenade_arc_remaining_reach.gd — Add `test_remaining_reach_zero_dist` asserting `GrenadeArc.remaining_reach(0, 5) == 5` VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_grenade_arc_remaining_reach.gd -gexit` (cat:test; multifile:no)
- [ ] [T2] tests/test_grenade_arc_remaining_reach.gd — Add `test_remaining_reach_large_values` asserting `GrenadeArc.remaining_reach(100, 1000) == 900` VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_grenade_arc_remaining_reach.gd -gexit` (cat:test; multifile:no)

# --- 27B-decomposed from roadmap [2026-09-14]: ZoneOfControl overlap-cells (contested tiles) — scripts/grid/zone_of_control.gd (verified  (review + tweak) ---
- [ ] [T1] scripts/grid/zone_of_control.gd — Add `static func overlap_cells(origin_a: Vector2i, origin_b: Vector2i, size: Vector2i) -> Array` that computes intersection of `controlled_cells` for both origins and sorts result ascending by x then y. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_zone_of_control_overlap.gd`. (cat:godot; multifile:no)
- [ ] [T2] tests/test_zone_of_control_overlap.gd — Create test file with `extends GutTest` and import `ZoneOfControl`. VERIFY: `grep -q "extends GutTest" tests/test_zone_of_control_overlap.gd`. (cat:test; multifile:no)
- [ ] [T2] tests/test_zone_of_control_overlap.gd — Add test case verifying empty array returned when origins are far apart (no overlap). VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_zone_of_control_overlap.gd`. (cat:test; multifile:no)
- [ ] [T2] tests/test_zone_of_control_overlap.gd — Add test case verifying correct overlapping cells returned for adjacent origins. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_zone_of_control_overlap.gd`. (cat:test; multifile:no)
- [ ] [T2] tests/test_zone_of_control_overlap.gd — Add test case verifying deterministic sorting order (x then y) of returned cells. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_zone_of_control_overlap.gd`. (cat:test; multifile:no)
- [ ] [T2] tests/test_zone_of_control_overlap.gd — Add test case verifying boundary conditions where overlap is at grid edge. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_zone_of_control_overlap.gd`. (cat:test; multifile:no)
