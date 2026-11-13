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
- [ ] [T1] scripts/battle/camera_input.gd — Replace pinch_scale assignment in remap_touch_to_camera with explicit float var using is_nan check to default to 1.0 VERIFY: `grep -q "var scale: float = 1.0 if is_nan(pinch_scale) else pinch_scale" scripts/battle/camera_input.gd` (cat:godot; multifile:no) [feat:xlite-20261110-camerainput-remap-touch-to-camera-passes]
- [ ] [T2] tests/test_camera_input.gd — Add test_nan_inputs_are_neutral function that asserts remap_touch_to_camera(Vector2(NAN, 4.0), NAN) returns zoom 1.0 and pan Vector2(0.0, 4.0) VERIFY: `grep -q "func test_nan_inputs_are_neutral" tests/test_camera_input.gd && grep -q "assert_eq(r\[\"zoom\"\], 1.0)" tests/test_camera_input.gd` (cat:test; multifile:no) [feat:xlite-20261110-camerainput-remap-touch-to-camera-passes]
- [ ] [T3] scripts/battle/camera_input.gd — Ensure clampf operations use the new sanitized dx, dy, and scale variables instead of raw inputs VERIFY: ~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_camera_input.gd -gexit 2>&1 | grep "0 failing" (cat:godot; multifile:no) [feat:xlite-20261110-camerainput-remap-touch-to-camera-passes]

