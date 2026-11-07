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
- [ ] [T3] scripts/ui/codex_view.gd — Add func _unhandled_input(event: InputEvent) -> void that calls get_viewport().set_input_as_handled() and _on_back_pressed() if BackNav.is_back(event) is true VERIFY: `grep -q "_unhandled_input" scripts/ui/codex_view.gd && grep -q "BackNav.is_back(" scripts/ui/codex_view.gd` (cat:godot; multifile:no) [feat:xlite-20261104-back-navigation-escape-gamepad-b-ui-canc]
- [ ] [T3] scripts/ui/tech_tree.gd — Add func _unhandled_input(event: InputEvent) -> void that calls get_viewport().set_input_as_handled() and _on_back_pressed() if BackNav.is_back(event) is true VERIFY: `grep -q "_unhandled_input" scripts/ui/tech_tree.gd && grep -q "BackNav.is_back(" scripts/ui/tech_tree.gd` (cat:godot; multifile:no) [feat:xlite-20261104-back-navigation-escape-gamepad-b-ui-canc]
- [ ] [T3] scripts/ui/roster_view.gd — Add func _unhandled_input(event: InputEvent) -> void that calls get_viewport().set_input_as_handled() and _on_back_pressed() if BackNav.is_back(event) is true VERIFY: `grep -q "_unhandled_input" scripts/ui/roster_view.gd && grep -q "BackNav.is_back(" scripts/ui/roster_view.gd` (cat:godot; multifile:no) [feat:xlite-20261104-back-navigation-escape-gamepad-b-ui-canc]
- [ ] [T3] scripts/ui/controls_help.gd — Add func _unhandled_input(event: InputEvent) -> void that calls get_viewport().set_input_as_handled() and _on_back_pressed() if BackNav.is_back(event) is true VERIFY: `grep -q "_unhandled_input" scripts/ui/controls_help.gd && grep -q "BackNav.is_back(" scripts/ui/controls_help.gd` (cat:godot; multifile:no) [feat:xlite-20261104-back-navigation-escape-gamepad-b-ui-canc]
- [ ] [T2] tests/test_back_nav.gd — Add test_source_scan_contains_back_nav_usage that uses FileAccess to read codex_view.gd, tech_tree.gd, roster_view.gd, and controls_help.gd and asserts each contains the string "BackNav.is_back(" VERIFY: ~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_back_nav.gd -gexit (cat:test; multifile:no) [feat:xlite-20261104-back-navigation-escape-gamepad-b-ui-canc]

# --- 27B-decomposed from roadmap [2026-11-04]: Tutorial overlay never takes keyboard/gamepad focus, so "Got it" cannot be pressed without (review + tweak) [feat:xlite-20261104-tutorial-overlay-never-takes-keyboard-ga] ---
- [ ] [T1] scripts/tutorial/tutorial_overlay.gd — Add `_next_button.grab_focus.call_deferred()` at the end of `setup()`. VERIFY: `grep -q "_next_button.grab_focus.call_deferred" scripts/tutorial/tutorial_overlay.gd` (cat:godot; multifile:no) [feat:xlite-20261104-tutorial-overlay-never-takes-keyboard-ga]
- [ ] [T2] scripts/tutorial/tutorial_overlay.gd — Add `_next_button.grab_focus.call_deferred()` inside `_refresh_step()` after text updates. VERIFY: `grep -q "_next_button.grab_focus.call_deferred" scripts/tutorial/tutorial_overlay.gd | wc -l | grep -q 2` (cat:godot; multifile:no) [feat:xlite-20261104-tutorial-overlay-never-takes-keyboard-ga]
- [ ] [T3] tests/test_tutorial_overlay_focus.gd — Create test file with `test_initial_focus_grabbed` that instantiates TutorialOverlay, calls setup({}), awaits frame, and asserts `_next_button.has_focus()`. VERIFY: ~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_tutorial_overlay_focus.gd -gexit. (cat:test; multifile:no) [feat:xlite-20261104-tutorial-overlay-never-takes-keyboard-ga]
- [ ] [T4] tests/test_tutorial_overlay_focus.gd — Add `test_focus_retained_after_next` that starts tutorial, presses next once, and asserts focus remains on `_next_button`. VERIFY: ~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_tutorial_overlay_focus.gd -gexit. (cat:test; multifile:no) [feat:xlite-20261104-tutorial-overlay-never-takes-keyboard-ga]
- [ ] [T5] tests/test_tutorial_overlay_focus.gd — Add `after_each` cleanup to call `TutorialManager.finish()` and delete tutorial settings save to prevent state leakage. VERIFY: `grep -q "TutorialManager.finish" tests/test_tutorial_overlay_focus.gd` (cat:test; multifile:no) [feat:xlite-20261104-tutorial-overlay-never-takes-keyboard-ga]

