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

# --- 27B-decomposed from roadmap [2026-09-30]: Result banner shows gross credits while upkeep is silently deducted, and reward math is du (review + tweak) [feat:xlite-20260930-result-banner-shows-gross-credits-while-] ---

# --- 27B-decomposed from roadmap [2026-09-30]: Bleed-out deaths skip the morale hit that every other soldier death applies — `_kill_or_do (review + tweak) [feat:xlite-20260930-bleed-out-deaths-skip-the-morale-hit-tha] ---

# --- 27B-decomposed from roadmap [2026-10-01]: Remove dead `_shot_aim` and the obsolete aim-space suppression dock — battle.gd:2319 `_sho (review + tweak) [feat:xlite-20261001-remove-dead-shot-aim-and-the-obsolete-ai] ---

# --- 27B-decomposed from roadmap [2026-10-01]: Guard the repo's Godot .uid hygiene with a test and clean stragglers — `git ls-files` show (review + tweak) [feat:xlite-20261001-guard-the-repo-s-godot-uid-hygiene-with-] ---

# --- 27B-decomposed from roadmap [2026-10-03]: DamagePreview: add test for `calculate_projected_damage` + remove orphaned `intent_data` p (review + tweak) [feat:xlite-20261003-damagepreview-add-test-for-calculate-pro] ---

# --- 27B-decomposed from roadmap [2026-10-03]: LoadoutPreset: delete dead always-true stub — scripts/roster/loadout_preset.gd:3-4: `is_va (review + tweak) [feat:xlite-20261003-loadoutpreset-delete-dead-always-true-st] ---

# --- 27B-decomposed from roadmap [2026-10-03]: CellRing.ring_index: delegate to AoeFalloff.ring_of to eliminate duplicate Chebyshev-dista (review + tweak) [feat:xlite-20261003-cellring-ring-index-delegate-to-aoefallo] ---

# --- 27B-decomposed from roadmap [2026-10-03]: MissionDirective: add `armor_reduction_percent` and `is_stealth_required` for HEAVY_ARMOR  (review + tweak) [feat:xlite-20261003-missiondirective-add-armor-reduction-per] ---

# --- 27B-decomposed from roadmap [2026-10-03]: Scar: add `wound_severity_for_penalty` inverse of `stat_penalty_percent` — scripts/roster/ (review + tweak) [feat:xlite-20261003-scar-add-wound-severity-for-penalty-inve] ---

# --- 27B-decomposed from roadmap [2026-10-03]: Morale: add `morale_percent(current, cap)` UI bar helper — scripts/battle/morale.gd has `m (review + tweak) [feat:xlite-20261003-morale-add-morale-percent-current-cap-ui] ---

# --- 27B-decomposed from roadmap [2026-10-03]: Resistance: add `is_resistant` and `is_weak` predicates mirroring `is_immune` — scripts/ba (review + tweak) [feat:xlite-20261003-resistance-add-is-resistant-and-is-weak-] ---

# --- 27B-decomposed from roadmap [2026-10-03]: StatusModifiers: add `is_stunned` and `is_slowed` predicates — scripts/units/status_modifi (review + tweak) [feat:xlite-20261003-statusmodifiers-add-is-stunned-and-is-sl] ---

# --- 27B-decomposed from roadmap [2026-10-03]: Momentum: add `tiles_for_max_bonus(per_tile, cap)` inverse of `charge_bonus` — scripts/bat (review + tweak) [feat:xlite-20261003-momentum-add-tiles-for-max-bonus-per-til] ---

# --- 27B-decomposed from roadmap [2026-10-03]: HitOdds: add `aim_bonus_needed(cover_tier, flanked, target_pct, height_bonus)` inverse of  (review + tweak) [feat:xlite-20261003-hitodds-add-aim-bonus-needed-cover-tier-] ---

# --- 27B-decomposed from roadmap [2026-10-03]: Dead-code: delete `DamagePreview.calculate_projected_damage` — Resolves the roadmap's flag (review + tweak) [feat:xlite-20261003-dead-code-delete-damagepreview-calculate] ---

# --- 27B-decomposed from roadmap [2026-10-03]: Dead-code: delete `Suppression.is_suppressed` and `has_suppression_tag` — `scripts/battle/ (review + tweak) [feat:xlite-20261003-dead-code-delete-suppression-is-suppress] ---

# --- 27B-decomposed from roadmap [2026-10-03]: Dead-code: delete INERT `Elevation` class — `scripts/battle/elevation.gd` (17 lines, verif (review + tweak) [feat:xlite-20261003-dead-code-delete-inert-elevation-class-s] ---

# --- 27B-decomposed from roadmap [2026-10-03]: Misplaced: move `AimModifiers.validate_itch_channel_name` → `scripts/release/itch_readines (review + tweak) [feat:xlite-20261003-misplaced-move-aimmodifiers-validate-itc] ---

# --- 27B-decomposed from roadmap [2026-10-03]: `TurnLimit.percent_elapsed` — turn-progress-bar helper — `scripts/mission/turn_limit.gd` ( (review + tweak) [feat:xlite-20261003-turnlimit-percent-elapsed-turn-progress-] ---

# --- 27B-decomposed from roadmap [2026-10-03]: `LoadoutPreset.is_valid_preset` stub — implement no-duplicate validation — `scripts/roster (review + tweak) [feat:xlite-20261003-loadoutpreset-is-valid-preset-stub-imple] ---

# --- 27B-decomposed from roadmap [2026-10-03]: Dead-code: delete `Aoe.hit_percent_needed` — `scripts/battle/aoe.gd:30-35` has a `hit_perc (review + tweak) [feat:xlite-20261003-dead-code-delete-aoe-hit-percent-needed-] ---

# --- 27B-decomposed from roadmap [2026-10-03]: Dead-code: delete `InRange` class — `scripts/grid/in_range.gd` (7 lines, verified) has `in (review + tweak) [feat:xlite-20261003-dead-code-delete-inrange-class-scripts-g] ---

# --- 27B-decomposed from roadmap [2026-10-04]: Delete scripts/battle/elevation.gd — roadmap credits this deletion as done ([x] feat:xlite (review + tweak) [feat:xlite-20261004-delete-scripts-battle-elevation-gd-roadm] ---

# --- 27B-decomposed from roadmap [2026-10-04]: Delete scripts/grid/in_range.gd — same missed-deletion as elevation.gd: roadmap marks [x]  (review + tweak) [feat:xlite-20261004-delete-scripts-grid-in-range-gd-same-mis] ---

# --- 27B-decomposed from roadmap [2026-10-04]: Resistance: apply_with_immunity combinator — scripts/battle/resistance.gd (verified via re (review + tweak) [feat:xlite-20261004-resistance-apply-with-immunity-combinato] ---

# --- 27B-decomposed from roadmap [2026-10-04]: Equipment: is_valid_tier predicate (silent-failure guard) — scripts/roster/equipment.gd (v (review + tweak) [feat:xlite-20261004-equipment-is-valid-tier-predicate-silent] ---

# --- 27B-decomposed from roadmap [2026-10-04]: FlankSide: side_name label helper — scripts/battle/flank_side.gd (verified via read, 22 li (review + tweak) [feat:xlite-20261004-flankside-side-name-label-helper-scripts] ---

# --- 27B-decomposed from roadmap [2026-10-04]: MissionDirective: HEAVY_ARMOR and SILENT_KILL are pure stubs — scripts/mission/mission_dir (review + tweak) [feat:xlite-20261004-missiondirective-heavy-armor-and-silent-] ---

# --- 27B-decomposed from roadmap [2026-10-04]: Formation: min_pair_gap exposes value is_bunched hides — scripts/battle/formation.gd (veri (review + tweak) [feat:xlite-20261004-formation-min-pair-gap-exposes-value-is-] ---

# --- 27B-decomposed from roadmap [2026-10-04]: Capture: turns_to_struggle_free counter — scripts/battle/capture.gd (verified via read, 71 (review + tweak) [feat:xlite-20261004-capture-turns-to-struggle-free-counter-s] ---

# --- 27B-decomposed from roadmap [2026-10-04]: ApRefund: refund_overflow wasted-AP counter — scripts/battle/ap_refund.gd (verified via re (review + tweak) [feat:xlite-20261004-aprefund-refund-overflow-wasted-ap-count] ---

# --- 27B-decomposed from roadmap [2026-10-04]: Test: BattleSaveCodec unit test file — scripts/battle/battle_save_codec.gd (169 lines, ver (review + tweak) [feat:xlite-20261004-test-battlesavecodec-unit-test-file-scri] ---

# --- 27B-decomposed from roadmap [2026-10-04]: Dead-code: delete AccuracyCurve.get_build_metadata + its three test cases — scripts/battle (review + tweak) [feat:xlite-20261004-dead-code-delete-accuracycurve-get-build] ---

# --- 27B-decomposed from roadmap [2026-10-04]: Dead-code: delete now-superseded BattleResumeValidator class — scripts/battle/battle_resum (review + tweak) [feat:xlite-20261004-dead-code-delete-now-superseded-battlere] ---

# --- 27B-decomposed from roadmap [2026-10-04]: Wire ItchReadinessCheck.validate_itch_channel_name into itch_uploader.gd before upload — s (review + tweak) [feat:xlite-20261004-wire-itchreadinesscheck-validate-itch-ch] ---

# --- 27B-decomposed from roadmap [2026-10-04]: Dead-code: delete LineOfFire class — scripts/battle/line_of_fire.gd (verified via Read) ha (review + tweak) [feat:xlite-20261004-dead-code-delete-lineoffire-class-script] ---

# --- 27B-decomposed from roadmap [2026-10-04]: Dead-code: delete SpawnBudget class — scripts/battle/spawn_budget.gd (verified via Read) h (review + tweak) [feat:xlite-20261004-dead-code-delete-spawnbudget-class-scrip] ---

# --- 27B-decomposed from roadmap [2026-10-04]: Dead-code: delete WeightedPick.cumulative — scripts/battle/weighted_pick.gd:9-12 (verified (review + tweak) [feat:xlite-20261004-dead-code-delete-weightedpick-cumulative] ---

# --- 27B-decomposed from roadmap [2026-10-04]: Delete FlankSide dead class — `scripts/battle/flank_side.gd` (`side_of`, `is_rear`) has 0  (review + tweak) [feat:xlite-20261004-delete-flankside-dead-class-scripts-batt] ---

# --- 27B-decomposed from roadmap [2026-10-04]: Deduplicate AoeTargeting._chebyshev via GridDistance.chebyshev — `scripts/battle/aoe_targe (review + tweak) [feat:xlite-20261004-deduplicate-aoetargeting-chebyshev-via-g] ---

# --- 27B-decomposed from roadmap [2026-10-04]: HitBreakdown.breakdown missing base key — `scripts/battle/hit_breakdown.gd:5-12` builds a  (review + tweak) [feat:xlite-20261004-hitbreakdown-breakdown-missing-base-key-] ---

# --- 27B-decomposed from roadmap [2026-10-04]: Wire MissionDirective into MissionData validation — `scripts/mission/mission_directive.gd` (review + tweak) [feat:xlite-20261004-wire-missiondirective-into-missiondata-v] ---

