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
- [ ] [T2] tests/test_reload_cost_ap_after.gd — Add `test_nothing_missing_keeps_full_ap` asserting `ReloadCost.ap_after_reload(5, 0, 2) == 5`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_reload_cost_ap_after.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-reloadcost-ap-after]
- [ ] [T3] tests/test_reload_cost_ap_after.gd — Add `test_zero_per_clip_costs_nothing` asserting `ReloadCost.ap_after_reload(5, 3, 0) == 5`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_reload_cost_ap_after.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-reloadcost-ap-after]
- [ ] [T3] tests/test_reload_cost_ap_after.gd — Add `test_exact_afford` asserting `ReloadCost.ap_after_reload(2, 3, 2) == 0`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_reload_cost_ap_after.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-reloadcost-ap-after]
- [ ] [T4] scripts/battle/reload_cost.gd — Add a doc comment above `ap_after_reload` explaining it is the "remaining AP after paying to reload" complement to `ap_to_reload`. VERIFY: `grep -q "remaining" scripts/battle/reload_cost.gd`. (cat:docs; multifile:no) [feat:xlite-20260922-reloadcost-ap-after]
- [ ] [T5] tests — Run the full GUT suite once to confirm `ap_after_reload` caused zero regressions elsewhere. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-reloadcost-ap-after]

# --- Claude-decomposed from roadmap [2026-09-22 deep pass]: ThreatPreview is_threatened — scripts/battle/threat_preview.gd ---
- [ ] [T1] scripts/battle/threat_preview.gd — Add `static func is_threatened(cell: Vector2i, enemy_pos: Vector2i, rng: int) -> bool`: `absi(cell.x - enemy_pos.x) + absi(cell.y - enemy_pos.y) <= rng`, matching `threatened_cells`' own diamond-distance formula exactly. VERIFY: `grep -q "static func is_threatened" scripts/battle/threat_preview.gd`. (cat:godot; multifile:no) [feat:xlite-20260922-threatpreview-is-threatened]
- [ ] [T2] tests/test_threat_preview_is_threatened.gd — Create new GUT test file (`extends GutTest`) with `test_within_range` asserting `ThreatPreview.is_threatened(Vector2i(1, 0), Vector2i(0, 0), 2)`. VERIFY: `grep -q "extends GutTest" tests/test_threat_preview_is_threatened.gd`. (cat:test; multifile:no) [feat:xlite-20260922-threatpreview-is-threatened]
- [ ] [T2] tests/test_threat_preview_is_threatened.gd — Add `test_outside_range` asserting `not ThreatPreview.is_threatened(Vector2i(5, 5), Vector2i(0, 0), 2)`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_threat_preview_is_threatened.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-threatpreview-is-threatened]
- [ ] [T2] tests/test_threat_preview_is_threatened.gd — Add `test_matches_threatened_cells_membership` asserting `ThreatPreview.is_threatened(Vector2i(2, 1), Vector2i(0, 0), 3) == ThreatPreview.threatened_cells(Vector2i(0, 0), 3).has(Vector2i(2, 1))`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_threat_preview_is_threatened.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-threatpreview-is-threatened]
- [ ] [T3] tests/test_threat_preview_is_threatened.gd — Add `test_own_cell_is_threatened` asserting `ThreatPreview.is_threatened(Vector2i(0, 0), Vector2i(0, 0), 0)`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_threat_preview_is_threatened.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-threatpreview-is-threatened]
- [ ] [T3] tests/test_threat_preview_is_threatened.gd — Add `test_boundary_cell_is_threatened` asserting `ThreatPreview.is_threatened(Vector2i(2, 0), Vector2i(0, 0), 2)`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_threat_preview_is_threatened.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-threatpreview-is-threatened]
- [ ] [T4] scripts/battle/threat_preview.gd — Add a doc comment above `is_threatened` explaining it is a per-cell membership check avoiding a full `threatened_cells` array build. VERIFY: `grep -q "per-cell" scripts/battle/threat_preview.gd`. (cat:docs; multifile:no) [feat:xlite-20260922-threatpreview-is-threatened]
- [ ] [T5] tests — Run the full GUT suite once to confirm `is_threatened` caused zero regressions elsewhere. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-threatpreview-is-threatened]