# --- 27B-decomposed from roadmap [2026-11-04]: RosterManager.get_all_class_ids is a hardcoded [0..4] that can drift from CLASS_DEFS — `sc (review + tweak) [feat:xlite-20261104-rostermanager-get-all-class-ids-is-a-har] ---
- [ ] [T1] tests/test_roster_class_ids.gd — Add GUT test case asserting `RosterManager.get_all_class_ids()` equals `RosterManager.CLASS_DEFS.keys()`. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_roster_class_ids.gd -gexit` (cat:test; multifile:no) [feat:xlite-20261104-rostermanager-get-all-class-ids-is-a-har]
- [ ] [T1] tests/test_roster_class_ids.gd — Add GUT test case iterating `Unit.PlayerClass.values()` and asserting each value is in `RosterManager.CLASS_DEFS.keys()`. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_roster_class_ids.gd -gexit` (cat:test; multifile:no) [feat:xlite-20261104-rostermanager-get-all-class-ids-is-a-har]
- [ ] [T1] tests/test_roster_class_ids.gd — Add GUT test case asserting `RosterManager.sanitize_player_class(4)` returns 4, `(5)` returns 0, and `(-1)` returns 0. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_roster_class_ids.gd -gexit` (cat:test; multifile:no) [feat:xlite-20261104-rostermanager-get-all-class-ids-is-a-har]
- [ ] [T3] scripts/roster/roster_manager.gd — Modify `get_all_class_ids()` to return `CLASS_DEFS.keys()` instead of hardcoded `[0, 1, 2, 3, 4]`. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_roster_class_ids.gd -gexit` (cat:godot; multifile:no) [feat:xlite-20261104-rostermanager-get-all-class-ids-is-a-har]

