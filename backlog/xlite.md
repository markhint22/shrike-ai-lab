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

# --- Claude-decomposed from roadmap [2026-09-22 deep pass]: CoverDegradation durability-percent — scripts/battle/cover_degradation.gd ---

# --- Claude-decomposed from roadmap [2026-09-22 deep pass]: SpiralCells filled-area — scripts/grid/spiral_cells.gd ---

# --- Claude-decomposed from roadmap [2026-09-22 deep pass]: Catapult is-out-of-range — scripts/battle/catapult.gd ---

# --- Claude-decomposed from roadmap [2026-09-22 deep pass]: Dead-code delete FlankBonus.get_bonus() — scripts/battle/flank_bonus.gd ---

# --- Claude-decomposed from roadmap [2026-09-22 deep pass]: Dead-code delete Destructible.is_destructible_obstacle() — scripts/battle/destructible.gd ---

# --- Claude-decomposed from roadmap [2026-09-22 deep pass]: Dedupe retire scripts/units/xp_curve.gd (full duplicate of XpCalc) ---
- [ ] [T5] tests — Run the full GUT suite once to confirm the retirement caused zero regressions elsewhere. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-xpcurve-dedupe-retire]

# --- 27B-decomposed from roadmap [2026-09-28]: Enemy faction enum + themed archetype re-skin (MACHINE/MUTANT) — the design direction from (review + tweak) [feat:xlite-20260928-enemy-faction-enum-themed-archetype-re-s] ---
- [ ] [T1] scripts/units/unit_faction.gd — Create file with `class_name UnitFaction` and `enum Faction { MACHINE = 0, MUTANT = 1 }`. VERIFY: `grep -q "class_name UnitFaction" scripts/units/unit_faction.gd && grep -q "MACHINE = 0" scripts/units/unit_faction.gd`. (cat:godot; multifile:no) [feat:xlite-20260928-enemy-faction-enum-themed-archetype-re-s]
- [ ] [T2] scripts/units/unit_faction.gd — Add `static func faction_for_enemy_type(enemy_type: int) -> int` mapping specific EnemyType values to MACHINE/MUTANT based on theme doc split. VERIFY: `grep -q "static func faction_for_enemy_type" scripts/units/unit_faction.gd`. (cat:godot; multifile:no) [feat:xlite-20260928-enemy-faction-enum-themed-archetype-re-s]
- [ ] [T2] scripts/units/unit_faction.gd — Add `static func display_name_for_enemy_type(enemy_type: int) -> String` returning themed names for the 10 archetypes. VERIFY: `grep -q "static func display_name_for_enemy_type" scripts/units/unit_faction.gd`. (cat:godot; multifile:no) [feat:xlite-20260928-enemy-faction-enum-themed-archetype-re-s]
- [ ] [T1] tests/test_unit_faction.gd — Create GUT test file extending GutTest with `func test_faction_coverage()`. VERIFY: `test -f tests/test_unit_faction.gd && grep -q "extends GutTest" tests/test_unit_faction.gd`. (cat:test; multifile:no) [feat:xlite-20260928-enemy-faction-enum-themed-archetype-re-s]
- [ ] [T2] tests/test_unit_faction.gd — Implement assertion that iterates all 10 `Unit.EnemyType` values and asserts `UnitFaction.faction_for_enemy_type(v)` returns valid Faction enum value. VERIFY: `grep -q "for v in Unit.EnemyType.values()" tests/test_unit_faction.gd`. (cat:test; multifile:no) [feat:xlite-20260928-enemy-faction-enum-themed-archetype-re-s]
- [ ] [T2] tests/test_unit_faction.gd — Implement assertion that MACHINE and MUTANT factions partition the set with no overlaps (count checks). VERIFY: `grep -q "assert_eq" tests/test_unit_faction.gd && grep -q "MACHINE" tests/test_unit_faction.gd`. (cat:test; multifile:no) [feat:xlite-20260928-enemy-faction-enum-themed-archetype-re-s]
- [ ] [T3] tests/test_unit_faction.gd — Add test verifying display names are non-empty and distinct for all 10 types. VERIFY: `grep -q "display_name_for_enemy_type" tests/test_unit_faction.gd`. (cat:test; multifile:no) [feat:xlite-20260928-enemy-faction-enum-themed-archetype-re-s]

