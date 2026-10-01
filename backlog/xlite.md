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

# --- 27B-decomposed from roadmap [2026-09-30]: Stop silently reseeding over a corrupt roster/tech save — roster_manager.gd `_load_roster` (review + tweak) [feat:xlite-20260930-stop-silently-reseeding-over-a-corrupt-r] ---

# --- 27B-decomposed from roadmap [2026-09-30]: TechManager never picks up balance changes or new techs for existing saves — `_save_techs` (review + tweak) [feat:xlite-20260930-techmanager-never-picks-up-balance-chang] ---

# --- 27B-decomposed from roadmap [2026-09-30]: Harden mid-battle resume against incomplete/older payloads — battle.gd `_try_resume_battle (review + tweak) [feat:xlite-20260930-harden-mid-battle-resume-against-incompl] ---
- [ ] [T2] tests/battle/test_battle_resume_validator.gd — Add test cases for unit dictionaries missing `cell` or `modulate` keys and incorrect types to ensure validator returns false. VERIFY: godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/battle/test_battle_resume_validator.gd -gexit. (cat:test; multifile:no) [feat:xlite-20260930-harden-mid-battle-resume-against-incompl]
- [ ] [T3] scripts/battle/battle.gd — Import `BattleResumeValidator` and call `BattleResumeValidator.is_valid(saved)` at the start of `_try_resume_battle_progress`; if false, call `_clear_battle_progress()`, printerr, and return false. VERIFY: grep -n "BattleResumeValidator.is_valid" scripts/battle/battle.gd && godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/battle/test_battle_resume_integration.gd -gexit. (cat:godot; multifile:no) [feat:xlite-20260930-harden-mid-battle-resume-against-incompl]
- [ ] [T3] tests/battle/test_battle_resume_integration.gd — Create GUT test that mocks a battle scene, feeds a truncated save dictionary to `_try_resume_battle_progress`, and verifies it returns false and clears progress without crashing. VERIFY: godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/battle/test_battle_resume_integration.gd -gexit. (cat:test; multifile:no) [feat:xlite-20260930-harden-mid-battle-resume-against-incompl]
- [ ] [T4] scripts/battle/battle.gd — Refactor `_unit_state_from_json` to use `.get()` with defaults for `cell` and `modulate` instead of direct indexing, ensuring no hard error on missing keys even if validator is bypassed. VERIFY: grep -n "out.get(\"cell\"" scripts/battle/battle.gd && godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/battle/test_battle_resume_integration.gd -gexit. (cat:refactor; multifile:no) [feat:xlite-20260930-harden-mid-battle-resume-against-incompl]
- [ ] [T4] scripts/battle/battle.gd — Replace all direct dictionary indexing in `_try_resume_battle_progress` (lines 2929-2984) with `.get()` calls providing safe defaults for obstacles, cover_durability, rubble_cells, hazard_cells, loot_cells, units, prisoners, current_turn, enemies_killed, captured_enemies, materials_collected. VERIFY: godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/battle/test_battle_resume_integration.gd -gexit && grep -c "saved\[" scripts/battle/battle.gd | grep -q "^0$" || true. (cat:refactor; multifile:no) [feat:xlite-20260930-harden-mid-battle-resume-against-incompl]