# --- 27B-decomposed from roadmap [2026-11-10]: `SafeArea.top_left`, `top_right` and `bottom_left` have no test - `scripts/ui/safe_area.gd (review + tweak) [feat:xlite-20261110-safearea-top-left-top-right-and-bottom-l] ---
- [ ] [T1] tests/test_safe_area.gd — Add `test_corner_helpers_are_zero_off_mobile() -> void` method containing `var n: Node = Node.new()`, `add_child_autofree(n)`, `assert_eq(SafeArea.top_left(n), Vector2.ZERO)`, `assert_eq(SafeArea.top_right(n), Vector2.ZERO)`, `assert_eq(SafeArea.bottom_left(n), Vector2.ZERO)`, and `assert_eq(SafeArea.insets(n), {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0})`. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_safe_area.gd -gexit` and confirm the new test passes. (cat:test; multifile:no) [feat:xlite-20261110-safearea-top-left-top-right-and-bottom-l]

# --- 27B-decomposed from roadmap [2026-11-10]: `Unit.portrait_path` is never tested - `scripts/units/unit.gd` `portrait_path(state := "id (review + tweak) [feat:xlite-20261110-unit-portrait-path-is-never-tested-scrip] ---
- [ ] [T1] tests/test_unit_portrait_path.gd — Add `test_portrait_path_player_heavy_idle()` verifying `Unit.new()` with `Team.PLAYER` and `PlayerClass.HEAVY` returns `res://assets/sprites/units/player/heavy/idle.png` for default state. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_unit_portrait_path.gd -gexit` shows 1 pass, 0 fail. (cat:test; multifile:no) [feat:xlite-20261110-unit-portrait-path-is-never-tested-scrip]
- [ ] [T1] tests/test_unit_portrait_path.gd — Add `test_portrait_path_player_heavy_walk()` verifying `Unit.new()` with `Team.PLAYER` and `PlayerClass.HEAVY` returns `res://assets/sprites/units/player/heavy/walk.png` for state `"walk"`. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_unit_portrait_path.gd -gexit` shows 2 pass, 0 fail. (cat:test; multifile:no) [feat:xlite-20261110-unit-portrait-path-is-never-tested-scrip]
- [ ] [T1] tests/test_unit_portrait_path.gd — Add `test_portrait_path_enemy_bomber_idle()` verifying `Unit.new()` with `Team.ENEMY` and `EnemyType.BOMBER` returns `res://assets/sprites/units/enemy/raider/idle.png` for state `"idle"`. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_unit_portrait_path.gd -gexit` shows 3 pass, 0 fail. (cat:test; multifile:no) [feat:xlite-20261110-unit-portrait-path-is-never-tested-scrip]
- [ ] [T1] tests/test_unit_portrait_path.gd — Add `test_portrait_path_enemy_bomber_walk()` verifying `Unit.new()` with `Team.ENEMY` and `EnemyType.BOMBER` returns `res://assets/sprites/units/enemy/raider/walk.png` for state `"walk"`. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_unit_portrait_path.gd -gexit` shows 4 pass, 0 fail. (cat:test; multifile:no) [feat:xlite-20261110-unit-portrait-path-is-never-tested-scrip]
- [ ] [T1] tests/test_unit_portrait_path.gd — Add `test_portrait_path_player_light_idle()` verifying `Unit.new()` with `Team.PLAYER` and `PlayerClass.LIGHT` returns `res://assets/sprites/units/player/light/idle.png` for default state. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_unit_portrait_path.gd -gexit` shows 5 pass, 0 fail. (cat:test; multifile:no) [feat:xlite-20261110-unit-portrait-path-is-never-tested-scrip]
- [ ] [T1] tests/test_unit_portrait_path.gd — Add `test_portrait_path_enemy_raider_idle()` verifying `Unit.new()` with `Team.ENEMY` and `EnemyType.RAIDER` returns `res://assets/sprites/units/enemy/raider/idle.png` for state `"idle"`. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_unit_portrait_path.gd -gexit` shows 6 pass, 0 fail. (cat:test; multifile:no) [feat:xlite-20261110-unit-portrait-path-is-never-tested-scrip]

# --- 27B-decomposed from roadmap [2026-11-10]: `MissionPathMap.configure` has no test - `scripts/mission/mission_path_map.gd` `configure( (review + tweak) [feat:xlite-20261110-missionpathmap-configure-has-no-test-scr] ---
- [ ] [T1] tests/test_mission_path_map.gd — Add `test_configure_stores_progress_and_sizes_the_control` method that instantiates `MissionPathMap`, calls `configure(20, 5, 6)`, and asserts `total_missions`, `completed_missions`, `current_mission`, and `custom_minimum_size` equal `Vector2(504.0, 76.0)`. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_mission_path_map.gd -gexit` shows the new test passing. (cat:test; multifile:no) [feat:xlite-20261110-missionpathmap-configure-has-no-test-scr]

# --- 27B-decomposed from roadmap [2026-11-10]: `SteamManager.unlock_milestone` is untested - `scripts/integrations/steam_manager.gd` `unl (review + tweak) [feat:xlite-20261110-steammanager-unlock-milestone-is-unteste] ---
- [ ] [T1] tests/test_steam_manager.gd — Add `test_unlock_milestone_is_a_safe_noop_when_inactive() -> void` that calls `SteamManager.unlock_milestone("definitely_not_a_milestone")`, iterates `AchievementRegistry.MAP.keys()` calling `SteamManager.unlock_milestone(id)`, and asserts `assert_false(SteamManager.is_active())`. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_steam_manager.gd -gexit` (cat:test; multifile:no) [feat:xlite-20261110-steammanager-unlock-milestone-is-unteste]

# --- 27B-decomposed from roadmap [2026-11-10]: `Unit.play_pose`, `play_attack` and `stand_up` have no tests of their guard and reset beha (review + tweak) [feat:xlite-20261110-unit-play-pose-play-attack-and-stand-up-] ---
- [ ] [T4] scripts/units/unit.gd — Ensure `play_pose(name)` returns early if `_sprite == null` to prevent errors before `_ready`. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_unit_pose_helpers.gd -gexit` passes. (cat:godot; multifile:no) [feat:xlite-20261110-unit-play-pose-play-attack-and-stand-up-]
- [ ] [T5] scripts/units/unit.gd — Ensure `play_attack(dir)` returns early if `_sprite == null` to prevent errors before `_ready`. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_unit_pose_helpers.gd -gexit` passes. (cat:godot; multifile:no) [feat:xlite-20261110-unit-play-pose-play-attack-and-stand-up-]
- [ ] [T2] tests/test_unit_pose_helpers.gd — Implement `test_pose_helpers_are_noops_before_ready()` to instantiate `Unit`, call `play_pose("idle")`, `play_pose("hit")`, `stand_up()`, `play_attack(Vector2i(1, 0))`, assert `u._sprite` is null, and free `u`. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_unit_pose_helpers.gd -gexit` shows 1 passing test. (cat:test; multifile:no) [feat:xlite-20261110-unit-play-pose-play-attack-and-stand-up-]
- [ ] [T1] tests/test_unit_pose_helpers.gd — Create file with `extends GutTest` and empty `test_pose_helpers_are_noops_before_ready() -> void` stub. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_unit_pose_helpers.gd -gexit` runs without parse errors. (cat:test; multifile:no) [feat:xlite-20261110-unit-play-pose-play-attack-and-stand-up-]
- [ ] [T3] tests/test_unit_pose_helpers.gd — Add `test_stand_up_clears_prone_rotation_and_offset()` to instantiate `Unit`, add to tree, set `_sprite.rotation` to 1.2 and `_sprite.offset.y` to 7.0, call `stand_up()`, assert rotation/offset are 0.0, then call `play_attack(Vector2i.ZERO)` and `play_pose("no_such_pose")` asserting instance validity. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_unit_pose_helpers.gd -gexit` shows 2 passing tests. (cat:test; multifile:no) [feat:xlite-20261110-unit-play-pose-play-attack-and-stand-up-]

# --- 27B-decomposed from roadmap [2026-11-10]: The Python mission-file helpers in `tools/tres_format.py` have no tests - `parse_vec_list` (review + tweak) [feat:xlite-20261110-the-python-mission-file-helpers-in-tools] ---
- [ ] [T1] tools/test_tres_format.py — Create file with `import unittest`, `import tres_format as tf`, and the exact `SAMPLE` string constant. VERIFY: `python3 -c "import ast; ast.parse(open('tools/test_tres_format.py').read())"`. (cat:test; multifile:no) [feat:xlite-20261110-the-python-mission-file-helpers-in-tools]
- [ ] [T2] tools/test_tres_format.py — Add `test_parse_functions` method to a `TestTresFormat(unittest.TestCase)` class asserting `tf.parse_vec_list(SAMPLE, "obstacles") == [(1, 2), (-3, 4)]`, `tf.parse_int_list(SAMPLE, "obstacle_types") == [0, 1]`, `tf.parse_vec(SAMPLE, "extraction_zone") == (5, 6)`, and that missing keys return `[]`, `[]`, `None`. VERIFY: `python3 tools/test_tres_format.py TestTresFormat.test_parse_functions`. (cat:test; multifile:no) [feat:xlite-20261110-the-python-mission-file-helpers-in-tools]
- [ ] [T3] tools/test_tres_format.py — Add assertions to `test_parse_functions` verifying that a sample with `obstacles = Array[Vector2i]([])` parses to `[]`. VERIFY: `python3 tools/test_tres_format.py TestTresFormat.test_parse_functions`. (cat:test; multifile:no) [feat:xlite-20261110-the-python-mission-file-helpers-in-tools]
- [ ] [T4] tools/test_tres_format.py — Add `test_setter_functions` method asserting `tf.set_vec_list_field(SAMPLE, "obstacles", [(7, 8)])` re-parses to `[(7, 8)]` with exactly one `obstacles =` line, and that appending `door_cells` and `enemy_types` produces the correct trailing lines. VERIFY: `python3 tools/test_tres_format.py TestTresFormat.test_setter_functions`. (cat:test; multifile:no) [feat:xlite-20261110-the-python-mission-file-helpers-in-tools]
- [ ] [T5] tools/test_tres_format.py — Add `test_format_patrol_routes` method asserting `tf.format_patrol_routes([[], [(7, 2), (9, 2)], []]) == "enemy_patrol_routes = [[], [Vector2i(7, 2), Vector2i(9, 2)], []]"` and `tf.format_patrol_routes([]) == "enemy_patrol_routes = []"`. VERIFY: `python3 tools/test_tres_format.py TestTresFormat.test_format_patrol_routes`. (cat:test; multifile:no) [feat:xlite-20261110-the-python-mission-file-helpers-in-tools]

# --- 27B-decomposed from roadmap [2026-11-10]: `tres_format.assemble_tres` and `reachable_ok` have no tests - `tools/tres_format.py` `ass (review + tweak) [feat:xlite-20261110-tres-format-assemble-tres-and-reachable-] ---
- [ ] [T1] tools/test_tres_assemble.py — Create file with `BASE` dict, `test_defaults_omitted` verifying header, required fields, absence of optional keys, and trailing newline. VERIFY: `python3 -m unittest tools.test_tres_assemble.TestTresAssemble.test_defaults_omitted -v`. (cat:test; multifile:no) [feat:xlite-20261110-tres-format-assemble-tres-and-reachable-]
- [ ] [T2] tools/test_tres_assemble.py — Add `test_non_default_fields_written` verifying all 10 optional fields appear with correct serialization formats in `assemble_tres` output. VERIFY: `python3 -m unittest tools.test_tres_assemble.TestTresAssemble.test_non_default_fields_written -v`. (cat:test; multifile:no) [feat:xlite-20261110-tres-format-assemble-tres-and-reachable-]
- [ ] [T3] tools/test_tres_assemble.py — Add `test_reachable_ok_cases` verifying `(True, "ok")`, extraction unreachable, target unreachable, and unit spawn unreachable return values. VERIFY: `python3 -m unittest tools.test_tres_assemble.TestTresAssemble.test_reachable_ok_cases -v`. (cat:test; multifile:no) [feat:xlite-20261110-tres-format-assemble-tres-and-reachable-]
- [ ] [T4] tools/test_tres_assemble.py — Add `if __name__ == "__main__": unittest.main()` block at end of file. VERIFY: `python3 tools/test_tres_assemble.py` prints "OK (3 tests)". (cat:test; multifile:no) [feat:xlite-20261110-tres-format-assemble-tres-and-reachable-]

# --- 27B-decomposed from roadmap [2026-11-12]: Add a codex entry filter and use it in the populate loops - add `static func entry_visible (review + tweak) [feat:xlite-20261112-add-a-codex-entry-filter-and-use-it-in-t] ---
- [ ] [T1] scripts/codex/codex_data.gd — Add `static func entry_visible(query: String, display_name: String, blurb: String, seen: bool) -> bool` that returns true if `query.strip_edges()` is empty, otherwise returns `seen and matches_query(display_name, blurb, query.strip_edges())`. VERIFY: `grep -q 'static func entry_visible' scripts/codex/codex_data.gd`. (cat:godot; multifile:no) [feat:xlite-20261112-add-a-codex-entry-filter-and-use-it-in-t]
- [ ] [T3] scripts/mission/codex_view.gd — Add `var _query: String = ""` and modify `_populate()` to compute `seen` per enemy/soldier, filter rows using `CodexData.entry_visible(_query, name, blurb, seen)`, and only call `_add_locked()` when `_query.strip_edges().is_empty()`. VERIFY: `grep -q 'CodexData.entry_visible' scripts/mission/codex_view.gd && grep -q '_query.strip_edges().is_empty()' scripts/mission/codex_view.gd`. (cat:godot; multifile:no) [feat:xlite-20261112-add-a-codex-entry-filter-and-use-it-in-t]
- [ ] [T2] tests/test_codex_entry_visible.gd — Create test file extending GutTest with cases for empty/whitespace query (true for seen/unseen), non-empty query on unseen (false), seen+name match (true), seen+blurb match (true), seen+no match (false), case-insensitivity, and whitespace stripping. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_codex_entry_visible.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20261112-add-a-codex-entry-filter-and-use-it-in-t]

