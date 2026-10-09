Proposals only (nothing applied). Also required: pytest-xdist in iptv-backend/requirements-dev.txt and billwatch-backend dev requirements + installed into each .venv (provision_test_envs.sh). Measured on 2026-09-29 in /tmp/xdist_exp copies: iptv 467s serial -> 64s with -n 8; billwatch 105s -> 18s; gitlark 110s -> 17s BUT 11 failures under xdist (needs test isolation; do NOT enable).
Also: ovn_stage_runner.sh line ~584 (full_verify pytest) could add -n 8 for repos that support it.

2026-10-02 NOTE: ovn_alembic_autogen.{sh,py} + the run_overnight.sh hook from this dir were applied on 2026-09-30 (commit 7bb579f) and wired into the staged runner + extended (iptv_apps allowlist, T2 credit) on 2026-10-02 (branch qa/h6-alembic-autogen). Kept here as history; the live copies are in scripts/.