# --- 27B-decomposed from roadmap [2026-09-30]: Result banner shows gross credits while upkeep is silently deducted, and reward math is du (review + tweak) [feat:xlite-20260930-result-banner-shows-gross-credits-while-] ---
- [ ] [T1] scripts/battle/reward_calc.gd — Add static method `RewardCalc.mission_payout(won: bool, kills: int, captures: int, mission_reward: int, kill_reward: int, capture_reward: int) -> int` that returns `mission_reward if won else 0 + kills * kill_reward + captures * capture_reward`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test/reward_calc_test.gd -gexit`. (cat:godot; multifile:no) [feat:xlite-20260930-result-banner-shows-gross-credits-while-]
- [ ] [T2] test/reward_calc_test.gd — Create GUT test file asserting `RewardCalc.mission_payout(true, 5, 2, 100, 10, 5)` equals 160 and `RewardCalc.mission_payout(false, 5, 2, 100, 10, 5)` equals 0. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test/reward_calc_test.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260930-result-banner-shows-gross-credits-while-]
- [ ] [T3] scripts/battle/battle.gd — Replace inline `credits_earned` calculation in `_end_battle` with `var credits_earned := RewardCalc.mission_payout(victory, _enemies_killed, _captured_enemies.size() if victory else 0, MISSION_REWARD, KILL_REWARD, CAPTURE_REWARD)`. VERIFY: `grep -n "RewardCalc.mission_payout" scripts/battle/battle.gd | wc -l` returns 1. (cat:godot; multifile:no) [feat:xlite-20260930-result-banner-shows-gross-credits-while-]
- [ ] [T3] scripts/battle/battle.gd — Capture return value of `RosterManager.pay_squad_upkeep(...)` into `var upkeep` in `_end_battle` and pass it to `_show_result_banner`. VERIFY: `grep -n "var upkeep := RosterManager.pay_squad_upkeep" scripts/battle/battle.gd | wc -l` returns 1. (cat:godot; multifile:no) [feat:xlite-20260930-result-banner-shows-gross-credits-while-]
- [ ] [T3] scripts/battle/battle.gd — Modify `_show_result_banner` signature to accept `upkeep: int` and append `\n-%d upkeep` to the banner text if `upkeep > 0`. VERIFY: `grep -n "upkeep" scripts/battle/battle.gd | wc -l` returns at least 3. (cat:godot; multifile:no) [feat:xlite-20260930-result-banner-shows-gross-credits-while-]
- [ ] [T2] test/battle_result_test.gd — Create GUT test mocking `RosterManager.pay_squad_upkeep` to return 40 and asserting `_show_result_banner` output contains "-40 upkeep" when victory is true. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test/battle_result_test.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260930-result-banner-shows-gross-credits-while-]
- [ ] [T2] test/battle_result_test.gd — Add test case asserting `_show_result_banner` output does NOT contain "upkeep" when `upkeep` is 0. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test/battle_result_test.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260930-result-banner-shows-gross-credits-while-]
- [ ] [T4] scripts/battle/battle.gd — Remove any remaining hardcoded credit calculation logic in `_end_battle` that duplicates `RewardCalc` logic to ensure single source of truth. VERIFY: `grep -n "credits_earned = " scripts/battle/battle.gd | wc -l` returns 0 (only assignment via RewardCalc remains). (cat:refactor; multifile:no) [feat:xlite-20260930-result-banner-shows-gross-credits-while-]

# --- 27B-decomposed from roadmap [2026-09-30]: Bleed-out deaths skip the morale hit that every other soldier death applies — `_kill_or_do (review + tweak) [feat:xlite-20260930-bleed-out-deaths-skip-the-morale-hit-tha] ---
- [ ] [T1] scripts/battle/battle.gd — Add `_finalize_death(u)` method that calls `u._become_corpse()`, `_apply_morale_loss(u.team)`, and `_remove_unit(u)`. VERIFY: `grep -n "_finalize_death" scripts/battle/battle.gd` shows definition. (cat:godot; multifile:no) [feat:xlite-20260930-bleed-out-deaths-skip-the-morale-hit-tha]
- [ ] [T3] scripts/battle/battle.gd — Replace logic in `_kill_or_down` (lines 3930-3934) to call `_finalize_death(u)` instead of separate `_apply_morale_loss` and `_remove_unit`. VERIFY: `grep -n "_finalize_death" scripts/battle/battle.gd` shows usage in `_kill_or_down`. (cat:godot; multifile:no) [feat:xlite-20260930-bleed-out-deaths-skip-the-morale-hit-tha]
- [ ] [T3] scripts/battle/battle.gd — Replace logic in `_tick_bleed_out_all` (lines 3943-3947) to call `_finalize_death(u)` instead of direct `_become_corpse` and `_remove_unit`. VERIFY: `grep -n "_finalize_death" scripts/battle/battle.gd` shows usage in `_tick_bleed_out_all`. (cat:godot; multifile:no) [feat:xlite-20260930-bleed-out-deaths-skip-the-morale-hit-tha]
- [ ] [T1] tests/battle/test_battle_morale.gd — Create test file inheriting from GUTTest with `setup()` to initialize battle state. VERIFY: `ls tests/battle/test_battle_morale.gd` exists. (cat:test; multifile:no) [feat:xlite-20260930-bleed-out-deaths-skip-the-morale-hit-tha]
- [ ] [T2] tests/battle/test_battle_morale.gd — Add test case `test_bleed_out_applies_morale_loss` that sets up two units, downs one with `bleed_out_turns=1`, calls `_tick_bleed_out_all()`, and asserts survivor morale decreased by `MORALE_LOSS_PER_ALLY_DEATH`. VERIFY: `gut -gdir=tests/battle -gname=test_battle_morale` passes. (cat:test; multifile:no) [feat:xlite-20260930-bleed-out-deaths-skip-the-morale-hit-tha]
- [ ] [T2] tests/battle/test_battle_morale.gd — Add test case `test_kill_or_down_still_applies_morale_loss` to ensure standard death path still works with refactored `_finalize_death`. VERIFY: `gut -gdir=tests/battle -gname=test_battle_morale` passes. (cat:test; multifile:no) [feat:xlite-20260930-bleed-out-deaths-skip-the-morale-hit-tha]
- [ ] [T4] scripts/battle/battle.gd — Remove redundant direct calls to `_remove_unit` and `_apply_morale_loss` in original locations if not already handled by T3, ensuring no double-morale application. VERIFY: `grep -n "_apply_morale_loss" scripts/battle/battle.gd` shows only call inside `_finalize_death`. (cat:refactor; multifile:no) [feat:xlite-20260930-bleed-out-deaths-skip-the-morale-hit-tha]

