#!/usr/bin/env bash
# Regression test: provision_test_envs.sh must correctly detect and report, per
# TARGETS entry, one of: missing-dir / ok / failed, using $HOME-relative paths
# (BASE="$HOME/overnight-queue/repos", LOG_DIR="$HOME/overnight-queue/provision-logs").
# We exploit that $HOME-relative-ness to sandbox the whole script by running it
# with HOME pointed at a temp dir - NEVER against the real repos/ tree.
#
# Real python3.12/npm are stubbed out via a PATH-prepended fake bin/ dir so this
# test needs no network access and runs in well under a second.
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/provision_test_envs.sh"
[ -f "$SCRIPT" ] || { echo "  SKIP: $SCRIPT not found"; exit 0; }
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"
FAKEBIN="$tmp/bin"; mkdir -p "$FAKEBIN"

# fake python3.12: `-m venv DIR` creates DIR/bin/pip, a stub honoring FAKE_PIP_EXIT
cat > "$FAKEBIN/python3.12" <<'PYEOF'
#!/usr/bin/env bash
if [ "$1" = "-m" ] && [ "$2" = "venv" ]; then
  mkdir -p "$3/bin"
  cat > "$3/bin/pip" <<'PIPEOF'
#!/usr/bin/env bash
exit "${FAKE_PIP_EXIT:-0}"
PIPEOF
  chmod +x "$3/bin/pip"
fi
exit 0
PYEOF
chmod +x "$FAKEBIN/python3.12"

# fake npm: stub honoring FAKE_NPM_EXIT, no real install/network
cat > "$FAKEBIN/npm" <<'NPMEOF'
#!/usr/bin/env bash
exit "${FAKE_NPM_EXIT:-0}"
NPMEOF
chmod +x "$FAKEBIN/npm"

RUN() { HOME="$tmp/home" PATH="$FAKEBIN:$PATH" bash "$SCRIPT" "$@"; }
CSV="$tmp/home/overnight-queue/provision-logs/summary.csv"

reset_home() {
  rm -rf "$tmp/home"
  mkdir -p "$tmp/home/overnight-queue/repos"
}

# --- A: healthy path - existing python dir w/ requirements.txt installs OK,
#        existing node dir installs OK, absent targets correctly = missing-dir --
reset_home
mkdir -p "$tmp/home/overnight-queue/repos/billwatch/billwatch-backend"
echo "fastapi" > "$tmp/home/overnight-queue/repos/billwatch/billwatch-backend/requirements.txt"
mkdir -p "$tmp/home/overnight-queue/repos/shrike-labs-website"
echo '{}' > "$tmp/home/overnight-queue/repos/shrike-labs-website/package.json"
FAKE_PIP_EXIT=0 FAKE_NPM_EXIT=0 RUN >/dev/null 2>&1
ok "python target with requirements.txt reports ok" "grep -q '^billwatch,billwatch-backend,python,ok$' '$CSV'"
ok "node target reports ok" "grep -q '^shrike-labs-website,\.,node,ok$' '$CSV'"
ok "absent target reports missing-dir" "grep -q '^gitlark,backend,python,missing-dir$' '$CSV'"
ok "missing-dir target: no dir was created for it" "[ ! -d '$tmp/home/overnight-queue/repos/gitlark' ]"
ok ".venv actually got created for the ok python target" "[ -d '$tmp/home/overnight-queue/repos/billwatch/billwatch-backend/.venv' ]"

# --- B: python install failure (pip fails outright) -> failed, with a log kept --
reset_home
mkdir -p "$tmp/home/overnight-queue/repos/billwatch/billwatch-backend"
echo "fastapi" > "$tmp/home/overnight-queue/repos/billwatch/billwatch-backend/requirements.txt"
FAKE_PIP_EXIT=1 RUN >/dev/null 2>&1
ok "pip failure -> failed status in summary.csv" "grep -q '^billwatch,billwatch-backend,python,failed$' '$CSV'"
ok "a log file was kept for the failed target" "[ -f \"$tmp/home/overnight-queue/provision-logs/billwatch__billwatch-backend.log\" ]"

