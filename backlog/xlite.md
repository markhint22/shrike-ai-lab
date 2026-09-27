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

# --- 27B-decomposed from roadmap [2026-09-18]: UpkeepCost: actual-payable-amount helper (dedupes RosterManager's inline clamp) — scripts/ (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-19]: MultiObjective: progress ratio (multi-objective counterpart to Objective.progress_ratio) — (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-19]: TileCost: remaining move-budget after a path — scripts/grid/tile_cost.gd (verified via rea (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-19]: TurnOrder: previous-actor lookup (reverse of next_actor_id) — scripts/turn/turn_order.gd ( (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-20]: ApPool: fill percentage for an AP-bar UI — scripts/units/ap_pool.gd (verified via read, 17 (review + tweak) [feat:xlite-20260920-appool-fill-percentage-for-an-ap-bar-ui-] ---

# --- 27B-decomposed from roadmap [2026-09-20]: Extraction: percent of squad extracted (feeds the existing "full_squad_extraction" achieve (review + tweak) [feat:xlite-20260920-extraction-percent-of-squad-extracted-fe] ---

# --- 27B-decomposed from roadmap [2026-09-20]: Grid: dedupe two identical Manhattan-distance implementations — scripts/grid/manhattan.gd  (review + tweak) [feat:xlite-20260920-grid-dedupe-two-identical-manhattan-dist] ---









# --- Claude-decomposed from roadmap [2026-09-22]: Dedupe scripts/battle/upkeep.gd (orphaned duplicate of UpkeepCost.amount_payable) ---

# --- Claude-decomposed from roadmap [2026-09-22]: XpCurve level-for-xp inverse lookup — scripts/units/xp_curve.gd ---

# --- Claude-decomposed from roadmap [2026-09-22]: CritOdds bonus-needed-for-guaranteed-crit — scripts/battle/crit_odds.gd ---

# --- Claude-decomposed from roadmap [2026-09-22]: BurstFire hit-percent-needed-to-kill — scripts/battle/burst_fire.gd ---

# --- Claude-decomposed from roadmap [2026-09-22]: ArmorPen damage-reduced-percentage — scripts/battle/armor_pen.gd ---

# --- Claude-decomposed from roadmap [2026-09-22]: SlotName index-from-label inverse — scripts/save/slot_name.gd ---

# --- Claude-decomposed from roadmap [2026-09-22 deep pass]: CoverValue cover-tier-needed-for-target-defense — scripts/battle/cover_value.gd ---

# --- Claude-decomposed from roadmap [2026-09-22 deep pass]: DodgeChance agility-needed-for-target-dodge — scripts/battle/dodge_chance.gd ---

# --- Claude-decomposed from roadmap [2026-09-22 deep pass]: SalvageValue total-scrap-for-a-tiered-batch — scripts/battle/salvage_value.gd ---

# --- Claude-decomposed from roadmap [2026-09-22 deep pass]: ExecuteThreshold percent-above-threshold — scripts/battle/execute_threshold.gd ---

# --- Claude-decomposed from roadmap [2026-09-22 deep pass]: HeightDamage levels-needed-for-bonus — scripts/battle/height_damage.gd ---

# --- Claude-decomposed from roadmap [2026-09-22 deep pass]: StatGrowth levels-needed-for-stat — scripts/roster/stat_growth.gd ---

# --- Claude-decomposed from roadmap [2026-09-22 deep pass]: ReloadCost ap-after-reload — scripts/battle/reload_cost.gd ---

# --- Claude-decomposed from roadmap [2026-09-22 deep pass]: ThreatPreview is_threatened — scripts/battle/threat_preview.gd ---

# --- Claude-decomposed from roadmap [2026-09-22 deep pass]: Hazard damage-over-turns — scripts/mission/hazard.gd ---

# --- Claude-decomposed from roadmap [2026-09-22 deep pass]: CounterAttack remaining-ap-after-counter — scripts/battle/counter_attack.gd ---