# --- 27B-decomposed from roadmap [2026-11-12]: Add the codex search box - in `scripts/mission/codex_view.gd` add `var _search_box: LineEd (review + tweak) [feat:xlite-20261112-add-the-codex-search-box-in-scripts-miss] ---
- [ ] [T2] scripts/mission/codex_view.gd — Add `func _on_search_changed(text: String) -> void` that sets `_query = text` and calls `_populate()` VERIFY: `grep -q 'func _on_search_changed' scripts/mission/codex_view.gd && grep -q '_query = text' scripts/mission/codex_view.gd`. (cat:godot; multifile:no) [feat:xlite-20261112-add-the-codex-search-box-in-scripts-miss]
- [ ] [T3] scripts/mission/codex_view.gd — Add `func _setup_search_box() -> void` that creates a `LineEdit` named `SearchBox`, sets `placeholder_text = "Search codex"`, `clear_button_enabled = true`, anchors to `PRESET_CENTER_TOP`, offsets `(-150, 150, 96, 128)`, connects `text_changed` to `_on_search_changed`, and adds it as a child VERIFY: `grep -q 'func _setup_search_box' scripts/mission/codex_view.gd && grep -q 'SearchBox' scripts/mission/codex_view.gd && grep -q 'text_changed.connect(_on_search_changed)' scripts/mission/codex_view.gd`. (cat:godot; multifile:no) [feat:xlite-20261112-add-the-codex-search-box-in-scripts-miss]
- [ ] [T1] tests/test_codex_view_search.gd — Create test file with `preload("res://scripts/mission/codex_view.gd") as _VIEW`, `gut_codex_view` slot, `before_each` loading/resetting `CodexManager` and marking `GRUNT`/`DRONE` seen, and `after_each` cleanup VERIFY: `grep -q 'preload' tests/test_codex_view_search.gd && grep -q 'gut_codex_view' tests/test_codex_view_search.gd && grep -q 'Unit.EnemyType.GRUNT' tests/test_codex_view_search.gd`. (cat:test; multifile:no) [feat:xlite-20261112-add-the-codex-search-box-in-scripts-miss]
- [ ] [T1] scripts/mission/codex_view.gd — Add `var _search_box: LineEdit` and `var _query: String = ""` to the class variables VERIFY: `grep -q 'var _search_box: LineEdit' scripts/mission/codex_view.gd && grep -q 'var _query: String = ""' scripts/mission/codex_view.gd`. (cat:godot; multifile:no) [feat:xlite-20261112-add-the-codex-search-box-in-scripts-miss]
- [ ] [T3] scripts/mission/codex_view.gd — Modify `_ready()` to call `_setup_search_box()` immediately after `_setup_portrait_panel()` and before `_populate()` VERIFY: `grep -A 5 'func _ready' scripts/mission/codex_view.gd | grep -q '_setup_search_box()'. (cat:godot; multifile:no) [feat:xlite-20261112-add-the-codex-search-box-in-scripts-miss]
- [ ] [T4] scripts/mission/codex_view.gd — Modify `_populate()` to filter entries based on `_query` (case-insensitive substring match on name) so only matching unlocked units are displayed, hiding locked placeholders when a query is active VERIFY: `grep -q '_query' scripts/mission/codex_view.gd && grep -q 'to_lower()' scripts/mission/codex_view.gd`. (cat:godot; multifile:no) [feat:xlite-20261112-add-the-codex-search-box-in-scripts-miss]
- [ ] [T2] tests/test_codex_view_search.gd — Add test case `test_search_filters_results` that instantiates view, calls `_on_search_changed("drone")`, awaits frame, asserts `Scroll/EntryList` contains "Drone" but not "Grunt" or locked placeholder text VERIFY: `grep -q 'test_search_filters_results' tests/test_codex_view_search.gd && grep -q '"drone"' tests/test_codex_view_search.gd`. (cat:test; multifile:no) [feat:xlite-20261112-add-the-codex-search-box-in-scripts-miss]
- [ ] [T2] tests/test_codex_view_search.gd — Add test case `test_clear_search_restores_all` that clears search, awaits frame, asserts "Grunt" and locked rows are visible again VERIFY: `grep -q 'test_clear_search_restores_all' tests/test_codex_view_search.gd && grep -q '_on_search_changed("")' tests/test_codex_view_search.gd`. (cat:test; multifile:no) [feat:xlite-20261112-add-the-codex-search-box-in-scripts-miss]
- [ ] [T2] tests/test_codex_view_search.gd — Add test case `test_search_box_node_exists` that asserts `view.get_node("SearchBox")` is a `LineEdit` VERIFY: `grep -q 'test_search_box_node_exists' tests/test_codex_view_search.gd && grep -q 'is(LineEdit)' tests/test_codex_view_search.gd`. (cat:test; multifile:no) [feat:xlite-20261112-add-the-codex-search-box-in-scripts-miss]

# --- 27B-decomposed from roadmap [2026-11-12]: Show the match count while searching - in `scripts/mission/codex_view.gd` add `static func (review + tweak) [feat:xlite-20261112-show-the-match-count-while-searching-in-] ---
- [ ] [T1] scripts/mission/codex_view.gd — Add `static func progress_text(shown: int, seen_total: int, grand_total: int, query: String) -> String` that returns `"Discovered: %d / %d" % [seen_total, grand_total]` if `query.strip_edges() == ""` else `"Showing %d of %d" % [maxi(shown, 0), maxi(grand_total, 0)]` VERIFY: `grep -q 'static func progress_text' scripts/mission/codex_view.gd`. (cat:godot; multifile:no) [feat:xlite-20261112-show-the-match-count-while-searching-in-]
- [ ] [T3] scripts/mission/codex_view.gd — Replace the inline progress label formatting in `_populate()` with `progress_label.text = progress_text(shown_total, seen_total, grand_total, _query)` VERIFY: `grep -q 'progress_label.text = progress_text(shown_total' scripts/mission/codex_view.gd`. (cat:godot; multifile:no) [feat:xlite-20261112-show-the-match-count-while-searching-in-]
- [ ] [T1] tests/test_codex_progress_text.gd — Create test file with `extends GutTest`, preload `res://scripts/mission/codex_view.gd` as `CodexView`, and add test cases asserting `progress_text(0, 3, 9, "") == "Discovered: 3 / 9"`, `progress_text(2, 3, 9, "dr") == "Showing 2 of 9"`, `progress_text(0, 3, 9, "   ") == "Discovered: 3 / 9"`, and `progress_text(-5, 3, 9, "x") == "Showing 0 of 9"` VERIFY: `ls tests/test_codex_progress_text.gd`. (cat:test; multifile:no) [feat:xlite-20261112-show-the-match-count-while-searching-in-]
- [ ] [T2] scripts/mission/codex_view.gd — In `_populate()`, initialize `var shown_total: int = 0` and increment it for every enemy, soldier, and tech row added VERIFY: `grep -q 'shown_total += 1' scripts/mission/codex_view.gd`. (cat:godot; multifile:no) [feat:xlite-20261112-show-the-match-count-while-searching-in-]
- [ ] [T4] tests/test_codex_progress_text.gd — Run the test suite to verify all static cases pass and no regressions occur VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_codex_progress_text.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20261112-show-the-match-count-while-searching-in-]