# --- 27B-decomposed from roadmap [2026-10-01]: Remove dead `_shot_aim` and the obsolete aim-space suppression dock — battle.gd:2319 `_sho (review + tweak) [feat:xlite-20261001-remove-dead-shot-aim-and-the-obsolete-ai] ---
- [ ] [T4] scripts/battle/battle.gd — Remove the `SUPPRESS_AIM_PENALTY` constant and the `_shot_aim` method definition. VERIFY: `grep -n "SUPPRESS_AIM_PENALTY\|_shot_aim" scripts/battle/battle.gd` returns no matches. (cat:refactor; multifile:no) [feat:xlite-20261001-remove-dead-shot-aim-and-the-obsolete-ai]
- [ ] [T1] tests/test_status_effects_battle.gd — Refactor the existing suppression test block to remove direct calls to `_shot_aim` and instead capture hit chance via `_calc_hit_chance` with `suppress_stacks`. VERIFY: `grep -n "_shot_aim" tests/test_status_effects_battle.gd` returns no matches. (cat:test; multifile:no) [feat:xlite-20261001-remove-dead-shot-aim-and-the-obsolete-ai]
- [ ] [T2] tests/test_status_effects_battle.gd — Add a test case asserting that a suppressed shooter's hit chance is strictly lower than an unsuppressed shooter's when `suppress_stacks > 0`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gtest=test_status_effects_battle.gd -gexit` passes. (cat:test; multifile:no) [feat:xlite-20261001-remove-dead-shot-aim-and-the-obsolete-ai]
- [ ] [T2] tests/test_status_effects_battle.gd — Add a test case asserting that the hit chance reduction due to suppression does not exceed `SUPPRESS_HIT_CAP`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gtest=test_status_effects_battle.gd -gexit` passes. (cat:test; multifile:no) [feat:xlite-20261001-remove-dead-shot-aim-and-the-obsolete-ai]
- [ ] [T2] tests/test_status_effects_battle.gd — Add a test case asserting that the suppressed hit chance never falls below the 10% floor (0.1). VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gtest=test_status_effects_battle.gd -gexit` passes. (cat:test; multifile:no) [feat:xlite-20261001-remove-dead-shot-aim-and-the-obsolete-ai]
- [ ] [T3] scripts/battle/battle.gd — Verify that `_calc_hit_chance` correctly integrates `suppress_stacks` into the final hit percentage calculation without referencing removed aim logic. VERIFY: `grep -n "suppress_stacks" scripts/battle/battle.gd` confirms usage in `_calc_hit_chance` and no references to `_shot_aim`. (cat:refactor; multifile:no) [feat:xlite-20261001-remove-dead-shot-aim-and-the-obsolete-ai]