# --- 27B-decomposed from roadmap [2026-10-04]: Wire SquadScore.missing_roles into roster_view warning label — `scripts/mission/roster_vie (review + tweak) [feat:xlite-20261004-wire-squadscore-missing-roles-into-roste] ---

# --- 27B-decomposed from roadmap [2026-10-04]: Delete UnitFaction dead enum class — `scripts/units/unit_faction.gd` defines `enum Faction (review + tweak) [feat:xlite-20261004-delete-unitfaction-dead-enum-class-scrip] ---

# --- 27B-decomposed from roadmap [2026-10-05]: Delete 8 orphaned .uid sidecars that cause test_uid_hygiene.gd to fail — `tests/test_uid_h (review + tweak) [feat:xlite-20261005-delete-8-orphaned-uid-sidecars-that-caus] ---

# --- 27B-decomposed from roadmap [2026-10-05]: Delete dead Scatter class — zero callers across all of scripts/ — `scripts/battle/scatter. (review + tweak) [feat:xlite-20261005-delete-dead-scatter-class-zero-callers-a] ---

# --- 27B-decomposed from roadmap [2026-10-05]: Delete dead SpawnSpread class — zero callers across all of scripts/ — `scripts/grid/spawn_ (review + tweak) [feat:xlite-20261005-delete-dead-spawnspread-class-zero-calle] ---

# --- 27B-decomposed from roadmap [2026-10-05]: Refactor Overwatch._chebyshev → GridDistance.chebyshev — `scripts/battle/overwatch.gd:45-4 (review + tweak) [feat:xlite-20261005-refactor-overwatch-chebyshev-griddistanc] ---

# --- 27B-decomposed from roadmap [2026-10-05]: Fix SCOUT missing from recruit button loop — `scripts/mission/roster_view.gd:107` iterates (review + tweak) [feat:xlite-20261005-fix-scout-missing-from-recruit-button-lo] ---

# --- 27B-decomposed from roadmap [2026-10-05]: Fix SquadScore.get_missing_roles_label str-on-int produces numeric strings — `scripts/batt (review + tweak) [feat:xlite-20261005-fix-squadscore-get-missing-roles-label-s] ---

# --- 27B-decomposed from roadmap [2026-10-05]: Implement MissionSummary.build() — `scripts/mission/mission_summary.gd` returns `{}` and ` (review + tweak) [feat:xlite-20261005-implement-missionsummary-build-scripts-m] ---

# --- 27B-decomposed from roadmap [2026-10-05]: Implement SpawnBudget.compute() — `scripts/battle/spawn_budget.gd` is a single-line placeh (review + tweak) [feat:xlite-20261005-implement-spawnbudget-compute-scripts-ba] ---

# --- 27B-decomposed from roadmap [2026-10-05]: Wire machine_completionist and mutant_completionist achievements — `scripts/steam/achievem (review + tweak) [feat:xlite-20261005-wire-machine-completionist-and-mutant-co] ---

# --- 27B-decomposed from roadmap [2026-10-05]: Wire KillPriority.score() to AI targeting or remove — `scripts/battle/kill_priority.gd` `s (review + tweak) [feat:xlite-20261005-wire-killpriority-score-to-ai-targeting-] ---

# --- 27B-decomposed from roadmap [2026-10-05]: Fix Damage.expected_damage floor inconsistency — `scripts/battle/damage.gd` `expected_dama (review + tweak) [feat:xlite-20261005-fix-damage-expected-damage-floor-inconsi] ---

# --- 27B-decomposed from roadmap [2026-10-05]: Remove dead enemy_pos parameter from EnemyIntent.generate_intent — `scripts/battle/enemy_i (review + tweak) [feat:xlite-20261005-remove-dead-enemy-pos-parameter-from-ene] ---

# --- 27B-decomposed from roadmap [2026-10-05]: Harden the roster save loader against corrupt scalar values — `scripts/roster/roster_manag (review + tweak) [feat:xlite-20261005-harden-the-roster-save-loader-against-co] ---

# --- 27B-decomposed from roadmap [2026-10-05]: Clamp the numeric fields of `RosterEntry` and coerce them on load — `scripts/roster/roster (review + tweak) [feat:xlite-20261005-clamp-the-numeric-fields-of-rosterentry-] ---

# --- 27B-decomposed from roadmap [2026-10-05]: Make the tech-tree loader reject corrupt and duplicate entries — `scripts/tech/tech_manage (review + tweak) [feat:xlite-20261005-make-the-tech-tree-loader-reject-corrupt] ---

# --- 27B-decomposed from roadmap [2026-10-05]: Cover the autosave validator's reject branches — `scripts/battle/battle_save_codec.gd:77-1 (review + tweak) [feat:xlite-20261005-cover-the-autosave-validator-s-reject-br] ---

# --- 27B-decomposed from roadmap [2026-10-05]: Remove the divergent, unused `XpCalc` XP curve so `RANKS` is the only one — `scripts/battl (review + tweak) [feat:xlite-20261005-remove-the-divergent-unused-xpcalc-xp-cu] ---

# --- 27B-decomposed from roadmap [2026-10-07]: Delete `KillPriority.get_target_priority_score` dead scene-coupled function — `scripts/bat (review + tweak) [feat:xlite-20261007-delete-killpriority-get-target-priority-] ---

# --- 27B-decomposed from roadmap [2026-10-07]: Fix `SquadScore._ROLE_NAMES` incomplete dict + wire label into roster_view + move ghost te (review + tweak) [feat:xlite-20261007-fix-squadscore-role-names-incomplete-dic] ---

# --- 27B-decomposed from roadmap [2026-10-07]: Delete `scripts/grid/manhattan_distance.gd` + `tests/test_manhattan_distance.gd` — `Manhat (review + tweak) [feat:xlite-20261007-delete-scripts-grid-manhattan-distance-g] ---

# --- 27B-decomposed from roadmap [2026-10-07]: `Momentum.tiles_to_charge` complement of live `is_charging` — `scripts/battle/battle.gd:21 (review + tweak) [feat:xlite-20261007-momentum-tiles-to-charge-complement-of-l] ---

# --- 27B-decomposed from roadmap [2026-10-07]: `StatusEffects.apply` always hardcodes merge-mode 0 making modes 1 and 2 unreachable — `sc (review + tweak) [feat:xlite-20261007-statuseffects-apply-always-hardcodes-mer] ---

# --- 27B-decomposed from roadmap [2026-10-07]: Add exhaustive faction assertions to `tests/test_enemy_faction_map.gd` — `EnemyFactionMap. (review + tweak) [feat:xlite-20261007-add-exhaustive-faction-assertions-to-tes] ---

# --- 27B-decomposed from roadmap [2026-10-07]: Consolidate `DiagonalStep` into `GridDistance` + wire into `knockback.gd` — `scripts/grid/ (review + tweak) [feat:xlite-20261007-consolidate-diagonalstep-into-griddistan] ---

# --- 27B-decomposed from roadmap [2026-10-07]: `MissionDirective.is_valid_directive` hardcodes `<= 4` — `scripts/mission/mission_directiv (review + tweak) [feat:xlite-20261007-missiondirective-is-valid-directive-hard] ---

# --- 27B-decomposed from roadmap [2026-10-07]: Fix SpawnBudget.compute ignoring difficulty parameter — scripts/battle/spawn_budget.gd:11- (review + tweak) [feat:xlite-20261007-fix-spawnbudget-compute-ignoring-difficu] ---

# --- 27B-decomposed from roadmap [2026-10-07]: Fix tech_tree.gd CREDIT_COSTS missing Kevlar and Optics — scripts/mission/tech_tree.gd CRE (review + tweak) [feat:xlite-20261007-fix-tech-tree-gd-credit-costs-missing-ke] ---

# --- 27B-decomposed from roadmap [2026-10-07]: Delete FlankBonus.get_flank_bonus hardcoded stub — scripts/battle/flank_bonus.gd `get_flan (review + tweak) [feat:xlite-20261007-delete-flankbonus-get-flank-bonus-hardco] ---

# --- 27B-decomposed from roadmap [2026-10-07]: Add Weapon Upgrades and Combat Stims to tech_tree.gd CREDIT_COSTS and MATERIAL_COSTS — scr (review + tweak) [feat:xlite-20261007-add-weapon-upgrades-and-combat-stims-to-] ---

# --- 27B-decomposed from roadmap [2026-10-07]: Fix dead file_exists variable and redundant SaveManager.file_exists_for call in tech_manag (review + tweak) [feat:xlite-20261007-fix-dead-file-exists-variable-and-redund] ---

# --- 27B-decomposed from roadmap [2026-10-08]: Fix MissionData.is_valid() ignoring invalid directive — `scripts/mission/mission_data.gd:9 (review + tweak) [feat:xlite-20261008-fix-missiondata-is-valid-ignoring-invali] ---

# --- 27B-decomposed from roadmap [2026-10-08]: tests/test_star_rating.gd — `scripts/mission/star_rating.gd:stars()` is called from `scrip (review + tweak) [feat:xlite-20261008-tests-test-star-rating-gd-scripts-missio] ---

# --- 27B-decomposed from roadmap [2026-10-08]: tests/test_mission_validator.gd — `scripts/mission/mission_validator.gd` has three functio (review + tweak) [feat:xlite-20261008-tests-test-mission-validator-gd-scripts-] ---

# --- 27B-decomposed from roadmap [2026-10-08]: Fix mission_data.gd:is_valid() allows directive=5 (off-by-one vs enum range) — scripts/mis (review + tweak) [feat:xlite-20261008-fix-mission-data-gd-is-valid-allows-dire] ---

# --- 27B-decomposed from roadmap [2026-10-08]: Delete ManhattanDistance orphan — queue misidentified it as already gone — scripts/grid/ma (review + tweak) [feat:xlite-20261008-delete-manhattandistance-orphan-queue-mi] ---

# --- 27B-decomposed from roadmap [2026-10-08]: Delete two dead helpers fleet added to ArmorPen with no production callers — scripts/battl (review + tweak) [feat:xlite-20261008-delete-two-dead-helpers-fleet-added-to-a] ---

# --- 27B-decomposed from roadmap [2026-10-08]: Delete 3 ghost/stub test files that have no test functions — tests/test_line_of_fire.gd (e (review + tweak) [feat:xlite-20261008-delete-3-ghost-stub-test-files-that-have] ---

# --- deterministic work supply 2026-10-08 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- deterministic work supply 2026-10-08 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- deterministic work supply 2026-10-08 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- deterministic work supply 2026-10-08 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-09]: Wire _is_valid_save_name() into save_save() to block path-traversal save names — `save_man (review + tweak) [feat:xlite-20261009-wire-is-valid-save-name-into-save-save-t] ---

# --- 27B-decomposed from roadmap [2026-10-09]: Delete BattleResumeValidator and its test file — `scripts/battle/battle_resume_validator.g (review + tweak) [feat:xlite-20261009-delete-battleresumevalidator-and-its-tes] ---

# --- 27B-decomposed from roadmap [2026-10-09]: Delete AimModifiers.get_aim_modifier_percent() and _is_directive_valid() silent stubs — `s (review + tweak) [feat:xlite-20261009-delete-aimmodifiers-get-aim-modifier-per] ---