# --- Claude-decomposed from roadmap [2026-09-22 deep pass]: Hazard damage-over-turns — scripts/mission/hazard.gd ---
- [ ] [T1] scripts/mission/hazard.gd — Add `static func damage_over_turns(hazard_tier: int, base: int, turns: int) -> int`: return 0 if `turns <= 0`; otherwise `damage_on_enter(hazard_tier, base) * turns`, reusing `damage_on_enter` rather than reimplementing it. VERIFY: `grep -q "static func damage_over_turns" scripts/mission/hazard.gd`. (cat:godot; multifile:no) [feat:xlite-20260922-hazard-damage-over-turns]
- [ ] [T2] tests/test_hazard_damage_over_turns.gd — Create new GUT test file (`extends GutTest`) with `test_multiple_turns` asserting `Hazard.damage_over_turns(2, 5, 3) == Hazard.damage_on_enter(2, 5) * 3`. VERIFY: `grep -q "extends GutTest" tests/test_hazard_damage_over_turns.gd`. (cat:test; multifile:no) [feat:xlite-20260922-hazard-damage-over-turns]
- [ ] [T2] tests/test_hazard_damage_over_turns.gd — Add `test_concrete_value` asserting `Hazard.damage_over_turns(2, 5, 3) == 21`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_hazard_damage_over_turns.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-hazard-damage-over-turns]
- [ ] [T2] tests/test_hazard_damage_over_turns.gd — Add `test_zero_turns_is_zero_damage` asserting `Hazard.damage_over_turns(2, 5, 0) == 0`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_hazard_damage_over_turns.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-hazard-damage-over-turns]
- [ ] [T3] tests/test_hazard_damage_over_turns.gd — Add `test_negative_turns_is_zero_damage` asserting `Hazard.damage_over_turns(2, 5, -1) == 0`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_hazard_damage_over_turns.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-hazard-damage-over-turns]
- [ ] [T3] tests/test_hazard_damage_over_turns.gd — Add `test_zero_tier_uses_base_only` asserting `Hazard.damage_over_turns(0, 5, 3) == 15`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_hazard_damage_over_turns.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-hazard-damage-over-turns]
- [ ] [T4] scripts/mission/hazard.gd — Add a doc comment above `damage_over_turns` explaining it feeds a "don't stand here N turns" warning tooltip. VERIFY: `grep -q "warning" scripts/mission/hazard.gd`. (cat:docs; multifile:no) [feat:xlite-20260922-hazard-damage-over-turns]
- [ ] [T5] tests — Run the full GUT suite once to confirm `damage_over_turns` caused zero regressions elsewhere. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-hazard-damage-over-turns]

# --- Claude-decomposed from roadmap [2026-09-22 deep pass]: CounterAttack remaining-ap-after-counter — scripts/battle/counter_attack.gd ---
- [ ] [T1] scripts/battle/counter_attack.gd — Add `static func remaining_ap_after_counter(defender_ap: int, counter_cost: int) -> int`: `maxi(defender_ap - maxi(counter_cost, 0), 0)`. VERIFY: `grep -q "static func remaining_ap_after_counter" scripts/battle/counter_attack.gd`. (cat:godot; multifile:no) [feat:xlite-20260922-counterattack-remaining-ap]
- [ ] [T2] tests/test_counter_attack_remaining_ap.gd — Create new GUT test file (`extends GutTest`) with `test_affordable_counter` asserting `CounterAttack.remaining_ap_after_counter(5, 2) == 3`. VERIFY: `grep -q "extends GutTest" tests/test_counter_attack_remaining_ap.gd`. (cat:test; multifile:no) [feat:xlite-20260922-counterattack-remaining-ap]
- [ ] [T2] tests/test_counter_attack_remaining_ap.gd — Add `test_exact_afford` asserting `CounterAttack.remaining_ap_after_counter(2, 2) == 0`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_counter_attack_remaining_ap.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-counterattack-remaining-ap]
- [ ] [T2] tests/test_counter_attack_remaining_ap.gd — Add `test_insufficient_ap_floors_at_zero` asserting `CounterAttack.remaining_ap_after_counter(1, 2) == 0`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_counter_attack_remaining_ap.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-counterattack-remaining-ap]
- [ ] [T3] tests/test_counter_attack_remaining_ap.gd — Add `test_negative_cost_treated_as_zero` asserting `CounterAttack.remaining_ap_after_counter(5, -2) == 5`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_counter_attack_remaining_ap.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-counterattack-remaining-ap]
- [ ] [T3] tests/test_counter_attack_remaining_ap.gd — Add `test_zero_ap_stays_zero` asserting `CounterAttack.remaining_ap_after_counter(0, 2) == 0`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_counter_attack_remaining_ap.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-counterattack-remaining-ap]
- [ ] [T4] scripts/battle/counter_attack.gd — Add a doc comment above `remaining_ap_after_counter` explaining it is a "remaining-after-spend" AP helper for a defender's action bar. VERIFY: `grep -q "remaining-after-spend" scripts/battle/counter_attack.gd`. (cat:docs; multifile:no) [feat:xlite-20260922-counterattack-remaining-ap]
- [ ] [T5] tests — Run the full GUT suite once to confirm `remaining_ap_after_counter` caused zero regressions elsewhere. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-counterattack-remaining-ap]

