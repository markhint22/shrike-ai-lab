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

# --- 27B-decomposed from roadmap [2026-09-29]: Veteran Scars: permanent post-injury stat trade-off (fills the gap between "heals fully" a (review + tweak) [feat:xlite-20260929-veteran-scars-permanent-post-injury-stat] ---

# --- 27B-decomposed from roadmap [2026-09-29]: Squad Loadout Presets: save/recall a named 4-unit squad composition — add new scripts/rost (review + tweak) [feat:xlite-20260929-squad-loadout-presets-save-recall-a-name] ---

# --- 27B-decomposed from roadmap [2026-09-29]: Codex: faction lore category — add `static func faction_key(faction_name: String) -> Strin (review + tweak) [feat:xlite-20260929-codex-faction-lore-category-add-static-f] ---

# --- 27B-decomposed from roadmap [2026-09-29]: Achievements: faction-completionist milestones ("defeated every MACHINE archetype at least (review + tweak) [feat:xlite-20260929-achievements-faction-completionist-miles] ---

# --- 27B-decomposed from roadmap [2026-09-30]: LIVE BUG: fallen soldiers are never dropped from the roster and casualties are never detec (review + tweak) [feat:xlite-20260930-live-bug-fallen-soldiers-are-never-dropp] ---

# --- 27B-decomposed from roadmap [2026-09-30]: LIVE BUG: mid-battle autosave/resume corrupts enemy patrol routes — scripts/battle/battle. (review + tweak) [feat:xlite-20260930-live-bug-mid-battle-autosave-resume-corr] ---

# --- 27B-decomposed from roadmap [2026-09-30]: LIVE BUG: the mid-battle autosave is one global slot, not per save slot — battle.gd:2834 ` (review + tweak) [feat:xlite-20260930-live-bug-the-mid-battle-autosave-is-one-] ---

# --- 27B-decomposed from roadmap [2026-09-30]: Make SaveManager writes atomic with a one-deep backup — scripts/save/save_manager.gd:66-72 (review + tweak) [feat:xlite-20260930-make-savemanager-writes-atomic-with-a-on] ---
- [ ] [T1] scripts/save/save_manager.gd — Add static function `_is_valid_save_name(name: String) -> bool` that returns false if name is empty, contains `/`, `\`, or `..`. VERIFY: Run `godot --headless -s res://tests/test_save_manager_validation.gd` which asserts `_is_valid_save_name("bad/name") == false`, `_is_valid_save_name("..") == false`, and `_is_valid_save_name("good") == true`. (cat:test; multifile:no) [feat:xlite-20260930-make-savemanager-writes-atomic-with-a-on]
- [ ] [T2] scripts/save/save_manager.gd — Modify `save_game` to call `_is_valid_save_name` at the start and return false if invalid, replacing the current blank-name check. VERIFY: Run `godot --headless -s res://tests/test_save_manager_validation.gd` which asserts `save_game("bad/name", data) == false`. (cat:test; multifile:no) [feat:xlite-20260930-make-savemanager-writes-atomic-with-a-on]
- [ ] [T3] scripts/save/save_manager.gd — Refactor `save_game` to write to `<name>.json.tmp`, close the file, copy existing `<name>.json` to `<name>.json.bak` if it exists, then rename `.tmp` to `.json`. VERIFY: Run `godot --headless -s res://tests/test_save_manager_atomicity.gd` which saves a game, verifies `<name>.json` exists, and verifies no `<name>.json.tmp` remains. (cat:refactor; multifile:no) [feat:xlite-20260930-make-savemanager-writes-atomic-with-a-on]
- [ ] [T4] scripts/save/save_manager.gd — Modify `load_save` to attempt loading `<name>.json`; if parsing fails or file is missing, attempt loading `<name>.json.bak`; return false only if both fail. VERIFY: Run `godot --headless -s res://tests/test_save_manager_recovery.gd` which creates a corrupted `.json` and valid `.bak`, then asserts `load_save` returns the backup data. (cat:refactor; multifile:no) [feat:xlite-20260930-make-savemanager-writes-atomic-with-a-on]
- [ ] [T5] scripts/save/save_manager.gd — Modify `list_saves` to filter files strictly by suffix `.json`, explicitly excluding `.json.bak` and `.json.tmp`. VERIFY: Run `godot --headless -s res://tests/test_save_manager_listing.gd` which creates `a.json`, `a.json.bak`, and `a.json.tmp`, then asserts `list_saves()` returns only `["a"]`. (cat:test; multifile:no) [feat:xlite-20260930-make-savemanager-writes-atomic-with-a-on]

