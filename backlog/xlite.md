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

# --- 27B-decomposed from roadmap [2026-09-28]: Enemy faction enum + themed archetype re-skin (MACHINE/MUTANT) — the design direction from (review + tweak) [feat:xlite-20260928-enemy-faction-enum-themed-archetype-re-s] ---

# --- 27B-decomposed from roadmap [2026-09-28]: Equipment/Loadout stat-modifier system (new economy sink + progression axis) — add new scr (review + tweak) [feat:xlite-20260928-equipment-loadout-stat-modifier-system-n] ---

# --- 27B-decomposed from roadmap [2026-09-29]: Mission Directives: per-mission modifier rolls (cheap combinatorial variety, no new author (review + tweak) [feat:xlite-20260929-mission-directives-per-mission-modifier-] ---

# --- 27B-decomposed from roadmap [2026-09-29]: MissionSummary: post-mission totals aggregator (composes 3 already-verified, currently-unw (review + tweak) [feat:xlite-20260929-missionsummary-post-mission-totals-aggre] ---
- [ ] [T2] tests/test_mission_summary.gd — Add integration test `test_build_full_structure` that verifies the returned Dictionary contains exactly the three keys `"credits"`, `"stars"`, and `"extraction_percent"` with correct types. VERIFY: `grep -q "func test_build_full_structure" tests/test_mission_summary.gd && grep -q "assert_eq(result.size(), 3)" tests/test_mission_summary.gd`. (cat:test; multifile:no) [feat:xlite-20260929-missionsummary-post-mission-totals-aggre]

# --- 27B-decomposed from roadmap [2026-09-29]: Veteran Scars: permanent post-injury stat trade-off (fills the gap between "heals fully" a (review + tweak) [feat:xlite-20260929-veteran-scars-permanent-post-injury-stat] ---
- [ ] [T1] scripts/roster/scar.gd — Create file with `class_name Scar` and empty static function stubs for `should_scar` and `stat_penalty_percent`. VERIFY: `grep -q "class_name Scar" scripts/roster/scar.gd && grep -q "static func should_scar" scripts/roster/scar.gd && grep -q "static func stat_penalty_percent" scripts/roster/scar.gd`. (cat:godot; multifile:no) [feat:xlite-20260929-veteran-scars-permanent-post-injury-stat]
- [ ] [T2] scripts/roster/scar.gd — Implement `static func should_scar(wound_severity: int, severe_threshold: int) -> bool` to return true only if `wound_severity > severe_threshold`. VERIFY: `grep -q "return wound_severity > severe_threshold" scripts/roster/scar.gd`. (cat:godot; multifile:no) [feat:xlite-20260929-veteran-scars-permanent-post-injury-stat]
- [ ] [T3] scripts/roster/scar.gd — Implement `static func stat_penalty_percent(wound_severity: int, per_severity: int, cap: int) -> int` to calculate `wound_severity * per_severity` and clamp it between 0 and `cap`. VERIFY: `grep -q "clamp" scripts/roster/scar.gd && grep -q "wound_severity \* per_severity" scripts/roster/scar.gd`. (cat:godot; multifile:no) [feat:xlite-20260929-veteran-scars-permanent-post-injury-stat]
- [ ] [T1] tests/test_scar.gd — Create test file inheriting from `GutTest` with a `before_each` setup and empty test methods for scar logic. VERIFY: `grep -q "extends GutTest" tests/test_scar.gd && grep -q "func before_each" tests/test_scar.gd`. (cat:test; multifile:no) [feat:xlite-20260929-veteran-scars-permanent-post-injury-stat]
- [ ] [T2] tests/test_scar.gd — Add test `test_should_scar_threshold` verifying `Scar.should_scar(5, 5)` is false and `Scar.should_scar(6, 5)` is true. VERIFY: `grep -q "assert_false(Scar.should_scar(5, 5))" tests/test_scar.gd && grep -q "assert_true(Scar.should_scar(6, 5))" tests/test_scar.gd`. (cat:test; multifile:no) [feat:xlite-20260929-veteran-scars-permanent-post-injury-stat]
- [ ] [T2] tests/test_scar.gd — Add test `test_stat_penalty_percent_clamp` verifying `Scar.stat_penalty_percent(10, 2, 15)` returns 15 (capped) and `Scar.stat_penalty_percent(1, 2, 15)` returns 2. VERIFY: `grep -q "assert_eq(15, Scar.stat_penalty_percent(10, 2, 15))" tests/test_scar.gd && grep -q "assert_eq(2, Scar.stat_penalty_percent(1, 2, 15))" tests/test_scar.gd`. (cat:test; multifile:no) [feat:xlite-20260929-veteran-scars-permanent-post-injury-stat]
- [ ] [T2] tests/test_scar.gd — Add test `test_stat_penalty_percent_zero` verifying `Scar.stat_penalty_percent(0, 5, 10)` returns 0. VERIFY: `grep -q "assert_eq(0, Scar.stat_penalty_percent(0, 5, 10))" tests/test_scar.gd`. (cat:test; multifile:no) [feat:xlite-20260929-veteran-scars-permanent-post-injury-stat]
- [ ] [T3] tests/test_scar.gd — Add test `test_stat_penalty_percent_negative_input` verifying `Scar.stat_penalty_percent(-1, 5, 10)` returns 0 (clamped lower bound). VERIFY: `grep -q "assert_eq(0, Scar.stat_penalty_percent(-1, 5, 10))" tests/test_scar.gd`. (cat:test; multifile:no) [feat:xlite-20260929-veteran-scars-permanent-post-injury-stat]