# --- Claude-decomposed from roadmap [2026-09-22 deep pass]: DamageFalloff falloff-percent — scripts/battle/damage_falloff.gd ---
- [ ] [T1] scripts/battle/damage_falloff.gd — Add `static func falloff_percent(dist: int, optimal: int) -> int` implemented as `return 100 - damage_at(100, dist, optimal)`, reusing `damage_at`'s existing float math via a synthetic base of 100 rather than duplicating it. VERIFY: `grep -q "static func falloff_percent" scripts/battle/damage_falloff.gd`. (cat:godot; multifile:no) [feat:xlite-20260922-damagefalloff-percent]
- [ ] [T2] tests/test_damage_falloff_percent.gd — Create new GUT test file (`extends GutTest`) with `test_no_falloff_at_optimal` asserting `DamageFalloff.falloff_percent(3, 3) == 0`. VERIFY: `grep -q "extends GutTest" tests/test_damage_falloff_percent.gd`. (cat:test; multifile:no) [feat:xlite-20260922-damagefalloff-percent]
- [ ] [T2] tests/test_damage_falloff_percent.gd — Add `test_falloff_beyond_optimal` asserting `DamageFalloff.falloff_percent(5, 3) == 20`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_damage_falloff_percent.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-damagefalloff-percent]
- [ ] [T2] tests/test_damage_falloff_percent.gd — Add `test_within_optimal_no_falloff` asserting `DamageFalloff.falloff_percent(1, 3) == 0`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_damage_falloff_percent.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-damagefalloff-percent]
- [ ] [T3] tests/test_damage_falloff_percent.gd — Add `test_matches_damage_at_relationship` asserting `DamageFalloff.falloff_percent(8, 3) == 100 - DamageFalloff.damage_at(100, 8, 3)`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_damage_falloff_percent.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-damagefalloff-percent]
- [ ] [T3] tests/test_damage_falloff_percent.gd — Add `test_extreme_distance_never_exceeds_75_percent_falloff` asserting `DamageFalloff.falloff_percent(50, 3) <= 75`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_damage_falloff_percent.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-damagefalloff-percent]
- [ ] [T4] scripts/battle/damage_falloff.gd — Add a doc comment above `falloff_percent` explaining it is a UI-facing percent form of `damage_at`, for a range-indicator overlay. VERIFY: `grep -q "range-indicator" scripts/battle/damage_falloff.gd`. (cat:docs; multifile:no) [feat:xlite-20260922-damagefalloff-percent]
- [ ] [T5] tests — Run the full GUT suite once to confirm `falloff_percent` caused zero regressions elsewhere. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-damagefalloff-percent]