# --- Claude-decomposed from roadmap [2026-09-22 deep pass]: DamageFalloff falloff-percent — scripts/battle/damage_falloff.gd ---

# --- Claude-decomposed from roadmap [2026-09-22 deep pass]: Lifesteal overheal-wasted — scripts/battle/lifesteal.gd ---

# --- Claude-decomposed from roadmap [2026-09-22 deep pass]: StreakBonus hits-to-cap — scripts/battle/streak_bonus.gd ---

# --- Claude-decomposed from roadmap [2026-09-22 deep pass]: DamageVariance roll-percent-of-range — scripts/battle/damage_variance.gd ---
- [ ] [T5] tests — Run the full GUT suite once to confirm `roll_percent_of_range` caused zero regressions elsewhere. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-damagevariance-roll-percent]

# --- Claude-decomposed from roadmap [2026-09-22 deep pass]: CoverDegradation durability-percent — scripts/battle/cover_degradation.gd ---
- [ ] [T1] scripts/battle/cover_degradation.gd — Add `static func durability_percent(current: int, max_durability: int) -> int`: return 0 if `max_durability <= 0`; otherwise `clampi(current * 100 / max_durability, 0, 100)`. VERIFY: `grep -q "static func durability_percent" scripts/battle/cover_degradation.gd`. (cat:godot; multifile:no) [feat:xlite-20260922-coverdegradation-percent]
- [ ] [T2] tests/test_cover_degradation_percent.gd — Create new GUT test file (`extends GutTest`) with `test_partial_durability` asserting `CoverDegradation.durability_percent(50, 100) == 50`. VERIFY: `grep -q "extends GutTest" tests/test_cover_degradation_percent.gd`. (cat:test; multifile:no) [feat:xlite-20260922-coverdegradation-percent]
- [ ] [T2] tests/test_cover_degradation_percent.gd — Add `test_full_durability` asserting `CoverDegradation.durability_percent(100, 100) == 100`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_cover_degradation_percent.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-coverdegradation-percent]
- [ ] [T2] tests/test_cover_degradation_percent.gd — Add `test_broken_durability` asserting `CoverDegradation.durability_percent(0, 100) == 0`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_cover_degradation_percent.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-coverdegradation-percent]
- [ ] [T3] tests/test_cover_degradation_percent.gd — Add `test_zero_max_durability_guard` asserting `CoverDegradation.durability_percent(10, 0) == 0`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_cover_degradation_percent.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-coverdegradation-percent]
- [ ] [T3] tests/test_cover_degradation_percent.gd — Add `test_never_exceeds_hundred` asserting `CoverDegradation.durability_percent(150, 100) == 100`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_cover_degradation_percent.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-coverdegradation-percent]
- [ ] [T4] scripts/battle/cover_degradation.gd — Add a doc comment above `durability_percent` explaining it feeds a cover-durability UI bar, mirroring `ApPool.percent_full`'s clamp style. VERIFY: `grep -q "durability UI bar\|durability bar" scripts/battle/cover_degradation.gd`. (cat:docs; multifile:no) [feat:xlite-20260922-coverdegradation-percent]
- [ ] [T5] tests — Run the full GUT suite once to confirm `durability_percent` caused zero regressions elsewhere. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-coverdegradation-percent]