# --- C: node install failure -> failed --------------------------------------
reset_home
mkdir -p "$tmp/home/overnight-queue/repos/shrike-labs-website"
FAKE_NPM_EXIT=1 RUN >/dev/null 2>&1
ok "npm failure -> failed status in summary.csv" "grep -q '^shrike-labs-website,\.,node,failed$' '$CSV'"

# --- D: python dir exists but has no requirements.txt -> failed, explained --
reset_home
mkdir -p "$tmp/home/overnight-queue/repos/billwatch/billwatch-backend"
RUN >/dev/null 2>&1
ok "no requirements.txt -> failed status" "grep -q '^billwatch,billwatch-backend,python,failed$' '$CSV'"
ok "log explains why (no requirements.txt found)" "grep -q 'no requirements.txt found' \"$tmp/home/overnight-queue/provision-logs/billwatch__billwatch-backend.log\""

# --- E: summary.csv header + one row per real TARGETS entry (15) ------------
reset_home
STDOUT="$(RUN 2>&1)"
ok "summary.csv has the header row" "head -1 '$CSV' | grep -q '^repo,subdir,kind,status$'"
ok "summary.csv has exactly 15 data rows (one per TARGETS entry)" "[ \"\$(tail -n +2 '$CSV' | grep -c .)\" -eq 15 ]"
ok "an all-missing run still reports the SUMMARY to stdout" "echo \"\$STDOUT\" | grep -q '=== SUMMARY ==='"

# --- F: FIXED BUG regression guard (2026-09-10) — STATUS used to be captured only from
# the LAST of 3 sequential pip installs (the generic pytest-tooling one), so a failed
# requirements.txt install (the one that actually matters) was masked by a successful
# tooling install afterward and falsely reported "ok". Pre-seed a .venv with a pip stub
# that fails ONLY on the `-r requirements.txt` call and succeeds on the other two. ---
reset_home
TDIR="$tmp/home/overnight-queue/repos/billwatch/billwatch-backend"
mkdir -p "$TDIR/.venv/bin"
echo "fastapi" > "$TDIR/requirements.txt"
cat > "$TDIR/.venv/bin/pip" <<'PIPEOF2'
#!/usr/bin/env bash
for a in "$@"; do [ "$a" = "-r" ] && exit 1; done
exit 0
PIPEOF2
chmod +x "$TDIR/.venv/bin/pip"
RUN >/dev/null 2>&1
ok "a failed requirements.txt install is NOT masked by a later successful tooling install" \
   "grep -q '^billwatch,billwatch-backend,python,failed$' '$CSV'"

# --- G: FIXED BUG regression guard (2026-09-10) — the script used to always exit 0 (its
# last command was `cat summary.csv`), so no caller could detect a provisioning failure
# without manually reading summary.csv. Now it exits non-zero when a REAL install failed
# (missing-dir alone does not trip it - some TARGETS entries are known-discontinued
# projects with no local clone, which would otherwise permanently fail every run). ---
reset_home
mkdir -p "$tmp/home/overnight-queue/repos/billwatch/billwatch-backend"
echo "fastapi" > "$tmp/home/overnight-queue/repos/billwatch/billwatch-backend/requirements.txt"
rc=0
FAKE_PIP_EXIT=1 RUN >/dev/null 2>&1 || rc=$?
ok "a run with a real install failure exits non-zero (was always 0 before the fix)" "[ '$rc' -ne 0 ]"

rc2=0
reset_home  # empty repos/ -> every target is missing-dir, none are real failures
RUN >/dev/null 2>&1 || rc2=$?
ok "an all-missing-dir run (no real install attempted) still exits 0" "[ '$rc2' -eq 0 ]"

rm -rf "$tmp"
echo "provision_test_envs: $P passed, $F failed"
[ "$F" -eq 0 ]