# --- Claude-decomposed from roadmap [2026-09-22 deep pass]: Lifesteal overheal-wasted — scripts/battle/lifesteal.gd ---
- [ ] [T1] scripts/battle/lifesteal.gd — Add `static func overheal_wasted(current: int, heal: int, max_hp: int) -> int`: `maxi((current + heal) - max_hp, 0)`. VERIFY: `grep -q "static func overheal_wasted" scripts/battle/lifesteal.gd`. (cat:godot; multifile:no) [feat:xlite-20260922-lifesteal-overheal-wasted]
- [ ] [T2] tests/test_lifesteal_overheal_wasted.gd — Create new GUT test file (`extends GutTest`) with `test_overheal_wasted` asserting `Lifesteal.overheal_wasted(90, 30, 100) == 20`. VERIFY: `grep -q "extends GutTest" tests/test_lifesteal_overheal_wasted.gd`. (cat:test; multifile:no) [feat:xlite-20260922-lifesteal-overheal-wasted]
- [ ] [T2] tests/test_lifesteal_overheal_wasted.gd — Add `test_no_overheal_is_zero` asserting `Lifesteal.overheal_wasted(50, 30, 100) == 0`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_lifesteal_overheal_wasted.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-lifesteal-overheal-wasted]
- [ ] [T2] tests/test_lifesteal_overheal_wasted.gd — Add `test_exact_fill_is_zero_waste` asserting `Lifesteal.overheal_wasted(70, 30, 100) == 0`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_lifesteal_overheal_wasted.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-lifesteal-overheal-wasted]
- [ ] [T3] tests/test_lifesteal_overheal_wasted.gd — Add `test_zero_heal_is_zero_waste` asserting `Lifesteal.overheal_wasted(90, 0, 100) == 0`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_lifesteal_overheal_wasted.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-lifesteal-overheal-wasted]
- [ ] [T3] tests/test_lifesteal_overheal_wasted.gd — Add `test_matches_capped_heal_relationship` asserting `Lifesteal.capped_heal(90, 30, 100) + Lifesteal.overheal_wasted(90, 30, 100) == 90 + 30`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_lifesteal_overheal_wasted.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-lifesteal-overheal-wasted]
- [ ] [T4] scripts/battle/lifesteal.gd — Add a doc comment above `overheal_wasted` explaining it mirrors `HealCalc.overheal_wasted`'s shape for the separate lifesteal domain. VERIFY: `grep -q "mirrors" scripts/battle/lifesteal.gd`. (cat:docs; multifile:no) [feat:xlite-20260922-lifesteal-overheal-wasted]
- [ ] [T5] tests — Run the full GUT suite once to confirm `overheal_wasted` caused zero regressions elsewhere. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-lifesteal-overheal-wasted]

# --- Claude-decomposed from roadmap [2026-09-22 deep pass]: StreakBonus hits-to-cap — scripts/battle/streak_bonus.gd ---
- [ ] [T1] scripts/battle/streak_bonus.gd — Add `static func hits_to_cap(consecutive_hits: int, per_hit: int, cap: int) -> int`: let `current = bonus(consecutive_hits, per_hit, cap)`; return 0 if `current >= cap`; return -1 if `per_hit <= 0`; otherwise `ceili(float(cap - current) / float(per_hit))`, reusing `bonus` rather than recomputing it. VERIFY: `grep -q "static func hits_to_cap" scripts/battle/streak_bonus.gd`. (cat:godot; multifile:no) [feat:xlite-20260922-streakbonus-hits-to-cap]
- [ ] [T2] tests/test_streak_bonus_hits_to_cap.gd — Create new GUT test file (`extends GutTest`) with `test_from_zero` asserting `StreakBonus.hits_to_cap(0, 5, 20) == 4`. VERIFY: `grep -q "extends GutTest" tests/test_streak_bonus_hits_to_cap.gd`. (cat:test; multifile:no) [feat:xlite-20260922-streakbonus-hits-to-cap]
- [ ] [T2] tests/test_streak_bonus_hits_to_cap.gd — Add `test_partway_there` asserting `StreakBonus.hits_to_cap(2, 5, 20) == 2`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_streak_bonus_hits_to_cap.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-streakbonus-hits-to-cap]
- [ ] [T2] tests/test_streak_bonus_hits_to_cap.gd — Add `test_already_capped` asserting `StreakBonus.hits_to_cap(4, 5, 20) == 0`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_streak_bonus_hits_to_cap.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-streakbonus-hits-to-cap]
- [ ] [T3] tests/test_streak_bonus_hits_to_cap.gd — Add `test_zero_per_hit_is_unreachable` asserting `StreakBonus.hits_to_cap(0, 0, 20) == -1`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_streak_bonus_hits_to_cap.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-streakbonus-hits-to-cap]
- [ ] [T3] tests/test_streak_bonus_hits_to_cap.gd — Add `test_roundtrip_reaches_cap` asserting `StreakBonus.bonus(2 + StreakBonus.hits_to_cap(2, 5, 20), 5, 20) == 20`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_streak_bonus_hits_to_cap.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-streakbonus-hits-to-cap]
- [ ] [T4] scripts/battle/streak_bonus.gd — Add a doc comment above `hits_to_cap` explaining it is the inverse of `bonus`, for a "N more hits to max streak" combat-log callout. VERIFY: `grep -q "inverse" scripts/battle/streak_bonus.gd`. (cat:docs; multifile:no) [feat:xlite-20260922-streakbonus-hits-to-cap]
- [ ] [T5] tests — Run the full GUT suite once to confirm `hits_to_cap` caused zero regressions elsewhere. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-streakbonus-hits-to-cap]

