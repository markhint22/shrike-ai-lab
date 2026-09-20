#!/usr/bin/env bash
# Tests for ovn_feature_watch.sh (2026-09-20) — fires a distinct "🎉 Feature complete" ntfy
# push the moment a REAL [feat:ID]-tagged feature's last remaining sub-item lands (and the
# backlog has nothing more queued for it). Verifies: (a) a brand-new repo's already-100%-done
# features are silently baselined on the first run (no flood of "new" completions for old
# work), (b) a genuine incomplete->complete transition on a LATER run fires exactly one push,
# (c) an already-notified feature never fires twice, and (d) file-based approximate groups
# (no [feat:] tag) never fire a completion push. Stubs curl; runs against a fixture
# $HOME/overnight-queue mirror so it never touches production data or the real network.
set -uo pipefail
OQ="${OVN_QUEUE_DIR:-$HOME/overnight-queue}"
SCRIPT="$OQ/ovn_feature_watch.sh"
[ -f "$SCRIPT" ] || { echo "  SKIP: $SCRIPT not found on this host"; exit 0; }

P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/state" "$tmp/scripts" "$tmp/repos/demo" "$tmp/backlog" "$tmp/roadmap" "$tmp/bin"
cp "$SCRIPT" "$tmp/ovn_feature_watch.sh"
cp "$OQ/scripts/ovn_feature_groups.py" "$tmp/scripts/ovn_feature_groups.py"
echo "faketopic" > "$tmp/state/ntfy_topic"
echo "# roadmap" > "$tmp/roadmap/demo.md"   # marks demo as planner-managed
: > "$tmp/backlog/demo.md"

CURLLOG="$tmp/curl_calls.log"
cat > "$tmp/bin/curl" <<CURLEOF
#!/usr/bin/env bash
echo "CALL: \$*" >> "$CURLLOG"
exit 0
CURLEOF
chmod +x "$tmp/bin/curl"

run_watch(){ ( cd "$tmp" && PATH="$tmp/bin:$PATH" HOME="$tmp" bash "$tmp/ovn_feature_watch.sh" >/dev/null 2>&1 ); }

# ---- 1: first-ever run sees an ALREADY-complete feature -> baseline silently, no push ----
cat > "$tmp/repos/demo/OVERNIGHT_PROGRESS.md" <<'EOF'
- [x] [T2] `app/a.py` — thing. VERIFY: x. (cat:python; multifile:no) [feat:demo-20260101-old-feature]
- [x] [T2] `app/b.py` — thing. VERIFY: x. (cat:python; multifile:no) [feat:demo-20260101-old-feature]
EOF
: > "$CURLLOG"
run_watch
ok "first-ever run (bootstrap) sends no push even for an already-complete feature" "[ ! -s '$CURLLOG' ]"
ok "the already-complete feature is recorded as notified during bootstrap" "grep -qxF 'demo-20260101-old-feature' '$tmp/state/feature_progress_notified.log'"

# ---- 2: a genuinely NEW feature, not yet complete -> no push ----
cat >> "$tmp/repos/demo/OVERNIGHT_PROGRESS.md" <<'EOF'
- [x] [T2] `app/c.py` — thing. VERIFY: x. (cat:python; multifile:no) [feat:demo-20260102-new-feature]
- [ ] [T2] `app/d.py` — thing. VERIFY: x. (cat:python; multifile:no) [feat:demo-20260102-new-feature]
EOF
: > "$CURLLOG"
run_watch
ok "an incomplete feature triggers no push" "[ ! -s '$CURLLOG' ]"

# ---- 3: landing its last item -> exactly one completion push fires ----
sed -i '' 's/- \[ \] \[T2\] `app\/d.py`/- [x] [T2] `app\/d.py`/' "$tmp/repos/demo/OVERNIGHT_PROGRESS.md" 2>/dev/null \
  || sed -i 's/- \[ \] \[T2\] `app\/d.py`/- [x] [T2] `app\/d.py`/' "$tmp/repos/demo/OVERNIGHT_PROGRESS.md"
: > "$CURLLOG"
run_watch
ok "completing the last sub-item fires exactly one push" "[ \$(grep -c '^CALL: -fsS' '$CURLLOG') -eq 1 ]"
ok "the push is titled distinctly as a feature-complete event" "grep -q 'Feature complete' '$CURLLOG'"
ok "the push names the completed feature id" "grep -q 'demo-20260102-new-feature' '$CURLLOG'"

# ---- 4: running again does NOT re-fire for the same completed feature ----
: > "$CURLLOG"
run_watch
ok "an already-notified completion never fires twice" "[ ! -s '$CURLLOG' ]"

# ---- 5: a file-based approximate group (no [feat:] tag) never fires a completion push ----
cat >> "$tmp/repos/demo/OVERNIGHT_PROGRESS.md" <<'EOF'
- [x] [T1] `app/shared.py` — fix 1. VERIFY: x. (cat:python; multifile:no)
- [x] [T1] `app/shared.py` — fix 2. VERIFY: x. (cat:python; multifile:no)
EOF
: > "$CURLLOG"
run_watch
ok "a fully-checked file-based (approx) group never fires a completion push" "[ ! -s '$CURLLOG' ]"

echo "ovn_feature_watch.sh: $P passed, $F failed"
[ "$F" -eq 0 ]
