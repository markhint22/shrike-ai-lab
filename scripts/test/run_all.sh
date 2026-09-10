#!/usr/bin/env bash
# Run the full overnight-queue regression suite. Exit 0 = all green.
cd "$(dirname "$0")"
rc=0
echo "===== Python helpers ====="; python3 test_helpers.py || rc=1
echo; echo "===== Bash helpers ====="; bash test_bash_helpers.sh || rc=1
echo; echo "===== Runner invariants ====="; bash test_runner_invariants.sh || rc=1
echo; echo "===== Hygiene invariants ====="; bash test_hygiene_invariants.sh || rc=1
echo; echo "===== Deploy self-heal ====="; bash test_deploy_watch.sh || rc=1
echo; echo "===== TS ratchet gate ====="; bash test_tsc_gate.sh || rc=1
echo; echo "===== Queue refill ====="; bash test_queue_refill.sh || rc=1
echo; echo "===== Higher-tier pipeline (godot gate / refill routing / inline branch / auto-pick) ====="; bash test_higher_tier_pipeline.sh || rc=1
echo; echo "===== Retire prefix-tolerance ====="; bash test_retire_prefix.sh || rc=1
echo; echo "===== Branch reconcile guard ====="; bash test_reconcile_branches.sh || rc=1
echo; echo "===== Outcome classification (record_outcome status->class) ====="; bash test_outcome_classification.sh || rc=1
echo; echo "===== Stage push-accounting (commits_pushed only on real push) ====="; bash test_stage_push_accounting.sh || rc=1
echo; echo "===== Cron repo-coverage (branch_hygiene covers every fleet repo) ====="; bash test_cron_coverage.sh || rc=1
echo; echo "===== Queue-health comment parsing ====="; bash test_queue_health_comments.sh || rc=1
echo; echo "===== Stage untracked-file detection (no-edit false-negative) ====="; bash test_stage_untracked_file_detection.sh || rc=1
echo; echo "===== Lock-guard holder identity (orphan detection under crash-loop) ====="; bash test_lock_guard_holder_identity.sh || rc=1
echo; echo "===== Verify-timeout headroom (iptv_apps false-revert prevention) ====="; bash test_verify_timeout_headroom.sh || rc=1
echo; echo "===== check_migrations.py (alembic safety gate) ====="; bash test_check_migrations.sh || rc=1
echo; echo "===== Ntfy digest stats (tier/planning) ====="; bash test_ntfy_stats.sh || rc=1
echo; echo "===== Queue-health dedup (no repeat deploy-failure alerts) ====="; bash test_queue_health_dedup.sh || rc=1
echo; echo "===== Stage node_modules provisioning (per-step frontend gate fix) ====="; bash test_stage_node_modules.sh || rc=1
echo; echo "===== Queue-refill dry dedup (no repeat out-of-items alerts) ====="; bash test_queue_refill_dry_dedup.sh || rc=1
echo; echo "===== Park sweep (parked items relocated out of active flow) ====="; bash test_park_sweep.sh || rc=1
echo; echo "===== Digest idle-message accuracy (no ambiguous idle-or-paused hedge) ====="; bash test_digest_idle_message.sh || rc=1
echo; echo "===== Classify-fail model-api-error (no test-red mislabel) ====="; bash test_classify_fail.sh || rc=1
echo; echo "===== Hygiene-stuck check (escalate persistent gate failures) ====="; bash test_hygiene_stuck_check.sh || rc=1
echo; echo "===== Item-guard token cap (escalate on spend, not just cycle count) ====="; bash test_item_guard_token_cap.sh || rc=1
echo; echo "===== Queue-refill pre-check (credit already-satisfied items) ====="; bash test_queue_refill_precheck.sh || rc=1
echo; echo "===== Pipeline audit false-positive regressions (lock multi-PID, LiteLLM 401) ====="; bash test_pipeline_audit.sh || rc=1
echo; echo "===== Pause-guard (stale deploy/stage-pause self-heal, manual-pause dedup) ====="; bash test_pause_guard.sh || rc=1
echo; echo "===== GPU autoswap (contention guard, restart/health recovery) ====="; bash test_gpu_autoswap.sh || rc=1
echo; echo "===== Fleet autofix (persistent-issue thresholds, dedup) ====="; bash test_fleet_autofix.sh || rc=1
echo; echo "===== Daily promote classification (promoted/blocked/no-change) ====="; bash test_daily_promote.sh || rc=1
echo; echo "===== ovn_planner (backlog decomposition, malformed-response guard) ====="; bash test_ovn_planner.sh || rc=1
echo; echo "===== ovn_prework (Claude briefing generation, no-clone/failure requeue) ====="; bash test_ovn_prework.sh || rc=1
echo; echo "===== ovn_cycle_triage (per-cycle why-line, parked-item fallthrough) ====="; bash test_ovn_cycle_triage.sh || rc=1
echo; echo "===== groom (backlog grooming proposals, stale-item detection) ====="; bash test_groom.sh || rc=1
echo; echo "===== Park-sweep wrapper (hold/commit/push around the python sweep) ====="; bash test_park_sweep_wrapper.sh || rc=1
echo; echo "===== Recover-parked (decompose retry, recovery-tag dedup) ====="; bash test_recover_parked.sh || rc=1
echo; echo "===== T3 report (land-rate windows, fail-cause tally) ====="; bash test_t3_report.sh || rc=1
echo; echo "===== Toks monitor (contention-aware slow-sample alerting) ====="; bash test_toks_monitor.sh || rc=1
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
echo; [ $rc -eq 0 ] && echo "✅ ALL QUEUE TESTS PASS" || echo "❌ SOME QUEUE TESTS FAILED"
exit $rc
