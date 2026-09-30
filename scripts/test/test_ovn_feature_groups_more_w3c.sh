#!/usr/bin/env bash
# Wave-3 coverage: remaining branches of scripts/ovn_feature_groups.py (real file, run in place):
# title-resolution misses, feat_lookup_for_file (imported by path), task_stats parsing edge rows,
# digest/in-progress max-total truncation, --min-total, usage exit.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../ovn_feature_groups.py"
P=0; F=0
ok(){ if [ "$2" = "1" ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
has(){ printf '%s' "$1" | grep -qF -- "$2" && echo 1 || echo 0; }
[ -f "$SCRIPT" ] || { echo "SKIP: no script"; echo "ovn_feature_groups_more: 0 passed, 0 failed"; exit 0; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/repos/aa" "$T/repos/bb" "$T/repos/nobl" "$T/backlog" "$T/state" "$T/roadmap" "$T/repos/afile.txt"
export OVN_QUEUE_DIR="$T" OVN_REPOS_DIR="$T/repos" OVN_BACKLOG_DIR="$T/backlog" OVN_TASK_STATS="$T/state/task_stats.log" OVN_ROADMAP_DIR="$T/roadmap"
slug="aa-20260101-ship-the-widget-feature-now-please-ok-wh"
cat > "$T/repos/aa/OVERNIGHT_PROGRESS.md" <<'E'
## Next Steps
not an item line
- [x] [T2] `app/a.py` — thing [feat:aa-20260101-ship-the-widget-feature-now-please-ok-wh]
- [ ] [T2] `app/b.py` — thing [feat:aa-20260101-ship-the-widget-feature-now-please-ok-wh]
- [ ] [T2] `app/c.py` — other [feat:aa-20260101-second-one]
- [ ] [T2] `app/d.py` — other [feat:aa-20260101-second-one]
- [ ] no path in this one at all
- [ ] [T1] y/solo.py — solo
- [ ] [T1] x/same.py — filekind
- [x] [T1] x/same.py — filekind
E
cat > "$T/repos/bb/OVERNIGHT_PROGRESS.md" <<'E'
- [ ] [T2] app/e.py — t [feat:bb-20260101-bbfeat]
- [x] [T2] app/f.py — t [feat:bb-20260101-bbfeat]
E
cat > "$T/repos/nobl/OVERNIGHT_PROGRESS.md" <<'E'
- [x] [T2] app/g.py — t [feat:nobl-20260101-done]
- [x] [T2] app/h.py — t [feat:nobl-20260101-done]
E
# roadmap for aa: a heading (non-matching) + a matching line; nobl has none
printf '%s\n' '# roadmap' '- [ ] [P2] [decomposed] Ship the widget feature now please ok — why {cat: x}' > "$T/roadmap/aa.md"
# backlog: aa has a leftover queued item, nobl has no backlog file
printf '%s\n' '- [ ] [T2] app/z.py — x [feat:aa-20260101-second-one]' > "$T/backlog/aa.md"

now=$(date +%s)
printf '%s\t%s\t%s\t%s\t%s\n' "$now" aa pass t app/c.py "$now" bb pass t app/e.py "$now" nobl pass t app/g.py \
  "$now" aa fail t app/a.py "notanumber" aa pass t app/b.py "$((now-999999))" aa pass t app/d.py > "$T/state/task_stats.log"
printf 'short\trow\n' >> "$T/state/task_stats.log"

# feature_title / feat_lookup_for_file via import-by-path
out="$(python3 - "$SCRIPT" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ofg", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print("T1", m.feature_title("aa", "zz-20260101-foo"))          # repo mismatch
print("T2", m.feature_title("nobl", "nobl-20260101-foo"))      # no roadmap file
print("T3", m.feature_title("aa", "aa-20260101-nomatch"))      # roadmap present, no slug match
print("T4", m.feature_title("aa", "aa-20260101-ship-the-widget-feature-now-please-ok-wh"))
print("T5", m.feature_title("aa", None))
print("L1", m.feat_lookup_for_file("aa", "app/a.py"))
print("L2", m.feat_lookup_for_file("aa", "x/same.py"))         # file-kind group skipped
print("L3", m.feat_lookup_for_file("aa", "nope.py"))
PY
)"
ok "title: repo mismatch -> None" "$(has "$out" 'T1 None')"
ok "title: no roadmap -> None" "$(has "$out" 'T2 None')"
ok "title: no slug match -> None" "$(has "$out" 'T3 None')"
ok "title: slug match resolves" "$(has "$out" 'T4 Ship the widget feature now please ok')"
ok "title: None id -> None" "$(has "$out" 'T5 None')"
ok "lookup: feat file found with title and pct" "$(has "$out" "L1 ('aa-20260101-ship-the-widget-feature-now-please-ok-wh', 'Ship the widget feature now please ok', 50)")"
ok "lookup: same-file group never attributed" "$(has "$out" 'L2 None')"
ok "lookup: unknown file -> None" "$(has "$out" 'L3 None')"

# repo listing: missing PROGRESS/DONE files tolerated (nobl has no DONE), json + --min-total
j="$(python3 "$SCRIPT" aa --json --min-total 1)"
ok "min-total 1 includes single-item groups" "$(has "$j" '"total": 1')"
ok "backlog_remaining counted" "$(has "$j" '"backlog_remaining": 1')"
j2="$(python3 "$SCRIPT" nobl --json)"
ok "done feat group without backlog file" "$(has "$j2" '"done": true')"
txt="$(python3 "$SCRIPT" aa)"
ok "text listing has approx label" "$(has "$txt" 'approx')"

# digest
d="$(python3 "$SCRIPT" --digest 3)"
ok "digest prints header" "$(has "$d" 'Feature progress')"
ok "digest shows aa second-one" "$(has "$d" 'second-one')"
d1="$(python3 "$SCRIPT" --digest 3 --max-total 1)"
ok "digest max-total 1 -> one line" "$([ "$(printf '%s\n' "$d1" | grep -c '^  ')" = 1 ] && echo 1 || echo 0)"
d0="$(python3 "$SCRIPT" --digest 0.0000001)"
ok "digest with nothing in window prints nothing" "$([ -z "$d0" ] && echo 1 || echo 0)"
dd="$(python3 "$SCRIPT" --digest --max-total 2)"
ok "digest default hours accepted" "$(has "$dd" 'Feature progress')"
# two touched groups in a single repo with max-total 1 (inner break)
now2=$(date +%s); printf '%s\t%s\t%s\t%s\t%s\n' "$now2" aa pass t app/a.py "$now2" aa pass t x/same.py >> "$T/state/task_stats.log"
d2="$(python3 "$SCRIPT" --digest 3 --max-total 1)"
ok "digest inner break keeps one line" "$([ "$(printf '%s\n' "$d2" | grep -c '^  ')" = 1 ] && echo 1 || echo 0)"

# in-progress
ip="$(python3 "$SCRIPT" --in-progress)"
ok "in-progress header" "$(has "$ip" 'Features in progress')"
ok "in-progress resolves title in quotes" "$(has "$ip" '"Ship the widget feature now please ok"')"
ok "in-progress skips done group" "$([ "$(has "$ip" nobl)" = 0 ] && echo 1 || echo 0)"
ip1="$(python3 "$SCRIPT" --in-progress --max-total 1)"
ok "in-progress max-total 1 -> one line" "$([ "$(printf '%s\n' "$ip1" | grep -c '^  ')" = 1 ] && echo 1 || echo 0)"
ip2="$(python3 "$SCRIPT" --in-progress --max-total 0)"
ok "in-progress max-total 0 prints nothing" "$([ -z "$ip2" ] && echo 1 || echo 0)"
# in-progress with no repos dir
ipn="$(OVN_REPOS_DIR="$T/nonexistent" python3 "$SCRIPT" --in-progress)"
ok "in-progress with absent repos dir prints nothing" "$([ -z "$ipn" ] && echo 1 || echo 0)"

# ready-count
rc="$(python3 "$SCRIPT" --ready-count 3)"
ok "ready-count counts done+landed group (nobl)" "$([ "$rc" = 1 ] && echo 1 || echo 0)"
rc2="$(python3 "$SCRIPT" --ready-count)"
ok "ready-count default hours" "$([ "$rc2" = 1 ] && echo 1 || echo 0)"

# usage
err="$(python3 "$SCRIPT" 2>&1 >/dev/null)"; rcx=$?
ok "no args -> usage + exit 2" "$([ "$rcx" = 2 ] && [ "$(has "$err" usage)" = 1 ] && echo 1 || echo 0)"

echo "ovn_feature_groups_more: $P passed, $F failed"
[ "$F" -eq 0 ]