# --- 27B-decomposed from roadmap [2026-11-12]: Say when a codex search matches nothing - in `scripts/mission/codex_view.gd` add `static f (review + tweak) [feat:xlite-20261112-say-when-a-codex-search-matches-nothing-] ---
- [ ] [T1] scripts/mission/codex_view.gd — Add `static func no_match_text(query: String) -> String` returning `"No codex entries match \"%s\"" % query.strip_edges().left(24)` VERIFY: `grep -q 'static func no_match_text' scripts/mission/codex_view.gd`. (cat:godot; multifile:no) [feat:xlite-20261112-say-when-a-codex-search-matches-nothing-]
- [ ] [T3] scripts/mission/codex_view.gd — Add `func _add_no_matches() -> void` that creates a `Label`, sets `modulate = Color(0.55, 0.55, 0.6)`, `custom_minimum_size = Vector2(0, 28)`, text to `no_match_text(_query)`, and adds it to the entry list container VERIFY: `grep -q 'func _add_no_matches' scripts/mission/codex_view.gd`. (cat:godot; multifile:no) [feat:xlite-20261112-say-when-a-codex-search-matches-nothing-]
- [ ] [T1] tests/test_codex_no_match_text.gd — Create test file with GUT setup and test case asserting `CodexView.no_match_text("zzz")` equals `"No codex entries match \"zzz\""` VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_codex_no_match_text.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20261112-say-when-a-codex-search-matches-nothing-]
- [ ] [T2] tests/test_codex_no_match_text.gd — Add test case asserting `CodexView.no_match_text("  zzz  ")` equals `"No codex entries match \"zzz\""` VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_codex_no_match_text.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20261112-say-when-a-codex-search-matches-nothing-]
- [ ] [T2] tests/test_codex_no_match_text.gd — Add test case asserting `CodexView.no_match_text("a".repeat(40))` equals `"No codex entries match \"aaaaaaaaaaaaaaaaaaaaaa\""` VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_codex_no_match_text.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20261112-say-when-a-codex-search-matches-nothing-]
- [ ] [T3] scripts/mission/codex_view.gd — Modify `_populate()` to call `_add_no_matches()` at the end if `_query.strip_edges() != ""` and `shown_total == 0` VERIFY: `grep -q '_add_no_matches()' scripts/mission/codex_view.gd`. (cat:godot; multifile:no) [feat:xlite-20261112-say-when-a-codex-search-matches-nothing-]
- [ ] [T2] tests/test_codex_no_match_text.gd — Add test case that instantiates the view, calls `_on_search_changed("zzzz-no-such-entry")`, awaits a frame, and asserts a label under `Scroll/EntryList` has text starting with `"No codex entries match"` VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_codex_no_match_text.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20261112-say-when-a-codex-search-matches-nothing-]

# --- 27B-decomposed from roadmap [2026-11-12]: Let the search also filter the tech rows - in the Tech loop of `_populate()` in `scripts/m (review + tweak) [feat:xlite-20261112-let-the-search-also-filter-the-tech-rows] ---
- [ ] [T1] scripts/mission/codex_view.gd — Add a guard in the tech loop of `_populate()` to only add a tech row when `CodexData.entry_visible(_query, tech.tech_name, tech.description, true)` is true and increment `shown_total` for each added row. VERIFY: `grep -q 'CodexData.entry_visible(_query, tech.tech_name' scripts/mission/codex_view.gd && grep -q 'shown_total += 1' scripts/mission/codex_view.gd`. (cat:godot; multifile:no) [feat:xlite-20261112-let-the-search-also-filter-the-tech-rows]
- [ ] [T2] tests/test_codex_view_search_tech.gd — Create a new GUT test file that instantiates the codex view, asserts the first tech name is visible with an empty query, remains visible after searching for its lower-cased name, and becomes invisible after searching for "zzzz-no-such-entry". VERIFY: `test -f tests/test_codex_view_search_tech.gd && grep -q 'zzzz-no-such-entry' tests/test_codex_view_search_tech.gd`. (cat:test; multifile:no) [feat:xlite-20261112-let-the-search-also-filter-the-tech-rows]
- [ ] [T3] . — Run the GUT test suite for the new tech search filter to confirm all assertions pass and no regressions occur in the codex view logic. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_codex_view_search_tech.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20261112-let-the-search-also-filter-the-tech-rows]

# --- 27B-decomposed from roadmap [2026-11-12]: Show a one-line summary under each used slot - in `scripts/mission/save_slot_select.gd` ad (review + tweak) [feat:xlite-20261112-show-a-one-line-summary-under-each-used-] ---
- [ ] [T1] scripts/mission/save_slot_select.gd — Add `static func _to_int(v: Variant) -> int` that returns `maxi(int(v), 0)` for int/float, `maxi(v.to_int(), 0)` for valid int strings, and `0` otherwise. VERIFY: `grep -q 'static func _to_int' scripts/mission/save_slot_select.gd`. (cat:godot; multifile:no) [feat:xlite-20261112-show-a-one-line-summary-under-each-used-]
- [ ] [T1] scripts/mission/save_slot_select.gd — Add `static func slot_summary_text(data: Dictionary) -> String` that returns `""` if data is empty or `data.get("entries")` is not an Array, else formats `"Soldiers: %d   Missions cleared: %d   Credits: %d   Materials: %d"` using `_to_int` for the stats and counting Dictionary items in entries. VERIFY: `grep -q 'static func slot_summary_text' scripts/mission/save_slot_select.gd`. (cat:godot; multifile:no) [feat:xlite-20261112-show-a-one-line-summary-under-each-used-]
- [ ] [T2] tests/test_slot_summary_text.gd — Create test file with GUT static tests verifying `slot_summary_text` returns correct strings for full data, empty dict, bad entries type, mixed entry types, negative credits, float credits, string missions, and non-dict materials. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_slot_summary_text.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20261112-show-a-one-line-summary-under-each-used-]
- [ ] [T3] scripts/mission/save_slot_select.gd — In `_refresh_slots()`, after adding a used slot row, load save data via `SaveManager.load_save(slot_name + "_roster")`, get summary text, and if not empty add a centered Label with font size 13 and modulate Color(1,1,1,0.7). VERIFY: `grep -q 'slot_summary_text(SaveManager.load_save' scripts/mission/save_slot_select.gd`. (cat:godot; multifile:no) [feat:xlite-20261112-show-a-one-line-summary-under-each-used-]
- [ ] [T4] tests/test_slot_summary_text.gd — Add test case verifying that when `SaveManager.load_save` returns empty dict, no Label is added to the slot row (mock or verify UI state). VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_slot_summary_text.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20261112-show-a-one-line-summary-under-each-used-]

# --- 27B-decomposed from roadmap [2026-11-12]: Label an unreadable used slot - in `scripts/mission/save_slot_select.gd` add `static func  (review + tweak) [feat:xlite-20261112-label-an-unreadable-used-slot-in-scripts] ---
- [ ] [T1] scripts/mission/save_slot_select.gd — Add `static func slot_status_text(used: bool, data: Dictionary) -> String` returning "Empty" if not used, "In progress" if used and `data.get("entries")` is an Array, else "Unreadable". VERIFY: `grep -q 'static func slot_status_text' scripts/mission/save_slot_select.gd`. (cat:godot; multifile:no) [feat:xlite-20261112-label-an-unreadable-used-slot-in-scripts]
- [ ] [T3] scripts/mission/save_slot_select.gd — In `_refresh_slots()`, replace inline status logic with `slot_status_text(used, SaveManager.load_save(slot_name + "_roster") if used else {})`. VERIFY: `grep -q 'slot_status_text(used' scripts/mission/save_slot_select.gd`. (cat:godot; multifile:no) [feat:xlite-20261112-label-an-unreadable-used-slot-in-scripts]
- [ ] [T2] tests/test_slot_status_text.gd — Create test file with static cases for "Empty", "In progress" (valid entries), "Unreadable" (empty dict), and "Unreadable" (entries is int 5). VERIFY: `ls tests/test_slot_status_text.gd`. (cat:test; multifile:no) [feat:xlite-20261112-label-an-unreadable-used-slot-in-scripts]
- [ ] [T4] tests/test_slot_status_text.gd — Add assertions verifying `slot_status_text(false, {})` returns "Empty". VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_slot_status_text.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20261112-label-an-unreadable-used-slot-in-scripts]
- [ ] [T5] tests/test_slot_status_text.gd — Add assertions verifying `slot_status_text(true, {"entries": []})` returns "In progress". VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_slot_status_text.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20261112-label-an-unreadable-used-slot-in-scripts]

