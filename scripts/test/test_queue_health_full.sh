#!/usr/bin/env bash
# Runs the REAL queue_health.sh in a fake tree and covers: low-queue alert + 24h cooldown, hygiene-stalled alert
# (review-flag gating, ahead>=25 threshold, non-git repo skip), default CHECKS, expected-substring mismatch, comment/blank
# filtering, recovery, missing ntfy topic (alerts become no-ops).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
QH=""
for c in "$HERE/../../queue_health.sh" "$HERE/../queue_health.sh" "$HERE/queue_health.sh"; do [ -f "$c" ] && { QH="$c"; break; }; done
[ -n "$QH" ] || { echo "  SKIP: queue_health.sh not found"; exit 0; }
P=0; F=0
ok(){ if [ "$2" = "1" ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
Q="$T/q"; BIN="$T/bin"; ALERTS="$T/alerts.txt"; CURLLOG="$T/curl.log"
mkdir -p "$Q/state" "$Q/repos" "$BIN"
cp "$QH" "$Q/queue_health.sh"
# curl stub: logs URL; records alert Titles; for health GETs honours -o <file> and returns body/code from ctl files
cat > "$BIN/curl" <<EOF
#!/usr/bin/env bash
out=""; url=""; fmt=""
while [ \$# -gt 0 ]; do
  case "\$1" in
    -o) out="\$2"; shift 2;;
    -w) fmt="\$2"; shift 2;;
    -H) case "\$2" in Title:*) echo "\$2" >> "$ALERTS";; esac; shift 2;;
    -d|--max-time) shift 2;;
    -*) shift;;
    *) url="\$1"; shift;;
  esac
done
echo "\$url" >> "$CURLLOG"
[ -n "\$out" ] && cat "$T/body" > "\$out" 2>/dev/null
if [ -n "\$fmt" ]; then
  code="\$(cat "$T/code" 2>/dev/null || echo 200)"
  printf '%s' "\$code"
  case "\$code" in 2*|3*) exit 0;; *) exit 22;; esac
fi
exit 0
EOF
chmod +x "$BIN/curl"
echo 200 > "$T/code"; echo "all good body" > "$T/body"
qh(){ ( cd "$Q" && PATH="$BIN:$PATH" env "$@" bash queue_health.sh >"$T/out.txt" 2>&1 ); RC=$?; }
cnt(){ local c; c="$(grep -c -- "$1" "$ALERTS" 2>/dev/null)"; echo "${c:-0}"; }
reset(){ : > "$ALERTS"; : > "$CURLLOG"; rm -f "$Q"/state/qh_bad_* "$Q/state/lowqueue_alert_last"; }

mkrepo(){ # $1 name $2 "doable count" ; creates repos/<n> with OVERNIGHT_PROGRESS.md and a bare origin w/ develop + overnight/feature
  local n="$1" d="$2" r="$Q/repos/$1"
  mkdir -p "$r"
  { echo "## Next Steps"; i=0; while [ "$i" -lt "$d" ]; do echo "- [ ] real item $i"; i=$((i+1)); done
    echo "- [ ] HUMAN-ONLY thing"; echo "- [ ] human/ dir item"; echo "- [ ] AUTO-SKIP me"; echo "- [ ] BLOCKED ITEM x"; echo "- [ ] (retired-vague) foo"; echo "- [x] done one"; } > "$r/OVERNIGHT_PROGRESS.md"
}
mkgit(){ # $1 name $2 ahead-count ; adds git + origin
  local n="$1" ahead="$2" r="$Q/repos/$1" o="$T/origin_$1.git"
  git init -q --bare "$o"
  ( cd "$r" && git init -q -b develop && git config user.email t@t && git config user.name t && git add -A && git commit -q -m base \
      && git remote add origin "$o" && git push -q origin develop \
      && git checkout -q -b overnight/feature && i=0 && while [ "$i" -lt "$ahead" ]; do git commit -q --allow-empty -m "c$i"; i=$((i+1)); done \
      && git push -q origin overnight/feature )
}

# tasks: alpha (enabled, low), beta (enabled, plenty + gets git), gamma (DISABLED), delta (enabled, no progress file), eps (enabled, not a git repo, flag set)
cat > "$Q/tasks.json" <<'EOF'
[
 {"id":"a","repo":"/x/repos/alpha"},
 {"id":"b","repo":"/x/repos/beta","enabled":true},
 {"id":"c","repo":"/x/repos/gamma","enabled":false},
 {"id":"d","repo":"/x/repos/delta"},
 {"id":"e","repo":"/x/repos/eps"}
]
EOF
mkrepo alpha 2; mkrepo beta 9; mkrepo gamma 0; mkrepo eps 9
mkdir -p "$Q/repos/delta"   # no progress file -> skipped

# ---- 1. low queue: alpha=2 < 5 fires once; gamma (disabled, 0 doable) is not reported; delta skipped ----
reset
qh NTFY_TOPIC=tt MIN_DOABLE=5
ok "low queue fires exactly one alert" "$([ "$(cnt 'Queue running low')" = 1 ] && echo 1 || echo 0)"
ok "marker file written with epoch" "$([ -s "$Q/state/lowqueue_alert_last" ] && echo 1 || echo 0)"
ok "default CHECKS endpoint is curl'd (chickadee-backend) and healthy -> no deploy alert" "$([ "$(cnt 'Deploy health check')" = 0 ] && grep -q 'chickadeestream-production' "$CURLLOG" && echo 1 || echo 0)"
qh NTFY_TOPIC=tt MIN_DOABLE=5
ok "second run within 24h is throttled" "$([ "$(cnt 'Queue running low')" = 1 ] && echo 1 || echo 0)"
echo $(( $(date +%s) - 90000 )) > "$Q/state/lowqueue_alert_last"
qh NTFY_TOPIC=tt MIN_DOABLE=5
ok "cooldown elapsed (>24h) -> alerts again" "$([ "$(cnt 'Queue running low')" = 2 ] && echo 1 || echo 0)"
reset
qh NTFY_TOPIC=tt MIN_DOABLE=1
ok "threshold respected: MIN_DOABLE=1 -> alpha (2) not low, no alert" "$([ "$(cnt 'Queue running low')" = 0 ] && echo 1 || echo 0)"