# --- 27B-decomposed from roadmap [2026-10-09]: Batch-delete 5 orphaned .uid files with no matching .gd source — Glob confirms no `.gd` co (review + tweak) [feat:xlite-20261009-batch-delete-5-orphaned-uid-files-with-n] ---

# --- 27B-decomposed from roadmap [2026-10-09]: Move CREDIT_COSTS and MATERIAL_COSTS from tech_tree.gd into TechManager — `scripts/mission (review + tweak) [feat:xlite-20261009-move-credit-costs-and-material-costs-fro] ---

# --- 27B-decomposed from roadmap [2026-10-09]: Fix TechManager prerequisite enforcement — can_research() and research_tech() ignore the ` (review + tweak) [feat:xlite-20261009-fix-techmanager-prerequisite-enforcement] ---

# --- 27B-decomposed from roadmap [2026-10-09]: Delete AchievementTriggers.on_enemy_faction_fully_seen() and its registry entries — `scrip (review + tweak) [feat:xlite-20261009-delete-achievementtriggers-on-enemy-fact] ---

# --- 27B-decomposed from roadmap [2026-10-09]: Delete EnemyFactionMap.get_faction() and get_all_factions() dead functions — `scripts/batt (review + tweak) [feat:xlite-20261009-delete-enemyfactionmap-get-faction-and-g] ---

# --- deterministic work supply 2026-10-09 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-09]: Coerce techs_data to Array on load — `scripts/tech/tech_manager.gd:195` reads `save_data.g (review + tweak) [feat:xlite-20261009-coerce-techs-data-to-array-on-load-scrip] ---

# --- 27B-decomposed from roadmap [2026-10-09]: Coerce seen_data to Dictionary on load — `scripts/codex/codex_manager.gd:100` reads `save_ (review + tweak) [feat:xlite-20261009-coerce-seen-data-to-dictionary-on-load-s] ---

# --- 27B-decomposed from roadmap [2026-10-09]: Coerce captured and entries to Arrays on load — `scripts/roster/roster_manager.gd:564` and (review + tweak) [feat:xlite-20261009-coerce-captured-and-entries-to-arrays-on] ---

# --- deterministic work supply 2026-10-09 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- deterministic work supply 2026-10-09 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- deterministic work supply 2026-10-09 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- deterministic work supply 2026-10-09 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- deterministic work supply 2026-10-09 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- deterministic work supply 2026-10-09 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-10]: Fix `_load_roster` double disk-read — `scripts/roster/roster_manager.gd:551-561`: when a s (review + tweak) [feat:xlite-20261010-fix-load-roster-double-disk-read-scripts] ---

# --- 27B-decomposed from roadmap [2026-10-10]: Fix `mission_data.gd::is_valid()` accepts out-of-range directive — `scripts/mission/missio (review + tweak) [feat:xlite-20261010-fix-mission-data-gd-is-valid-accepts-out] ---

# --- 27B-decomposed from roadmap [2026-10-10]: Atomic write for `save_manager.gd::save_save()` — `scripts/save/save_manager.gd:66`: `File (review + tweak) [feat:xlite-20261010-atomic-write-for-save-manager-gd-save-sa] ---

# --- 27B-decomposed from roadmap [2026-10-10]: Wire `TechManager.material_cost()` to real per-tech values — `scripts/tech/tech_manager.gd (review + tweak) [feat:xlite-20261010-wire-techmanager-material-cost-to-real-p] ---

# --- 27B-decomposed from roadmap [2026-10-10]: Gate mission-hub debug tools behind `OS.is_debug_build()` — `scripts/mission/mission_hub.g (review + tweak) [feat:xlite-20261010-gate-mission-hub-debug-tools-behind-os-i] ---

# --- 27B-decomposed from roadmap [2026-10-11]: Ghost tests in `test/` directory never run — `test/battle/test_squad_score.gd` and `test/c (review + tweak) [feat:xlite-20261011-ghost-tests-in-test-directory-never-run-] ---

# --- 27B-decomposed from roadmap [2026-10-11]: `SfxBus.play_music()` ignores mute and volume state — `scripts/audio/sfx_bus.gd:55-65`: `p (review + tweak) [feat:xlite-20261011-sfxbus-play-music-ignores-mute-and-volum] ---

# --- 27B-decomposed from roadmap [2026-10-11]: `AimModifiers.calc_suppression_aim_penalty` returns float but its consumer `final_percent` (review + tweak) [feat:xlite-20261011-aimmodifiers-calc-suppression-aim-penalt] ---

# --- 27B-decomposed from roadmap [2026-10-11]: Delete orphan `scripts/battle/save_manager.gd` — 9-line file with `extends Node` and no `c (review + tweak) [feat:xlite-20261011-delete-orphan-scripts-battle-save-manage] ---

# --- 27B-decomposed from roadmap [2026-10-11]: Delete root-level placeholder stubs `scatter.gd` and `in_range.gd` — both files at repo ro (review + tweak) [feat:xlite-20261011-delete-root-level-placeholder-stubs-scat] ---

# --- 27B-decomposed from roadmap [2026-10-11]: Delete dead `CodexData.get_soldier_name` and align its test to the canonical function — `s (review + tweak) [feat:xlite-20261011-delete-dead-codexdata-get-soldier-name-a] ---

# --- 27B-decomposed from roadmap [2026-10-11]: Delete `scripts/battle/enemy_fattle/enemy_faction_map.gd` typo-directory artifact — empty  (review + tweak) [feat:xlite-20261011-delete-scripts-battle-enemy-fattle-enemy] ---

# --- 27B-decomposed from roadmap [2026-10-12]: Add `EnemyFactionMap.faction_for()` + `AchievementTriggers.on_faction_codex_complete()` to (review + tweak) [feat:xlite-20261012-add-enemyfactionmap-faction-for-achievem] ---

# --- 27B-decomposed from roadmap [2026-10-12]: Fix `Aggro.is_valid_directive` hardcoded `<= 4` sentinel — `scripts/battle/aggro.gd:25-26` (review + tweak) [feat:xlite-20261012-fix-aggro-is-valid-directive-hardcoded-4] ---

# --- 27B-decomposed from roadmap [2026-10-12]: Delete `Damage.coerce_to_array` and `Damage.simulate_single_load` — misplaced functions br (review + tweak) [feat:xlite-20261012-delete-damage-coerce-to-array-and-damage] ---

# --- 27B-decomposed from roadmap [2026-10-12]: Delete `Aoe.is_destructible_type` (dead String-keyed orphan) and its 3 redundant test file (review + tweak) [feat:xlite-20261012-delete-aoe-is-destructible-type-dead-str] ---

# --- 27B-decomposed from roadmap [2026-10-12]: Delete `AccuracyCurve.get_build_metadata` (exact duplicate of `BuildInfo.get_build_metadat (review + tweak) [feat:xlite-20261012-delete-accuracycurve-get-build-metadata-] ---

# --- 27B-decomposed from roadmap [2026-10-12]: Delete `CellRing` — full geometry duplicate of `SpiralCells`, both INERT — `scripts/battle (review + tweak) [feat:xlite-20261012-delete-cellring-full-geometry-duplicate-] ---

# --- 27B-decomposed from roadmap [2026-10-12]: Delete `FlankBonus.get_flank_bonus` (ignores both Vector2 parameters, returns constant 1.0 (review + tweak) [feat:xlite-20261012-delete-flankbonus-get-flank-bonus-ignore] ---

# --- 27B-decomposed from roadmap [2026-10-13]: Fix Unit.display_name() omitting EnemyType.RAIDER — scripts/units/unit.gd:802-824 match st (review + tweak) [feat:xlite-20261013-fix-unit-display-name-omitting-enemytype] ---

# --- 27B-decomposed from roadmap [2026-10-13]: Fix slot deletion leaving codex save on disk — save_slot_select.gd:44 SLOT_SUFFIXES list i (review + tweak) [feat:xlite-20261013-fix-slot-deletion-leaving-codex-save-on-] ---

# --- 27B-decomposed from roadmap [2026-10-13]: Fix get_techs() copying TechItem without preserving material_cost — tech_manager.gd:61 cre (review + tweak) [feat:xlite-20261013-fix-get-techs-copying-techitem-without-p] ---

# --- 27B-decomposed from roadmap [2026-10-13]: Fix CAPTURED_CLASS missing "Bomber" and "Arc Gunner" entries — roster_manager.gd:299-309 C (review + tweak) [feat:xlite-20261013-fix-captured-class-missing-bomber-and-ar] ---

# --- 27B-decomposed from roadmap [2026-10-13]: Add display_name() invariant to test_unit_enemy_archetypes.gd — tests/test_unit_enemy_arch (review + tweak) [feat:xlite-20261013-add-display-name-invariant-to-test-unit-] ---

# --- 27B-decomposed from roadmap [2026-10-13]: Wire MissionDirective.bonus_enemy_count and aim_modifier_percent into battle spawn — scrip (review + tweak) [feat:xlite-20261013-wire-missiondirective-bonus-enemy-count-] ---

# --- 27B-decomposed from roadmap [2026-10-13]: Harden test_campaign_save_load_integration.gd to cover codex slot isolation — tests/test_c (review + tweak) [feat:xlite-20261013-harden-test-campaign-save-load-integrati] ---

# --- 27B-decomposed from roadmap [2026-10-14]: Fix Scout display_name returning "Assault" — `scripts/units/unit.gd:793-801` `display_name (review + tweak) [feat:xlite-20261014-fix-scout-display-name-returning-assault] ---

# --- 27B-decomposed from roadmap [2026-10-14]: Fix _codex suffix not stripped in slot-picker — `scripts/mission/save_slot_select.gd:28-35 (review + tweak) [feat:xlite-20261014-fix-codex-suffix-not-stripped-in-slot-pi] ---

# --- 27B-decomposed from roadmap [2026-10-14]: Fix Boss display_name mismatch with codex — `scripts/units/unit.gd:820` returns "Boss" for (review + tweak) [feat:xlite-20261014-fix-boss-display-name-mismatch-with-code] ---

# --- 27B-decomposed from roadmap [2026-10-14]: Fix Research button enabled despite unmet prerequisites — `scripts/mission/tech_tree.gd:15 (review + tweak) [feat:xlite-20261014-fix-research-button-enabled-despite-unme] ---

# --- 27B-decomposed from roadmap [2026-10-15]: _save_techs() silently drops material_cost field — `tech_manager.gd:168–182` builds the sa (review + tweak) [feat:xlite-20261015-save-techs-silently-drops-material-cost-] ---

# --- 27B-decomposed from roadmap [2026-10-15]: directive_ok integration path has zero test coverage — `test_all_numbered_missions_pass_mi (review + tweak) [feat:xlite-20261015-directive-ok-integration-path-has-zero-t] ---

# --- 27B-decomposed from roadmap [2026-10-16]: Rescue unique directive sweep from ghost test then delete all three subdirectory ghost fil (review + tweak) [feat:xlite-20261016-rescue-unique-directive-sweep-from-ghost] ---

# --- 27B-decomposed from roadmap [2026-10-16]: Delete dead `AchievementRegistry.on_faction_codex_update` and replace its tests with asser (review + tweak) [feat:xlite-20261016-delete-dead-achievementregistry-on-facti] ---

