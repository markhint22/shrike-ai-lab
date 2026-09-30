#!/usr/bin/env bash
# Regression: render_dashboard.py turns state/fleet_stats.json into a self-contained www/fleet_dashboard.html.
# Hermetic: the script is copied into a temp "tree" (it derives state/ and www/ from its own dir), so the real
# ~/overnight-queue/state and www are never read or written.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SUT=""; for c in "$HERE/../../render_dashboard.py" "$HERE/../render_dashboard.py" "$HERE/render_dashboard.py"; do [ -f "$c" ] && { SUT="$c"; break; }; done
[ -n "$SUT" ] || { echo "render_dashboard.py not found"; exit 2; }
pass=0; fail=0; ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/tree/state"; cp "$SUT" "$T/tree/render_dashboard.py"
OUT="$T/tree/www/fleet_dashboard.html"; ST="$T/tree/state/fleet_stats.json"
has(){ grep -qF -- "$1" "$OUT" && echo 1 || echo 0; }
run(){ python3 "$T/tree/render_dashboard.py" >"$T/out.txt" 2>"$T/err.txt"; echo $?; }

# 1. missing stats file
rc="$(run)"
ok "missing fleet_stats.json -> exit 1" "$([ "$rc" = 1 ] && echo 1 || echo 0)"
ok "missing stats -> helpful stderr message" "$(grep -q 'run fleet_stats.py first' "$T/err.txt" && echo 1 || echo 0)"
ok "missing stats -> no www dir created" "$([ ! -e "$T/tree/www" ] && echo 1 || echo 0)"

# 2. full render
cat > "$ST" <<'J'
{"generated_at":"2026-09-30T01:02:03Z",
 "fleet":{"llama_requests_today":12345,"tokens_today":1234567.89,"context_overflow_today":0},
 "repos":{
  "zeta":{"doable":2,"done":1500,"landed_1d":3,"landed_7d":20,"runway_days":0.5,"unpromoted":31,"pass_rate_7d":60.0,
          "by_category_7d":{"python":{"attempted":10,"landed":6,"pass_rate":60.0},
                            "docs":{"attempted":40,"landed":38,"pass_rate":95.0},
                            "mid":{"attempted":20,"landed":15,"pass_rate":75.0},
                            "none":{"attempted":5,"landed":0,"pass_rate":null}}},
  "alpha":{"doable":5,"done":3,"landed_1d":0,"landed_7d":1,"runway_days":2.9,"unpromoted":30,"pass_rate_7d":85.0,"by_category_7d":{}},
  "<b>x&y</b>":{"doable":null,"runway_days":null,"unpromoted":null,"pass_rate_7d":null}
 }}