# --- 27B-decomposed from roadmap [2026-09-30]: Stop silently reseeding over a corrupt roster/tech save — roster_manager.gd `_load_roster` (review + tweak) [feat:xlite-20260930-stop-silently-reseeding-over-a-corrupt-r] ---
- [ ] [T1] scripts/save/save_manager.gd — Add `file_exists_for(save_name: String) -> bool` method that checks `FileAccess.file_exists("user://saves/" + save_name + ".json")`. VERIFY: Run `godot --headless -s res://test/test_save_manager.gd` where the test asserts `SaveManager.new().file_exists_for("roster")` returns false initially. (cat:godot; multifile:no) [feat:xlite-20260930-stop-silently-reseeding-over-a-corrupt-r]
- [ ] [T1] scripts/save/save_manager.gd — Add `quarantine(save_name: String) -> String` method that copies `"user://saves/" + save_name + ".json"` to `"user://saves/" + save_name + ".corrupt-" + str(Time.get_unix_time_from_system()) + ".json"` and returns the new path. VERIFY: Run `godot --headless -s res://test/test_save_manager.gd` where the test writes a dummy file, calls quarantine, and asserts the new file exists with the `.corrupt-` prefix. (cat:godot; multifile:no) [feat:xlite-20260930-stop-silently-reseeding-over-a-corrupt-r]
- [ ] [T2] scripts/save/test_save_manager.gd — Create GUT test suite for `SaveManager` covering `file_exists_for` and `quarantine` logic including edge cases for missing files. VERIFY: Run `gut -gdir=res://test -gexit` and ensure all tests pass. (cat:test; multifile:no) [feat:xlite-20260930-stop-silently-reseeding-over-a-corrupt-r]
- [ ] [T3] scripts/roster/roster_manager.gd — Modify `_load_roster` to check `SaveManager.file_exists_for("roster")`; if true but load returns `{}`, call `SaveManager.quarantine("roster")` and `printerr("Roster save quarantined")` before returning empty. VERIFY: Run `godot --headless -s res://test/test_roster_recovery.gd` where garbage is written to roster.json, `load_slot("")` is called, and the test asserts a `.corrupt-*` file exists. (cat:godot; multifile:no) [feat:xlite-20260930-stop-silently-reseeding-over-a-corrupt-r]
- [ ] [T3] scripts/tech/tech_manager.gd — Modify `_load_techs` to check `SaveManager.file_exists_for("tech")`; if true but load returns `{}`, call `SaveManager.quarantine("tech")` and `printerr("Tech save quarantined")` before returning empty. VERIFY: Run `godot --headless -s res://test/test_tech_recovery.gd` where garbage is written to tech.json, `_load_techs` is triggered, and the test asserts a `.corrupt-*` file exists. (cat:godot; multifile:no) [feat:xlite-20260930-stop-silently-reseeding-over-a-corrupt-r]
- [ ] [T2] scripts/roster/test_roster_recovery.gd — Create GUT test that writes invalid JSON to `user://saves/roster.json`, triggers roster load, and verifies the original file is preserved as a `.corrupt-*` copy while the roster is reseeded. VERIFY: Run `gut -gdir=res://scripts/roster -gexit` and ensure the recovery test passes. (cat:test; multifile:no) [feat:xlite-20260930-stop-silently-reseeding-over-a-corrupt-r]
- [ ] [T2] scripts/tech/test_tech_recovery.gd — Create GUT test that writes invalid JSON to `user://saves/tech.json`, triggers tech load, and verifies the original file is preserved as a `.corrupt-*` copy while techs are reseeded. VERIFY: Run `gut -gdir=res://scripts/tech -gexit` and ensure the recovery test passes. (cat:test; multifile:no) [feat:xlite-20260930-stop-silently-reseeding-over-a-corrupt-r]

# --- 27B-decomposed from roadmap [2026-09-30]: TechManager never picks up balance changes or new techs for existing saves — `_save_techs` (review + tweak) [feat:xlite-20260930-techmanager-never-picks-up-balance-chang] ---
- [ ] [T1] scripts/battle/tech_manager.gd — Extract `_default_techs()` function returning `Array[Dictionary]` with current hardcoded tech definitions from `_seed_default_techs`. VERIFY: `grep -q "func _default_techs" scripts/battle/tech_manager.gd && grep -q "return \[" scripts/battle/tech_manager.gd`. (cat:godot; multifile:no) [feat:xlite-20260930-techmanager-never-picks-up-balance-chang]
- [ ] [T2] tests/test_tech_manager_defaults.gd — Create new test file verifying `_default_techs()` returns exactly 8 unique techs with required keys (`name`, `cost`, `description`, `branch`, `requires`). VERIFY: `godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gtest=test_tech_manager_defaults.gd`. (cat:test; multifile:no) [feat:xlite-20260930-techmanager-never-picks-up-balance-chang]
- [ ] [T3] scripts/battle/tech_manager.gd — Refactor `_seed_default_techs` to call `_default_techs()` and populate `_techs` from the returned array. VERIFY: `grep -q "_default_techs()" scripts/battle/tech_manager.gd && ! grep -q "var techs = \[" scripts/battle/tech_manager.gd`. (cat:refactor; multifile:no) [feat:xlite-20260930-techmanager-never-picks-up-balance-chang]
- [ ] [T4] scripts/battle/tech_manager.gd — Modify `_load_techs` to initialize `_techs` from `_default_techs()` then overlay `researched` flags from save data by matching `name`, ignoring unknown saved names. VERIFY: `grep -q "for tech in _default_techs()" scripts/battle/tech_manager.gd && grep -q "researched" scripts/battle/tech_manager.gd`. (cat:refactor; multifile:no) [feat:xlite-20260930-techmanager-never-picks-up-balance-chang]
- [ ] [T5] tests/test_tech_manager_load_legacy.gd — Create test simulating a legacy save with old costs and missing "Combat Stims", asserting loaded techs have current costs, new tech is present but unresearched, and existing researched flags are preserved. VERIFY: `godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gtest=test_tech_manager_load_legacy.gd`. (cat:test; multifile:no) [feat:xlite-20260930-techmanager-never-picks-up-balance-chang]