# --- 27B-decomposed from roadmap [2026-09-29]: Squad Loadout Presets: save/recall a named 4-unit squad composition — add new scripts/rost (review + tweak) [feat:xlite-20260929-squad-loadout-presets-save-recall-a-name] ---
- [ ] [T1] scripts/roster/loadout_preset.gd — Create file with `class_name LoadoutPreset` and empty `static func is_valid_preset(unit_ids: Array) -> bool: return true` VERIFY: `grep -q "class_name LoadoutPreset" scripts/roster/loadout_preset.gd && grep -q "static func is_valid_preset" scripts/roster/loadout_preset.gd`. (cat:godot; multifile:no) [feat:xlite-20260929-squad-loadout-presets-save-recall-a-name]
- [ ] [T2] tests/test_loadout_preset.gd — Create GUT test file `extends GutTest` with `func test_empty_array_is_valid(): assert_true(LoadoutPreset.is_valid_preset([]))` VERIFY: `grep -q "extends GutTest" tests/test_loadout_preset.gd && grep -q "test_empty_array_is_valid" tests/test_loadout_preset.gd`. (cat:test; multifile:no) [feat:xlite-20260929-squad-loadout-presets-save-recall-a-name]
- [ ] [T1] scripts/roster/loadout_preset.gd — Implement size check in `is_valid_preset` to return `false` if `unit_ids.size() > 4` VERIFY: `grep -q "size() > 4" scripts/roster/loadout_preset.gd`. (cat:godot; multifile:no) [feat:xlite-20260929-squad-loadout-presets-save-recall-a-name]
- [ ] [T2] tests/test_loadout_preset.gd — Add test `func test_five_units_invalid(): assert_false(LoadoutPreset.is_valid_preset([1, 2, 3, 4, 5]))` VERIFY: `grep -q "test_five_units_invalid" tests/test_loadout_preset.gd`. (cat:test; multifile:no) [feat:xlite-20260929-squad-loadout-presets-save-recall-a-name]
- [ ] [T1] scripts/roster/loadout_preset.gd — Implement duplicate check in `is_valid_preset` using a local dictionary to detect repeated IDs and return `false` on collision VERIFY: `grep -q "duplicate" scripts/roster/loadout_preset.gd || grep -q "has(" scripts/roster/loadout_preset.gd`. (cat:godot; multifile:no) [feat:xlite-20260929-squad-loadout-presets-save-recall-a-name]
- [ ] [T2] tests/test_loadout_preset.gd — Add test `func test_duplicate_units_invalid(): assert_false(LoadoutPreset.is_valid_preset([1, 1, 2, 3]))` VERIFY: `grep -q "test_duplicate_units_invalid" tests/test_loadout_preset.gd`. (cat:test; multifile:no) [feat:xlite-20260929-squad-loadout-presets-save-recall-a-name]
- [ ] [T2] tests/test_loadout_preset.gd — Add test `func test_valid_four_unique_units(): assert_true(LoadoutPreset.is_valid_preset([1, 2, 3, 4]))` VERIFY: `grep -q "test_valid_four_unique_units" tests/test_loadout_preset.gd`. (cat:test; multifile:no) [feat:xlite-20260929-squad-loadout-presets-save-recall-a-name]
- [ ] [T2] tests/test_loadout_preset.gd — Add test `func test_valid_three_unique_units(): assert_true(LoadoutPreset.is_valid_preset([1, 2, 3]))` VERIFY: `grep -q "test_valid_three_unique_units" tests/test_loadout_preset.gd`. (cat:test; multifile:no) [feat:xlite-20260929-squad-loadout-presets-save-recall-a-name]