# --- Claude-decomposed from roadmap [2026-09-22 deep pass]: DamageVariance roll-percent-of-range — scripts/battle/damage_variance.gd ---
- [ ] [T1] scripts/battle/damage_variance.gd — Add `static func roll_percent_of_range(roll: int, base: int, variance_pct: int) -> int`: let `lo = min_roll(base, variance_pct)`, `hi = max_roll(base, variance_pct)`; return 100 if `hi <= lo`; otherwise `clampi((roll - lo) * 100 / (hi - lo), 0, 100)`, reusing `min_roll`/`max_roll` rather than recomputing them. VERIFY: `grep -q "static func roll_percent_of_range" scripts/battle/damage_variance.gd`. (cat:godot; multifile:no) [feat:xlite-20260922-damagevariance-roll-percent]
- [ ] [T2] tests/test_damage_variance_roll_percent.gd — Create new GUT test file (`extends GutTest`) with `test_lowest_roll_is_zero_percent` asserting `DamageVariance.roll_percent_of_range(90, 100, 10) == 0`. VERIFY: `grep -q "extends GutTest" tests/test_damage_variance_roll_percent.gd`. (cat:test; multifile:no) [feat:xlite-20260922-damagevariance-roll-percent]
- [ ] [T2] tests/test_damage_variance_roll_percent.gd — Add `test_highest_roll_is_hundred_percent` asserting `DamageVariance.roll_percent_of_range(110, 100, 10) == 100`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_damage_variance_roll_percent.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-damagevariance-roll-percent]
- [ ] [T2] tests/test_damage_variance_roll_percent.gd — Add `test_midpoint_roll_is_fifty_percent` asserting `DamageVariance.roll_percent_of_range(100, 100, 10) == 50`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_damage_variance_roll_percent.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-damagevariance-roll-percent]
- [ ] [T3] tests/test_damage_variance_roll_percent.gd — Add `test_zero_variance_band_returns_hundred` asserting `DamageVariance.roll_percent_of_range(100, 100, 0) == 100`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_damage_variance_roll_percent.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-damagevariance-roll-percent]
- [ ] [T3] tests/test_damage_variance_roll_percent.gd — Add `test_out_of_band_roll_clamps` asserting `DamageVariance.roll_percent_of_range(200, 100, 10) == 100` and `DamageVariance.roll_percent_of_range(0, 100, 10) == 0`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_damage_variance_roll_percent.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-damagevariance-roll-percent]
- [ ] [T4] scripts/battle/damage_variance.gd — Add a doc comment above `roll_percent_of_range` explaining it feeds a "high roll!" damage-number flourish. VERIFY: `grep -q "flourish" scripts/battle/damage_variance.gd`. (cat:docs; multifile:no) [feat:xlite-20260922-damagevariance-roll-percent]
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