# --- 27B-decomposed from roadmap [2026-11-12]: Give the slot buttons descriptive tooltips - in `scripts/mission/save_slot_select.gd` add  (review + tweak) [feat:xlite-20261112-give-the-slot-buttons-descriptive-toolti] ---
- [ ] [T1] scripts/mission/save_slot_select.gd — Add `static func slot_button_tooltip(kind: String, slot_label: String, summary: String) -> String` that returns `"Continue %s" % slot_label + (" (%s)" % summary if summary != "" else "")` for "continue", `"Delete %s" % slot_label` for "delete", `"Start a new run in %s" % slot_label` for "start", and `""` otherwise. VERIFY: `grep -q 'static func slot_button_tooltip' scripts/mission/save_slot_select.gd`. (cat:godot; multifile:no) [feat:xlite-20261112-give-the-slot-buttons-descriptive-toolti]
- [ ] [T3] scripts/mission/save_slot_select.gd — In `_refresh_slots()`, set `tooltip_text` on the Continue button to `slot_button_tooltip("continue", SlotName.slot_label(i - 1), slot_summary_text.text)` where `slot_summary_text` is the existing summary label node. VERIFY: `grep -q 'slot_button_tooltip("continue"' scripts/mission/save_slot_select.gd`. (cat:godot; multifile:no) [feat:xlite-20261112-give-the-slot-buttons-descriptive-toolti]
- [ ] [T4] scripts/mission/save_slot_select.gd — In `_refresh_slots()`, set `tooltip_text` on the Delete button to `slot_button_tooltip("delete", SlotName.slot_label(i - 1), "")`. VERIFY: `grep -q 'slot_button_tooltip("delete"' scripts/mission/save_slot_select.gd`. (cat:godot; multifile:no) [feat:xlite-20261112-give-the-slot-buttons-descriptive-toolti]
- [ ] [T5] scripts/mission/save_slot_select.gd — In `_refresh_slots()`, set `tooltip_text` on the Start New Run button to `slot_button_tooltip("start", SlotName.slot_label(i - 1), "")`. VERIFY: `grep -q 'slot_button_tooltip("start"' scripts/mission/save_slot_select.gd`. (cat:godot; multifile:no) [feat:xlite-20261112-give-the-slot-buttons-descriptive-toolti]
- [ ] [T2] tests/test_slot_button_tooltip.gd — Create test file with static cases verifying `slot_button_tooltip("continue", "Slot 1", "Level 5")` equals `"Continue Slot 1 (Level 5)"`, `slot_button_tooltip("continue", "Slot 1", "")` equals `"Continue Slot 1"`, `slot_button_tooltip("delete", "Slot 2", "x")` equals `"Delete Slot 2"`, `slot_button_tooltip("start", "Slot 3", "y")` equals `"Start a new run in Slot 3"`, and `slot_button_tooltip("unknown", "S", "z")` equals `""`. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_slot_button_tooltip.gd -gexit` returns 0 failing tests. (cat:test; multifile:no) [feat:xlite-20261112-give-the-slot-buttons-descriptive-toolti]

# --- 27B-decomposed from roadmap [2026-11-12]: Start keyboard and gamepad focus on the first used slot - in `scripts/mission/save_slot_se (review + tweak) [feat:xlite-20261112-start-keyboard-and-gamepad-focus-on-the-] ---
- [ ] [T1] scripts/mission/save_slot_select.gd — Add `static func first_used_slot_index(saves, slot_count: int) -> int` that iterates 0 to slot_count-1, checks `is_slot_used("slot%d" % (i + 1), saves)`, returns the first matching index or -1. VERIFY: `grep -q 'static func first_used_slot_index' scripts/mission/save_slot_select.gd`. (cat:godot; multifile:no) [feat:xlite-20261112-start-keyboard-and-gamepad-focus-on-the-]
- [ ] [T3] scripts/mission/save_slot_select.gd — Add `var _action_buttons: Array[Button] = []` member variable. VERIFY: `grep -q '_action_buttons' scripts/mission/save_slot_select.gd`. (cat:godot; multifile:no) [feat:xlite-20261112-start-keyboard-and-gamepad-focus-on-the-]
- [ ] [T4] scripts/mission/save_slot_select.gd — In `_refresh_slots()`, clear `_action_buttons` at the top and append each row's Continue/Start button to `_action_buttons` in slot order. VERIFY: `grep -q '_action_buttons.clear()' scripts/mission/save_slot_select.gd && grep -q '_action_buttons.append' scripts/mission/save_slot_select.gd`. (cat:godot; multifile:no) [feat:xlite-20261112-start-keyboard-and-gamepad-focus-on-the-]
- [ ] [T5] scripts/mission/save_slot_select.gd — In `_ready()`, call `first_used_slot_index` to get index; if valid (>=0), call `_action_buttons[idx].grab_focus.call_deferred()`, else keep existing `_first_focusable` fallback. VERIFY: `grep -q 'grab_focus.call_deferred' scripts/mission/save_slot_select.gd`. (cat:godot; multifile:no) [feat:xlite-20261112-start-keyboard-and-gamepad-focus-on-the-]
- [ ] [T2] tests/test_first_used_slot_index.gd — Create test file with cases: empty saves returns -1, `["slot2_roster"]` returns 1, `["slot3_roster", "slot2_roster"]` returns 1, PackedStringArray input works, slot_count 1 with only slot2_roster returns -1. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_first_used_slot_index.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20261112-start-keyboard-and-gamepad-focus-on-the-]