# --- 27B-decomposed from roadmap [2026-09-29]: Codex: faction lore category — add `static func faction_key(faction_name: String) -> Strin (review + tweak) [feat:xlite-20260929-codex-faction-lore-category-add-static-f] ---
- [ ] [T1] scripts/codex/codex_data.gd — Add `static func faction_key(faction_name: String) -> String` that returns `faction_name.to_lower().replace(" ", "_")`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=tests/test_codex_data_faction.gd -gexit` passes. (cat:godot; multifile:no) [feat:xlite-20260929-codex-faction-lore-category-add-static-f]
- [ ] [T1] tests/test_codex_data_faction.gd — Create new test file extending `GutTest` with `test_faction_key_transforms_name` asserting `CodexData.faction_key("Iron Legion") == "iron_legion"` and `CodexData.faction_key("  Void Cult ") == "void_cult"`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=tests/test_codex_data_faction.gd -gexit` passes. (cat:test; multifile:no) [feat:xlite-20260929-codex-faction-lore-category-add-static-f]
- [ ] [T2] scripts/codex/codex_manager.gd — Add constant `const CAT_FACTION: String = "faction"` and function `func mark_faction_seen(faction_name: String) -> bool` that calls `return mark_seen(CAT_FACTION, CodexData.faction_key(faction_name))`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=tests/test_codex_manager.gd -gexit` passes. (cat:godot; multifile:no) [feat:xlite-20260929-codex-faction-lore-category-add-static-f]
- [ ] [T2] tests/test_codex_manager.gd — Add test case `test_mark_faction_seen_updates_state` that mocks `CodexData.faction_key`, calls `mark_faction_seen("Test Faction")`, and asserts the return value is `true` and `is_seen(CAT_FACTION, "test_faction")` is true. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=tests/test_codex_manager.gd -gexit` passes. (cat:test; multifile:no) [feat:xlite-20260929-codex-faction-lore-category-add-static-f]

# --- 27B-decomposed from roadmap [2026-09-29]: Achievements: faction-completionist milestones ("defeated every MACHINE archetype at least (review + tweak) [feat:xlite-20260929-achievements-faction-completionist-miles] ---
- [ ] [T1] scripts/battle/achievement_registry.gd — Add "machine_completionist" key to MAP with value "ACH_MACHINE_COMPLETIONIST". VERIFY: grep -q '"machine_completionist": "ACH_MACHINE_COMPLETIONIST"' scripts/battle/achievement_registry.gd. (cat:godot; multifile:no) [feat:xlite-20260929-achievements-faction-completionist-miles]
- [ ] [T1] scripts/battle/achievement_registry.gd — Add "mutant_completionist" key to MAP with value "ACH_MUTANT_COMPLETIONIST". VERIFY: grep -q '"mutant_completionist": "ACH_MUTANT_COMPLETIONIST"' scripts/battle/achievement_registry.gd. (cat:godot; multifile:no) [feat:xlite-20260929-achievements-faction-completionist-miles]
- [ ] [T2] tests/test_achievement_registry.gd — Add test case asserting steam_id_for("machine_completionist") returns "ACH_MACHINE_COMPLETIONIST". VERIFY: godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gtest=test_achievement_registry.gd -gexit. (cat:test; multifile:no) [feat:xlite-20260929-achievements-faction-completionist-miles]
- [ ] [T2] tests/test_achievement_registry.gd — Add test case asserting steam_id_for("mutant_completionist") returns "ACH_MUTANT_COMPLETIONIST". VERIFY: godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gtest=test_achievement_registry.gd -gexit. (cat:test; multifile:no) [feat:xlite-20260929-achievements-faction-completionist-miles]
- [ ] [T2] tests/test_achievement_registry.gd — Add test case asserting validate() returns true after adding new entries. VERIFY: godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gtest=test_achievement_registry.gd -gexit. (cat:test; multifile:no) [feat:xlite-20260929-achievements-faction-completionist-miles]
