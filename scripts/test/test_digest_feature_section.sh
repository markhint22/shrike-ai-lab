#!/usr/bin/env bash
# Regression test: digest_notify.sh's 3h digest surfaces feature-progress (2026-09-20) — when
# a multi-item group ([feat:ID] or the file-based approximate fallback) had a landed item in
# the window, the digest includes a "🧩 Feature progress" section built from
# scripts/ovn_feature_groups.py --digest. Mirrors digest_notify.sh (+ its real script
# dependencies) into a fixture dir so it never touches production data or the real network.
set -uo pipefail
OQ="${OVN_QUEUE_DIR:-$HOME/overnight-queue}"
D="$OQ/digest_notify.sh"
[ -f "$D" ] || { echo "  SKIP: $D not found on this host"; exit 0; }

P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/state" "$tmp/scripts" "$tmp/repos/demo" "$tmp/backlog" "$tmp/bin"
cp "$D" "$tmp/digest_notify.sh"
for f in ovn_landed_detail.py ovn_tier_stats.py ovn_stats.py ovn_planning_stats.py ovn_feature_groups.py; do
  [ -f "$OQ/scripts/$f" ] && cp "$OQ/scripts/$f" "$tmp/scripts/$f"
done
echo "faketopic" > "$tmp/state/ntfy_topic"
echo '{}' > "$tmp/tasks.json"

now="$(date +%s)"
printf '%s\tdemo\tpass\t{py.other.T2.tested}\tapp/a.py\n' "$now" > "$tmp/state/task_stats.log"
printf '%s\t1\t0\t0\t0\t0\tPASS=demo\tFAIL=\tREV=\tERR=\n' "$now" > "$tmp/state/digest_buffer.log"
cat > "$tmp/repos/demo/OVERNIGHT_PROGRESS.md" <<'EOF'
- [x] [T2] `app/a.py` — thing. VERIFY: x. (cat:python; multifile:no) [feat:demo-20260101-widget]
- [ ] [T2] `app/b.py` — thing. VERIFY: x. (cat:python; multifile:no) [feat:demo-20260101-widget]
EOF
: > "$tmp/repos/demo/OVERNIGHT_DONE.md"
: > "$tmp/backlog/demo.md"

BODYLOG="$tmp/body.log"
cat > "$tmp/bin/curl" <<CURLEOF
#!/usr/bin/env bash
prev=""
for a in "\$@"; do
  if [ "\$prev" = "-d" ]; then printf '%s' "\$a" > "$BODYLOG"; fi
  prev="\$a"
done
exit 0
CURLEOF
chmod +x "$tmp/bin/curl"

( cd "$tmp" && PATH="$tmp/bin:$PATH" HOME="$tmp" bash "$tmp/digest_notify.sh" >/dev/null 2>&1 )

ok "digest body includes the feature-progress section" "grep -q 'Feature progress' '$BODYLOG'"
ok "digest body names the touched feature and its % complete" "grep -q 'demo-20260101-widget: 1/2 (50%)' '$BODYLOG'"

echo "Digest feature-progress section: $P passed, $F failed"
[ "$F" -eq 0 ]