# --- 27B-decomposed from roadmap [2026-11-12]: Show "Step N of M" on the tutorial overlay - in `scripts/tutorial/tutorial_manager.gd` add (review + tweak) [feat:xlite-20261112-show-step-n-of-m-on-the-tutorial-overlay] ---
- [ ] [T1] scripts/tutorial/tutorial_manager.gd — Add `static func step_position_text(index: int, total: int) -> String` that returns empty string if `total <= 0`, else `"Step %d of %d" % [clampi(index, 0, total - 1) + 1, total]`. VERIFY: `grep -q "static func step_position_text" scripts/tutorial/tutorial_manager.gd`. (cat:godot; multifile:no) [feat:xlite-20261112-show-step-n-of-m-on-the-tutorial-overlay]
- [ ] [T1] scripts/tutorial/tutorial_manager.gd — Add `func current_index() -> int` that returns `_step_index`. VERIFY: `grep -q "func current_index" scripts/tutorial/tutorial_manager.gd`. (cat:godot; multifile:no) [feat:xlite-20261112-show-step-n-of-m-on-the-tutorial-overlay]
- [ ] [T3] scripts/tutorial/tutorial_overlay.gd — In `_build_ui()`, create `_step_label` as the first child of `button_col` with font size 13, `modulate = Color(1, 1, 1, 0.75)`, and centered alignment. VERIFY: `grep -q "_step_label" scripts/tutorial/tutorial_overlay.gd && grep -q "button_col" scripts/tutorial/tutorial_overlay.gd`. (cat:godot; multifile:no) [feat:xlite-20261112-show-step-n-of-m-on-the-tutorial-overlay]
- [ ] [T3] scripts/tutorial/tutorial_overlay.gd — Add `var _step_label: Label` member variable. VERIFY: `grep -q "var _step_label" scripts/tutorial/tutorial_overlay.gd`. (cat:godot; multifile:no) [feat:xlite-20261112-show-step-n-of-m-on-the-tutorial-overlay]
- [ ] [T3] scripts/tutorial/tutorial_overlay.gd — In `_refresh_step()`, after the empty-step early return, set `_step_label.text = TutorialManager.step_position_text(TutorialManager.current_index(), TutorialManager.STEPS.size())`. VERIFY: `grep -q "step_position_text" scripts/tutorial/tutorial_overlay.gd`. (cat:godot; multifile:no) [feat:xlite-20261112-show-step-n-of-m-on-the-tutorial-overlay]
- [ ] [T2] tests/test_tutorial_step_position.gd — Create test file extending `GutTest`; in `before_each` call `TutorialManager.start()`; in `after_each` set `TutorialManager._active = false` and `TutorialManager._step_index = 0` (do NOT call `finish()`); add static tests for `step_position_text` cases: `(0,4)=="Step 1 of 4"`, `(3,4)=="Step 4 of 4"`, `(9,4)=="Step 4 of 4"`, `(-2,4)=="Step 1 of 4"`, `(0,0)==""`. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_tutorial_step_position.gd -gexit` and confirm 0 failing. (cat:test; multifile:no) [feat:xlite-20261112-show-step-n-of-m-on-the-tutorial-overlay]
- [ ] [T2] tests/test_tutorial_step_position.gd — Add overlay integration test: instantiate `TutorialOverlay.new()`, `add_child_autofree(overlay)`, call `overlay.setup({})`, assert `overlay._step_label.text == "Step 1 of 4"`, call `overlay._on_next_pressed()`, assert `overlay._step_label.text == "Step 2 of 4"`. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_tutorial_step_position.gd -gexit` and confirm 0 failing. (cat:test; multifile:no) [feat:xlite-20261112-show-step-n-of-m-on-the-tutorial-overlay]

# --- 27B-decomposed from roadmap [2026-11-12]: Add a Back button to the tutorial overlay - in `scripts/tutorial/tutorial_manager.gd` add  (review + tweak) [feat:xlite-20261112-add-a-back-button-to-the-tutorial-overla] ---
- [ ] [T1] scripts/tutorial/tutorial_manager.gd — Add `func is_first_step() -> bool` returning `_step_index <= 0`. VERIFY: `grep -q "func is_first_step" scripts/tutorial/tutorial_manager.gd`. (cat:godot; multifile:no) [feat:xlite-20261112-add-a-back-button-to-the-tutorial-overla]
- [ ] [T1] scripts/tutorial/tutorial_manager.gd — Add `func previous_step() -> bool` that decrements `_step_index` if > 0 and returns true, else returns false. VERIFY: `grep -q "func previous_step" scripts/tutorial/tutorial_manager.gd`. (cat:godot; multifile:no) [feat:xlite-20261112-add-a-back-button-to-the-tutorial-overla]
- [ ] [T3] scripts/tutorial/tutorial_overlay.gd — Add `func _on_back_pressed() -> void` calling `TutorialManager.previous_step()` and `_refresh_step()`. VERIFY: `grep -q "func _on_back_pressed" scripts/tutorial/tutorial_overlay.gd`. (cat:godot; multifile:no) [feat:xlite-20261112-add-a-back-button-to-the-tutorial-overla]
- [ ] [T3] scripts/tutorial/tutorial_overlay.gd — Add `var _back_button: Button` and instantiate it in `_build_ui()` between "Got it" and "Skip Tutorial" buttons with text "Back" connected to `_on_back_pressed`. VERIFY: `grep -q "_back_button.text = \"Back\"" scripts/tutorial/tutorial_overlay.gd`. (cat:godot; multifile:no) [feat:xlite-20261112-add-a-back-button-to-the-tutorial-overla]
- [ ] [T3] scripts/tutorial/tutorial_overlay.gd — Update `_refresh_step()` to set `_back_button.disabled = TutorialManager.is_first_step()` and ensure `_next_button` focus. VERIFY: `grep -q "_back_button.disabled = TutorialManager.is_first_step()" scripts/tutorial/tutorial_overlay.gd`. (cat:godot; multifile:no) [feat:xlite-20261112-add-a-back-button-to-the-tutorial-overla]
- [ ] [T2] tests/test_tutorial_back_button.gd — Create test file with setup/teardown for tutorial manager and overlay, adding test cases for `previous_step()` logic. VERIFY: `grep -q "func test_previous_step_at_zero" tests/test_tutorial_back_button.gd`. (cat:test; multifile:no) [feat:xlite-20261112-add-a-back-button-to-the-tutorial-overla]
- [ ] [T2] tests/test_tutorial_back_button.gd — Add test cases verifying Back button state changes (disabled at start, enabled after next, disabled after back to start). VERIFY: `grep -q "func test_back_button_state" tests/test_tutorial_back_button.gd`. (cat:test; multifile:no) [feat:xlite-20261112-add-a-back-button-to-the-tutorial-overla]
- [ ] [T4] scripts/tutorial/tutorial_manager.gd — Ensure `_step_index` is accessible or provide getter if needed for tests, verify integration with overlay. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_tutorial_back_button.gd -gexit`. (cat:godot; multifile:yes) [feat:xlite-20261112-add-a-back-button-to-the-tutorial-overla]

# --- 27B-decomposed from roadmap [2026-11-12]: Name the key or button for the step being taught - in `scripts/tutorial/tutorial_manager.g (review + tweak) [feat:xlite-20261112-name-the-key-or-button-for-the-step-bein] ---
- [ ] [T1] scripts/tutorial/tutorial_manager.gd — Add `static func step_input_action(highlight: String) -> String` returning `"tile_select"` for `"move"` and `"shoot"`, `"end_turn"` for `"end_turn"`, and `""` otherwise. VERIFY: `grep -q 'static func step_input_action' scripts/tutorial/tutorial_manager.gd && ~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_tutorial_step_input.gd -gexit`. (cat:godot; multifile:no) [feat:xlite-20261112-name-the-key-or-button-for-the-step-bein]
- [ ] [T1] scripts/tutorial/tutorial_overlay.gd — Add `static func input_mode_for(joypad_count: int) -> String` returning `GlyphHints.MODE_GAMEPAD` if `joypad_count > 0` else `GlyphHints.MODE_KEYBOARD_MOUSE`. VERIFY: `grep -q 'static func input_mode_for' scripts/tutorial/tutorial_overlay.gd && ~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_tutorial_step_input.gd -gexit`. (cat:godot; multifile:no) [feat:xlite-20261112-name-the-key-or-button-for-the-step-bein]
- [ ] [T3] scripts/tutorial/tutorial_overlay.gd — Modify `_refresh_step()` to append `"  (%s)" % GlyphHints.for_action(action, input_mode_for(Input.get_connected_joypads().size()))` to prompt text only when action is not empty and glyph is not `"—"`. VERIFY: `grep -q 'input_mode_for' scripts/tutorial/tutorial_overlay.gd && ~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_tutorial_step_input.gd -gexit`. (cat:godot; multifile:no) [feat:xlite-20261112-name-the-key-or-button-for-the-step-bein]
- [ ] [T2] tests/test_tutorial_step_input.gd — Create test file with static cases for `TutorialManager.step_input_action` (move, shoot, end_turn, overwatch, unknown) and `TutorialOverlay.input_mode_for` (0, 2). VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_tutorial_step_input.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20261112-name-the-key-or-button-for-the-step-bein]
- [ ] [T2] tests/test_tutorial_step_input.gd — Add overlay integration test verifying that after `TutorialManager.start()` and `overlay.setup({})` on step 1, the prompt label text contains `GlyphHints.for_action("tile_select", TutorialOverlay.input_mode_for(Input.get_connected_joypads().size()))`. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_tutorial_step_input.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20261112-name-the-key-or-button-for-the-step-bein]