# --- Claude-decomposed from roadmap [2026-09-22 deep pass]: SpiralCells filled-area — scripts/grid/spiral_cells.gd ---
- [ ] [T1] scripts/grid/spiral_cells.gd — Add `static func filled_area(center: Vector2i, radius: int) -> Array`: return an empty Array if `radius < 0`; otherwise accumulate `ring_at(center, r)` via `append_array` for `r` in `range(radius + 1)`, reusing `ring_at` rather than reimplementing its geometry. VERIFY: `grep -q "static func filled_area" scripts/grid/spiral_cells.gd`. (cat:godot; multifile:no) [feat:xlite-20260922-spiralcells-filled-area]
- [ ] [T2] tests/test_spiral_cells_filled_area.gd — Create new GUT test file (`extends GutTest`) with `test_radius_zero_is_one_cell` asserting `SpiralCells.filled_area(Vector2i(5, 5), 0).size() == 1`. VERIFY: `grep -q "extends GutTest" tests/test_spiral_cells_filled_area.gd`. (cat:test; multifile:no) [feat:xlite-20260922-spiralcells-filled-area]
- [ ] [T2] tests/test_spiral_cells_filled_area.gd — Add `test_matches_count_in_radius_for_radius_one` asserting `SpiralCells.filled_area(Vector2i(5, 5), 1).size() == SpiralCells.count_in_radius(1)`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_spiral_cells_filled_area.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-spiralcells-filled-area]
- [ ] [T2] tests/test_spiral_cells_filled_area.gd — Add `test_matches_count_in_radius_for_radius_two` asserting `SpiralCells.filled_area(Vector2i(5, 5), 2).size() == SpiralCells.count_in_radius(2)`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_spiral_cells_filled_area.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-spiralcells-filled-area]
- [ ] [T3] tests/test_spiral_cells_filled_area.gd — Add `test_negative_radius_is_empty` asserting `SpiralCells.filled_area(Vector2i(5, 5), -1).is_empty()`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_spiral_cells_filled_area.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-spiralcells-filled-area]
- [ ] [T3] tests/test_spiral_cells_filled_area.gd — Add `test_contains_center` asserting `SpiralCells.filled_area(Vector2i(5, 5), 2).has(Vector2i(5, 5))`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_spiral_cells_filled_area.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-spiralcells-filled-area]
- [ ] [T4] scripts/grid/spiral_cells.gd — Add a doc comment above `filled_area` explaining it aggregates `ring_at` across every radius from 0 through `radius`, the filled-disc counterpart to `count_in_radius`'s cell count. VERIFY: `grep -q "filled-disc\|filled disc" scripts/grid/spiral_cells.gd`. (cat:docs; multifile:no) [feat:xlite-20260922-spiralcells-filled-area]
- [ ] [T5] tests — Run the full GUT suite once to confirm `filled_area` caused zero regressions elsewhere. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-spiralcells-filled-area]

# --- Claude-decomposed from roadmap [2026-09-22 deep pass]: Catapult is-out-of-range — scripts/battle/catapult.gd ---
- [ ] [T1] scripts/battle/catapult.gd — Add `static func is_out_of_range(from: Vector2i, to: Vector2i, max_range: int) -> bool`: `chebyshev_distance(from, to) > max_range`, reusing `chebyshev_distance` exactly like `is_too_close` already does. VERIFY: `grep -q "static func is_out_of_range" scripts/battle/catapult.gd`. (cat:godot; multifile:no) [feat:xlite-20260922-catapult-out-of-range]
- [ ] [T2] tests/test_catapult_out_of_range.gd — Create new GUT test file (`extends GutTest`) with `test_beyond_max_range` asserting `Catapult.is_out_of_range(Vector2i(0, 0), Vector2i(10, 0), 5)`. VERIFY: `grep -q "extends GutTest" tests/test_catapult_out_of_range.gd`. (cat:test; multifile:no) [feat:xlite-20260922-catapult-out-of-range]
- [ ] [T2] tests/test_catapult_out_of_range.gd — Add `test_within_max_range` asserting `not Catapult.is_out_of_range(Vector2i(0, 0), Vector2i(3, 0), 5)`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_catapult_out_of_range.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-catapult-out-of-range]
- [ ] [T2] tests/test_catapult_out_of_range.gd — Add `test_exactly_at_max_range_is_not_out_of_range` asserting `not Catapult.is_out_of_range(Vector2i(0, 0), Vector2i(5, 0), 5)`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_catapult_out_of_range.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-catapult-out-of-range]
- [ ] [T3] tests/test_catapult_out_of_range.gd — Add `test_diagonal_uses_chebyshev` asserting `not Catapult.is_out_of_range(Vector2i(0, 0), Vector2i(4, 4), 4)`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_catapult_out_of_range.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-catapult-out-of-range]
- [ ] [T3] tests/test_catapult_out_of_range.gd — Add `test_never_both_too_close_and_out_of_range` asserting `not (Catapult.is_too_close(Vector2i(0, 0), Vector2i(3, 0), 2) and Catapult.is_out_of_range(Vector2i(0, 0), Vector2i(3, 0), 5))`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_catapult_out_of_range.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-catapult-out-of-range]
- [ ] [T4] scripts/battle/catapult.gd — Add a doc comment above `is_out_of_range` explaining it is the "too far" complement to `is_too_close`, for a lob-target cursor's failure-reason feedback. VERIFY: `grep -q "complement" scripts/battle/catapult.gd`. (cat:docs; multifile:no) [feat:xlite-20260922-catapult-out-of-range]
- [ ] [T5] tests — Run the full GUT suite once to confirm `is_out_of_range` caused zero regressions elsewhere. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-catapult-out-of-range]