# --- 27B-decomposed from roadmap [2026-10-16]: Delete dead `Aggro.bonus_enemy_count` wrapper — `scripts/battle/aggro.gd:28-31` defines `s (review + tweak) [feat:xlite-20261016-delete-dead-aggro-bonus-enemy-count-wrap] ---

# --- 27B-decomposed from roadmap [2026-10-16]: Cancel the stale deletion of `tests/test_roster_load_hardening.gd` and remove it from the  (review + tweak) [feat:xlite-20261016-cancel-the-stale-deletion-of-tests-test-] ---

# --- 27B-decomposed from roadmap [2026-10-17]: Delete `Damage.get_max_directive_value` dead helper — `scripts/battle/damage.gd:55-56` has (review + tweak) [feat:xlite-20261017-delete-damage-get-max-directive-value-de] ---

# --- 27B-decomposed from roadmap [2026-10-17]: Delete INERT `LootTable` class — `scripts/battle/loot_table.gd` provides `roll()`, `total_ (review + tweak) [feat:xlite-20261017-delete-inert-loottable-class-scripts-bat] ---

# --- 27B-decomposed from roadmap [2026-10-17]: Delete dead `FriendlyFire.is_friendly_fire()` and `allies_in_blast()` — `scripts/battle/fr (review + tweak) [feat:xlite-20261017-delete-dead-friendlyfire-is-friendly-fir] ---

# --- 27B-decomposed from roadmap [2026-10-17]: Fix doubled warning label in roster_view — `scripts/mission/roster_view.gd:76` produces "⚠ (review + tweak) [feat:xlite-20261017-fix-doubled-warning-label-in-roster-view] ---

# --- 27B-decomposed from roadmap [2026-10-17]: Delete `Aggro.is_valid_directive` dead production wrapper — `scripts/battle/aggro.gd:25-26 (review + tweak) [feat:xlite-20261017-delete-aggro-is-valid-directive-dead-pro] ---

# --- 27B-decomposed from roadmap [2026-10-17]: Delete `EnemyIntent.generate_intent` and `EnemyIntent.intent_label` dead helpers — `script (review + tweak) [feat:xlite-20261017-delete-enemyintent-generate-intent-and-e] ---

# --- 27B-decomposed from roadmap [2026-10-17]: Show next-mission objective type in mission hub — `scripts/mission/mission_hub.gd:74` rend (review + tweak) [feat:xlite-20261017-show-next-mission-objective-type-in-miss] ---

# --- 27B-decomposed from roadmap [2026-10-17]: `MissionDirective` effects invisible to player — `scripts/mission/mission_directive.gd` de (review + tweak) [feat:xlite-20261017-missiondirective-effects-invisible-to-pl] ---

# --- 27B-decomposed from roadmap [2026-10-17]: `MissionValidator` does not check patrol-route waypoint bounds — `scripts/mission/mission_ (review + tweak) [feat:xlite-20261017-missionvalidator-does-not-check-patrol-r] ---

# --- 27B-decomposed from roadmap [2026-10-18]: delete Overwatch.has_line_of_sight — dead divergent LOS implementation, zero production ca (review + tweak) [feat:xlite-20261018-delete-overwatch-has-line-of-sight-dead-] ---

# --- 27B-decomposed from roadmap [2026-10-18]: delete AimModifiers.calc_suppression_aim_penalty and its float constant — dead per-stack p (review + tweak) [feat:xlite-20261018-delete-aimmodifiers-calc-suppression-aim] ---

# --- 27B-decomposed from roadmap [2026-10-18]: Mission directives shown in hub but never applied in battle — `MissionDirective.aim_modifi (review + tweak) [feat:xlite-20261018-mission-directives-shown-in-hub-but-neve] ---

# --- 27B-decomposed from roadmap [2026-10-18]: `Aoe.hit_percent_needed` returns >100 in violation of its documented 0-100 contract — `scr (review + tweak) [feat:xlite-20261018-aoe-hit-percent-needed-returns-100-in-vi] ---

# --- 27B-decomposed from roadmap [2026-10-18]: `StatusEffects`/`StatusModifiers` are fully implemented and tested but completely inert in (review + tweak) [feat:xlite-20261018-statuseffects-statusmodifiers-are-fully-] ---

# --- 27B-decomposed from roadmap [2026-10-18]: `MissionValidator.directive_ok` is wired into `MissionData.is_valid()` at `scripts/mission (review + tweak) [feat:xlite-20261018-missionvalidator-directive-ok-is-wired-i] ---

# --- 27B-decomposed from roadmap [2026-10-18]: `AchievementRegistry.MAP` silently drops `perfect_mission` and `full_squad_extraction` — ` (review + tweak) [feat:xlite-20261018-achievementregistry-map-silently-drops-p] ---

# --- 27B-decomposed from roadmap [2026-10-18]: `AchievementRegistry.on_faction_codex_update` (lines 62-71) and `on_faction_codex_complete (review + tweak) [feat:xlite-20261018-achievementregistry-on-faction-codex-upd] ---

# --- 27B-decomposed from roadmap [2026-10-18]: `MissionPathMap.status_for` has an off-by-one when `current == completed`: `mission_path_m (review + tweak) [feat:xlite-20261018-missionpathmap-status-for-has-an-off-by-] ---

# --- 27B-decomposed from roadmap [2026-10-18]: Fix Capture.hits_to_incapacitate false-zero for dead units — scripts/battle/capture.gd:52  (review + tweak) [feat:xlite-20261018-fix-capture-hits-to-incapacitate-false-z] ---

# --- 27B-decomposed from roadmap [2026-10-18]: Fix misleading capture-fail message when captor is out of reach — scripts/battle/battle.gd (review + tweak) [feat:xlite-20261018-fix-misleading-capture-fail-message-when] ---

# --- 27B-decomposed from roadmap [2026-10-18]: Fix StatusModifiers.move_multiplier_percent ignoring Blind — scripts/units/status_modifier (review + tweak) [feat:xlite-20261018-fix-statusmodifiers-move-multiplier-perc] ---

# --- 27B-decomposed from roadmap [2026-10-18]: Delete ~20 dead TurnManager helpers — scripts/turn/turn_manager.gd:48-178 contains get_pha (review + tweak) [feat:xlite-20261018-delete-20-dead-turnmanager-helpers-scrip] ---

# --- 27B-decomposed from roadmap [2026-10-18]: Fix Overwatch.will_trigger missing exits-range case — `scripts/battle/overwatch.gd:7-17`:  (review + tweak) [feat:xlite-20261018-fix-overwatch-will-trigger-missing-exits] ---

# --- 27B-decomposed from roadmap [2026-10-18]: Delete Cover.hit_chance dead function — `scripts/battle/cover.gd:14-15` `hit_chance(base,  (review + tweak) [feat:xlite-20261018-delete-cover-hit-chance-dead-function-sc] ---

# --- 27B-decomposed from roadmap [2026-10-18]: Fix AoeTargeting.get_affected_cells out-of-bounds returns — `scripts/battle/aoe_targeting. (review + tweak) [feat:xlite-20261018-fix-aoetargeting-get-affected-cells-out-] ---

# --- 27B-decomposed from roadmap [2026-10-18]: Coerce codex seen load to dict — `scripts/codex/codex_manager.gd:135` reads `save_data.get (review + tweak) [feat:xlite-20261018-coerce-codex-seen-load-to-dict-scripts-c] ---

# --- 27B-decomposed from roadmap [2026-10-19]: Delete INERT LevelCurve class — `scripts/roster/level_curve.gd` (verified: parameterized X (review + tweak) [feat:xlite-20261019-delete-inert-levelcurve-class-scripts-ro] ---

# --- 27B-decomposed from roadmap [2026-10-20]: Dead code: delete `DamagePreview` class and its test — `scripts/battle/damage_preview.gd`  (review + tweak) [feat:xlite-20261020-dead-code-delete-damagepreview-class-and] ---

# --- 27B-decomposed from roadmap [2026-10-20]: Dead code: delete `LevelCurve` class and its test — `scripts/roster/level_curve.gd` (29 li (review + tweak) [feat:xlite-20261020-dead-code-delete-levelcurve-class-and-it] ---

# --- 27B-decomposed from roadmap [2026-10-20]: Fix ThreatPreview to use Chebyshev distance matching the targeting system — `scripts/battl (review + tweak) [feat:xlite-20261020-fix-threatpreview-to-use-chebyshev-dista] ---

# --- 27B-decomposed from roadmap [2026-10-20]: Fix StatusEffects.get_move_speed_multiplier returns 0.5 for stunned, contradicting StatusM (review + tweak) [feat:xlite-20261020-fix-statuseffects-get-move-speed-multipl] ---

# --- 27B-decomposed from roadmap [2026-10-20]: Fix SNIPER faction mapping wrong (mutant) contradicting the design doc — `scripts/battle/e (review + tweak) [feat:xlite-20261020-fix-sniper-faction-mapping-wrong-mutant-] ---

# --- 27B-decomposed from roadmap [2026-10-20]: Add charges field to Ability to close the API gap with AbilityStatsValidator and AbilityRe (review + tweak) [feat:xlite-20261020-add-charges-field-to-ability-to-close-th] ---

# --- 27B-decomposed from roadmap [2026-10-20]: Fix Damage.expected_damage floors armor-mitigated damage at 1 but mitigated() and resolve_ (review + tweak) [feat:xlite-20261020-fix-damage-expected-damage-floors-armor-] ---

# --- 27B-decomposed from roadmap [2026-10-20]: Delete dead `Resistance` class (no production callers) — `scripts/battle/resistance.gd` (c (review + tweak) [feat:xlite-20261020-delete-dead-resistance-class-no-producti] ---

# --- 27B-decomposed from roadmap [2026-10-20]: Silent DOT damage scaling bug — `scripts/battle/battle.gd:3356-3358` calls `DotDamage.tick (review + tweak) [feat:xlite-20261020-silent-dot-damage-scaling-bug-scripts-ba] ---

# --- 27B-decomposed from roadmap [2026-10-21]: Wire TechManager.research_tech to call CodexManager.mark_tech_seen — `CodexManager.mark_te (review + tweak) [feat:xlite-20261021-wire-techmanager-research-tech-to-call-c] ---

# --- 27B-decomposed from roadmap [2026-10-21]: Wire CodexManager.mark_faction_seen inside mark_enemy_seen to reveal faction codex entries (review + tweak) [feat:xlite-20261021-wire-codexmanager-mark-faction-seen-insi] ---

# --- 27B-decomposed from roadmap [2026-10-21]: Delete dead AchievementRegistry.on_faction_codex_update and on_faction_codex_complete — Bo (review + tweak) [feat:xlite-20261021-delete-dead-achievementregistry-on-facti] ---