# --- 27B-decomposed from roadmap [2026-11-12]: Show the volume slider as a percent - in `scripts/mission/mission_select.gd` add `static f (review + tweak) [feat:xlite-20261112-show-the-volume-slider-as-a-percent-in-s] ---

# --- 27B-decomposed from roadmap [2026-11-12]: Add a volume readout next to the slider - in `scripts/mission/mission_select.gd` add `stat (review + tweak) [feat:xlite-20261112-add-a-volume-readout-next-to-the-slider-] ---
- [ ] [T1] scripts/battle/aoe.gd — Add `static func volume_percent_for_db(db: float) -> int` that clamps `db` to [-80.0, 0.0] and returns `int(100.0 * pow(10.0, db / 20.0))`. VERIFY: `grep -q 'static func volume_percent_for_db' scripts/battle/aoe.gd`. (cat:godot; multifile:no) [feat:xlite-20261112-add-a-volume-readout-next-to-the-slider-]
- [ ] [T1] tests/test_aoe_volume_percent.gd — Create test file with cases verifying `Aoe.volume_percent_for_db(0.0)` is 100, `Aoe.volume_percent_for_db(-80.0)` is 0, and `Aoe.volume_percent_for_db(-6.0)` is 50. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_aoe_volume_percent.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20261112-add-a-volume-readout-next-to-the-slider-]