# ---- 1b. hygiene stalled ----
mkgit beta 30
mkdir -p "$Q/repos/eps/.git"   # eps: .git dir exists but is not a real repo
reset
qh NTFY_TOPIC=tt MIN_DOABLE=0
ok "30 ahead but NO review flag -> not stalled (no alert)" "$([ "$(cnt 'Hygiene stalled')" = 0 ] && echo 1 || echo 0)"
echo "gate red: tests failing in foo" > "$Q/state/branch_hygiene_review_beta"
qh NTFY_TOPIC=tt MIN_DOABLE=0
ok "flag + ahead>=25 -> Hygiene stalled alert" "$([ "$(cnt 'Hygiene stalled')" = 1 ] && echo 1 || echo 0)"
echo "flag" > "$Q/state/branch_hygiene_review_eps"
qh NTFY_TOPIC=tt MIN_DOABLE=0
ok "flagged non-repo (eps) does not crash; still only stalled on beta" "$([ "$RC" = 0 ] && echo 1 || echo 0)"
# now make beta only slightly ahead
rm -rf "$Q/repos/beta/.git" "$T/origin_beta.git"; mkgit beta 3
reset
qh NTFY_TOPIC=tt MIN_DOABLE=0
ok "flag but ahead<25 -> no stalled alert" "$([ "$(cnt 'Hygiene stalled')" = 0 ] && echo 1 || echo 0)"

# ---- 2. health endpoints file: comments/blanks filtered, substring check, dedupe + recovery ----
reset
cat > "$Q/state/health_endpoints.txt" <<'EOF'
# name|url|expected
   # indented comment

svc-a|https://a.example.test/health|
svc-b|https://b.example.test/health|"status":"ok"
svc-nourl|
EOF
echo 200 > "$T/code"; echo 'nothing useful' > "$T/body"
qh NTFY_TOPIC=tt MIN_DOABLE=0
ok "2xx but missing expected substring -> FAILED alert" "$([ "$(cnt 'Deploy health check FAILED')" = 1 ] && echo 1 || echo 0)"
ok "missing-substring marker holds the reason" "$(grep -q "missing" "$Q/state/qh_bad_svc-b" 2>/dev/null && echo 1 || echo 0)"
ok "svc-a (no expectation) healthy, no marker" "$([ ! -f "$Q/state/qh_bad_svc-a" ] && echo 1 || echo 0)"
ok "entry without url skipped (never curl'd)" "$(grep -q 'svc-nourl' "$CURLLOG" && echo 0 || echo 1)"
ok "comment header never curl'd as a url" "$(grep -qx 'url' "$CURLLOG" && echo 0 || echo 1)"
: > "$ALERTS"
qh NTFY_TOPIC=tt MIN_DOABLE=0
ok "still bad -> no repeat alert (still_bad branch)" "$([ "$(cnt 'Deploy health check FAILED')" = 0 ] && echo 1 || echo 0)"
echo '{"status":"ok"}' > "$T/body"
qh NTFY_TOPIC=tt MIN_DOABLE=0
ok "substring present -> recovery alert + marker cleared" "$([ "$(cnt 'Deploy health check recovered')" = 1 ] && [ ! -f "$Q/state/qh_bad_svc-b" ] && echo 1 || echo 0)"
echo 503 > "$T/code"
: > "$ALERTS"
qh NTFY_TOPIC=tt MIN_DOABLE=0
ok "non-2xx/3xx -> FAILED for both endpoints in ONE alert" "$([ "$(cnt 'Deploy health check FAILED')" = 1 ] && grep -q 'HTTP 503' "$Q/state/qh_bad_svc-a" && echo 1 || echo 0)"
echo 301 > "$T/code"; : > "$ALERTS"
qh NTFY_TOPIC=tt MIN_DOABLE=0
ok "3xx counts as healthy -> recovered" "$([ "$(cnt 'Deploy health check recovered')" = 1 ] && echo 1 || echo 0)"

# ---- no ntfy topic: alert() is a silent no-op, script still exits 0 ----
reset; rm -f "$Q/state/health_endpoints.txt" "$Q/state/ntfy_topic"
echo 500 > "$T/code"
( cd "$Q" && PATH="$BIN:$PATH" env -u NTFY_TOPIC MIN_DOABLE=5 bash queue_health.sh >"$T/out.txt" 2>&1 ); RC=$?
ok "no topic: exits 0 and sends no alerts" "$([ "$RC" = 0 ] && [ ! -s "$ALERTS" ] && echo 1 || echo 0)"
echo "fromfile" > "$Q/state/ntfy_topic"; echo 200 > "$T/code"; rm -f "$Q/state/qh_bad_chickadee-backend" "$Q/state/lowqueue_alert_last"; : > "$CURLLOG"; : > "$ALERTS"
( cd "$Q" && PATH="$BIN:$PATH" env -u NTFY_TOPIC MIN_DOABLE=5 bash queue_health.sh >"$T/out.txt" 2>&1 ); RC=$?
ok "topic read from state/ntfy_topic" "$(grep -q 'ntfy.sh/fromfile' "$CURLLOG" && echo 1 || echo 0)"

echo "queue_health_full: $P passed, $F failed"
[ "$F" = 0 ]