# --- 27B-decomposed from roadmap [2026-10-21]: GridDistance.within_chebyshev convenience predicate — `scripts/grid/grid_distance.gd` (ver (review + tweak) [feat:xlite-20261021-griddistance-within-chebyshev-convenienc] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Persist and restore the colorblind and large-text accessibility prefs — today `scripts/mis (review + tweak) [feat:xlite-20261028-persist-and-restore-the-colorblind-and-l] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Add user UI-scale preference on top of the automatic factor — `scripts/ui/ui_scale.gd` onl (review + tweak) [feat:xlite-20261028-add-user-ui-scale-preference-on-top-of-t] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Mission validator: spawn and objective bounds checks — `scripts/mission/mission_validator. (review + tweak) [feat:xlite-20261028-mission-validator-spawn-and-objective-bo] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Music state to track mapping with crossfade in the SFX bus — `scripts/audio/audio_state.gd (review + tweak) [feat:xlite-20261028-music-state-to-track-mapping-with-crossf] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Export preset readiness check — `export_presets.cfg` defines presets "Windows Desktop", "m (review + tweak) [feat:xlite-20261028-export-preset-readiness-check-export-pre] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Campaign totals for the mission hub — `scripts/mission/mission_summary.gd` only has `Missi (review + tweak) [feat:xlite-20261028-campaign-totals-for-the-mission-hub-scri] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Codex search over seen entries — `scripts/codex/codex_manager.gd` has `mark_seen`/`has_see (review + tweak) [feat:xlite-20261028-codex-search-over-seen-entries-scripts-c] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Fix InputRemapper default "pause" binding pointing at a non-existent action — `scripts/set (review + tweak) [feat:xlite-20261101-fix-inputremapper-default-pause-binding-] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Coerce loaded bindings in InputRemapper.load_bindings — `scripts/settings/input_remapper.g (review + tweak) [feat:xlite-20261101-coerce-loaded-bindings-in-inputremapper-] ---

# --- 27B-decomposed from roadmap [2026-11-01]: ExportPresetCheck should match presets by their `platform=` line, not their display `name= (review + tweak) [feat:xlite-20261101-exportpresetcheck-should-match-presets-b] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Clamp and coerce ui_scale_pct when WindowConfig loads it — `scripts/settings/window_config (review + tweak) [feat:xlite-20261101-clamp-and-coerce-ui-scale-pct-when-windo] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Make WindowConfig._map_accessibility_prefs return strict booleans — `scripts/settings/wind (review + tweak) [feat:xlite-20261101-make-windowconfig-map-accessibility-pref] ---

# --- 27B-decomposed from roadmap [2026-11-01]: MissionSummary.aggregate must skip entries with non-numeric fields instead of crashing — ` (review + tweak) [feat:xlite-20261101-missionsummary-aggregate-must-skip-entri] ---

# --- 27B-decomposed from roadmap [2026-11-01]: UpkeepCost.deficit should clamp negative funds like amount_payable does — `scripts/roster/ (review + tweak) [feat:xlite-20261101-upkeepcost-deficit-should-clamp-negative] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Move enemy spawns off obstacle cells in missions 12 and 20 — a repo scan of `missions/*.tr (review + tweak) [feat:xlite-20261101-move-enemy-spawns-off-obstacle-cells-in-] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Move enemy spawns off obstacle cells in missions 24, 31 and 37 — `missions/mission_24.tres (review + tweak) [feat:xlite-20261101-move-enemy-spawns-off-obstacle-cells-in-] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Wire the bounds and obstacle validators into MissionData.is_valid — `scripts/mission/missi (review + tweak) [feat:xlite-20261101-wire-the-bounds-and-obstacle-validators-] ---

# --- 27B-decomposed from roadmap [2026-11-02]: WindowConfig load path re-breaks its own sanitizer: `int()` around the raw value and `bool (review + tweak) [feat:xlite-20261102-windowconfig-load-path-re-breaks-its-own] ---

# --- 27B-decomposed from roadmap [2026-11-02]: TutorialManager.has_seen_tutorial returns the raw Variant — `scripts/tutorial/tutorial_man (review + tweak) [feat:xlite-20261102-tutorialmanager-has-seen-tutorial-return] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Sanitize SfxBus volume and mute values loaded from the settings save — `scripts/audio/sfx_ (review + tweak) [feat:xlite-20261102-sanitize-sfxbus-volume-and-mute-values-l] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Make SfxBus use AudioState for music-state mapping and crossfade decisions — `scripts/audi (review + tweak) [feat:xlite-20261102-make-sfxbus-use-audiostate-for-music-sta] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Coerce string and bool fields when TechManager loads a tech save — `scripts/tech/tech_mana (review + tweak) [feat:xlite-20261102-coerce-string-and-bool-fields-when-techm] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Validate soldier name and class when RosterManager loads a roster save — `scripts/roster/r (review + tweak) [feat:xlite-20261102-validate-soldier-name-and-class-when-ros] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Enforce roster invariants at load: unique names, strict deployed flag, MAX_SQUAD cap — `sc (review + tweak) [feat:xlite-20261102-enforce-roster-invariants-at-load-unique] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Release readiness check that actually runs the release helpers — `scripts/release/export_p (review + tweak) [feat:xlite-20261102-release-readiness-check-that-actually-ru] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Mission validator: terrain cells must be inside the grid — `scripts/mission/mission_valida (review + tweak) [feat:xlite-20261102-mission-validator-terrain-cells-must-be-] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Mission validator: no duplicate or overlapping spawn cells — `scripts/mission/mission_vali (review + tweak) [feat:xlite-20261102-mission-validator-no-duplicate-or-overla] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Mission validator: objective cells must be reachable and parameters sane — `scripts/missio (review + tweak) [feat:xlite-20261102-mission-validator-objective-cells-must-b] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Show research materials on the mission hub status line — `scripts/mission/mission_hub.gd`  (review + tweak) [feat:xlite-20261102-show-research-materials-on-the-mission-h] ---

# --- 27B-decomposed from roadmap [2026-11-04]: MissionEditor load then save silently drops patrol routes, defend_until and directive — `s (review + tweak) [feat:xlite-20261104-missioneditor-load-then-save-silently-dr] ---

# --- 27B-decomposed from roadmap [2026-11-04]: MissionEditor dropdowns cannot represent Defend objective or the 9 non-wasteland/city them (review + tweak) [feat:xlite-20261104-missioneditor-dropdowns-cannot-represent] ---

# --- 27B-decomposed from roadmap [2026-11-04]: MissionEditor Save must refuse invalid missions and unsafe filenames — `scripts/tools/miss (review + tweak) [feat:xlite-20261104-missioneditor-save-must-refuse-invalid-m] ---

# --- 27B-decomposed from roadmap [2026-11-04]: SaveManager.list_saves lists quarantined .corrupt-<ts>.json files as real saves — `scripts (review + tweak) [feat:xlite-20261104-savemanager-list-saves-lists-quarantined] ---

# --- 27B-decomposed from roadmap [2026-11-04]: SaveManager load_save/delete_save/file_exists_for/quarantine accept path-traversal names — (review + tweak) [feat:xlite-20261104-savemanager-load-save-delete-save-file-e] ---

# --- 27B-decomposed from roadmap [2026-11-04]: SaveManager.save_save mutates the caller's Dictionary (adds save_version) — `scripts/save/ (review + tweak) [feat:xlite-20261104-savemanager-save-save-mutates-the-caller] ---

# --- 27B-decomposed from roadmap [2026-11-04]: InputRemapper accepts key names that resolve to no key and stores them as the binding — `s (review + tweak) [feat:xlite-20261104-inputremapper-accepts-key-names-that-res] ---

# --- 27B-decomposed from roadmap [2026-11-04]: BattleSaveCodec.validate checks types only, so out-of-range values pass and crash resume — (review + tweak) [feat:xlite-20261104-battlesavecodec-validate-checks-types-on] ---

# --- 27B-decomposed from roadmap [2026-11-04]: Apply the saved UI scale: WindowConfig stores ui_scale_pct but nothing ever uses it — `scr (review + tweak) [feat:xlite-20261104-apply-the-saved-ui-scale-windowconfig-st] ---

# --- 27B-decomposed from roadmap [2026-11-04]: CodexManager accepts arbitrary category strings and persists phantom categories — `scripts (review + tweak) [feat:xlite-20261104-codexmanager-accepts-arbitrary-category-] ---

# --- 27B-decomposed from roadmap [2026-11-04]: Back navigation: Escape / gamepad B (ui_cancel) does nothing on the Codex, Tech Tree, Cont (review + tweak) [feat:xlite-20261104-back-navigation-escape-gamepad-b-ui-canc] ---

# --- 27B-decomposed from roadmap [2026-11-04]: Tutorial overlay never takes keyboard/gamepad focus, so "Got it" cannot be pressed without (review + tweak) [feat:xlite-20261104-tutorial-overlay-never-takes-keyboard-ga] ---

# --- 27B-decomposed from roadmap [2026-11-04]: RosterManager.get_all_class_ids is a hardcoded [0..4] that can drift from CLASS_DEFS — `sc (review + tweak) [feat:xlite-20261104-rostermanager-get-all-class-ids-is-a-har] ---

# --- 27B-decomposed from roadmap [2026-11-06]: `RosterManager.normalize_loaded_entries` duplicate-rename can itself create a duplicate na (review + tweak) [feat:xlite-20261106-rostermanager-normalize-loaded-entries-d] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Benched survivors are never re-deployed, so a won mission can leave ZERO deployed soldiers (review + tweak) [feat:xlite-20261106-benched-survivors-are-never-re-deployed-] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Destructive one-click buttons have no confirmation: "Reset Techs" and slot "Delete" — `scr (review + tweak) [feat:xlite-20261106-destructive-one-click-buttons-have-no-co] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Tech tree Research button stays enabled when the player cannot afford the credits/material (review + tweak) [feat:xlite-20261106-tech-tree-research-button-stays-enabled-] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Pending promotions leak across slots: `load_slot` and `reset_roster` never clear `last_pro (review + tweak) [feat:xlite-20261106-pending-promotions-leak-across-slots-loa] ---

# --- 27B-decomposed from roadmap [2026-11-06]: No test guards that every enemy archetype is present in the roster/codex/faction tables (a (review + tweak) [feat:xlite-20261106-no-test-guards-that-every-enemy-archetyp] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Aspect threshold and letterbox-bar math is untested at its boundaries (mutation scan: `>=` (review + tweak) [feat:xlite-20261106-aspect-threshold-and-letterbox-bar-math-] ---

# --- 27B-decomposed from roadmap [2026-11-06]: CoverDegradation tier thresholds and the zero-max percent guard are untested at the bounda (review + tweak) [feat:xlite-20261106-coverdegradation-tier-thresholds-and-the] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Capture reach/fail-reason tests only ever put the captor at (0,0), so a sign flip in the C (review + tweak) [feat:xlite-20261106-capture-reach-fail-reason-tests-only-eve] ---

# --- 27B-decomposed from roadmap [2026-11-06]: InteriorDetector never seeds its flood from the right or bottom map border in any test (mu (review + tweak) [feat:xlite-20261106-interiordetector-never-seeds-its-flood-f] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Formation helpers are only tested with cells at/near the origin, and one test uses `Format (review + tweak) [feat:xlite-20261106-formation-helpers-are-only-tested-with-c] ---

# --- 27B-decomposed from roadmap [2026-11-06]: IsoGrid line-of-sight is only tested with axis-aligned and adjacent shots, and `IsoGrid._l (review + tweak) [feat:xlite-20261106-isogrid-line-of-sight-is-only-tested-wit] ---

