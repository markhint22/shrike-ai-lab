#!/usr/bin/env bash
# Run the full overnight-queue regression suite. Exit 0 = all green.
cd "$(dirname "$0")"
# 2026-09-30: never let the suite reach the real ntfy.sh (shared per-IP quota; tests exhausted it and silenced all production alerts)
HERE_RA="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE_RA/ntfy_guard.sh"
rc=0
echo "===== Canonical GOOD/BAD/BENIGN outcome classifier (pass-rate metrics-integrity fix) ====="; python3 test_outcome_buckets.py || rc=1
echo; echo "===== lib_item_select (real-item resolver — scout-file match over blind top-of-file) ====="; bash test_lib_item_select.sh || rc=1
echo; echo "===== BUILD-GATE Variant-type grounding (Dictionary/Array runtime errors stay tests:FAIL) ====="; bash test_buildgate_variant_type_grounding.sh || rc=1
echo; echo "===== Recover-parked lineage normalization (path-phrasing no longer bypasses RECOVERY_LINEAGE_CAP) ====="; bash test_recover_parked_lineage_normalization.sh || rc=1
echo; echo "===== Recover-parked already-satisfied filter (decomposed sub-items no longer resurface checked-off work) ====="; bash test_recover_parked_already_satisfied_filter.sh || rc=1
echo; echo "===== Queue-refill roadmap-aware dry check (backlog-drained-but-roadmap-has-fuel is not genuine dry) ====="; bash test_queue_refill_roadmap_aware_dry.sh || rc=1
echo; echo "===== Implement-time ALREADY-DONE classification (no-change-needed mid-implement is benign, not a flail) ====="; bash test_implement_time_already_done.sh || rc=1
echo; echo "===== Residue-guard salvage check (timeout-truncated but passing work is re-verified before discard) ====="; bash test_residue_guard_salvage.sh || rc=1
echo; echo "===== Python helpers ====="; python3 test_helpers.py || rc=1
echo; echo "===== Bash helpers ====="; bash test_bash_helpers.sh || rc=1
echo; echo "===== Runner invariants ====="; bash test_runner_invariants.sh || rc=1
echo; echo "===== Hygiene invariants ====="; bash test_hygiene_invariants.sh || rc=1
echo; echo "===== Deploy self-heal ====="; bash test_deploy_watch.sh || rc=1
echo; echo "===== TS ratchet gate ====="; bash test_tsc_gate.sh || rc=1
echo; echo "===== Queue refill ====="; bash test_queue_refill.sh || rc=1
echo; echo "===== Higher-tier pipeline (godot gate / refill routing / inline branch / auto-pick) ====="; bash test_higher_tier_pipeline.sh || rc=1
echo; echo "===== Retire prefix-tolerance ====="; bash test_retire_prefix.sh || rc=1
echo; echo "===== Branch reconcile guard ====="; bash test_reconcile_branches.sh || rc=1
echo; echo "===== Context budget invariants (OVERNIGHT_PROGRESS.md context-overflow chain) ====="; bash test_context_budget_invariants.sh || rc=1
echo; echo "===== Outcome classification (record_outcome status->class) ====="; bash test_outcome_classification.sh || rc=1
echo; echo "===== Stage push-accounting (commits_pushed only on real push) ====="; bash test_stage_push_accounting.sh || rc=1
echo; echo "===== Cron repo-coverage (branch_hygiene covers every fleet repo) ====="; bash test_cron_coverage.sh || rc=1
echo; echo "===== Queue-health comment parsing ====="; bash test_queue_health_comments.sh || rc=1
echo; echo "===== Stage untracked-file detection (no-edit false-negative) ====="; bash test_stage_untracked_file_detection.sh || rc=1
echo; echo "===== Lock-guard holder identity (orphan detection under crash-loop) ====="; bash test_lock_guard_holder_identity.sh || rc=1
echo; echo "===== Verify-timeout headroom (iptv_apps false-revert prevention) ====="; bash test_verify_timeout_headroom.sh || rc=1
echo; echo "===== check_migrations.py (alembic safety gate) ====="; bash test_check_migrations.sh || rc=1
echo; echo "===== Ntfy digest stats (tier/planning) ====="; bash test_ntfy_stats.sh || rc=1
echo; echo "===== Ntfy landed-detail (per-item repo/tier/file lines for digests) ====="; bash test_ovn_landed_detail.sh || rc=1
echo; echo "===== Ntfy no-op/reverted repeat-detail (grouped/deduped stuck-item lines) ====="; bash test_ovn_noop_detail.sh || rc=1
echo; echo "===== Work summary (24h fleet digest: aggregate counts + landed detail) ====="; bash test_work_summary.sh || rc=1
echo; echo "===== Queue-health dedup (no repeat deploy-failure alerts) ====="; bash test_queue_health_dedup.sh || rc=1
echo; echo "===== Stage node_modules provisioning (per-step frontend gate fix) ====="; bash test_stage_node_modules.sh || rc=1
echo; echo "===== Queue-refill dry dedup (no repeat out-of-items alerts) ====="; bash test_queue_refill_dry_dedup.sh || rc=1
echo; echo "===== Park sweep (parked items relocated out of active flow) ====="; bash test_park_sweep.sh || rc=1
echo; echo "===== Digest idle-message accuracy (no ambiguous idle-or-paused hedge) ====="; bash test_digest_idle_message.sh || rc=1
echo; echo "===== Classify-fail model-api-error (no test-red mislabel) ====="; bash test_classify_fail.sh || rc=1
echo; echo "===== Hygiene-stuck check (escalate persistent gate failures) ====="; bash test_hygiene_stuck_check.sh || rc=1
echo; echo "===== Item-guard token cap (escalate on spend, not just cycle count) ====="; bash test_item_guard_token_cap.sh || rc=1
echo; echo "===== Item-guard feat-tag churn (regeneration date-bump no longer resets the streak) ====="; bash test_item_guard_feattag_churn.sh || rc=1
echo; echo "===== Item-guard streak isolation (per-(id,item_hash) state, not per-id) ====="; bash test_item_guard_streak_isolation.sh || rc=1
echo; echo "===== Capstone escalation cap (stuck regression-check item no longer starves the T3-5 lane) ====="; bash test_capstone_escalation_cap.sh || rc=1
echo; echo "===== Queue-refill pre-check (credit already-satisfied items) ====="; bash test_queue_refill_precheck.sh || rc=1
echo; echo "===== Pipeline audit false-positive regressions (lock multi-PID, LiteLLM 401) ====="; bash test_pipeline_audit.sh || rc=1
echo; echo "===== Pause-guard (stale deploy/stage-pause self-heal, manual-pause dedup) ====="; bash test_pause_guard.sh || rc=1
echo; echo "===== GPU autoswap (contention guard, restart/health recovery) ====="; bash test_gpu_autoswap.sh || rc=1
echo; echo "===== Fleet autofix (persistent-issue thresholds, dedup) ====="; bash test_fleet_autofix.sh || rc=1
echo; echo "===== Lock-guard alert cooldown (fleet-autofix contention-alert dedup) ====="; bash test_lib_lock_cooldown.sh || rc=1
echo; echo "===== Daily promote classification (promoted/blocked/no-change) ====="; bash test_daily_promote.sh || rc=1
echo; echo "===== ovn_planner (backlog decomposition, malformed-response guard) ====="; bash test_ovn_planner.sh || rc=1
echo; echo "===== ovn_prework (Claude briefing generation, no-clone/failure requeue) ====="; bash test_ovn_prework.sh || rc=1
echo; echo "===== ovn_cycle_triage (per-cycle why-line, parked-item fallthrough) ====="; bash test_ovn_cycle_triage.sh || rc=1
echo; echo "===== groom (backlog grooming proposals, stale-item detection) ====="; bash test_groom.sh || rc=1
echo; echo "===== Park-sweep wrapper (hold/commit/push around the python sweep) ====="; bash test_park_sweep_wrapper.sh || rc=1
echo; echo "===== Recover-parked (decompose retry, recovery-tag dedup) ====="; bash test_recover_parked.sh || rc=1
echo; echo "===== T3 report (land-rate windows, fail-cause tally) ====="; bash test_t3_report.sh || rc=1
echo; echo "===== Toks monitor: RETIRED 2026-09-26 (superseded by test_toks_monitor_regression.sh - the solo/contended design this tested never once fired a real solo sample in 3 weeks of production; see ovn_toks_monitor.sh header) ====="
echo; echo "===== Legacy-log derivation (Phase 5 step 1: task_stats/cycle_summary derived FROM outcomes.jsonl, run alongside the real writers) ====="; bash test_derive_legacy_logs.sh || rc=1
echo; echo "===== Test-watch emergency enqueue (dedup, lock respect) ====="; bash test_test_watch.sh || rc=1
echo; echo "===== Cycle notify (digest bucketing, qualified-status fallthrough) ====="; bash test_cycle_notify.sh || rc=1
echo; echo "===== Provision test envs (per-target status, real exit code) ====="; bash test_provision_test_envs.sh || rc=1
echo; echo "===== Supervisor digest (findings routing, auto-recovery one-shot) ====="; bash test_supervisor.sh || rc=1
echo; echo "===== run_all.sh meta-test (aggregation/exit-code correctness) ====="; bash test_run_all_meta.sh || rc=1
echo; echo "===== Dedupe GD duplicate functions (annotation-safe removal) ====="; python3 test_dedupe_gd_duplicate_functions.py || rc=1
echo; echo "===== Dedupe Python duplicate defs (decorator-safe removal) ====="; python3 test_dedupe_python_duplicate_defs.py || rc=1
echo; echo "===== Dedupe progress headers (merge order, non-adjacent collapse) ====="; python3 test_dedupe_progress_headers.py || rc=1
echo; echo "===== update_progress.py (DONE/NEW/DECISION trailer application) ====="; python3 test_update_progress.py || rc=1
echo; echo "===== Git sync (auto-commit+push overnight-queue itself to shrike-ai-lab) ====="; bash test_git_sync.sh || rc=1
echo; echo "===== Generate-items self-generation (T1 tagging) ====="; python3 test_generate_items.py || rc=1
echo; echo "===== Queue health sweep (auto-recover starved repos, report dupes/already-done) ====="; bash test_queue_health_sweep.sh || rc=1
echo; echo "===== Filesize retag (T1/T2 large-file items route to staged pipeline) ====="; python3 test_filesize_retag.py || rc=1
echo; echo "===== Godot report (noise-filtered pass-rate windows) ====="; python3 test_godot_report.py || rc=1
echo; echo "===== Redgreen net-new-file guard (no false [redgreen:SUSPECT] on new files) ====="; bash test_redgreen_net_new_file.sh || rc=1
echo; echo "===== Stage scope guard (multifile:no rejects undeclared/junk files) ====="; bash test_stage_scope_guard.sh || rc=1
echo; echo "===== Stage-routed task_stats.log write (ovn_stats.py stage-runner blind spot) ====="; bash test_stage_task_stats_write.sh || rc=1
echo; echo "===== Feature groups (feat-tag + file-based approximate grouping, % complete) ====="; bash test_ovn_feature_groups.sh || rc=1
echo; echo "===== Feature-complete watch (distinct completion push, no double-fire) ====="; bash test_ovn_feature_watch.sh || rc=1
echo; echo "===== Hourly digest (lean 1h summary, silent when idle) ====="; bash test_hourly_notify.sh || rc=1
echo; echo "===== Digest feature-progress section wiring ====="; bash test_digest_feature_section.sh || rc=1
echo; echo "===== Digest no-op/reverted repeat-detail wiring ====="; bash test_digest_noop_detail.sh || rc=1
echo; echo "===== Migration-safety gate bounded fix-up (zero-repair gap closed) ====="; bash test_migration_gate_fixup.sh || rc=1
echo; echo "===== BUILD-GATE Kotlin diagnostic grounding (kotlinc file:line:col extraction) ====="; bash test_buildgate_kotlinc_grounding.sh || rc=1
echo; echo "===== Android Gradle flavor-task disambiguation (ambiguous VERIFY command guard) ====="; bash test_gradle_flavor_guard.sh || rc=1
echo; echo "===== Delete-hint prompt guidance (aider DELETE: trailer steering) ====="; bash test_delete_hint_prompt.sh || rc=1
echo; echo "===== Research-batch scorecard (letter-grade distribution, D/F detail, no silent truncation) ====="; bash test_batch_scorecard.sh || rc=1
echo; echo "===== Batch stragglers finder (chronically-F batch detection for open siblings) ====="; bash test_batch_stragglers.sh || rc=1
echo; echo "===== Batch straggler parking (AUTO-SKIP low-grade handling, worktree-isolated) ====="; bash test_batch_park_stragglers.sh || rc=1
echo; echo "===== Build-fix/Tier-2 fix-up file exclusion (no unbounded OVERNIGHT_PROGRESS.md context blowup) ====="; bash test_buildfix_exclude_progress_files.sh || rc=1
echo; echo "===== Credit-verify shadow-check tool-path resolution (godot/pytest/venv self-heal) ====="; bash test_credit_verify_tool_paths.sh || rc=1
echo; echo "===== Credit-verify enforce promotion (FAIL refuses credit, shadow-mode rollback preserved) ====="; bash test_credit_already_satisfied_enforce.sh || rc=1
echo; echo "===== Credit-verify shadow-mode gate (pinned to shadow mode explicitly, was silently running in enforce) ====="; bash test_credit_verify_shadow.sh || rc=1
echo; echo "===== Credit-already-satisfied recall fix (real missed already-done phrasings now credited) ====="; bash test_credit_already_satisfied_recall.sh || rc=1
echo; echo "===== Backup-branch sweep (orphaned backup-diverged-* branch cleanup + escalating alert) ====="; bash test_backup_branch_sweep.sh || rc=1
echo; echo "===== Multifile scope guard (multifile:no items never accumulate extra files, run_overnight.sh) ====="; bash test_multifile_scope_guard.sh || rc=1
echo; echo "===== Toks-monitor rolling baseline (sustained-regression detection, not an unreachable solo gate) ====="; bash test_toks_monitor_regression.sh || rc=1
echo; echo "===== Stale top item check (persisted first-seen clock, not git-blame-on-bulk-edit) ====="; bash test_stale_top_item_check.sh || rc=1
echo; echo "===== Verify-skip guard (lock-contended .ovn-verify.sh no longer lands as an unverified pass) ====="; bash test_verify_skip_guard.sh || rc=1
echo; echo "===== Scout file-fallback (empty FILE_ARGS resolves a named function to its real defining file) ====="; bash test_scout_file_fallback.sh || rc=1
echo; echo "===== BUILD-GATE test-assertion exclusion (plain Gradle AssertionError no longer misclassified as a structural break) ====="; bash test_buildgate_test_assertion_exclusion.sh || rc=1
echo; echo "===== Ongoing-lane deletion-hint fix (background lane top-item peek catches delete-shaped items the generic wrapper prompt hides) ====="; bash test_deletehint_ongoing_lane.sh || rc=1
echo; echo "===== Alembic new-file stub (brand-new migration file no longer hits the silent unreliable-new-file-udiff no-op) ====="; bash test_alembic_new_file_stub.sh || rc=1
echo; echo "===== Recover-parked alembic-migration-dropped guard (decomposition can't silently drop a schema item's migration step) ====="; bash test_alembic_migration_dropped_guard.sh || rc=1
echo; echo "===== New-source-file stub (Alembic-only fix generalized: any brand-new gd/py/ts/tsx/vue/kt/swift file, not just Alembic migrations) ====="; bash test_new_source_file_stub.sh || rc=1
echo; echo "===== Verify-direction existence-only check (cat:schema/cat:endpoint bare hasattr/is-not-None/import-only VERIFY, shadow-mode) ====="; bash test_verify_direction_existence_check.sh || rc=1
echo; echo "===== Ungrounded-plan guard (PROCEED verdict with zero real file-shaped tokens skips implement instead of forcing a blind attempt) ====="; bash test_ungrounded_plan_guard.sh || rc=1
echo; echo "===== Failure triage (cluster BAD outcomes by error signature; new-vs-fixed-then-regressed registry, --ack, --digest) ====="; python3 test_failure_triage.py || rc=1
echo; echo "===== Failure-triage notifications (capped new-pattern digest section; exactly-once high-priority regression push; failed push kept pending) ====="; bash test_failure_triage_notify.sh || rc=1
echo; echo "===== queue_refill dedup date-strip (regenerated [feat:] tag collapses onto its queued twin; siblings sharing a tag stay distinct) ====="; bash test_queue_refill_feattag_norm.sh || rc=1
echo; echo "===== auto-research validator (format/dedupe/grounding gate before roadmap append) ====="; bash test_auto_research_validate.sh || rc=1
echo; echo "===== planner single-instance lock (concurrent passes double-decomposed one feature) ====="; bash test_planner_single_instance.sh || rc=1
echo; echo "===== supervisor recover-count grep never falls back to stdin (hung 35min under an open pipe) ====="; bash test_supervisor_no_stdin_hang.sh || rc=1
echo; echo "===== credit target-path gate (no-VERIFY credits must have a sane target path) ====="; bash test_credit_path_gate.sh || rc=1
echo; echo "===== reconcile post-merge sanity gate (clean merge that synthesizes a broken file is not pushed) ====="; bash test_reconcile_merge_sanity.sh || rc=1
echo; echo "===== whitespace-only-line strip tool (semantics-preserving, python strings untouched) ====="; bash test_ws_strip.sh || rc=1
echo; echo "===== delete executor (deterministic git rm for whole-file delete items) ====="; bash test_delete_executor.sh || rc=1
echo; echo "===== alembic autogen hook (regenerates the missing migration for model drift) ====="; bash test_alembic_autogen.sh || rc=1
echo; echo "===== record_outcome item_hash agrees with the shared ovn_item_hash (outcomes.jsonl hash joins the guard state-file key; date-bump regeneration keeps one identity) ====="; bash test_record_outcome_item_hash_agrees.sh || rc=1
echo; echo "===== pytest-xdist guard (parallel flag only when repo allowlisted AND xdist importable; never breaks a venv without it) ====="; bash test_pytest_parallel_guard.sh || rc=1
echo; echo "===== alembic_autogen_py ====="; bash test_alembic_autogen_py.sh || rc=1
echo; echo "===== archive_done ====="; bash test_archive_done.sh || rc=1
echo; echo "===== art_runner ====="; bash test_art_runner.sh || rc=1
echo; echo "===== art_sh ====="; bash test_art_sh.sh || rc=1
echo; echo "===== billwatch_summary_backfill ====="; bash test_billwatch_summary_backfill.sh || rc=1
echo; echo "===== branch_hygiene_run ====="; bash test_branch_hygiene_run.sh || rc=1
echo; echo "===== deploy_watch_run ====="; bash test_deploy_watch_run.sh || rc=1
echo; echo "===== fix_backlog_paths ====="; bash test_fix_backlog_paths.sh || rc=1
echo; echo "===== fleet_stats_py ====="; bash test_fleet_stats_py.sh || rc=1
echo; echo "===== gitlark_control_consumer ====="; bash test_gitlark_control_consumer.sh || rc=1
echo; echo "===== install_agents_md ====="; bash test_install_agents_md.sh || rc=1
echo; echo "===== lib_worktree ====="; bash test_lib_worktree.sh || rc=1
echo; echo "===== lib_worktree_paths ====="; bash test_lib_worktree_paths.sh || rc=1
echo; echo "===== ovn_autotest_run ====="; bash test_ovn_autotest_run.sh || rc=1
echo; echo "===== ovn_backlog_format_check ====="; bash test_ovn_backlog_format_check.sh || rc=1
echo; echo "===== ovn_batch_scorecard ====="; bash test_ovn_batch_scorecard.sh || rc=1
echo; echo "===== ovn_citation_check ====="; bash test_ovn_citation_check.sh || rc=1
echo; echo "===== ovn_extract_failure ====="; bash test_ovn_extract_failure.sh || rc=1
echo; echo "===== ovn_filesize_retag ====="; bash test_ovn_filesize_retag.sh || rc=1
echo; echo "===== ovn_fleet_health_run ====="; bash test_ovn_fleet_health_run.sh || rc=1
echo; echo "===== ovn_log_tokens ====="; bash test_ovn_log_tokens.sh || rc=1
echo; echo "===== ovn_path_gate ====="; bash test_ovn_path_gate.sh || rc=1
echo; echo "===== ovn_pipeline_audit_run ====="; bash test_ovn_pipeline_audit_run.sh || rc=1
echo; echo "===== ovn_prioritize_tiers ====="; bash test_ovn_prioritize_tiers.sh || rc=1
echo; echo "===== ovn_progress_slice ====="; bash test_ovn_progress_slice.sh || rc=1
echo; echo "===== ovn_research_trigger_check ====="; bash test_ovn_research_trigger_check.sh || rc=1
echo; echo "===== ovn_stage_runner_flow ====="; bash test_ovn_stage_runner_flow.sh || rc=1
echo; echo "===== ovn_stage_runner_verify ====="; bash test_ovn_stage_runner_verify.sh || rc=1
echo; echo "===== ovn_stage_stats ====="; bash test_ovn_stage_stats.sh || rc=1
echo; echo "===== ovn_stage_sweep ====="; bash test_ovn_stage_sweep.sh || rc=1
echo; echo "===== ovn_stale_top_item_check ====="; bash test_ovn_stale_top_item_check.sh || rc=1
echo; echo "===== ovn_swift_retag ====="; bash test_ovn_swift_retag.sh || rc=1
echo; echo "===== ovn_tag_items ====="; bash test_ovn_tag_items.sh || rc=1
echo; echo "===== ovn_test_watch_run ====="; bash test_ovn_test_watch_run.sh || rc=1
echo; echo "===== ovn_tier_stats_run ====="; bash test_ovn_tier_stats_run.sh || rc=1
echo; echo "===== ovn_toks_monitor_run ====="; bash test_ovn_toks_monitor_run.sh || rc=1
echo; echo "===== ovn_worktree_sweep ====="; bash test_ovn_worktree_sweep.sh || rc=1
echo; echo "===== passrate_check ====="; bash test_passrate_check.sh || rc=1
echo; echo "===== pipeline_lint ====="; bash test_pipeline_lint.sh || rc=1
echo; echo "===== probe_tsc_cmd ====="; bash test_probe_tsc_cmd.sh || rc=1
echo; echo "===== promote_to_prod_run ====="; bash test_promote_to_prod_run.sh || rc=1
echo; echo "===== queue_health_full ====="; bash test_queue_health_full.sh || rc=1
echo; echo "===== queue_refill_py_paths ====="; bash test_queue_refill_py_paths.sh || rc=1
echo; echo "===== queue_sh_cli ====="; bash test_queue_sh_cli.sh || rc=1
echo; echo "===== rebaseline_tsc ====="; bash test_rebaseline_tsc.sh || rc=1
echo; echo "===== register_monitors ====="; bash test_register_monitors.sh || rc=1
echo; echo "===== render_dashboard ====="; bash test_render_dashboard.sh || rc=1
echo; echo "===== run_overnight_aider1_flow ====="; bash test_run_overnight_aider1_flow.sh || rc=1
echo; echo "===== run_overnight_aider2_flow ====="; bash test_run_overnight_aider2_flow.sh || rc=1
echo; echo "===== run_overnight_aider2_gates ====="; bash test_run_overnight_aider2_gates.sh || rc=1
echo; echo "===== run_overnight_aider2_push ====="; bash test_run_overnight_aider2_push.sh || rc=1
echo; echo "===== run_overnight_core_funcs ====="; bash test_run_overnight_core_funcs.sh || rc=1
echo; echo "===== run_overnight_core_loop2 ====="; bash test_run_overnight_core_loop2.sh || rc=1
echo; echo "===== run_overnight_core_main ====="; bash test_run_overnight_core_main.sh || rc=1
echo; echo "===== run_overnight_core_verify ====="; bash test_run_overnight_core_verify.sh || rc=1
echo; echo "===== shrike_notify_lib ====="; bash test_shrike_notify_lib.sh || rc=1
echo; echo "===== staging_smoke ====="; bash test_staging_smoke.sh || rc=1
echo; echo "===== sync_branches ====="; bash test_sync_branches.sh || rc=1
echo; echo "===== tree_guard ====="; bash test_tree_guard.sh || rc=1
echo; echo "===== un_park ====="; bash test_un_park.sh || rc=1
echo; echo "===== ovn coverage cron ====="; bash test_ovn_coverage_cron.sh || rc=1
echo; echo "===== alembic autogen more w3d ====="; bash test_alembic_autogen_more_w3d.sh || rc=1
echo; echo "===== art py more w3c ====="; bash test_art_py_more_w3c.sh || rc=1
echo; echo "===== batch park stragglers more w3d ====="; bash test_batch_park_stragglers_more_w3d.sh || rc=1
echo; echo "===== classify fail more w3b ====="; bash test_classify_fail_more_w3b.sh || rc=1
echo; echo "===== credit tool paths real w3d ====="; bash test_credit_tool_paths_real_w3d.sh || rc=1
echo; echo "===== cycle notify more paths ====="; bash test_cycle_notify_more_paths.sh || rc=1
echo; echo "===== dedupe gd duplicate functions cov ====="; bash test_dedupe_gd_duplicate_functions_cov.sh || rc=1
echo; echo "===== dedupe progress headers cov ====="; bash test_dedupe_progress_headers_cov.sh || rc=1
echo; echo "===== dedupe python duplicate defs cov ====="; bash test_dedupe_python_duplicate_defs_cov.sh || rc=1
echo; echo "===== digest notify more paths ====="; bash test_digest_notify_more_paths.sh || rc=1
echo; echo "===== failure triage cov ====="; bash test_failure_triage_cov.sh || rc=1
echo; echo "===== failure triage cron more w3d ====="; bash test_failure_triage_cron_more_w3d.sh || rc=1
echo; echo "===== filesize retag cov ====="; bash test_filesize_retag_cov.sh || rc=1
echo; echo "===== groom paused w3d ====="; bash test_groom_paused_w3d.sh || rc=1
echo; echo "===== hourly notify more paths ====="; bash test_hourly_notify_more_paths.sh || rc=1
echo; echo "===== item guard nolib w3d ====="; bash test_item_guard_nolib_w3d.sh || rc=1
echo; echo "===== lib path normalize more w3d ====="; bash test_lib_path_normalize_more_w3d.sh || rc=1
echo; echo "===== outcome buckets cov ====="; bash test_outcome_buckets_cov.sh || rc=1
echo; echo "===== ovn alembic generate more w3c ====="; bash test_ovn_alembic_generate_more_w3c.sh || rc=1
echo; echo "===== ovn failure triage more w3c ====="; bash test_ovn_failure_triage_more_w3c.sh || rc=1
echo; echo "===== ovn feature groups more w3c ====="; bash test_ovn_feature_groups_more_w3c.sh || rc=1
echo; echo "===== ovn misc py more w3c ====="; bash test_ovn_misc_py_more_w3c.sh || rc=1
echo; echo "===== ovn planner more w3d ====="; bash test_ovn_planner_more_w3d.sh || rc=1
echo; echo "===== ovn reports py more w3c ====="; bash test_ovn_reports_py_more_w3c.sh || rc=1
echo; echo "===== ovn stats more w3c ====="; bash test_ovn_stats_more_w3c.sh || rc=1
echo; echo "===== queue refill more w3b ====="; bash test_queue_refill_more_w3b.sh || rc=1
echo; echo "===== reconcile branches more w3b ====="; bash test_reconcile_branches_more_w3b.sh || rc=1
echo; echo "===== recover parked more w3b ====="; bash test_recover_parked_more_w3b.sh || rc=1
echo; echo "===== small py more cov ====="; bash test_small_py_more_cov.sh || rc=1
echo; echo "===== small py more w3c ====="; bash test_small_py_more_w3c.sh || rc=1
echo; echo "===== small py more w3cb ====="; bash test_small_py_more_w3cb.sh || rc=1
echo; echo "===== supervisor more w3b ====="; bash test_supervisor_more_w3b.sh || rc=1
echo; echo "===== tsc gate more w3d ====="; bash test_tsc_gate_more_w3d.sh || rc=1
echo; echo "===== update progress cov ====="; bash test_update_progress_cov.sh || rc=1
echo; echo "===== verify direction check more w3b ====="; bash test_verify_direction_check_more_w3b.sh || rc=1
echo; echo "===== work summary more cov ====="; bash test_work_summary_more_cov.sh || rc=1
echo; echo "===== ntfy guard ====="; bash test_ntfy_guard.sh || rc=1
echo; echo "===== verify fail closed ====="; bash test_verify_fail_closed.sh || rc=1
echo; echo "===== ovn notify ====="; bash test_ovn_notify.sh || rc=1
echo; [ $rc -eq 0 ] && echo "✅ ALL QUEUE TESTS PASS" || echo "❌ SOME QUEUE TESTS FAILED"
exit $rc