# --- 27B-decomposed from roadmap [2026-11-06]: `RosterManager.normalize_loaded_entries` duplicate-rename can itself create a duplicate na (review + tweak) [feat:xlite-20261106-rostermanager-normalize-loaded-entries-d] ---
- [ ] [T1] tests/test_roster_normalize_collision.gd — Add GutTest file with `test_duplicate_rename_collision` verifying `["A","A","A-2"]` normalizes to `["A","A-3","A-2"]`. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_roster_normalize_collision.gd -gexit` shows 1 failing test. (cat:test; multifile:no) [feat:xlite-20261106-rostermanager-normalize-loaded-entries-d]
- [ ] [T2] scripts/roster/roster_manager.gd — Modify `normalize_loaded_entries` to build a `used` Dictionary of all sanitized names in a first pass, then in the second pass loop `n` upward from the counter until `"%s-%d" % [name, n]` is not in `used` before assigning and adding to `used`. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_roster_normalize_collision.gd -gexit` shows 0 failing tests for the collision case. (cat:godot; multifile:no) [feat:xlite-20261106-rostermanager-normalize-loaded-entries-d]
- [ ] [T3] tests/test_roster_normalize_collision.gd — Add `test_uniqueness_guarantee` verifying that for input `["A","A","A","A-2","A-3"]`, the resulting names form a set of the same size as the list (checked via Dictionary). VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_roster_normalize_collision.gd -gexit` shows 0 failing tests. (cat:test; multifile:no) [feat:xlite-20261106-rostermanager-normalize-loaded-entries-d]
- [ ] [T4] tests/test_roster_normalize_collision.gd — Add `test_original_vega_case` verifying that `["Vega","Vega","Vega"]` still normalizes to `["Vega","Vega-2","Vega-3"]`. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_roster_normalize_collision.gd -gexit` shows 0 failing tests. (cat:test; multifile:no) [feat:xlite-20261106-rostermanager-normalize-loaded-entries-d]
- [ ] [T5] tests/test_roster_normalize_collision.gd — Add `test_deployed_capping_unchanged` verifying that the `deployed` capping logic in `normalize_loaded_entries` remains unchanged for inputs with deployed flags. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_roster_normalize_collision.gd -gexit` shows 0 failing tests. (cat:test; multifile:no) [feat:xlite-20261106-rostermanager-normalize-loaded-entries-d]

# --- 27B-decomposed from roadmap [2026-11-06]: Benched survivors are never re-deployed, so a won mission can leave ZERO deployed soldiers (review + tweak) [feat:xlite-20261106-benched-survivors-are-never-re-deployed-] ---
- [ ] [T1] scripts/roster/roster_manager.gd — Add `static func _ensure_squad_deployed()` that marks the first `MAX_SQUAD` entries as deployed if `_entries` is non-empty and `get_deployed_count() == 0`, then calls `_save_roster()`. VERIFY: `grep -q "func _ensure_squad_deployed" scripts/roster/roster_manager.gd`. (cat:godot; multifile:no) [feat:xlite-20261106-benched-survivors-are-never-re-deployed-]
- [ ] [T3] scripts/roster/roster_manager.gd — Call `_ensure_squad_deployed()` at the end of `sync_from_battle` to prevent zero-deployed states after a battle. VERIFY: `grep -A 5 "func sync_from_battle" scripts/roster/roster_manager.gd | grep -q "_ensure_squad_deployed"`. (cat:godot; multifile:no) [feat:xlite-20261106-benched-survivors-are-never-re-deployed-]
- [ ] [T1] scripts/mission/roster_view.gd — Add `static func empty_squad_warning(deployed: int, total: int) -> String` returning the warning message only when `total > 0 and deployed == 0`, else "". VERIFY: `grep -q "func empty_squad_warning" scripts/mission/roster_view.gd`. (cat:godot; multifile:no) [feat:xlite-20261106-benched-survivors-are-never-re-deployed-]
- [ ] [T3] scripts/mission/roster_view.gd — Display the result of `empty_squad_warning` as an orange Label in `_refresh()` next to the existing no-medic warning. VERIFY: `grep -q "empty_squad_warning" scripts/mission/roster_view.gd`. (cat:godot; multifile:no) [feat:xlite-20261106-benched-survivors-are-never-re-deployed-]
- [ ] [T2] tests/test_roster_empty_squad.gd — Create test file with `test_sync_from_battle_restores_deployed` verifying that syncing with empty fallen list restores deployment count to 2 after all are benched. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_roster_empty_squad.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20261106-benched-survivors-are-never-re-deployed-]
- [ ] [T2] tests/test_roster_empty_squad.gd — Add `test_sync_from_battle_with_fallen_restores_survivors` verifying that with 6 soldiers and 4 fallen, the 2 survivors become deployed. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_roster_empty_squad.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20261106-benched-survivors-are-never-re-deployed-]
- [ ] [T2] tests/test_roster_empty_squad.gd — Add `test_sync_from_battle_preserves_existing_deployment` verifying that a squad with 1 deployed soldier remains unchanged after sync. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_roster_empty_squad.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20261106-benched-survivors-are-never-re-deployed-]
- [ ] [T2] tests/test_roster_empty_squad.gd — Add `test_sync_from_battle_empty_roster_no_error` verifying that syncing with an empty roster does not crash or change state. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_roster_empty_squad.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20261106-benched-survivors-are-never-re-deployed-]
- [ ] [T2] tests/test_roster_empty_squad.gd — Add `test_empty_squad_warning_logic` verifying `RosterView.empty_squad_warning(0, 3) != ""`, `(2, 3) == ""`, and `(0, 0) == ""`. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_roster_empty_squad.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20261106-benched-survivors-are-never-re-deployed-]

# --- 27B-decomposed from roadmap [2026-11-06]: Destructive one-click buttons have no confirmation: "Reset Techs" and slot "Delete" — `scr (review + tweak) [feat:xlite-20261106-destructive-one-click-buttons-have-no-co] ---
- [ ] [T1] scripts/ui/confirm_gate.gd — Add `class_name ConfirmGate`, `extends RefCounted`, `var armed_key: String = ""`, `func press(key: String) -> bool` (returns true only if `key == armed_key` then disarms, else arms and returns false), `func disarm() -> void`, and `static func label_for(base: String, armed: bool) -> String`. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_confirm_gate.gd -gexit` (cat:godot; multifile:no) [feat:xlite-20261106-destructive-one-click-buttons-have-no-co]
- [ ] [T2] tests/test_confirm_gate.gd — Add GUT test file verifying `press("slot1")` is false then true, third press is false, `press("slot1")` then `press("slot2")` results in `armed_key == "slot2"`, `disarm()` clears state, and `label_for` outputs correct strings. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_confirm_gate.gd -gexit` (cat:test; multifile:no) [feat:xlite-20261106-destructive-one-click-buttons-have-no-co]
- [ ] [T3] scripts/mission/tech_tree.gd — Add `var _reset_gate := ConfirmGate.new()`, modify `_on_reset_pressed()` to arm gate and update button text on first press, call `TechManager.reset_techs()` only on second press, and reset button text after action. VERIFY: `grep -q "ConfirmGate" scripts/mission/tech_tree.gd` (cat:godot; multifile:no) [feat:xlite-20261106-destructive-one-click-buttons-have-no-co]
- [ ] [T4] scripts/mission/save_slot_select.gd — Add `var _delete_gate := ConfirmGate.new()`, modify `_on_slot_deleted(slot_name)` to arm gate with `slot_name` and update button label on first press, delete slot only on confirming press, and ensure `_refresh_slots()` re-labels armed row's Delete button. VERIFY: `grep -q "ConfirmGate" scripts/mission/save_slot_select.gd` (cat:godot; multifile:no) [feat:xlite-20261106-destructive-one-click-buttons-have-no-co]
- [ ] [T5] tests/test_confirm_gate.gd — Add source-scan tests using `FileAccess.get_file_as_string` to verify `scripts/mission/tech_tree.gd` and `scripts/mission/save_slot_select.gd` both contain the string "ConfirmGate". VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_confirm_gate.gd -gexit` (cat:test; multifile:no) [feat:xlite-20261106-destructive-one-click-buttons-have-no-co]

# --- 27B-decomposed from roadmap [2026-11-06]: Tech tree Research button stays enabled when the player cannot afford the credits/material (review + tweak) [feat:xlite-20261106-tech-tree-research-button-stays-enabled-] ---
- [ ] [T1] scripts/mission/tech_tree.gd — Add `static func can_afford(credits: int, materials: int, credit_cost: int, material_cost: int) -> bool` returning `credits >= credit_cost and materials >= material_cost`. VERIFY: `grep -q "static func can_afford" scripts/mission/tech_tree.gd` (cat:godot; multifile:no) [feat:xlite-20261106-tech-tree-research-button-stays-enabled-]
- [ ] [T1] scripts/mission/tech_tree.gd — Add `static func shortfall_text(credits: int, materials: int, credit_cost: int, material_cost: int) -> String` returning "" if affordable, else "need N cr", "need N mat", or "need N cr, N mat" based on deficits. VERIFY: `grep -q "static func shortfall_text" scripts/mission/tech_tree.gd` (cat:godot; multifile:no) [feat:xlite-20261106-tech-tree-research-button-stays-enabled-]
- [ ] [T2] tests/test_tech_tree_afford.gd — Create test file preloading `res://scripts/mission/tech_tree.gd` and asserting `can_afford(100, 2, 100, 2)` is true, `(99, 2, 100, 2)` is false, `(100, 1, 100, 2)` is false, and `(0, 0, 0, 0)` is true. VERIFY: ~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_tech_tree_afford.gd -gexit. (cat:test; multifile:no) [feat:xlite-20261106-tech-tree-research-button-stays-enabled-]
- [ ] [T2] tests/test_tech_tree_afford.gd — Add assertions for `shortfall_text`: `(50, 5, 80, 1)` equals "need 30 cr", `(100, 0, 80, 2)` equals "need 2 mat", `(10, 0, 80, 2)` equals "need 70 cr, 2 mat", and `(100, 5, 80, 2)` equals "". VERIFY: ~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_tech_tree_afford.gd -gexit. (cat:test; multifile:no) [feat:xlite-20261106-tech-tree-research-button-stays-enabled-]
- [ ] [T3] scripts/mission/tech_tree.gd — Modify `_populate_techs()` to set `button.disabled = not (TechManager.can_research(...) and can_afford(...))` and append `shortfall_text(...)` to the button label if non-empty. VERIFY: `grep -q "can_afford" scripts/mission/tech_tree.gd && grep -q "shortfall_text" scripts/mission/tech_tree.gd` (cat:godot; multifile:no) [feat:xlite-20261106-tech-tree-research-button-stays-enabled-]
- [ ] [T3] scripts/mission/tech_tree.gd — Modify `_on_research_pressed()` to check `can_afford(...)` instead of inline credit/material comparisons and return early if false. VERIFY: `grep -q "can_afford" scripts/mission/tech_tree.gd && ! grep -q "get_credits() >= cost" scripts/mission/tech_tree.gd` (cat:godot; multifile:no) [feat:xlite-20261106-tech-tree-research-button-stays-enabled-]