# --- 27B-decomposed from roadmap [2026-11-06]: README claims no assets are needed and lists 3 of 9 autoloads — drift vs code — README.md  (review + tweak) [feat:xlite-20261106-readme-claims-no-assets-are-needed-and-l] ---

# --- 27B-decomposed from roadmap [2026-11-09]: BuildInfo.is_valid_version accepts a trailing newline, so a version of "1.2.3\n" is report (review + tweak) [feat:xlite-20261109-buildinfo-is-valid-version-accepts-a-tra] ---

# --- 27B-decomposed from roadmap [2026-11-09]: Objective.progress_ratio for ELIMINATE is not clamped, so a bad context gives a negative o (review + tweak) [feat:xlite-20261109-objective-progress-ratio-for-eliminate-i] ---

# --- 27B-decomposed from roadmap [2026-11-09]: WeightedPick lets a negative weight corrupt the buckets so later entries can never be pick (review + tweak) [feat:xlite-20261109-weightedpick-lets-a-negative-weight-corr] ---

# --- 27B-decomposed from roadmap [2026-11-09]: TurnSnapshot.capture crashes on a non-Dictionary entry instead of skipping it - `scripts/t (review + tweak) [feat:xlite-20261109-turnsnapshot-capture-crashes-on-a-non-di] ---

# --- 27B-decomposed from roadmap [2026-11-09]: ItchUploader.build_butler_command builds a butler push argv with an empty build path - `sc (review + tweak) [feat:xlite-20261109-itchuploader-build-butler-command-builds] ---

# --- 27B-decomposed from roadmap [2026-11-09]: StatusModifiers.get_move_speed_multiplier is order-dependent and ignores slowed, disagreei (review + tweak) [feat:xlite-20261109-statusmodifiers-get-move-speed-multiplie] ---

# --- 27B-decomposed from roadmap [2026-11-09]: SpiralCells.count_in_radius(-1) returns 1 while filled_area(center, -1) is empty - `script (review + tweak) [feat:xlite-20261109-spiralcells-count-in-radius-1-returns-1-] ---

# --- 27B-decomposed from roadmap [2026-11-09]: TouchSelect tie-break and threshold boundaries are untested (docs promise ties go to the l (review + tweak) [feat:xlite-20261109-touchselect-tie-break-and-threshold-boun] ---

# --- 27B-decomposed from roadmap [2026-11-09]: No test pins the hard-coded terrain ints in TileCost, Hazard and Destructible to MissionDa (review + tweak) [feat:xlite-20261109-no-test-pins-the-hard-coded-terrain-ints] ---

# --- 27B-decomposed from roadmap [2026-11-09]: No test checks that every achievement id the triggers can emit exists in AchievementRegist (review + tweak) [feat:xlite-20261109-no-test-checks-that-every-achievement-id] ---

# --- 27B-decomposed from roadmap [2026-11-09]: No test keeps SquadScore's hard-coded role names in sync with RosterManager.CLASS_DEFS - ` (review + tweak) [feat:xlite-20261109-no-test-keeps-squadscore-s-hard-coded-ro] ---

# --- 27B-decomposed from roadmap [2026-11-09]: ArmorPen.damage_reduced_percent hard-codes the valid directive range 0..4 with no test tie (review + tweak) [feat:xlite-20261109-armorpen-damage-reduced-percent-hard-cod] ---

# --- 27B-decomposed from roadmap [2026-11-09]: ObjectiveFailure's hard-coded objective constants are not tied to Objective's objective li (review + tweak) [feat:xlite-20261109-objectivefailure-s-hard-coded-objective-] ---

# --- 27B-decomposed from roadmap [2026-11-09]: Catapult range checks are only tested from the origin, so a sign flip in the Chebyshev dis (review + tweak) [feat:xlite-20261109-catapult-range-checks-are-only-tested-fr] ---

# --- 27B-decomposed from roadmap [2026-11-09]: Threat.nearest_target and count_in_range are only tested with the enemy at (0,0) - `script (review + tweak) [feat:xlite-20261109-threat-nearest-target-and-count-in-range] ---

# --- 27B-decomposed from roadmap [2026-11-09]: ExportPresetCheck is untested against Windows (CRLF) export_presets.cfg text - `scripts/re (review + tweak) [feat:xlite-20261109-exportpresetcheck-is-untested-against-wi] ---

# --- 27B-decomposed from roadmap [2026-11-10]: MissionData.first_invalid_reason never calls MissionValidator.terrain_cells_ok, so a missi (review + tweak) [feat:xlite-20261110-missiondata-first-invalid-reason-never-c] ---

# --- 27B-decomposed from roadmap [2026-11-10]: MissionValidator.objective_ok has no direct test, so the objective-type, SURVIVE turn-limi (review + tweak) [feat:xlite-20261110-missionvalidator-objective-ok-has-no-dir] ---

# --- 27B-decomposed from roadmap [2026-11-10]: Aoe.hit_percent_needed returns 0 ("no hit needed") for a negative shot count or negative p (review + tweak) [feat:xlite-20261110-aoe-hit-percent-needed-returns-0-no-hit-] ---

# --- 27B-decomposed from roadmap [2026-11-10]: ChainDamage.at_jump with a decay_percent above 100 flips the sign each hop and makes damag (review + tweak) [feat:xlite-20261110-chaindamage-at-jump-with-a-decay-percent] ---

# --- 27B-decomposed from roadmap [2026-11-10]: Damage.resolve gives a SHOTGUN attack extra damage when the target distance is below 1, so (review + tweak) [feat:xlite-20261110-damage-resolve-gives-a-shotgun-attack-ex] ---

# --- 27B-decomposed from roadmap [2026-11-10]: Ammo.shots_after_fire adds ammo back when called with a negative shot count - `scripts/bat (review + tweak) [feat:xlite-20261110-ammo-shots-after-fire-adds-ammo-back-whe] ---

# --- 27B-decomposed from roadmap [2026-11-10]: RangeFalloff.damage_at_range returns negative damage for a negative base while DamageFallo (review + tweak) [feat:xlite-20261110-rangefalloff-damage-at-range-returns-neg] ---

# --- 27B-decomposed from roadmap [2026-11-10]: DamageVariance.roll_percent_of_range returns NaN when the band is degenerate (max_val equa (review + tweak) [feat:xlite-20261110-damagevariance-roll-percent-of-range-ret] ---

# --- 27B-decomposed from roadmap [2026-11-10]: Capture.paralysis_percent returns a negative percent for negative paralysis - `scripts/bat (review + tweak) [feat:xlite-20261110-capture-paralysis-percent-returns-a-nega] ---

# --- 27B-decomposed from roadmap [2026-11-10]: StatGrowth.stat_at_level drops below the base stat for a level below 1 - `scripts/roster/s (review + tweak) [feat:xlite-20261110-statgrowth-stat-at-level-drops-below-the] ---

# --- 27B-decomposed from roadmap [2026-11-10]: CoverDegradation.durability_after_hits repairs cover when given a negative hit count or ne (review + tweak) [feat:xlite-20261110-coverdegradation-durability-after-hits-r] ---

# --- 27B-decomposed from roadmap [2026-11-10]: AimModifiers.height_bonus goes negative for a negative per_level or negative cap, turning  (review + tweak) [feat:xlite-20261110-aimmodifiers-height-bonus-goes-negative-] ---

# --- 27B-decomposed from roadmap [2026-11-10]: HeightDamage.total returns negative damage when the bonus percent is below -100 - `scripts (review + tweak) [feat:xlite-20261110-heightdamage-total-returns-negative-dama] ---

# --- 27B-decomposed from roadmap [2026-11-10]: AoeFalloff.damage_at increases damage with distance for a negative falloff_per_ring - `scr (review + tweak) [feat:xlite-20261110-aoefalloff-damage-at-increases-damage-wi] ---

# --- 27B-decomposed from roadmap [2026-11-10]: CritOdds.crit_damage returns negative damage for a negative multiplier percent - `scripts/ (review + tweak) [feat:xlite-20261110-critodds-crit-damage-returns-negative-da] ---

# --- 27B-decomposed from roadmap [2026-11-10]: TileCost.cost_for_terrain, the function every path-cost helper is built on, has no direct  (review + tweak) [feat:xlite-20261110-tilecost-cost-for-terrain-the-function-e] ---

# --- 27B-decomposed from roadmap [2026-11-10]: CameraInput.remap_touch_to_camera passes NaN straight through, so a degenerate pinch (two  (review + tweak) [feat:xlite-20261110-camerainput-remap-touch-to-camera-passes] ---

# --- 27B-decomposed from roadmap [2026-11-10]: `SafeArea.top_left`, `top_right` and `bottom_left` have no test - `scripts/ui/safe_area.gd (review + tweak) [feat:xlite-20261110-safearea-top-left-top-right-and-bottom-l] ---

# --- 27B-decomposed from roadmap [2026-11-10]: `Unit.portrait_path` is never tested - `scripts/units/unit.gd` `portrait_path(state := "id (review + tweak) [feat:xlite-20261110-unit-portrait-path-is-never-tested-scrip] ---

# --- 27B-decomposed from roadmap [2026-11-10]: `MissionPathMap.configure` has no test - `scripts/mission/mission_path_map.gd` `configure( (review + tweak) [feat:xlite-20261110-missionpathmap-configure-has-no-test-scr] ---

# --- 27B-decomposed from roadmap [2026-11-10]: `SteamManager.unlock_milestone` is untested - `scripts/integrations/steam_manager.gd` `unl (review + tweak) [feat:xlite-20261110-steammanager-unlock-milestone-is-unteste] ---

# --- 27B-decomposed from roadmap [2026-11-10]: `Unit.play_pose`, `play_attack` and `stand_up` have no tests of their guard and reset beha (review + tweak) [feat:xlite-20261110-unit-play-pose-play-attack-and-stand-up-] ---

# --- 27B-decomposed from roadmap [2026-11-10]: The Python mission-file helpers in `tools/tres_format.py` have no tests - `parse_vec_list` (review + tweak) [feat:xlite-20261110-the-python-mission-file-helpers-in-tools] ---

# --- 27B-decomposed from roadmap [2026-11-10]: `tres_format.assemble_tres` and `reachable_ok` have no tests - `tools/tres_format.py` `ass (review + tweak) [feat:xlite-20261110-tres-format-assemble-tres-and-reachable-] ---

# --- 27B-decomposed from roadmap [2026-11-12]: Add a codex entry filter and use it in the populate loops - add `static func entry_visible (review + tweak) [feat:xlite-20261112-add-a-codex-entry-filter-and-use-it-in-t] ---

# --- 27B-decomposed from roadmap [2026-11-12]: Add the codex search box - in `scripts/mission/codex_view.gd` add `var _search_box: LineEd (review + tweak) [feat:xlite-20261112-add-the-codex-search-box-in-scripts-miss] ---

# --- 27B-decomposed from roadmap [2026-11-12]: Show the match count while searching - in `scripts/mission/codex_view.gd` add `static func (review + tweak) [feat:xlite-20261112-show-the-match-count-while-searching-in-] ---

# --- 27B-decomposed from roadmap [2026-11-12]: Say when a codex search matches nothing - in `scripts/mission/codex_view.gd` add `static f (review + tweak) [feat:xlite-20261112-say-when-a-codex-search-matches-nothing-] ---

