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
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }   # 2026-10-16: fail-closed sandbox helpers (see lint_unsafe_rm.py)
OQ="${OVN_QUEUE_DIR:-$HOME/overnight-queue}"
SCRIPT="$OQ/ovn_feature_watch.sh"
[ -f "$SCRIPT" ] || { echo "  SKIP: $SCRIPT not found on this host"; exit 0; }

P=0; F=0
# 2026-10-08: assertions are evaluated with pipefail OFF - under pipefail `A | grep -q X` is flaky (grep -q exits at its first hit, A may take SIGPIPE: rc 141) and `! A | grep -q X` can mask a real failure
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(safe_mktemp_dir)" || exit 1; trap 'rm -rf "$tmp"' EXIT
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

# sections 1-5 test the legacy per-feature push (OVN_FEATURE_AGGREGATE=off); section 6 (S2/F5) tests the default aggregated mode
run_watch(){ ( cd "$tmp" && PATH="$tmp/bin:$PATH" HOME="$tmp" OVN_FEATURE_AGGREGATE="${AGG_MODE:-off}" bash "${WATCH_SCRIPT:-$tmp/ovn_feature_watch.sh}" >/dev/null 2>&1 ); }

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

# ---- 6 (S2/F5): default mode aggregates: a burst of completions in one tick = ONE note-class push (the per-item pushes were all dropped by the relay: 51 of 53 'dropped'), at most one per flush window
AGG_MODE=on
mkdir -p "$tmp/repos/demo2"; echo "# roadmap" > "$tmp/roadmap/demo2.md"; : > "$tmp/backlog/demo2.md"
: > "$tmp/repos/demo2/OVERNIGHT_PROGRESS.md"; : > "$CURLLOG"; run_watch      # baselines demo2 silently
addfeat(){ for k in a b; do echo "- [x] [T2] \`app/f$1$k.py\` — thing. VERIFY: x. (cat:python; multifile:no) [feat:demo2-2026110$1-feat-$1]" >> "$tmp/repos/demo2/OVERNIGHT_PROGRESS.md"; done; }   # a feature needs >= 2 items to count
for i in 1 2 3; do addfeat $i; done
: > "$CURLLOG"; rm -f "$tmp/state/feature_complete_last_flush"
run_watch
ok "aggregated: 3 completions in one tick -> exactly ONE push" "[ \$(grep -c '^CALL: -fsS' '$CURLLOG') -eq 1 ]"
ok "aggregated: the push is a note-class title that the relay does not drop ('Features ready to test: 3', no 'Feature complete')" "grep -q 'Features ready to test: 3' '$CURLLOG' && ! grep -qi 'Feature complete' '$CURLLOG'"
ok "aggregated: the body names the features" "grep -q 'demo2-20261101-feat-1' '$CURLLOG' && grep -q 'demo2-20261103-feat-3' '$CURLLOG'"
addfeat 4
: > "$CURLLOG"; run_watch
ok "aggregated: a new completion inside the flush window is buffered, no push yet" "[ ! -s '$CURLLOG' ] && grep -q 'demo2-20261104-feat-4' '$tmp/state/feature_complete_pending.log'"
echo 1 > "$tmp/state/feature_complete_last_flush"; : > "$CURLLOG"; run_watch
ok "aggregated: after the window the buffered completion goes out as ONE push and the buffer is cleared" "[ \$(grep -c '^CALL: -fsS' '$CURLLOG') -eq 1 ] && grep -q 'Features ready to test: 1' '$CURLLOG' && [ ! -s '$tmp/state/feature_complete_pending.log' ]"
# mutant: aggregation ignored (per-item pushes again) must be caught by the burst check
sed 's/^AGG="\${OVN_FEATURE_AGGREGATE:-on}"/AGG=off/' "$tmp/ovn_feature_watch.sh" > "$tmp/mut_watch.sh"
ok "mutant anchor applies" "! cmp -s '$tmp/ovn_feature_watch.sh' '$tmp/mut_watch.sh'"
for i in 5 6 7; do addfeat $i; done
: > "$CURLLOG"; WATCH_SCRIPT="$tmp/mut_watch.sh" AGG_MODE=on run_watch
ok "mutant (aggregation ignored) is caught: a 3-feature burst would send 3 pushes" "[ \$(grep -c '^CALL: -fsS' '$CURLLOG') -eq 3 ]"

# ---- S2 review fix: an unreachable relay at flush time must NOT lose the buffered list or advance the flush clock ----
for i in 8 9; do addfeat $i; done
setcurl(){ printf '#!/usr/bin/env bash\necho "CALL: $*" >> "%s"\nexit %s\n' "$CURLLOG" "$1" > "$tmp/bin/curl"; chmod +x "$tmp/bin/curl"; }
setcurl 7
echo 1 > "$tmp/state/feature_complete_last_flush"; : > "$CURLLOG"; AGG_MODE=on run_watch
ok "flush with relay down: pending buffer kept (>=2 entries) and flush clock NOT advanced" "[ \$(wc -l < '$tmp/state/feature_complete_pending.log') -ge 2 ] && [ \$(cat '$tmp/state/feature_complete_last_flush') = 1 ]"
setcurl 0
: > "$CURLLOG"; AGG_MODE=on run_watch
ok "relay back: the retained list is delivered in one push and the buffer cleared" "grep -q 'demo2-20261108-feat-8' '$CURLLOG' && [ ! -s '$tmp/state/feature_complete_pending.log' ]"
# mutant: alert() swallows failures again (old behaviour) -> buffer lost on a failed push
sed 's#>/dev/null 2>&1; }#>/dev/null 2>\&1 || true; }#' "$tmp/ovn_feature_watch.sh" > "$tmp/mut2.sh"
ok "mutant2 anchor applies" "! cmp -s '$tmp/ovn_feature_watch.sh' '$tmp/mut2.sh' && bash -n '$tmp/mut2.sh'"
echo "demo2 mutfeat" >> "$tmp/state/feature_complete_pending.log"; setcurl 7
echo 1 > "$tmp/state/feature_complete_last_flush"; WATCH_SCRIPT="$tmp/mut2.sh" AGG_MODE=on run_watch
ok "mutant (failure swallowed, unconditional clear) is caught: buffer lost on a failed push" "[ ! -s '$tmp/state/feature_complete_pending.log' ]"

echo "ovn_feature_watch.sh: $P passed, $F failed"
[ "$F" -eq 0 ]