# --- 27B-decomposed from roadmap [2026-11-06]: Pending promotions leak across slots: `load_slot` and `reset_roster` never clear `last_pro (review + tweak) [feat:xlite-20261106-pending-promotions-leak-across-slots-loa] ---
- [ ] [T1] tests/test_roster_promotions_reset.gd — Add GUT test case `test_load_slot_clears_last_promotions` that sets `RosterManager.last_promotions = [{"name": "X", "from": "Rookie", "to": "Private"}]`, calls `RosterManager.load_slot("zz_promo")`, asserts `RosterManager.take_promotions().is_empty()`, and cleans up with `RosterManager.load_slot("")` and `SaveManager.delete_save("zz_promo_roster")`. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_roster_promotions_reset.gd -gexit` shows 1 failing test (before fix). (cat:test; multifile:no) [feat:xlite-20261106-pending-promotions-leak-across-slots-loa]
- [ ] [T1] tests/test_roster_promotions_reset.gd — Add GUT test case `test_reset_roster_clears_last_promotions` that sets `RosterManager.last_promotions = [{"name": "Y", "from": "Private", "to": "Corporal"}]`, calls `RosterManager.reset_roster()`, asserts `RosterManager.take_promotions().is_empty()`, and cleans up with `RosterManager.load_slot("")`. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_roster_promotions_reset.gd -gexit` shows 1 failing test (before fix). (cat:test; multifile:no) [feat:xlite-20261106-pending-promotions-leak-across-slots-loa]
- [ ] [T3] scripts/roster/roster_manager.gd — Insert `last_promotions.clear()` at the end of the `load_slot()` function body, after `_missions_completed` is cleared. VERIFY: `grep -n "last_promotions.clear()" scripts/roster/roster_manager.gd | grep -A1 "load_slot"` confirms presence in `load_slot` context. (cat:godot; multifile:no) [feat:xlite-20261106-pending-promotions-leak-across-slots-loa]
- [ ] [T3] scripts/roster/roster_manager.gd — Insert `last_promotions.clear()` at the end of the `reset_roster()` function body, after `_missions_completed` is cleared. VERIFY: `grep -n "last_promotions.clear()" scripts/roster/roster_manager.gd | grep -A1 "reset_roster"` confirms presence in `reset_roster` context. (cat:godot; multifile:no) [feat:xlite-20261106-pending-promotions-leak-across-slots-loa]
- [ ] [T2] tests/test_roster_promotions_reset.gd — Verify both test cases pass by running the full test file. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_roster_promotions_reset.gd -gexit` shows 0 failing tests in raw totals. (cat:test; multifile:no) [feat:xlite-20261106-pending-promotions-leak-across-slots-loa]

# --- 27B-decomposed from roadmap [2026-11-06]: No test guards that every enemy archetype is present in the roster/codex/faction tables (a (review + tweak) [feat:xlite-20261106-no-test-guards-that-every-enemy-archetyp] ---
- [ ] [T1] tests/test_enemy_tables_in_sync.gd — Add `extends GutTest` class with `before_each` initializing a fresh `Unit` instance and `after_each` calling `queue_free()` on it. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_enemy_tables_in_sync.gd -gexit` runs without parse errors. (cat:test; multifile:no) [feat:xlite-20261106-no-test-guards-that-every-enemy-archetyp]
- [ ] [T2] tests/test_enemy_tables_in_sync.gd — Add test `test_roster_captured_class_coverage` that loops `Unit.EnemyType.values()`, configures a unit, and asserts `RosterManager.CAPTURED_CLASS.has(u.display_name())` is true. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_enemy_tables_in_sync.gd -gexit` passes this specific test. (cat:test; multifile:no) [feat:xlite-20261106-no-test-guards-that-every-enemy-archetyp]
- [ ] [T3] tests/test_enemy_tables_in_sync.gd — Add test `test_roster_class_defs_validity` that loops `Unit.EnemyType.values()`, configures a unit, gets the class from `RosterManager.CAPTURED_CLASS`, and asserts `RosterManager.CLASS_DEFS.has(class_name)` is true. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_enemy_tables_in_sync.gd -gexit` passes this specific test. (cat:test; multifile:no) [feat:xlite-20261106-no-test-guards-that-every-enemy-archetyp]
- [ ] [T4] tests/test_enemy_tables_in_sync.gd — Add test `test_codex_name_matches_display` that loops `Unit.EnemyType.values()`, configures a unit, and asserts `CodexData.enemy_name(t) == u.display_name()`. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_enemy_tables_in_sync.gd -gexit` passes this specific test. (cat:test; multifile:no) [feat:xlite-20261106-no-test-guards-that-every-enemy-archetyp]
- [ ] [T5] tests/test_enemy_tables_in_sync.gd — Add test `test_faction_map_no_unknowns` that loops `Unit.EnemyType.values()`, configures a unit, and asserts `EnemyFactionMap.faction_for(t) != "unknown"`. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_enemy_tables_in_sync.gd -gexit` passes this specific test. (cat:test; multifile:no) [feat:xlite-20261106-no-test-guards-that-every-enemy-archetyp]

