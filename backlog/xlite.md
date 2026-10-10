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