# --- Claude-decomposed from roadmap [2026-09-22 deep pass]: Dead-code delete FlankBonus.get_bonus() — scripts/battle/flank_bonus.gd ---
- [ ] [T1] scripts/battle/flank_bonus.gd — Re-confirm via `grep -rn "FlankBonus.get_bonus" scripts tests` that `get_bonus()` has zero callers anywhere (including its own test file) before touching anything. VERIFY: `! grep -rq "FlankBonus\.get_bonus" scripts tests`. (cat:test; multifile:no) [feat:xlite-20260922-flankbonus-dedupe-get-bonus]
- [ ] [T1] scripts/battle/flank_bonus.gd — Delete the `static func get_bonus() -> float: return 1.0` block entirely; leave `get_flank_bonus`, `get_multiplier`, `bonus_percent`, and `total_damage` untouched. VERIFY: `! grep -q "static func get_bonus" scripts/battle/flank_bonus.gd`. (cat:godot; multifile:no) [feat:xlite-20260922-flankbonus-dedupe-get-bonus]
- [ ] [T2] scripts/battle/flank_bonus.gd — Confirm the file still declares exactly 4 remaining static functions after the deletion. VERIFY: `test $(grep -c "^static func" scripts/battle/flank_bonus.gd) -eq 4`. (cat:test; multifile:no) [feat:xlite-20260922-flankbonus-dedupe-get-bonus]
- [ ] [T2] tests/test_flank_bonus.gd — Confirm no test in this file references the deleted function. VERIFY: `! grep -q "FlankBonus\.get_bonus" tests/test_flank_bonus.gd`. (cat:test; multifile:no) [feat:xlite-20260922-flankbonus-dedupe-get-bonus]
- [ ] [T3] tests/test_flank_bonus.gd — Run just this file's existing tests to confirm the remaining 4 functions (`get_flank_bonus`, `get_multiplier`, `bonus_percent`, `total_damage`) still pass unmodified. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_flank_bonus.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-flankbonus-dedupe-get-bonus]
- [ ] [T5] tests — Run the full GUT suite once to confirm the deletion caused zero regressions elsewhere. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-flankbonus-dedupe-get-bonus]