J
rc="$(run)"
ok "full render exits 0" "$([ "$rc" = 0 ] && echo 1 || echo 0)"
ok "prints 'wrote <path>'" "$(grep -q "^wrote .*fleet_dashboard.html" "$T/out.txt" && echo 1 || echo 0)"
ok "output file exists and is an HTML doc" "$(head -c 15 "$OUT" | grep -qi '<!doctype html>' && echo 1 || echo 0)"
ok "no .tmp file left behind" "$([ ! -e "$OUT.tmp" ] && echo 1 || echo 0)"
ok "generated_at is shown" "$(has 'Generated 2026-09-30T01:02:03Z')"
ok "fleet int gets thousands separator" "$(has '12,345')"
ok "fleet float gets 1 decimal + separators" "$(has '1,234,567.9')"
ok "zero renders as 0 (not dash)" "$(python3 - "$OUT" <<'P'
import re,sys
h=open(sys.argv[1]).read()
m=re.search(r"context overflows today</span>\s*<span class=\"value\">([^<]*)<",h)
print(1 if m and m.group(1)=="0" else 0)
P
)"
ok "repo names sorted (alpha before zeta)" "$(python3 - "$OUT" <<'P'
import sys
h=open(sys.argv[1]).read()
print(1 if 0<h.index("<h3>alpha</h3>")<h.index("<h3>zeta</h3>") else 0)
P
)"
ok "repo name is html-escaped" "$([ "$(has '<h3>&lt;b&gt;x&amp;y&lt;/b&gt;</h3>')" = 1 ] && ! grep -qF '<h3><b>' "$OUT" && echo 1 || echo 0)"
ok "doable<5 flagged stat-danger" "$(has 'stat-value stat-danger">2<')"
ok "doable==5 not flagged" "$(has 'stat-value ">5<')"
ok "unpromoted>30 flagged stat-warn" "$(has 'stat-value stat-warn">31<')"
ok "unpromoted==30 not flagged" "$(has 'stat-value ">30<')"
ok "runway<1 -> runway-low" "$(has 'runway-low">0.5d')"
ok "runway<3 -> runway-warn" "$(has 'runway-warn">2.9d')"
ok "None values render as em-dash (runway shows '—d')" "$(has '>—d<')"
ok "pass rate <70 -> rate-low" "$(has 'stat-value rate-low">60.0%')"
ok "pass rate ==85 -> rate-good" "$(has 'stat-value rate-good">85.0%')"
ok "pass rate None -> '—%' with no class" "$(has 'stat-value ">—%')"
ok "75% category bar -> rate-warn fill" "$(has "cat-bar-fill rate-warn' style='width:75.0%'")"
ok "category bars sorted by attempted desc (docs first)" "$(python3 - "$OUT" <<'P'
import sys
h=open(sys.argv[1]).read()
i=[h.index(f"<span class='cat-name'>{c}</span>") for c in ("docs","mid","python","none")]
print(1 if i==sorted(i) else 0)
P
)"
ok "null pass_rate category -> width:0% and dash" "$(has "style='width:0%'")"
ok "category shows landed/attempted" "$(has '(38/40)')"
ok "empty by_category -> 'no attempts recorded'" "$(has 'no attempts recorded')"
ok "page has no external asset/network refs" "$(grep -qE 'src=|href=|https?://' "$OUT" && echo 0 || echo 1)"

# 3. idempotent + overwrite
cp "$OUT" "$T/first.html"; rc="$(run)"
ok "re-render is deterministic/idempotent" "$(cmp -s "$OUT" "$T/first.html" && echo 1 || echo 0)"

# 4. minimal data
echo '{}' > "$ST"; rc="$(run)"
ok "empty json {} renders (exit 0)" "$([ "$rc" = 0 ] && echo 1 || echo 0)"
ok "missing generated_at -> 'unknown'" "$(has 'Generated unknown')"
ok "missing fleet values -> dashes" "$([ "$(grep -o '<span class="value">—</span>' "$OUT" | wc -l | tr -d ' ')" = 3 ] && echo 1 || echo 0)"
ok "no repos -> empty grid" "$(has '<div class="grid"></div>')"

# 5. corrupt json: fails loudly, does not clobber last good output
echo '{"repos": ' > "$ST"; cp "$OUT" "$T/good.html"; rc="$(run)"
ok "corrupt json -> nonzero exit" "$([ "$rc" != 0 ] && echo 1 || echo 0)"
ok "corrupt json -> previous output untouched" "$(cmp -s "$OUT" "$T/good.html" && echo 1 || echo 0)"

# 6. helper functions directly
ok "helpers: fmt_num/runway_class/pass_rate_class boundaries" "$(cd "$T/tree" && python3 - <<'P'
import render_dashboard as r
c=[r.fmt_num(None)=="—", r.fmt_num(0)=="0", r.fmt_num(1234)=="1,234", r.fmt_num(0.04)=="0.0",
   r.runway_class(None)=="", r.runway_class(0.99)=="runway-low", r.runway_class(1)=="runway-warn",
   r.runway_class(3)=="", r.pass_rate_class(None)=="", r.pass_rate_class(69.9)=="rate-low",
   r.pass_rate_class(70)=="rate-warn", r.pass_rate_class(84.9)=="rate-warn", r.pass_rate_class(85)=="rate-good",
   "no attempts" in r.render_category_bars({}), "no attempts" in r.render_category_bars(None)]
print(1 if all(c) else 0)
P
)"
echo "$pass passed, $fail failed"; [ "$fail" -eq 0 ]