# --- 27B-decomposed from roadmap [2026-11-06]: Aspect threshold and letterbox-bar math is untested at its boundaries (mutation scan: `>=` (review + tweak) [feat:xlite-20261106-aspect-threshold-and-letterbox-bar-math-] ---
- [ ] [T1] tests/test_aspect.gd — Add test case asserting `classify(Vector2(2000, 1000)) == "ultrawide"` to verify the >= 2.0 boundary. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_aspect.gd -gexit` (cat:test; multifile:no) [feat:xlite-20261106-aspect-threshold-and-letterbox-bar-math-]
- [ ] [T1] tests/test_aspect.gd — Add test case asserting `classify(Vector2(1500, 1000)) == "wide"` to verify the >= 1.5 boundary. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_aspect.gd -gexit` (cat:test; multifile:no) [feat:xlite-20261106-aspect-threshold-and-letterbox-bar-math-]
- [ ] [T1] tests/test_aspect.gd — Add test case asserting `classify(Vector2(900, 1000)) == "standard"` to verify the >= 0.9 boundary. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_aspect.gd -gexit` (cat:test; multifile:no) [feat:xlite-20261106-aspect-threshold-and-letterbox-bar-math-]
- [ ] [T1] tests/test_aspect.gd — Add test case asserting `classify(Vector2(899, 1000)) == "tall"` to verify the < 0.9 boundary. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_aspect.gd -gexit` (cat:test; multifile:no) [feat:xlite-20261106-aspect-threshold-and-letterbox-bar-math-]
- [ ] [T1] tests/test_aspect.gd — Add test case asserting `letterbox_bars(Vector2(2560, 1080), 16.0 / 9.0)` has `x` almost 320.0 and `y == 0.0`. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_aspect.gd -gexit` (cat:test; multifile:no) [feat:xlite-20261106-aspect-threshold-and-letterbox-bar-math-]
- [ ] [T1] tests/test_aspect.gd — Add test case asserting `letterbox_bars(Vector2(1024, 768), 16.0 / 9.0)` has `x == 0.0` and `y` almost 96.0. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_aspect.gd -gexit` (cat:test; multifile:no) [feat:xlite-20261106-aspect-threshold-and-letterbox-bar-math-]
- [ ] [T1] tests/test_aspect.gd — Add test case asserting `letterbox_bars(Vector2(0, 100), 1.0)` returns `Vector2.ZERO`. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_aspect.gd -gexit` (cat:test; multifile:no) [feat:xlite-20261106-aspect-threshold-and-letterbox-bar-math-]
- [ ] [T1] tests/test_aspect.gd — Add test case asserting `letterbox_bars(Vector2(100, 0), 1.0)` returns `Vector2.ZERO`. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_aspect.gd -gexit` (cat:test; multifile:no) [feat:xlite-20261106-aspect-threshold-and-letterbox-bar-math-]