# --- Claude-decomposed from roadmap [2026-09-22 deep pass]: Dead-code delete Destructible.is_destructible_obstacle() — scripts/battle/destructible.gd ---
- [ ] [T1] scripts/battle/destructible.gd — Re-confirm via `grep -rn "is_destructible_obstacle" scripts tests` that the function has zero callers anywhere (including tests/test_destructible_type.gd) before touching anything. VERIFY: `! grep -rq "is_destructible_obstacle" scripts tests`. (cat:test; multifile:no) [feat:xlite-20260922-destructible-dedupe-obstacle-string]
- [ ] [T1] scripts/battle/destructible.gd — Delete the `static func is_destructible_obstacle(type: String) -> bool` block entirely; leave `is_destructible` and `degrade_to` untouched. VERIFY: `! grep -q "static func is_destructible_obstacle" scripts/battle/destructible.gd`. (cat:godot; multifile:no) [feat:xlite-20260922-destructible-dedupe-obstacle-string]
- [ ] [T2] scripts/battle/destructible.gd — Confirm the file still declares exactly 2 remaining static functions after the deletion. VERIFY: `test $(grep -c "^static func" scripts/battle/destructible.gd) -eq 2`. (cat:test; multifile:no) [feat:xlite-20260922-destructible-dedupe-obstacle-string]
- [ ] [T3] tests/test_destructible_type.gd — Run just this file's existing tests to confirm `is_destructible`/`degrade_to` coverage still passes unmodified. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_destructible_type.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-destructible-dedupe-obstacle-string]
- [ ] [T5] tests — Run the full GUT suite once to confirm the deletion caused zero regressions elsewhere. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-destructible-dedupe-obstacle-string]

# --- Claude-decomposed from roadmap [2026-09-22 deep pass]: Dedupe retire scripts/units/xp_curve.gd (full duplicate of XpCalc) ---
- [ ] [T1] scripts/units/xp_curve.gd — Re-confirm via `grep -rn "XpCurve\." scripts tests` that every reference is confined to xp_curve.gd's own test files (tests/test_xp_curve.gd, tests/test_xp_curve_level_for_xp.gd) before deleting anything. VERIFY: `! grep -rl "XpCurve\." scripts tests | grep -v -e test_xp_curve.gd -e test_xp_curve_level_for_xp.gd -e xp_curve.gd`. (cat:test; multifile:yes) [feat:xlite-20260922-xpcurve-dedupe-retire]
- [ ] [T1] scripts/units/xp_curve.gd — Confirm `scripts/battle/xp_calc.gd`'s `XpCalc.xp_for_level`/`XpCalc.level_for_xp` produce identical output to `XpCurve.xp_for_level`/`XpCurve.level_for_xp` for levels 1 through 20 (a scratch GUT test asserting the two classes agree), to prove XpCalc is a safe drop-in replacement before deleting XpCurve. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_xp_calc.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-xpcurve-dedupe-retire]
- [ ] [T2] scripts/units/xp_curve.gd — Delete the file entirely. VERIFY: `! test -f scripts/units/xp_curve.gd`. (cat:godot; multifile:yes) [feat:xlite-20260922-xpcurve-dedupe-retire]
- [ ] [T2] tests/test_xp_curve.gd — Delete this test file. VERIFY: `! test -f tests/test_xp_curve.gd`. (cat:test; multifile:yes) [feat:xlite-20260922-xpcurve-dedupe-retire]
- [ ] [T2] tests/test_xp_curve_level_for_xp.gd — Delete this test file. VERIFY: `! test -f tests/test_xp_curve_level_for_xp.gd`. (cat:test; multifile:yes) [feat:xlite-20260922-xpcurve-dedupe-retire]
- [ ] [T3] scripts/battle/xp_calc.gd — Add a doc comment above the `XpCalc` class_name line noting it is the single canonical xp-curve implementation (scripts/units/xp_curve.gd, a full duplicate, was retired 2026-09-22). VERIFY: `grep -q "canonical" scripts/battle/xp_calc.gd`. (cat:docs; multifile:no) [feat:xlite-20260922-xpcurve-dedupe-retire]
- [ ] [T4] tests — Confirm no `.uid` orphans remain for the deleted files. VERIFY: `! test -f tests/test_xp_curve.gd.uid && ! test -f tests/test_xp_curve_level_for_xp.gd.uid`. (cat:test; multifile:no) [feat:xlite-20260922-xpcurve-dedupe-retire]
- [ ] [T5] tests — Run the full GUT suite once to confirm the retirement caused zero regressions elsewhere. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-xpcurve-dedupe-retire]