# --- 27B-decomposed from roadmap [2026-09-28]: Equipment/Loadout stat-modifier system (new economy sink + progression axis) — add new scr (review + tweak) [feat:xlite-20260928-equipment-loadout-stat-modifier-system-n] ---
- [ ] [T1] scripts/roster/equipment.gd — Create file with class_name Equipment and static func is_valid_slot(slot_name: String) -> bool that returns true only for "WEAPON_MOD", "ARMOR", or "UTILITY". VERIFY: godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_equipment.gd -gexit. (cat:godot; multifile:no) [feat:xlite-20260928-equipment-loadout-stat-modifier-system-n]
- [ ] [T1] scripts/roster/equipment.gd — Add static func cost_for_tier(tier: int) -> int that returns tier * 100 for tiers 1-4 and 0 otherwise. VERIFY: godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_equipment.gd -gexit. (cat:godot; multifile:no) [feat:xlite-20260928-equipment-loadout-stat-modifier-system-n]
- [ ] [T1] scripts/roster/equipment.gd — Add static func stat_bonus_for_tier(tier: int, per_tier: int) -> int that returns tier * per_tier for valid tiers and 0 otherwise. VERIFY: godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_equipment.gd -gexit. (cat:godot; multifile:no) [feat:xlite-20260928-equipment-loadout-stat-modifier-system-n]
- [ ] [T2] tests/test_equipment.gd — Create test file with class_name TestEquipment extending GutTest, including test_is_valid_slot_accepts_valid_slots and test_is_valid_slot_rejects_invalid_slots. VERIFY: godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_equipment.gd -gexit. (cat:test; multifile:no) [feat:xlite-20260928-equipment-loadout-stat-modifier-system-n]
- [ ] [T2] tests/test_equipment.gd — Add test_cost_for_tier_returns_correct_values verifying tier 1=100, tier 2=200, tier 3=300, tier 4=400, and invalid tiers return 0. VERIFY: godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_equipment.gd -gexit. (cat:test; multifile:no) [feat:xlite-20260928-equipment-loadout-stat-modifier-system-n]
- [ ] [T2] tests/test_equipment.gd — Add test_stat_bonus_for_tier_returns_correct_values verifying additive calculation (e.g., tier 3, per_tier 10 = 30) and invalid inputs return 0. VERIFY: godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_equipment.gd -gexit. (cat:test; multifile:no) [feat:xlite-20260928-equipment-loadout-stat-modifier-system-n]
- [ ] [T2] tests/test_equipment.gd — Add test_is_valid_slot_fail_closed_behavior ensuring unknown slots like "HELMET" or empty strings return false. VERIFY: godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_equipment.gd -gexit. (cat:test; multifile:no) [feat:xlite-20260928-equipment-loadout-stat-modifier-system-n]

# --- 27B-decomposed from roadmap [2026-09-29]: Mission Directives: per-mission modifier rolls (cheap combinatorial variety, no new author (review + tweak) [feat:xlite-20260929-mission-directives-per-mission-modifier-] ---
- [ ] [T1] scripts/mission/mission_directive.gd — Create file with `class_name MissionDirective` and static func `is_valid_directive(directive: int) -> bool` returning true for 0-4, false otherwise. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=tests -gtest=test_mission_directive.gd -gexit` passes test `test_is_valid_directive`. (cat:godot; multifile:no) [feat:xlite-20260929-mission-directives-per-mission-modifier-]
- [ ] [T1] scripts/mission/mission_directive.gd — Add static func `aim_modifier_percent(directive: int) -> int` returning -10 for directive 1 (NIGHT_OPS) and 0 for all valid directives. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=tests -gtest=test_mission_directive.gd -gexit` passes test `test_aim_modifier_percent`. (cat:godot; multifile:no) [feat:xlite-20260929-mission-directives-per-mission-modifier-]
- [ ] [T1] scripts/mission/mission_directive.gd — Add static func `bonus_enemy_count(directive: int) -> int` returning 1 for directive 2 (REINFORCEMENTS) and 0 for all valid directives. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=tests -gtest=test_mission_directive.gd -gexit` passes test `test_bonus_enemy_count`. (cat:godot; multifile:no) [feat:xlite-20260929-mission-directives-per-mission-modifier-]
- [ ] [T2] tests/test_mission_directive.gd — Create GUT test suite extending GutTest with test cases for `is_valid_directive`, `aim_modifier_percent`, and `bonus_enemy_count` covering valid/invalid inputs and specific directive values. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=tests -gtest=test_mission_directive.gd -gexit` exits with code 0 and reports 0 failures. (cat:test; multifile:no) [feat:xlite-20260929-mission-directives-per-mission-modifier-]
- [ ] [T2] scripts/mission/mission_directive.gd — Ensure `aim_modifier_percent` and `bonus_enemy_count` return 0 for any invalid directive input to prevent undefined behavior. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=tests -gtest=test_mission_directive.gd -gexit` passes test `test_invalid_directive_returns_zero`. (cat:godot; multifile:no) [feat:xlite-20260929-mission-directives-per-mission-modifier-]
- [ ] [T2] tests/test_mission_directive.gd — Add specific assertions verifying NIGHT_OPS (1) yields -10 aim mod and REINFORCEMENTS (2) yields +1 enemy count. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=tests -gtest=test_mission_directive.gd -gexit` passes test `test_specific_directive_values`. (cat:test; multifile:no) [feat:xlite-20260929-mission-directives-per-mission-modifier-]