# --- 27B-decomposed from roadmap [2026-11-06]: CoverDegradation tier thresholds and the zero-max percent guard are untested at the bounda (review + tweak) [feat:xlite-20261106-coverdegradation-tier-thresholds-and-the] ---
- [ ] [T1] tests/test_cover_degradation.gd — Add test case asserting `tier_for_durability(75, 100) == 2` to verify the inclusive lower bound of tier 2. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_cover_degradation.gd -gexit` (cat:test; multifile:no) [feat:xlite-20261106-coverdegradation-tier-thresholds-and-the]
- [ ] [T1] tests/test_cover_degradation.gd — Add test case asserting `tier_for_durability(74, 100) == 1` to verify the exclusive upper bound of tier 2. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_cover_degradation.gd -gexit` (cat:test; multifile:no) [feat:xlite-20261106-coverdegradation-tier-thresholds-and-the]
- [ ] [T1] tests/test_cover_degradation.gd — Add test case asserting `tier_for_durability(25, 100) == 1` to verify the inclusive lower bound of tier 1. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_cover_degradation.gd -gexit` (cat:test; multifile:no) [feat:xlite-20261106-coverdegradation-tier-thresholds-and-the]
- [ ] [T1] tests/test_cover_degradation.gd — Add test case asserting `tier_for_durability(24, 100) == 0` to verify the exclusive upper bound of tier 1. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_cover_degradation.gd -gexit` (cat:test; multifile:no) [feat:xlite-20261106-coverdegradation-tier-thresholds-and-the]
- [ ] [T1] tests/test_cover_degradation.gd — Add test case asserting `tier_for_durability(100, 100) == 2` to verify the maximum durability boundary. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_cover_degradation.gd -gexit` (cat:test; multifile:no) [feat:xlite-20261106-coverdegradation-tier-thresholds-and-the]
- [ ] [T1] tests/test_cover_degradation.gd — Add test case asserting `tier_for_durability(-5, 100) == 0` to verify negative durability clamps to tier 0. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_cover_degradation.gd -gexit` (cat:test; multifile:no) [feat:xlite-20261106-coverdegradation-tier-thresholds-and-the]
- [ ] [T1] tests/test_cover_degradation_percent.gd — Add test case asserting `durability_percent(5, 0) == 0` to verify the zero-max durability guard prevents division by zero. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_cover_degradation_percent.gd -gexit` (cat:test; multifile:no) [feat:xlite-20261106-coverdegradation-tier-thresholds-and-the]
- [ ] [T1] tests/test_cover_degradation_percent.gd — Add test case asserting `durability_percent(0, 0) == 0` to verify the zero-max durability guard with zero current durability. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_cover_degradation_percent.gd -gexit` (cat:test; multifile:no) [feat:xlite-20261106-coverdegradation-tier-thresholds-and-the]
- [ ] [T1] tests/test_cover_degradation_percent.gd — Add test case asserting `durability_percent(150, 100) == 100` to verify the upper clamp of durability percentage. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_cover_degradation_percent.gd -gexit` (cat:test; multifile:no) [feat:xlite-20261106-coverdegradation-tier-thresholds-and-the]

# --- 27B-decomposed from roadmap [2026-11-06]: Capture reach/fail-reason tests only ever put the captor at (0,0), so a sign flip in the C (review + tweak) [feat:xlite-20261106-capture-reach-fail-reason-tests-only-eve] ---
- [ ] [T1] tests/test_capture_offgrid_origin.gd — Add `test_can_capture_positive_quadrant` verifying `can_capture(Vector2i(5, 5), Vector2i(6, 5), 1, true, 0, 5)` returns true. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_capture_offgrid_origin.gd -gexit` shows 1 passing test. (cat:test; multifile:no) [feat:xlite-20261106-capture-reach-fail-reason-tests-only-eve]
- [ ] [T2] tests/test_capture_offgrid_origin.gd — Add `test_can_capture_out_of_range_positive_quadrant` verifying `can_capture(Vector2i(5, 5), Vector2i(7, 5), 1, true, 0, 5)` returns false. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_capture_offgrid_origin.gd -gexit` shows 2 passing tests. (cat:test; multifile:no) [feat:xlite-20261106-capture-reach-fail-reason-tests-only-eve]
- [ ] [T3] tests/test_capture_offgrid_origin.gd — Add `test_can_capture_negative_direction` verifying `can_capture(Vector2i(6, 6), Vector2i(5, 5), 1, true, 0, 5)` returns true. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_capture_offgrid_origin.gd -gexit` shows 3 passing tests. (cat:test; multifile:no) [feat:xlite-20261106-capture-reach-fail-reason-tests-only-eve]
- [ ] [T4] tests/test_capture_offgrid_origin.gd — Add `test_can_capture_paralysis_override` verifying `can_capture(Vector2i(2, 9), Vector2i(2, 8), 1, false, 6, 5)` returns true. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_capture_offgrid_origin.gd -gexit` shows 4 passing tests. (cat:test; multifile:no) [feat:xlite-20261106-capture-reach-fail-reason-tests-only-eve]
- [ ] [T5] tests/test_capture_offgrid_origin.gd — Add `test_fail_reason_out_of_range` verifying `capture_fail_reason(Vector2i(5, 5), Vector2i(9, 5), 1, true, 0, 5)` returns "Move adjacent to capture". VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_capture_offgrid_origin.gd -gexit` shows 5 passing tests. (cat:test; multifile:no) [feat:xlite-20261106-capture-reach-fail-reason-tests-only-eve]

