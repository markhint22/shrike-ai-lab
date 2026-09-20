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

# --- 27B-decomposed from roadmap [2026-09-14]: RageMeter UI progress percent — scripts/battle/rage_meter.gd (verified via read, 11 lines) (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: GrenadeArc remaining-reach indicator — scripts/battle/grenade_arc.gd (verified via read, 7 (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: ZoneOfControl overlap-cells (contested tiles) — scripts/grid/zone_of_control.gd (verified  (review + tweak) ---
- [ ] [T1] scripts/grid/zone_of_control.gd — Add `static func overlap_cells(origin_a: Vector2i, origin_b: Vector2i, size: Vector2i) -> Array` that computes intersection of `controlled_cells` for both origins and sorts result ascending by x then y. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_zone_of_control_overlap.gd`. (cat:godot; multifile:no)
- [ ] [T2] tests/test_zone_of_control_overlap.gd — Create test file with `extends GutTest` and import `ZoneOfControl`. VERIFY: `grep -q "extends GutTest" tests/test_zone_of_control_overlap.gd`. (cat:test; multifile:no)
- [ ] [T2] tests/test_zone_of_control_overlap.gd — Add test case verifying empty array returned when origins are far apart (no overlap). VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_zone_of_control_overlap.gd`. (cat:test; multifile:no)
- [ ] [T2] tests/test_zone_of_control_overlap.gd — Add test case verifying correct overlapping cells returned for adjacent origins. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_zone_of_control_overlap.gd`. (cat:test; multifile:no)
- [ ] [T2] tests/test_zone_of_control_overlap.gd — Add test case verifying deterministic sorting order (x then y) of returned cells. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_zone_of_control_overlap.gd`. (cat:test; multifile:no)
- [ ] [T2] tests/test_zone_of_control_overlap.gd — Add test case verifying boundary conditions where overlap is at grid edge. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_zone_of_control_overlap.gd`. (cat:test; multifile:no)

# --- 27B-decomposed from roadmap [2026-09-18]: UpkeepCost: actual-payable-amount helper (dedupes RosterManager's inline clamp) — scripts/ (review + tweak) ---
- [ ] [T1] scripts/roster/upkeep_cost.gd — Add `static func amount_payable(funds: int, upkeep: int) -> int` returning `mini(maxi(funds, 0), maxi(upkeep, 0))`. VERIFY: `grep -q "static func amount_payable" scripts/roster/upkeep_cost.gd`. (cat:godot; multifile:no)
- [ ] [T2] tests/test_upkeep_cost_payable.gd — Create new test file with GUT test cases verifying `amount_payable` clamps negative funds to 0, negative upkeep to 0, and returns min of positive values. VERIFY: `grep -q "func test_amount_payable" tests/test_upkeep_cost_payable.gd`. (cat:test; multifile:no)
- [ ] [T3] tests/test_upkeep_cost_payable.gd — Add specific assertions for edge cases: `amount_payable(-10, 5)` returns 0, `amount_payable(10, -5)` returns 0, `amount_payable(10, 20)` returns 10. VERIFY: `grep -q "assert_eq(amount_payable(-10, 5), 0)" tests/test_upkeep_cost_payable.gd`. (cat:test; multifile:no)
- [ ] [T3] tests/test_upkeep_cost_payable.gd — Add assertion for standard case: `amount_payable(100, 50)` returns 50. VERIFY: `grep -q "assert_eq(amount_payable(100, 50), 50)" tests/test_upkeep_cost_payable.gd`. (cat:test; multifile:no)
- [ ] [T4] scripts/roster/upkeep_cost.gd — Ensure `amount_payable` is static and accessible without instantiation. VERIFY: `grep -q "static func amount_payable" scripts/roster/upkeep_cost.gd`. (cat:godot; multifile:no)

# --- 27B-decomposed from roadmap [2026-09-19]: MultiObjective: progress ratio (multi-objective counterpart to Objective.progress_ratio) — (review + tweak) ---
- [ ] [T1] scripts/mission/multi_objective.gd — Add `static func progress_ratio(statuses: Array) -> float` that returns 0.0 if statuses.is_empty() else float(completed_count(statuses)) / float(statuses.size()). VERIFY: grep -q "static func progress_ratio" scripts/mission/multi_objective.gd && grep -q "return 0.0" scripts/mission/multi_objective.gd. (cat:godot; multifile:no)
- [ ] [T2] tests/test_multi_objective_progress_ratio.gd — Create new test file extending GutTest that imports MultiObjective and asserts progress_ratio([]) == 0.0, progress_ratio([true, false]) == 0.5, and progress_ratio([true, true]) == 1.0. VERIFY: godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_multi_objective_progress_ratio.gd -gexit. (cat:test; multifile:no)
- [ ] [T3] tests/test_multi_objective_progress_ratio.gd — Add test case verifying progress_ratio([false, false]) == 0.0 and progress_ratio([true, false, true, false]) == 0.5 to cover edge cases of mixed statuses. VERIFY: godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_multi_objective_progress_ratio.gd -gexit. (cat:test; multifile:no)
- [ ] [T4] scripts/mission/multi_objective.gd — Ensure `completed_count` is accessible or correctly implemented to support the new static function, verifying it counts true values in the array. VERIFY: grep -q "func completed_count" scripts/mission/multi_objective.gd && godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_multi_objective_progress_ratio.gd -gexit. (cat:godot; multifile:no)

# --- 27B-decomposed from roadmap [2026-09-19]: TileCost: remaining move-budget after a path — scripts/grid/tile_cost.gd (verified via rea (review + tweak) ---
- [ ] [T1] scripts/grid/tile_cost.gd — Add `static func remaining_budget(terrain_types: Array, budget: int) -> int` that returns -1 if `path_cost(terrain_types)` is negative, else `maxi(budget - path_cost(terrain_types), 0)`. VERIFY: `grep -q "static func remaining_budget" scripts/grid/tile_cost.gd && grep -q "return -1" scripts/grid/tile_cost.gd`. (cat:godot; multifile:no)
- [ ] [T2] tests/test_tile_cost_remaining_budget.gd — Create new GUT test file extending `addons/gut/test.gd` with a test case for `remaining_budget` returning 0 when budget equals cost. VERIFY: `ls -la tests/test_tile_cost_remaining_budget.gd && grep -q "func test_remaining_budget_exact" tests/test_tile_cost_remaining_budget.gd`. (cat:test; multifile:no)
- [ ] [T2] tests/test_tile_cost_remaining_budget.gd — Add test case for `remaining_budget` returning positive integer when budget exceeds cost. VERIFY: `grep -q "func test_remaining_budget_surplus" tests/test_tile_cost_remaining_budget.gd`. (cat:test; multifile:no)
- [ ] [T2] tests/test_tile_cost_remaining_budget.gd — Add test case for `remaining_budget` returning -1 when path is impassable (negative cost). VERIFY: `grep -q "func test_remaining_budget_impassable" tests/test_tile_cost_remaining_budget.gd`. (cat:test; multifile:no)
- [ ] [T2] tests/test_tile_cost_remaining_budget.gd — Add test case for `remaining_budget` returning 0 when budget is less than cost. VERIFY: `grep -q "func test_remaining_budget_insufficient" tests/test_tile_cost_remaining_budget.gd`. (cat:test; multifile:no)
- [ ] [T1] scripts/grid/tile_cost.gd — Ensure `remaining_budget` uses `maxi` to clamp result to 0 for non-negative path costs. VERIFY: `grep -q "maxi(budget - path_cost(terrain_types), 0)" scripts/grid/tile_cost.gd`. (cat:godot; multifile:no)

# --- 27B-decomposed from roadmap [2026-09-19]: TurnOrder: previous-actor lookup (reverse of next_actor_id) — scripts/turn/turn_order.gd ( (review + tweak) ---
- [ ] [T1] scripts/turn/turn_order.gd — Add `static func previous_actor_id(order: Array, current_id: int) -> int` that returns -1 if order is empty, wraps to `order[-1].id` if `current_id` matches `order[0].id` or is not found, otherwise returns the id of the preceding element. VERIFY: `grep -q "static func previous_actor_id" scripts/turn/turn_order.gd`. (cat:godot; multifile:no)
- [ ] [T2] tests/test_turn_order_previous_actor.gd — Create new GUT test file with `test_previous_actor_empty_order` asserting return value is -1 for empty array. VERIFY: `gut -gdir=tests -ginclude="test_turn_order_previous_actor" -gexit`. (cat:test; multifile:no)
- [ ] [T3] tests/test_turn_order_previous_actor.gd — Add `test_previous_actor_wrap_around` asserting that for order `[A, B, C]`, calling with `current_id=A.id` returns `C.id`. VERIFY: `gut -gdir=tests -ginclude="test_turn_order_previous_actor" -gexit`. (cat:test; multifile:no)
- [ ] [T4] tests/test_turn_order_previous_actor.gd — Add `test_previous_actor_middle_element` asserting that for order `[A, B, C]`, calling with `current_id=B.id` returns `A.id`. VERIFY: `gut -gdir=tests -ginclude="test_turn_order_previous_actor" -gexit`. (cat:test; multifile:no)
- [ ] [T5] tests/test_turn_order_previous_actor.gd — Add `test_previous_actor_not_found` asserting that for order `[A, B]`, calling with `current_id=999` returns `B.id` (wrap to last). VERIFY: `gut -gdir=tests -ginclude="test_turn_order_previous_actor" -gexit`. (cat:test; multifile:no)

# --- 27B-decomposed from roadmap [2026-09-20]: ApPool: fill percentage for an AP-bar UI — scripts/units/ap_pool.gd (verified via read, 17 (review + tweak) [feat:xlite-20260920-appool-fill-percentage-for-an-ap-bar-ui-] ---
- [ ] [T1] scripts/units/ap_pool.gd — Add `static func percent_full(current: int, cap: int) -> int` that returns 0 if `cap <= 0`, else `clampi(current * 100 / cap, 0, 100)`. VERIFY: `grep -q "static func percent_full" scripts/units/ap_pool.gd`. (cat:godot; multifile:no) [feat:xlite-20260920-appool-fill-percentage-for-an-ap-bar-ui-]
- [ ] [T2] tests/test_ap_pool_percent_full.gd — Create new GUT test file with `test_percent_full_zero_cap` asserting `ApPool.percent_full(5, 0) == 0` and `test_percent_full_negative_cap` asserting `ApPool.percent_full(5, -1) == 0`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=tests/test_ap_pool_percent_full.gd -gexit -gquiet`. (cat:test; multifile:no) [feat:xlite-20260920-appool-fill-percentage-for-an-ap-bar-ui-]
- [ ] [T2] tests/test_ap_pool_percent_full.gd — Add `test_percent_full_empty` asserting `ApPool.percent_full(0, 10) == 0` and `test_percent_full_half` asserting `ApPool.percent_full(5, 10) == 50`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=tests/test_ap_pool_percent_full.gd -gexit -gquiet`. (cat:test; multifile:no) [feat:xlite-20260920-appool-fill-percentage-for-an-ap-bar-ui-]
- [ ] [T2] tests/test_ap_pool_percent_full.gd — Add `test_percent_full_full` asserting `ApPool.percent_full(10, 10) == 100` and `test_percent_full_overflow` asserting `ApPool.percent_full(15, 10) == 100`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=tests/test_ap_pool_percent_full.gd -gexit -gquiet`. (cat:test; multifile:no) [feat:xlite-20260920-appool-fill-percentage-for-an-ap-bar-ui-]
- [ ] [T2] tests/test_ap_pool_percent_full.gd — Add `test_percent_full_underflow` asserting `ApPool.percent_full(-5, 10) == 0` and `test_percent_full_one_cap` asserting `ApPool.percent_full(1, 1) == 100`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=tests/test_ap_pool_percent_full.gd -gexit -gquiet`. (cat:test; multifile:no) [feat:xlite-20260920-appool-fill-percentage-for-an-ap-bar-ui-]