# --- 27B-decomposed from roadmap [2026-11-12]: Let the search also filter the tech rows - in the Tech loop of `_populate()` in `scripts/m (review + tweak) [feat:xlite-20261112-let-the-search-also-filter-the-tech-rows] ---

# --- 27B-decomposed from roadmap [2026-11-12]: Show a one-line summary under each used slot - in `scripts/mission/save_slot_select.gd` ad (review + tweak) [feat:xlite-20261112-show-a-one-line-summary-under-each-used-] ---

# --- 27B-decomposed from roadmap [2026-11-12]: Label an unreadable used slot - in `scripts/mission/save_slot_select.gd` add `static func  (review + tweak) [feat:xlite-20261112-label-an-unreadable-used-slot-in-scripts] ---

# --- 27B-decomposed from roadmap [2026-11-12]: Give the slot buttons descriptive tooltips - in `scripts/mission/save_slot_select.gd` add  (review + tweak) [feat:xlite-20261112-give-the-slot-buttons-descriptive-toolti] ---

# --- 27B-decomposed from roadmap [2026-11-12]: Start keyboard and gamepad focus on the first used slot - in `scripts/mission/save_slot_se (review + tweak) [feat:xlite-20261112-start-keyboard-and-gamepad-focus-on-the-] ---

# --- 27B-decomposed from roadmap [2026-11-12]: Show "Step N of M" on the tutorial overlay - in `scripts/tutorial/tutorial_manager.gd` add (review + tweak) [feat:xlite-20261112-show-step-n-of-m-on-the-tutorial-overlay] ---

# --- 27B-decomposed from roadmap [2026-11-12]: Add a Back button to the tutorial overlay - in `scripts/tutorial/tutorial_manager.gd` add  (review + tweak) [feat:xlite-20261112-add-a-back-button-to-the-tutorial-overla] ---

# --- 27B-decomposed from roadmap [2026-11-12]: Name the key or button for the step being taught - in `scripts/tutorial/tutorial_manager.g (review + tweak) [feat:xlite-20261112-name-the-key-or-button-for-the-step-bein] ---

# --- 27B-decomposed from roadmap [2026-11-12]: Show the volume slider as a percent - in `scripts/mission/mission_select.gd` add `static f (review + tweak) [feat:xlite-20261112-show-the-volume-slider-as-a-percent-in-s] ---

# --- 27B-decomposed from roadmap [2026-11-12]: Add a volume readout next to the slider - in `scripts/mission/mission_select.gd` add `stat (review + tweak) [feat:xlite-20261112-add-a-volume-readout-next-to-the-slider-] ---

# --- 27B-decomposed from roadmap [2026-11-12]: Name the Start, Back and trigger inputs in the glyph hints - in `scripts/ui/glyph_hints.gd (review + tweak) [feat:xlite-20261112-name-the-start-back-and-trigger-inputs-i] ---

# --- 27B-decomposed from roadmap [2026-11-12]: Take the controls help column headers from one function - in `scripts/ui/glyph_hints.gd` a (review + tweak) [feat:xlite-20261112-take-the-controls-help-column-headers-fr] ---

# --- 27B-decomposed from roadmap [2026-11-12]: Add plain tooltips to the settings widgets - in `scripts/mission/mission_select.gd` add `s (review + tweak) [feat:xlite-20261112-add-plain-tooltips-to-the-settings-widge] ---

# --- 27B-decomposed from roadmap [2026-11-12]: Add the Loc hook and use it in the save slot picker - create `scripts/ui/loc.gd` with `cla (review + tweak) [feat:xlite-20261112-add-the-loc-hook-and-use-it-in-the-save-] ---

# --- 27B-decomposed from roadmap [2026-11-14]: Route the controls help action labels through Loc - in the row loop of `_populate()` in `s (review + tweak) [feat:xlite-20261114-route-the-controls-help-action-labels-th] ---
- [ ] [T5] scripts/ui/controls_help.gd — Verify that the `ACTIONS` table still contains English fallback labels and that `Loc.t` is called with the correct key format `controls.action.<action>`. VERIFY: `grep -q 'controls.action.' scripts/ui/controls_help.gd && grep -q 'End Turn' scripts/ui/controls_help.gd`. (cat:godot; multifile:no) [feat:xlite-20261114-route-the-controls-help-action-labels-th]
- [ ] [T1] tests/test_controls_help_loc.gd — Create new test file that instantiates `res://scenes/controls_help.tscn` and asserts all original `ACTIONS` labels are visible when no translations exist. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_controls_help_loc.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20261114-route-the-controls-help-action-labels-th]
- [ ] [T2] tests/test_controls_help_loc.gd — Add a test case that registers a `Translation` for `controls.action.end_turn` with text `"Finish Turn"`, instantiates the view, asserts `"Finish Turn"` is present and `"End Turn"` is absent, then cleans up the translation. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_controls_help_loc.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20261114-route-the-controls-help-action-labels-th]
- [ ] [T4] tests/test_controls_help_loc.gd — Ensure the test file follows the same `Translation` setup and `remove_translation` cleanup pattern as `tests/test_loc.gd` to prevent state leakage between tests. VERIFY: `grep -q 'remove_translation' tests/test_controls_help_loc.gd && ~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_controls_help_loc.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20261114-route-the-controls-help-action-labels-th]
- [ ] [T3] scripts/ui/controls_help.gd — Ensure the `_add_row` method signature and internal logic remain unchanged, only the input label is modified to be localized. VERIFY: `grep -q '_add_row' scripts/ui/controls_help.gd && ~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_controls_help_loc.gd -gexit`. (cat:godot; multifile:no) [feat:xlite-20261114-route-the-controls-help-action-labels-th]
- [ ] [T4] tests/test_controls_help_loc.gd — Confirm the test correctly handles the case where `Loc.t` returns the fallback label when no translation is found, ensuring backward compatibility. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_controls_help_loc.gd,res://tests/test_controls_help.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20261114-route-the-controls-help-action-labels-th]
- [ ] [T5] tests/test_controls_help_loc.gd — Run the full test suite including existing `test_controls_help.gd` to ensure no regressions in the controls help UI behavior. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_controls_help_loc.gd,res://tests/test_controls_help.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20261114-route-the-controls-help-action-labels-th]

# --- 27B-decomposed from roadmap [2026-11-14]: Route codex enemy and soldier names through Loc - in `scripts/codex/codex_data.gd` make `e (review + tweak) [feat:xlite-20261114-route-codex-enemy-and-soldier-names-thro] ---
- [ ] [T1] scripts/codex/codex_data.gd — Modify `enemy_name(t)` to return `Loc.t("codex.enemy.%s.name" % enemy_key(t), _ENEMY_NAMES.get(t, "Grunt"))`. VERIFY: `grep -q 'Loc.t("codex.enemy.%s.name"' scripts/codex/codex_data.gd`. (cat:godot; multifile:no) [feat:xlite-20261114-route-codex-enemy-and-soldier-names-thro]
- [ ] [T1] scripts/codex/codex_data.gd — Modify `soldier_name(c)` to return `Loc.t("codex.soldier.%s.name" % soldier_key(c), _SOLDIER_NAMES.get(c, "Soldier"))` assuming `_SOLDIER_NAMES` is the existing table. VERIFY: `grep -q 'Loc.t("codex.soldier.%s.name"' scripts/codex/codex_data.gd`. (cat:godot; multifile:no) [feat:xlite-20261114-route-codex-enemy-and-soldier-names-thro]
- [ ] [T2] tests/test_codex_data_loc.gd — Create test file with `before_each`/`after_each` to manage `Loc` translation state, asserting `enemy_name(Unit.EnemyType.DRONE)` is `"Drone"` without translation. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_codex_data_loc.gd -gexit` passes. (cat:test; multifile:no) [feat:xlite-20261114-route-codex-enemy-and-soldier-names-thro]
- [ ] [T2] tests/test_codex_data_loc.gd — Add test case verifying all `CodexData.ENEMY_ORDER` entries return their original names when no translation is loaded. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_codex_data_loc.gd -gexit` passes. (cat:test; multifile:no) [feat:xlite-20261114-route-codex-enemy-and-soldier-names-thro]
- [ ] [T2] tests/test_codex_data_loc.gd — Add test case setting translation for `codex.enemy.drone.name` to `"Dron"` and asserting `enemy_name(Unit.EnemyType.DRONE)` returns `"Dron"`. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_codex_data_loc.gd -gexit` passes. (cat:test; multifile:no) [feat:xlite-20261114-route-codex-enemy-and-soldier-names-thro]
- [ ] [T2] tests/test_codex_data_loc.gd — Add test case asserting `display_name_for("enemies", "drone")` returns `"Dron"` when translation is active. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_codex_data_loc.gd -gexit` passes. (cat:test; multifile:no) [feat:xlite-20261114-route-codex-enemy-and-soldier-names-thro]
- [ ] [T3] tests/test_codex_data_loc.gd — Ensure cleanup in `after_each` restores `Loc` to default state to prevent test pollution. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_codex_data_loc.gd,res://tests/test_loc.gd -gexit` passes with 0 failures. (cat:test; multifile:no) [feat:xlite-20261114-route-codex-enemy-and-soldier-names-thro]