# --- 27B-decomposed from roadmap [2026-11-06]: InteriorDetector never seeds its flood from the right or bottom map border in any test (mu (review + tweak) [feat:xlite-20261106-interiordetector-never-seeds-its-flood-f] ---
- [ ] [T1] tests/test_interior_detector_edges.gd — Create new GutTest file with `extends GutTest` and a helper to build a 5x5 grid with specified obstacle coordinates using TerrainType int 1. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_interior_detector_edges.gd -gexit` runs without parse errors. (cat:test; multifile:no) [feat:xlite-20261106-interiordetector-never-seeds-its-flood-f]
- [ ] [T2] tests/test_interior_detector_edges.gd — Add test case `test_right_border_pocket_not_interior` that sets obstacles `{(4,0):1,(4,4):1,(3,1):1,(3,2):1,(3,3):1}` on a 5x5 grid and asserts `interior_cells(...)` returns an empty dictionary. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_interior_detector_edges.gd -gexit` shows this specific test passing. (cat:test; multifile:no) [feat:xlite-20261106-interiordetector-never-seeds-its-flood-f]
- [ ] [T3] tests/test_interior_detector_edges.gd — Add test case `test_bottom_border_pocket_not_interior` that sets obstacles `{(0,4):1,(4,4):1,(1,3):1,(2,3):1,(3,3):1}` on a 5x5 grid and asserts `interior_cells(...)` returns an empty dictionary. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_interior_detector_edges.gd -gexit` shows this specific test passing. (cat:test; multifile:no) [feat:xlite-20261106-interiordetector-never-seeds-its-flood-f]
- [ ] [T4] tests/test_interior_detector_edges.gd — Add test case `test_sealed_ring_bottom_right_corner` that sets obstacles `{(2,2):1,(3,2):1,(4,2):1,(2,3):1,(4,3):1,(2,4):1,(3,4):1,(4,4):1}` on a 5x5 grid and asserts `interior_cells(...)` returns a dictionary of size 1 containing key `Vector2i(3, 3)`. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_interior_detector_edges.gd -gexit` shows this specific test passing. (cat:test; multifile:no) [feat:xlite-20261106-interiordetector-never-seeds-its-flood-f]
- [ ] [T5] tests/test_interior_detector_edges.gd — Run full verification to confirm all 3 new tests pass and no existing tests are broken by the new file addition. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_interior_detector_edges.gd -gexit` reports 0 failing tests in the raw totals. (cat:test; multifile:no) [feat:xlite-20261106-interiordetector-never-seeds-its-flood-f]

# --- 27B-decomposed from roadmap [2026-11-06]: Formation helpers are only tested with cells at/near the origin, and one test uses `Format (review + tweak) [feat:xlite-20261106-formation-helpers-are-only-tested-with-c] ---
- [ ] [T1] tests/test_formation_offset.gd — Add `test_is_bunched_offset_true` asserting `Formation.is_bunched([Vector2i(5,5), Vector2i(6,5)], 2)` is true. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_formation_offset.gd -gexit` passes this specific test. (cat:test; multifile:no) [feat:xlite-20261106-formation-helpers-are-only-tested-with-c]
- [ ] [T2] tests/test_formation_offset.gd — Add `test_is_bunched_offset_boundary_false` asserting `Formation.is_bunched([Vector2i(5,5), Vector2i(7,5)], 2)` is false to verify the `dist < min_spacing` boundary. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_formation_offset.gd -gexit` passes this specific test. (cat:test; multifile:no) [feat:xlite-20261106-formation-helpers-are-only-tested-with-c]
- [ ] [T3] tests/test_formation_offset.gd — Add `test_is_bunched_multi_offset_true` asserting `Formation.is_bunched([Vector2i(8,3), Vector2i(8,5), Vector2i(2,9)], 3)` is true. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_formation_offset.gd -gexit` passes this specific test. (cat:test; multifile:no) [feat:xlite-20261106-formation-helpers-are-only-tested-with-c]
- [ ] [T4] tests/test_formation_offset.gd — Add `test_spread_score_offset` asserting `Formation.spread_score([Vector2i(5,5), Vector2i(6,5), Vector2i(9,5)]) == 5`. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_formation_offset.gd -gexit` passes this specific test. (cat:test; multifile:no) [feat:xlite-20261106-formation-helpers-are-only-tested-with-c]
- [ ] [T5] tests/test_formation_offset.gd — Add `test_min_pair_gap_offset` asserting `Formation.min_pair_gap([Vector2i(5,5), Vector2i(8,5), Vector2i(9,6)]) == 1`. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_formation_offset.gd -gexit` passes this specific test. (cat:test; multifile:no) [feat:xlite-20261106-formation-helpers-are-only-tested-with-c]

# --- 27B-decomposed from roadmap [2026-11-06]: IsoGrid line-of-sight is only tested with axis-aligned and adjacent shots, and `IsoGrid._l (review + tweak) [feat:xlite-20261106-isogrid-line-of-sight-is-only-tested-wit] ---
- [ ] [T1] tests/test_iso_grid.gd — Add `test_diagonal_shot_obstacle_blocks` verifying `IsoGrid.has_line_of_sight(Vector2i(0,0), Vector2i(4,2), {Vector2i(1,0): true}) == false`, `{Vector2i(2,1): true} == false`, and `{Vector2i(3,1): true} == false`. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_iso_grid.gd -gexit` (cat:test; multifile:no) [feat:xlite-20261106-isogrid-line-of-sight-is-only-tested-wit]
- [ ] [T2] tests/test_iso_grid.gd — Add `test_diagonal_shot_obstacle_does_not_block` verifying `IsoGrid.has_line_of_sight(Vector2i(0,0), Vector2i(4,2), {Vector2i(2,0): true}) == true` and `{Vector2i(2,2): true} == true`. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_iso_grid.gd -gexit` (cat:test; multifile:no) [feat:xlite-20261106-isogrid-line-of-sight-is-only-tested-wit]
- [ ] [T3] tests/test_iso_grid.gd — Add `test_reverse_diagonal_shot_obstacle_blocks` verifying `IsoGrid.has_line_of_sight(Vector2i(4,2), Vector2i(0,0), {Vector2i(2,1): true}) == false`. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_iso_grid.gd -gexit` (cat:test; multifile:no) [feat:xlite-20261106-isogrid-line-of-sight-is-only-tested-wit]
- [ ] [T4] tests/test_iso_grid.gd — Add `test_line_cells_method_removed` containing `assert_false(IsoGrid.has_method("_line_cells"))`. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_iso_grid.gd -gexit` (cat:test; multifile:no) [feat:xlite-20261106-isogrid-line-of-sight-is-only-tested-wit]
- [ ] [T5] scripts/grid/iso_grid.gd — Delete the entire `_line_cells` function definition (lines 127-151). VERIFY: `grep -q "_line_cells" scripts/grid/iso_grid.gd && exit 1 || exit 0` (cat:refactor; multifile:no) [feat:xlite-20261106-isogrid-line-of-sight-is-only-tested-wit]