# --- 27B-decomposed from roadmap [2026-11-12]: Name the Start, Back and trigger inputs in the glyph hints - in `scripts/ui/glyph_hints.gd (review + tweak) [feat:xlite-20261112-name-the-start-back-and-trigger-inputs-i] ---
- [ ] [T1] scripts/ui/glyph_hints.gd — Add `JOY_BUTTON_START` returning `"Start"` and `JOY_BUTTON_BACK` returning `"Back"` to `_joypad_button_glyph` VERIFY: `grep -q 'JOY_BUTTON_START' scripts/ui/glyph_hints.gd && grep -q '"Start"' scripts/ui/glyph_hints.gd`. (cat:godot; multifile:no) [feat:xlite-20261112-name-the-start-back-and-trigger-inputs-i]
- [ ] [T1] scripts/ui/glyph_hints.gd — Add `JOY_AXIS_TRIGGER_LEFT` returning `"LT"` and `JOY_AXIS_TRIGGER_RIGHT` returning `"RT"` to `_joypad_axis_glyph` VERIFY: `grep -q 'JOY_AXIS_TRIGGER_LEFT' scripts/ui/glyph_hints.gd && grep -q '"LT"' scripts/ui/glyph_hints.gd`. (cat:godot; multifile:no) [feat:xlite-20261112-name-the-start-back-and-trigger-inputs-i]
- [ ] [T2] tests/test_glyph_hints_start_back_triggers.gd — Create test file with `after_each` cleanup for `gut_glyph_probe` action and test case for `JOY_BUTTON_START` asserting `"Start"` VERIFY: `grep -q 'JOY_BUTTON_START' tests/test_glyph_hints_start_back_triggers.gd && grep -q '"Start"' tests/test_glyph_hints_start_back_triggers.gd`. (cat:test; multifile:no) [feat:xlite-20261112-name-the-start-back-and-trigger-inputs-i]
- [ ] [T2] tests/test_glyph_hints_start_back_triggers.gd — Add test case for `JOY_BUTTON_BACK` asserting `"Back"` VERIFY: `grep -q 'JOY_BUTTON_BACK' tests/test_glyph_hints_start_back_triggers.gd && grep -q '"Back"' tests/test_glyph_hints_start_back_triggers.gd`. (cat:test; multifile:no) [feat:xlite-20261112-name-the-start-back-and-trigger-inputs-i]
- [ ] [T2] tests/test_glyph_hints_start_back_triggers.gd — Add test case for `JOY_AXIS_TRIGGER_LEFT` asserting `"LT"` VERIFY: `grep -q 'JOY_AXIS_TRIGGER_LEFT' tests/test_glyph_hints_start_back_triggers.gd && grep -q '"LT"' tests/test_glyph_hints_start_back_triggers.gd`. (cat:test; multifile:no) [feat:xlite-20261112-name-the-start-back-and-trigger-inputs-i]
- [ ] [T2] tests/test_glyph_hints_start_back_triggers.gd — Add test case for `JOY_AXIS_TRIGGER_RIGHT` asserting `"RT"` VERIFY: `grep -q 'JOY_AXIS_TRIGGER_RIGHT' tests/test_glyph_hints_start_back_triggers.gd && grep -q '"RT"' tests/test_glyph_hints_start_back_triggers.gd`. (cat:test; multifile:no) [feat:xlite-20261112-name-the-start-back-and-trigger-inputs-i]
- [ ] [T3] scripts/ui/glyph_hints.gd — Ensure `_joypad_button_glyph` and `_joypad_axis_glyph` handle new constants without breaking existing returns VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_glyph_hints_start_back_triggers.gd -gexit`. (cat:godot; multifile:no) [feat:xlite-20261112-name-the-start-back-and-trigger-inputs-i]

# --- 27B-decomposed from roadmap [2026-11-12]: Take the controls help column headers from one function - in `scripts/ui/glyph_hints.gd` a (review + tweak) [feat:xlite-20261112-take-the-controls-help-column-headers-fr] ---
- [ ] [T1] scripts/ui/glyph_hints.gd — Add static func device_label(mode: String) -> String that returns "Keyboard / Mouse" for MODE_KEYBOARD_MOUSE, "Gamepad" for MODE_GAMEPAD, and "" otherwise. VERIFY: `grep -q 'static func device_label' scripts/ui/glyph_hints.gd && grep -q 'return "Keyboard / Mouse"' scripts/ui/glyph_hints.gd && grep -q 'return "Gamepad"' scripts/ui/glyph_hints.gd` (cat:godot; multifile:no) [feat:xlite-20261112-take-the-controls-help-column-headers-fr]
- [ ] [T3] scripts/ui/controls_help.gd — In _populate(), replace the string literal "Keyboard / Mouse" passed to _add_header with GlyphHints.device_label(GlyphHints.MODE_KEYBOARD_MOUSE). VERIFY: `grep -q 'GlyphHints.device_label(GlyphHints.MODE_KEYBOARD_MOUSE)' scripts/ui/controls_help.gd && ! grep -q '"Keyboard / Mouse"' scripts/ui/controls_help.gd` (cat:godot; multifile:no) [feat:xlite-20261112-take-the-controls-help-column-headers-fr]
- [ ] [T4] scripts/ui/controls_help.gd — In _populate(), replace the string literal "Gamepad" passed to _add_header with GlyphHints.device_label(GlyphHints.MODE_GAMEPAD). VERIFY: `grep -q 'GlyphHints.device_label(GlyphHints.MODE_GAMEPAD)' scripts/ui/controls_help.gd && ! grep -q '"Gamepad"' scripts/ui/controls_help.gd` (cat:godot; multifile:no) [feat:xlite-20261112-take-the-controls-help-column-headers-fr]
- [ ] [T2] tests/test_glyph_hints_device_label.gd — Create test file with GUT test cases verifying GlyphHints.device_label returns correct strings for MODE_KEYBOARD_MOUSE, MODE_GAMEPAD, and an invalid mode. VERIFY: ~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_glyph_hints_device_label.gd -gexit 2>&1 | grep -q "0 failing". (cat:test; multifile:no) [feat:xlite-20261112-take-the-controls-help-column-headers-fr]
- [ ] [T5] tests/test_glyph_hints_device_label.gd — Add test case that instantiates res://scenes/controls_help.tscn and verifies header row texts still include "Keyboard / Mouse" and "Gamepad". VERIFY: ~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_glyph_hints_device_label.gd -gexit 2>&1 | grep -q "0 failing". (cat:test; multifile:no) [feat:xlite-20261112-take-the-controls-help-column-headers-fr]

# --- 27B-decomposed from roadmap [2026-11-12]: Add plain tooltips to the settings widgets - in `scripts/mission/mission_select.gd` add `s (review + tweak) [feat:xlite-20261112-add-plain-tooltips-to-the-settings-widge] ---
- [ ] [T1] scripts/mission/mission_select.gd — Add `const _SETTING_TOOLTIPS := { "volume": "Master volume for sound effects and music", "mute": "Silence all audio without changing the volume", "quality": "Rendering quality preset", "shadows": "Draw unit shadows", "fullscreen": "Switch between windowed and fullscreen", "large_text": "Scale menu text up", "colorblind": "Use colourblind-safe markers and colours" }` and `static func setting_tooltip(key: String) -> String: return _SETTING_TOOLTIPS.get(key, "")`. VERIFY: `grep -q 'const _SETTING_TOOLTIPS' scripts/mission/mission_select.gd && grep -q 'static func setting_tooltip' scripts/mission/mission_select.gd` (cat:godot; multifile:no) [feat:xlite-20261112-add-plain-tooltips-to-the-settings-widge]
- [ ] [T3] scripts/mission/mission_select.gd — In `_setup_settings_panel()`, set `tooltip_text = setting_tooltip("volume")` on the volume slider. VERIFY: `grep -q 'tooltip_text = setting_tooltip("volume")' scripts/mission/mission_select.gd` (cat:godot; multifile:no) [feat:xlite-20261112-add-plain-tooltips-to-the-settings-widge]
- [ ] [T3] scripts/mission/mission_select.gd — In `_setup_settings_panel()`, set `tooltip_text = setting_tooltip("mute")` on the mute button. VERIFY: `grep -q 'tooltip_text = setting_tooltip("mute")' scripts/mission/mission_select.gd` (cat:godot; multifile:no) [feat:xlite-20261112-add-plain-tooltips-to-the-settings-widge]
- [ ] [T3] scripts/mission/mission_select.gd — In `_setup_settings_panel()`, set `tooltip_text = setting_tooltip("quality")` on `quality_option_box`. VERIFY: `grep -q 'tooltip_text = setting_tooltip("quality")' scripts/mission/mission_select.gd` (cat:godot; multifile:no) [feat:xlite-20261112-add-plain-tooltips-to-the-settings-widge]
- [ ] [T3] scripts/mission/mission_select.gd — In `_setup_settings_panel()`, set `tooltip_text = setting_tooltip("shadows")` on `shadow_check`. VERIFY: `grep -q 'tooltip_text = setting_tooltip("shadows")' scripts/mission/mission_select.gd` (cat:godot; multifile:no) [feat:xlite-20261112-add-plain-tooltips-to-the-settings-widge]
- [ ] [T3] scripts/mission/mission_select.gd — In `_setup_settings_panel()`, set `tooltip_text = setting_tooltip("fullscreen")` on `fullscreen_check`. VERIFY: `grep -q 'tooltip_text = setting_tooltip("fullscreen")' scripts/mission/mission_select.gd` (cat:godot; multifile:no) [feat:xlite-20261112-add-plain-tooltips-to-the-settings-widge]
- [ ] [T3] scripts/mission/mission_select.gd — In `_setup_settings_panel()`, set `tooltip_text = setting_tooltip("large_text")` on `large_text_check`. VERIFY: `grep -q 'tooltip_text = setting_tooltip("large_text")' scripts/mission/mission_select.gd` (cat:godot; multifile:no) [feat:xlite-20261112-add-plain-tooltips-to-the-settings-widge]
- [ ] [T3] scripts/mission/mission_select.gd — In `_setup_settings_panel()`, set `tooltip_text = setting_tooltip("colorblind")` on `colorblind_check`. VERIFY: `grep -q 'tooltip_text = setting_tooltip("colorblind")' scripts/mission/mission_select.gd && ~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_mission_select_setting_tooltip.gd -gexit` (cat:godot; multifile:no) [feat:xlite-20261112-add-plain-tooltips-to-the-settings-widge]
- [ ] [T2] tests/test_mission_select_setting_tooltip.gd — Create test file extending `GutTest` with `test_setting_tooltip_values()` asserting all 7 keys return exact strings and `test_setting_tooltip_unknown()` asserting `""` for "unknown_key", and `test_no_exclamation_marks()` iterating keys to ensure no `!`. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_mission_select_setting_tooltip.gd -gexit` (cat:test; multifile:no) [feat:xlite-20261112-add-plain-tooltips-to-the-settings-widge]

# --- 27B-decomposed from roadmap [2026-11-12]: Add the Loc hook and use it in the save slot picker - create `scripts/ui/loc.gd` with `cla (review + tweak) [feat:xlite-20261112-add-the-loc-hook-and-use-it-in-the-save-] ---
- [ ] [T2] scripts/ui/loc.gd — Add static `tf(key: String, fallback: String, args: Array) -> String` that calls `t` and replaces `"{%d}" % i` with `str(args[i])` for each index. VERIFY: `grep -q 'static func tf' scripts/ui/loc.gd && grep -q '"{%d}" % i' scripts/ui/loc.gd`. (cat:godot; multifile:no) [feat:xlite-20261112-add-the-loc-hook-and-use-it-in-the-save-]
- [ ] [T1] scripts/ui/loc.gd — Add `class_name Loc` extending `RefCounted` with static `t(key: String, fallback: String) -> String` that returns `fallback` if key is empty or translation is empty/equal to key, else the translated string. VERIFY: `grep -q 'class_name Loc' scripts/ui/loc.gd && grep -q 'static func t' scripts/ui/loc.gd`. (cat:godot; multifile:no) [feat:xlite-20261112-add-the-loc-hook-and-use-it-in-the-save-]
- [ ] [T3] tests/test_loc.gd — Create test file verifying `Loc.t` returns fallback for missing/empty keys and correct translation for registered keys, and `Loc.tf` performs placeholder replacement without `%` formatting errors. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_loc.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20261112-add-the-loc-hook-and-use-it-in-the-save-]
- [ ] [T4] scripts/mission/save_slot_select.gd — Replace hardcoded "Save Slots" title text with `Loc.t("ui.save_slots.title", "Save Slots")`. VERIFY: `grep -q 'Loc.t("ui.save_slots.title", "Save Slots")' scripts/mission/save_slot_select.gd`. (cat:godot; multifile:no) [feat:xlite-20261112-add-the-loc-hook-and-use-it-in-the-save-]
- [ ] [T5] scripts/mission/save_slot_select.gd — Replace hardcoded hint text with `Loc.t("ui.save_slots.hint", "Continue a saved run, or start a new one.")`. VERIFY: `grep -q 'Loc.t("ui.save_slots.hint", "Continue a saved run, or start a new one.")' scripts/mission/save_slot_select.gd`. (cat:godot; multifile:no) [feat:xlite-20261112-add-the-loc-hook-and-use-it-in-the-save-]
