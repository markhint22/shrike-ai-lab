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
- [ ] [T4] scripts/battle/burst_fire.gd — Add a doc comment above `hit_percent_needed` explaining it feeds a "will this burst kill?" preview tooltip, and that it is the inverse of `expected_damage`. VERIFY: `grep -q "inverse of" scripts/battle/burst_fire.gd`. (cat:docs; multifile:no) [feat:xlite-20260922-burstfire-hit-percent-needed]
- [ ] [T5] tests — Run the full GUT suite once to confirm `hit_percent_needed` caused zero regressions elsewhere. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-burstfire-hit-percent-needed]

# --- Claude-decomposed from roadmap [2026-09-22]: ArmorPen damage-reduced-percentage — scripts/battle/armor_pen.gd ---
- [ ] [T1] scripts/battle/armor_pen.gd — Add `static func damage_reduced_percent(raw: int, armor: int, pen: int) -> int` (percent of raw damage absorbed by armor after pen, for a damage-preview tooltip): return 0 if `raw <= 0`; otherwise `clampi((raw - mitigated(raw, armor, pen)) * 100 / raw, 0, 100)`, reusing the existing `mitigated` helper rather than recomputing its math. VERIFY: `grep -q "static func damage_reduced_percent" scripts/battle/armor_pen.gd`. (cat:godot; multifile:no) [feat:xlite-20260922-armorpen-damage-reduced-percent]
- [ ] [T2] tests/test_armor_pen_reduced_percent.gd — Create new GUT test file (`extends GutTest`) with `test_partial_reduction` asserting `ArmorPen.damage_reduced_percent(100, 30, 10) == 20`. VERIFY: `grep -q "extends GutTest" tests/test_armor_pen_reduced_percent.gd`. (cat:test; multifile:no) [feat:xlite-20260922-armorpen-damage-reduced-percent]
- [ ] [T2] tests/test_armor_pen_reduced_percent.gd — Add `test_no_armor_reduces_nothing` asserting `ArmorPen.damage_reduced_percent(100, 0, 0) == 0`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_armor_pen_reduced_percent.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-armorpen-damage-reduced-percent]
- [ ] [T2] tests/test_armor_pen_reduced_percent.gd — Add `test_armor_exceeding_raw_fully_absorbs` asserting `ArmorPen.damage_reduced_percent(50, 100, 0) == 100`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_armor_pen_reduced_percent.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-armorpen-damage-reduced-percent]
- [ ] [T3] tests/test_armor_pen_reduced_percent.gd — Add `test_pen_fully_cancels_armor` asserting `ArmorPen.damage_reduced_percent(100, 30, 30) == 0`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_armor_pen_reduced_percent.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-armorpen-damage-reduced-percent]
- [ ] [T3] tests/test_armor_pen_reduced_percent.gd — Add `test_zero_raw_damage_guard` asserting `ArmorPen.damage_reduced_percent(0, 30, 10) == 0`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_armor_pen_reduced_percent.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-armorpen-damage-reduced-percent]
- [ ] [T4] tests/test_armor_pen_reduced_percent.gd — Add `test_negative_raw_damage_guard` asserting `ArmorPen.damage_reduced_percent(-10, 30, 10) == 0`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_armor_pen_reduced_percent.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-armorpen-damage-reduced-percent]
- [ ] [T4] scripts/battle/armor_pen.gd — Add a doc comment above `damage_reduced_percent` explaining it is a UI-facing percent form of the existing `mitigated`, for a damage-preview tooltip. VERIFY: `grep -q "damage-preview" scripts/battle/armor_pen.gd`. (cat:docs; multifile:no) [feat:xlite-20260922-armorpen-damage-reduced-percent]
- [ ] [T5] tests — Run the full GUT suite once to confirm `damage_reduced_percent` caused zero regressions elsewhere. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-armorpen-damage-reduced-percent]

# --- Claude-decomposed from roadmap [2026-09-22]: SlotName index-from-label inverse — scripts/save/slot_name.gd ---
- [ ] [T1] scripts/save/slot_name.gd — Add `static func index_from_label(label: String) -> int` (inverse of `slot_label`): return -1 if `label` doesn't start with `"Slot "`; otherwise take the substring after it, return -1 if it isn't a valid integer (`String.is_valid_int()`), else `maxi(label.substr(5).to_int() - 1, 0)`. VERIFY: `grep -q "static func index_from_label" scripts/save/slot_name.gd`. (cat:godot; multifile:no) [feat:xlite-20260922-slotname-index-from-label]
- [ ] [T2] tests/test_slot_name_index_from_label.gd — Create new GUT test file (`extends GutTest`) with `test_first_slot` asserting `SlotName.index_from_label("Slot 1") == 0`. VERIFY: `grep -q "extends GutTest" tests/test_slot_name_index_from_label.gd`. (cat:test; multifile:no) [feat:xlite-20260922-slotname-index-from-label]
- [ ] [T2] tests/test_slot_name_index_from_label.gd — Add `test_later_slot` asserting `SlotName.index_from_label("Slot 5") == 4`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_slot_name_index_from_label.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-slotname-index-from-label]
- [ ] [T2] tests/test_slot_name_index_from_label.gd — Add `test_roundtrip_with_slot_label` asserting `SlotName.index_from_label(SlotName.slot_label(3)) == 3`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_slot_name_index_from_label.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-slotname-index-from-label]
- [ ] [T3] tests/test_slot_name_index_from_label.gd — Add `test_wrong_prefix_returns_negative_one` asserting `SlotName.index_from_label("Bad Label") == -1`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_slot_name_index_from_label.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-slotname-index-from-label]
- [ ] [T3] tests/test_slot_name_index_from_label.gd — Add `test_non_numeric_suffix_returns_negative_one` asserting `SlotName.index_from_label("Slot abc") == -1`. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_slot_name_index_from_label.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-slotname-index-from-label]
- [ ] [T4] tests/test_slot_name_index_from_label.gd — Add `test_slot_zero_clamps_to_zero` asserting `SlotName.index_from_label("Slot 0") == 0` (a malformed 1-based label below the minimum still clamps rather than going negative). VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_slot_name_index_from_label.gd -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-slotname-index-from-label]
- [ ] [T4] scripts/save/slot_name.gd — Add a doc comment above `index_from_label` explaining it is the inverse of `slot_label`, returning -1 (matching the codebase's existing not-found sentinel convention, e.g. `TieBreaker.lowest_id`) for any malformed label. VERIFY: `grep -q "inverse" scripts/save/slot_name.gd`. (cat:docs; multifile:no) [feat:xlite-20260922-slotname-index-from-label]
- [ ] [T5] tests — Run the full GUT suite once to confirm `index_from_label` caused zero regressions elsewhere. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`. (cat:test; multifile:no) [feat:xlite-20260922-slotname-index-from-label]