# --- 27B-decomposed from roadmap [2026-09-29]: MissionSummary: post-mission totals aggregator (composes 3 already-verified, currently-unw (review + tweak) [feat:xlite-20260929-missionsummary-post-mission-totals-aggre] ---
- [ ] [T1] scripts/mission/mission_summary.gd — Create new file with `class_name MissionSummary` and empty static method `build` returning an empty Dictionary. VERIFY: `grep -q "class_name MissionSummary" scripts/mission/mission_summary.gd && grep -q "static func build" scripts/mission/mission_summary.gd`. (cat:godot; multifile:no) [feat:xlite-20260929-missionsummary-post-mission-totals-aggre]
- [ ] [T1] tests/test_mission_summary.gd — Create new test file with `extends GutTest` and a placeholder test case that asserts true. VERIFY: `grep -q "extends GutTest" tests/test_mission_summary.gd && grep -q "func test_placeholder" tests/test_mission_summary.gd`. (cat:test; multifile:no) [feat:xlite-20260929-missionsummary-post-mission-totals-aggre]
- [ ] [T2] scripts/mission/mission_summary.gd — Implement `build` to call `RewardCalc.mission_payout` and assign result to `"credits"` key in returned Dictionary. VERIFY: `grep -q "RewardCalc.mission_payout" scripts/mission/mission_summary.gd && grep -q '"credits"' scripts/mission/mission_summary.gd`. (cat:godot; multifile:no) [feat:xlite-20260929-missionsummary-post-mission-totals-aggre]
- [ ] [T2] tests/test_mission_summary.gd — Add test `test_build_returns_credits` that calls `MissionSummary.build` with mock inputs and asserts `"credits"` key exists and matches expected `RewardCalc` output. VERIFY: `grep -q "func test_build_returns_credits" tests/test_mission_summary.gd && grep -q "assert_eq" tests/test_mission_summary.gd`. (cat:test; multifile:no) [feat:xlite-20260929-missionsummary-post-mission-totals-aggre]
- [ ] [T2] scripts/mission/mission_summary.gd — Extend `build` to call `StarRating.stars` and assign result to `"stars"` key in returned Dictionary. VERIFY: `grep -q "StarRating.stars" scripts/mission/mission_summary.gd && grep -q '"stars"' scripts/mission/mission_summary.gd`. (cat:godot; multifile:no) [feat:xlite-20260929-missionsummary-post-mission-totals-aggre]
- [ ] [T2] tests/test_mission_summary.gd — Add test `test_build_returns_stars` that verifies `"stars"` key matches expected `StarRating` output for given inputs. VERIFY: `grep -q "func test_build_returns_stars" tests/test_mission_summary.gd && grep -q '"stars"' tests/test_mission_summary.gd`. (cat:test; multifile:no) [feat:xlite-20260929-missionsummary-post-mission-totals-aggre]
- [ ] [T2] scripts/mission/mission_summary.gd — Extend `build` to call `Extraction.percent_extracted` and assign result to `"extraction_percent"` key in returned Dictionary. VERIFY: `grep -q "Extraction.percent_extracted" scripts/mission/mission_summary.gd && grep -q '"extraction_percent"' scripts/mission/mission_summary.gd`. (cat:godot; multifile:no) [feat:xlite-20260929-missionsummary-post-mission-totals-aggre]
- [ ] [T2] tests/test_mission_summary.gd — Add test `test_build_returns_extraction` that verifies `"extraction_percent"` key matches expected `Extraction` output. VERIFY: `grep -q "func test_build_returns_extraction" tests/test_mission_summary.gd && grep -q '"extraction_percent"' tests/test_mission_summary.gd`. (cat:test; multifile:no) [feat:xlite-20260929-missionsummary-post-mission-totals-aggre]
- [ ] [T2] tests/test_mission_summary.gd — Add integration test `test_build_full_structure` that verifies the returned Dictionary contains exactly the three keys `"credits"`, `"stars"`, and `"extraction_percent"` with correct types. VERIFY: `grep -q "func test_build_full_structure" tests/test_mission_summary.gd && grep -q "assert_eq(result.size(), 3)" tests/test_mission_summary.gd`. (cat:test; multifile:no) [feat:xlite-20260929-missionsummary-post-mission-totals-aggre]