# --- 27B-decomposed from roadmap [2026-11-06]: README claims no assets are needed and lists 3 of 9 autoloads — drift vs code — README.md  (review + tweak) [feat:xlite-20261106-readme-claims-no-assets-are-needed-and-l] ---
- [ ] [T1] tests/test_readme_drift.gd — Add `extends GutTest` and a `_test_autoloads_in_readme()` method that reads `project.godot` via `FileAccess`, parses `[autoload]` section keys, and asserts `README.md` contains each key name. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_readme_drift.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20261106-readme-claims-no-assets-are-needed-and-l]
- [ ] [T2] tests/test_readme_drift.gd — Add `_test_no_false_asset_claim()` method that asserts `README.md` does NOT contain "No image assets are required". VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_readme_drift.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20261106-readme-claims-no-assets-are-needed-and-l]
- [ ] [T3] tests/test_readme_drift.gd — Add `_test_layout_includes_codex()` method that asserts `README.md` contains "scripts/codex". VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_readme_drift.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20261106-readme-claims-no-assets-are-needed-and-l]
- [ ] [T4] README.md — Replace the "No image assets are required" sentence and empty `assets/sprites/` comment with a note stating sprites, backgrounds, and audio under `assets/` are required to run. VERIFY: `grep -q "required to run" README.md && ! grep -q "No image assets are required" README.md`. (cat:docs; multifile:no) [feat:xlite-20261106-readme-claims-no-assets-are-needed-and-l]
- [ ] [T5] README.md — Update the "Project layout" section to list all 9 autoloads (IsoGrid, SaveManager, RosterManager, TechManager, CodexManager, SfxBus, WindowConfig, TutorialManager, SteamManager) and add directories `scripts/codex`, `scripts/audio`, `scripts/settings`, `scripts/tutorial`, `scripts/steam`, `scripts/release`, `scripts/tools`. VERIFY: `grep -q "CodexManager" README.md && grep -q "SfxBus" README.md && grep -q "WindowConfig" README.md && grep -q "TutorialManager" README.md && grep -q "SteamManager" README.md && grep -q "scripts/codex" README.md`. (cat:docs; multifile:no) [feat:xlite-20261106-readme-claims-no-assets-are-needed-and-l]