# --- 27B-decomposed from roadmap [2026-11-15]: Add a key extraction tool for the Loc calls - create `tools/extract_loc_keys.py` with `ext (review + tweak) [feat:xlite-20261115-add-a-key-extraction-tool-for-the-loc-ca] ---
- [ ] [T1] tools/extract_loc_keys.py — Add `extract_keys(text: str) -> list[tuple[str, str]]` that parses `Loc.t` and `Loc.tf` calls using a regex to capture the first two arguments, validates they are double-quoted string literals (handling escaped quotes), unescapes them, and returns the list of `(key, english)` tuples. VERIFY: `python3 -c "import sys; sys.path.insert(0, 'tools'); from extract_loc_keys import extract_keys; assert extract_keys('Loc.t(\"k1\", \"v1\")') == [('k1', 'v1')] and extract_keys('Loc.tf(\"k2\", \"v2\", [1])') == [('k2', 'v2')] and extract_keys('Loc.t(var, \"v3\")') == []"`. (cat:python; multifile:no) [feat:xlite-20261115-add-a-key-extraction-tool-for-the-loc-ca]
- [ ] [T1] tools/extract_loc_keys.py — Add `collect(root: str) -> list[tuple[str, str]]` that walks `root/scripts/**/*.gd` in sorted path order, calls `extract_keys` on each file's content, aggregates all pairs, removes duplicates, and returns the unique pairs sorted by key. VERIFY: `python3 -c "import sys; sys.path.insert(0, 'tools'); from extract_loc_keys import collect; import os; os.makedirs('tmp_test/scripts', exist_ok=True); open('tmp_test/scripts/a.gd','w').write('Loc.t(\"b\", \"B\")\nLoc.t(\"a\", \"A\")'); open('tmp_test/scripts/b.gd','w').write('Loc.t(\"a\", \"A\")\nLoc.t(\"c\", \"C\")'); assert collect('tmp_test') == [('a', 'A'), ('b', 'B'), ('c', 'C')]"`. (cat:python; multifile:no) [feat:xlite-20261115-add-a-key-extraction-tool-for-the-loc-ca]
- [ ] [T2] tools/tests/test_extract_loc_keys.py — Create the test file with `sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))` and add `test_extract_t_and_tf` which asserts that `extract_keys` correctly identifies and returns pairs for both `Loc.t` and `Loc.tf` calls. VERIFY: `python3 -m unittest tools.tests.test_extract_loc_keys.TestExtractLocKeys.test_extract_t_and_tf`. (cat:test; multifile:no) [feat:xlite-20261115-add-a-key-extraction-tool-for-the-loc-ca]
- [ ] [T3] tools/extract_loc_keys.py — Add `main()` that calls `collect('.')`, prints the header `keys,en`, and iterates over the results printing each pair as a CSV row using the `csv` module's `writer` with `sys.stdout`. VERIFY: `python3 tools/extract_loc_keys.py | head -1 | grep -q "keys,en"`. (cat:python; multifile:no) [feat:xlite-20261115-add-a-key-extraction-tool-for-the-loc-ca]
- [ ] [T2] tools/tests/test_extract_loc_keys.py — Add `test_duplicate_collapse_and_sort` which creates a temporary directory structure with multiple `.gd` files containing duplicate and unsorted keys, calls `collect`, and asserts the result is unique and sorted by key. VERIFY: `python3 -m unittest tools.tests.test_extract_loc_keys.TestExtractLocKeys.test_duplicate_collapse_and_sort`. (cat:test; multifile:no) [feat:xlite-20261115-add-a-key-extraction-tool-for-the-loc-ca]
- [ ] [T2] tools/tests/test_extract_loc_keys.py — Add `test_skip_variable_key` which asserts that `extract_keys` returns an empty list when the first argument of a `Loc.t` call is a variable (non-literal). VERIFY: `python3 -m unittest tools.tests.test_extract_loc_keys.TestExtractLocKeys.test_skip_variable_key`. (cat:test; multifile:no) [feat:xlite-20261115-add-a-key-extraction-tool-for-the-loc-ca]
- [ ] [T2] tools/tests/test_extract_loc_keys.py — Add `test_escaped_quote` which asserts that `extract_keys` correctly unescapes a backslash-escaped quote inside the string literal arguments. VERIFY: `python3 -m unittest tools.tests.test_extract_loc_keys.TestExtractLocKeys.test_escaped_quote`. (cat:test; multifile:no) [feat:xlite-20261115-add-a-key-extraction-tool-for-the-loc-ca]

# --- 27B-decomposed from roadmap [2026-11-15]: Keep each Loc key tied to one English text - create `tests/test_loc_keys_consistent.gd` (` (review + tweak) [feat:xlite-20261115-keep-each-loc-key-tied-to-one-english-te] ---
- [ ] [T1] tests/test_loc_keys_consistent.gd — Add `extends GutTest` and `_test_walk_scripts_dir()` that uses `DirAccess.open("res://scripts")` to recursively list all `.gd` files, reads each with `FileAccess.get_file_as_string`, and asserts the walk yields at least 50 files to prevent vacuous passes. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_loc_keys_consistent.gd -gexit` shows 1 passing test. (cat:test; multifile:no) [feat:xlite-20261115-keep-each-loc-key-tied-to-one-english-te]
- [ ] [T2] tests/test_loc_keys_consistent.gd — Add `_test_extract_loc_calls()` that defines `var rx: RegEx = RegEx.new()`, compiles pattern `Loc\.tf?\("([^"\\]+)",\s*"((?:[^"\\]|\\.)*)"`, and asserts it correctly extracts key `"ui.common.back"` and text `"Back"` from a sample string. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_loc_keys_consistent.gd -gexit` shows 2 passing tests. (cat:test; multifile:no) [feat:xlite-20261115-keep-each-loc-key-tied-to-one-english-te]
- [ ] [T3] tests/test_loc_keys_consistent.gd — Add `_test_build_key_map()` that iterates all `.gd` files in `res://scripts`, applies the regex to find `Loc.t`/`Loc.tf` calls, and builds a `Dictionary` mapping keys to their English text, asserting the map contains `"ui.common.back"`. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_loc_keys_consistent.gd -gexit` shows 3 passing tests. (cat:test; multifile:no) [feat:xlite-20261115-keep-each-loc-key-tied-to-one-english-te]
- [ ] [T4] tests/test_loc_keys_consistent.gd — Add `_test_no_duplicate_conflicts()` that iterates the built key map and fails with a readable message listing any key that appears with two different English texts, ensuring consistency across the codebase. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_loc_keys_consistent.gd -gexit` shows 4 passing tests. (cat:test; multifile:no) [feat:xlite-20261115-keep-each-loc-key-tied-to-one-english-te]
- [ ] [T5] tests/test_loc_keys_consistent.gd — Add `_test_required_keys_present()` that asserts the key map contains at least five keys starting with `"ui.save_slots."` and specifically includes `"ui.common.back"`, ensuring the save slot picker step's keys are detected. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_loc_keys_consistent.gd -gexit` shows 5 passing tests. (cat:test; multifile:no) [feat:xlite-20261115-keep-each-loc-key-tied-to-one-english-te]

# --- 27B-decomposed from roadmap [2026-11-15]: Print an ASCII preview of a generated mission - in `tools/mission_level_generator.py` add  (review + tweak) [feat:xlite-20261115-print-an-ascii-preview-of-a-generated-mi] ---
- [ ] [T1] tools/mission_level_generator.py — Add `render_ascii(mission: dict) -> str` function that iterates grid rows y=0..height-1 and cols x=0..width-1, mapping cell types to characters with priority: player_spawns (`P`), enemy_spawns (`E`), extraction_zone (`X`), doors (`D`), high_ground (`^`), obstacles (types 1,0,2,3 -> `!`, others -> `#`), roads (`=`), open (`.`). VERIFY: `python3 -c "import sys; sys.path.insert(0, 'tools'); import mission_level_generator as gen; m = gen.generate('city', (13, 13), 3, 2, 6, 'ELIMINATE', 7); out = gen.render_ascii(m); assert len(out.splitlines()) == 13 and all(len(l) == 13 for l in out.splitlines()); print('OK')"`. (cat:python; multifile:no) [feat:xlite-20261115-print-an-ascii-preview-of-a-generated-mi]
- [ ] [T3] tools/mission_level_generator.py — Modify `main()` to parse `--preview` flag and call `print(render_ascii(mission))` after the summary line, ensuring no file writes occur when `--write` is absent. VERIFY: `python3 tools/mission_level_generator.py --preview 2>&1 | grep -q "P\|E\|X\|#\|=\|\.\|!\|^"`. (cat:python; multifile:no) [feat:xlite-20261115-print-an-ascii-preview-of-a-generated-mi]
- [ ] [T2] tools/tests/test_mission_ascii.py — Create file with `sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))` and `import mission_level_generator as gen`; add `test_render_ascii_structure` asserting 13 rows of 13 chars for seed 7. VERIFY: `python3 -m unittest discover -s tools/tests -p test_mission_ascii.py`. (cat:test; multifile:no) [feat:xlite-20261115-print-an-ascii-preview-of-a-generated-mi]
- [ ] [T2] tools/tests/test_mission_ascii.py — Add `test_render_ascii_counts` asserting `P` count equals `len(mission['player_spawns'])`, `X` count is 1, `E` count equals `len(set(mission['enemy_spawns']))`, and `#` appears at least once. VERIFY: `python3 -m unittest discover -s tools/tests -p test_mission_ascii.py`. (cat:test; multifile:no) [feat:xlite-20261115-print-an-ascii-preview-of-a-generated-mi]
- [ ] [T2] tools/tests/test_mission_ascii.py — Add `test_render_ascii_deterministic` asserting `render_ascii(m1) == render_ascii(m2)` for two calls to `gen.generate` with same seed 7. VERIFY: `python3 -m unittest discover -s tools/tests -p test_mission_ascii.py`. (cat:test; multifile:no) [feat:xlite-20261115-print-an-ascii-preview-of-a-generated-mi]

# --- 27B-decomposed from roadmap [2026-11-15]: Give ASSASSINATE missions a real target - `generate()` in `tools/mission_level_generator.p (review + tweak) [feat:xlite-20261115-give-assassinate-missions-a-real-target-] ---
- [ ] [T3] tools/mission_level_generator.py — In `generate()`, add logic to set `mission["target_enemy_index"] = len(enemy_spawns) - 1`, update `enemy_types` at that index to `ELITE`, and clear `patrol_routes` at that index to `[]` when `objective == "ASSASSINATE"`. VERIFY: `python3 -m unittest discover -s tools/tests -p test_mission_assassinate.py` passes. (cat:python; multifile:no) [feat:xlite-20261115-give-assassinate-missions-a-real-target-]
- [ ] [T1] tools/tests/test_mission_assassinate.py — Add test class `TestAssassinateTarget` with method `test_seed7_target_index_valid` that generates a mission with seed 7 and asserts `mission["target_enemy_index"]` is within `range(len(mission["enemy_spawns"]))`. VERIFY: `python3 -m unittest tools.tests.test_mission_assassinate.TestAssassinateTarget.test_seed7_target_index_valid` fails before change. (cat:test; multifile:no) [feat:xlite-20261115-give-assassinate-missions-a-real-target-]
- [ ] [T1] tools/tests/test_mission_assassinate.py — Add method `test_seed7_target_is_elite` to `TestAssassinateTarget` that asserts the enemy at `target_enemy_index` has type `gen.ELITE`. VERIFY: `python3 -m unittest tools.tests.test_mission_assassinate.TestAssassinateTarget.test_seed7_target_is_elite` fails before change. (cat:test; multifile:no) [feat:xlite-20261115-give-assassinate-missions-a-real-target-]
- [ ] [T1] tools/tests/test_mission_assassinate.py — Add method `test_seed7_target_patrol_empty` to `TestAssassinateTarget` that asserts the patrol route for the target enemy is an empty list. VERIFY: `python3 -m unittest tools.tests.test_mission_assassinate.TestAssassinateTarget.test_seed7_target_patrol_empty` fails before change. (cat:test; multifile:no) [feat:xlite-20261115-give-assassinate-missions-a-real-target-]
- [ ] [T1] tools/tests/test_mission_assassinate.py — Add method `test_tres_contains_target_index` to `TestAssassinateTarget` that imports `tres_format as tf`, assembles the mission, and asserts the string contains `target_enemy_index = ` followed by the correct index. VERIFY: `python3 -m unittest tools.tests.test_mission_assassinate.TestAssassinateTarget.test_tres_contains_target_index` fails before change. (cat:test; multifile:no) [feat:xlite-20261115-give-assassinate-missions-a-real-target-]
- [ ] [T1] tools/tests/test_mission_assassinate.py — Add method `test_eliminate_has_no_target_index` to `TestAssassinateTarget` that generates an ELIMINATE mission with seed 7 and asserts `"target_enemy_index" not in mission`. VERIFY: `python3 -m unittest tools.tests.test_mission_assassinate.TestAssassinateTarget.test_eliminate_has_no_target_index` passes before change. (cat:test; multifile:no) [feat:xlite-20261115-give-assassinate-missions-a-real-target-]
