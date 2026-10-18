#!/usr/bin/env bash
# ovn_auto_research.sh + ovn_auto_research_validate.py, 2026-10-18 ("backlog is out for many repos" incident). Covers, with real replies as fixtures:
#   1. the research lane covers EVERY active repo by default (was "iptv_apps xlite": 5 repos 'excluded' for 16-22h) and repos starving >= 12h are served first, longest first
#   2. the reply parser recovers the real xlite reply (bold "- **[needs-research -> ready] P1 . bug . area** ..." with no title separator / no {cat:} meta) that the old
#      `grep '^- \[ \]'` threw away as a FAILED pass; prose and invalid lines (no priority, P7, no status) are still rejected; canonical lines pass byte-for-byte
#   3. OVN_AR_SALVAGE_REPO re-validates a saved reply without calling claude and without touching the daily count / cooldown markers (works at the cap)
#   4. a rc=124 pass (36 of 103 logged passes) gets ONE smaller-scope retry (<=4 items, no web tools, own $ cap); the per-pass --max-budget-usd stays on both attempts
#   5. a failed pass starts a SHORT escalating cooldown (1h,2h,4h cap) instead of none, a success clears it, and a daily failed-pass cap exists
#   6. the daily cap is derived from the burn rate and the arithmetic is logged; OVN_AR_MAX_PER_DAY still overrides
# Hermetic (lib_ar_fixture.sh): temp HOME/state, stub ssh/scp/claude/timeout, the "box" is a temp dir. Mutation checks at the bottom (each mutant must break a check).
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../../ovn_auto_research.sh"; [ -f "$SCRIPT" ] || SCRIPT="$HERE/../ovn_auto_research.sh"
VALIDATOR="$HERE/../../ovn_auto_research_validate.py"; [ -f "$VALIDATOR" ] || VALIDATOR="$HERE/../ovn_auto_research_validate.py"
FIX="$HERE/fixtures"
XL="$FIX/ar_reply_xlite_bold_2026-10-18.txt"; IPTV="$FIX/ar_reply_iptv_canonical_2026-10-18.txt"
. "$HERE/lib_ar_fixture.sh"
P=0; F=0
ok(){ if [ "$2" = 1 ] || { [ "$2" != 0 ] && eval "$2" >/dev/null 2>&1; }; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
MT="$(__d="$(safe_mktemp_dir)" || exit 1 && [ -n "$__d" ] && cd "$__d" && pwd -P)" || exit 1; trap 'rm -rf "${MT:?}"; [ -n "${T:-}" ] && rm -rf "$T"' EXIT
META='{cat: backend; size: S; multifile: no; research: repo}'
[ -f "$XL" ] && [ -f "$IPTV" ] || { echo "  FAIL: fixtures missing"; exit 1; }

mutate(){   # <src> <dest> <anchor> <replacement>  (the anchor must exist, else the test itself is stale)
  python3 - "$1" "$2" "$3" "$4" 2>/dev/null <<'PY' || { F=$((F+1)); echo "  FAIL mutation anchor missing - the test is stale: $3"; }
import sys
src, dest, a, b = sys.argv[1:5]
s = open(src).read()
assert a in s, "mutation anchor missing: %r" % a
open(dest, "w").write(s.replace(a, b, 1))
PY
}
chk(){ if eval "$2" >/dev/null 2>&1; then echo "1|$1"; else echo "0|$1"; fi; }
order_of(){ grep -a "starting research pass" "$T/out.txt" | sed 's/^[^ ]* [^ ]* \([^:]*\):.*/\1/' | tr '\n' ' '; }
now(){ date +%s; }

# fixture: all 7 active repos + a discontinued one on the fake box; stub claude (scripted replies) + stub timeout (scripted rc=124)
setup(){   # <script> <validator>
  ar_setup "$1" "$2"
  for r in gitlark test-automation-agent; do mkdir -p "$CLONES/$r"; git init -q "$CLONES/$r" 2>/dev/null; done
  for r in iptv_apps xlite billwatch shrike-notify shrike-monitor gitlark test-automation-agent shrike-labs-website; do ar_roadmap "$r" "- [x] [P1] [done] Old feature of $r — app/old.py $META"; done
  cat > "$FAKEBIN/claude" <<'EOS'
#!/usr/bin/env bash
# scripted claude: call N replies per line N of $CAPTURE/modes: NONE | boldnone | prose | fail | reply:<file>   (default NONE)
n=$(( $(cat "$CAPTURE/n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$CAPTURE/n"
prompt=""; a=("$@"); while [ $# -gt 0 ]; do case "$1" in -p) prompt="$2"; shift;; esac; shift; done
printf '%s\n' "${a[@]}" > "$CAPTURE/cargs_$n.txt"
repo="$(printf '%s\n' "$prompt" | sed -n 's/.*REPO: \([A-Za-z0-9_-]*\)\..*/\1/p' | head -1)"
echo "${repo:-unknown}" >> "$CAPTURE/calls.log"
m="$(sed -n "${n}p" "$CAPTURE/modes" 2>/dev/null)"
case "$m" in
  reply:*) cat "${m#reply:}" ;;
  boldnone) echo '**NONE**' ;;
  fail) echo "boom" >&2; exit 3 ;;
  prose) echo 'I looked around the repository and everything seems fine. Nothing to report in the requested format.' ;;
  *) echo NONE ;;
esac
EOS
  cat > "$FAKEBIN/timeout" <<'EOS'
#!/usr/bin/env bash
# scripted timeout: call N behaves per line N of $CAPTURE/tmodes: timeout (exit 124, claude never runs) | run (default)
k=$(( $(cat "$CAPTURE/tn" 2>/dev/null || echo 0) + 1 )); echo "$k" > "$CAPTURE/tn"
echo "$1" >> "$CAPTURE/timeouts.log"; shift
printf '%s\n' "$@" > "$CAPTURE/targs_$k.txt"
[ "$(sed -n "${k}p" "$CAPTURE/tmodes" 2>/dev/null)" = timeout ] && exit 124
exec "$@"
EOS
  chmod +x "$FAKEBIN/claude" "$FAKEBIN/timeout"
  : > "$CAP/modes"; : > "$CAP/tmodes"
}
modes(){ printf '%s\n' "$@" > "$CAP/modes"; }
tmodes(){ printf '%s\n' "$@" > "$CAP/tmodes"; }
nclaude(){ [ -f "$CAP/calls.log" ] && wc -l < "$CAP/calls.log" | tr -d ' ' || echo 0; }
ntimeout(){ [ -f "$CAP/timeouts.log" ] && wc -l < "$CAP/timeouts.log" | tr -d ' ' || echo 0; }

# ---- 1. default lane + fairness
ck_default(){   # <script> <validator>
  setup "$1" "$2"
  ar_starving billwatch:22 shrike-monitor:19 test-automation-agent:18 gitlark:15.5 shrike-notify:15 xlite:5.5 iptv_apps:3 shrike-labs-website:30
  ar_run DRY_RUN=1 OVN_AR_MAX_PER_RUN=9
  local o; o="$(order_of)"
  chk "default lane = all 7 active repos, >=12h-starving first longest first, then round-robin [$o]" '[ "$o" = "billwatch shrike-monitor test-automation-agent gitlark shrike-notify xlite iptv_apps " ]'
  chk "the discontinued repo stays excluded and the reason is logged" 'grep -aq "excluded shrike-labs-website: not in the research lane allowlist" "$T/out.txt"'
  chk "fairness is logged in the order line" 'grep -aq "fairness: starving >= 12h served first" "$T/out.txt"'
  ar_cleanup; T=""
  setup "$1" "$2"
  ar_starving billwatch:22 xlite:5.5
  ar_runlog $((20*3600)) billwatch "accepted 3/4"; ar_runlog $((10*3600)) billwatch "accepted 2/3"
  ar_run DRY_RUN=1 OVN_AR_MAX_PER_RUN=9; o="$(order_of)"
  chk "22h-starving billwatch goes before xlite although it had 2 accepted passes in 48h [$o]" '[ "$o" = "billwatch xlite " ]'
  ar_run DRY_RUN=1 OVN_AR_MAX_PER_RUN=9 OVN_AR_FAIR_H=0; o="$(order_of)"
  chk "OVN_AR_FAIR_H=0 restores pure round-robin (xlite first) [$o]" '[ "$o" = "xlite billwatch " ]'
  ar_cleanup; T=""
}

# ---- 2. parser (validator CLI)
ck_parse(){   # <script> <validator>
  local v="$2" d out err; d="$(__d="$(safe_mktemp_dir)" || exit 1 && [ -n "$__d" ] && cd "$__d" && pwd -P)" || return 1
  python3 "$v" --normalize "$XL" --default-cat game > "$d/xl.out" 2> "$d/xl.err"
  : > "$d/e.md"; python3 "$v" "$d/xl.out" "$d/e.md" 12 > "$d/xl.acc" 2> "$d/xl.acc.err"
  chk "real xlite bold reply: 4 lines recovered" '[ "$(grep -c "^- \[ \] \[P[1-4]\] \[ready\] " "$d/xl.out")" = 4 ]'
  chk "recovered lines pass the real validator (accepted 4/4)" 'grep -aq "^accepted 4/4" "$d/xl.acc.err"'
  chk "xlite items get cat game / test from the tags, a derived title without an em dash in it" 'grep -aq "^- \[ \] \[P1\] \[ready\] bug units/status: StatusEffects.get_move_speed_multiplier() returns 0.5 for \"stunned\" — .*{cat: game; " "$d/xl.out" && grep -aq "{cat: test; \|test mission/objective" "$d/xl.out"'
  printf '%s\n' '- [ ] [P1] [ready] Fix `foo()` in **bar** handler — body cites app/a.py:3 and `b()` {cat: backend; size: S; multifile: no; research: none}' > "$d/canon.txt"
  python3 "$v" --normalize "$d/canon.txt" > "$d/canon.out" 2>/dev/null
  chk "a canonical line with backticks/bold in its title is NOT rewritten" 'diff "$d/canon.txt" "$d/canon.out"'
  python3 "$v" --normalize "$IPTV" > "$d/ip.out" 2>/dev/null
  chk "canonical lines pass through byte-for-byte" 'diff <(grep "^- \[ \]" "$IPTV") "$d/ip.out"'
  cat > "$d/bad.txt" <<'EOT'
Based on my investigation, here are the items I would propose:
- P1 fix the thing in app/x.py
- [ ] [P7] [ready] Bad priority — body app/x.py {cat: backend; size: S; multifile: no; research: none}
- [ ] [P0] [ready] Zero priority — body app/x.py {cat: backend; size: S; multifile: no; research: none}
- **Fix foo in app/x.py** — body text in app/x.py with enough words
Some closing prose that mentions [P1] [ready] inside a sentence.
- [ ] [P2] [ready] Good canonical one — body app/y.py:12 {cat: backend; size: S; multifile: no; research: none}
[P3] [ready] Bare bracket form without a bullet — it cites app/z.py and has a body {cat: web; size: S; multifile: no; research: none}
EOT
  python3 "$v" --normalize "$d/bad.txt" > "$d/bad.out" 2> "$d/bad.err"
  chk "prose / no-priority / P7 / P0 / no-status lines are rejected, only the 2 valid lines come out [$(grep -c '' "$d/bad.out")]" '[ "$(grep -c "" "$d/bad.out")" = 2 ] && grep -aq "Good canonical one" "$d/bad.out" && grep -aq "Bare bracket form" "$d/bad.out"'
  chk "each rejected bullet is reported on stderr (4 rejects)" '[ "$(grep -c "^normalize: reject" "$d/bad.err")" = 4 ]'
  OVN_AR_NORMALIZE=off python3 "$v" --normalize "$XL" > "$d/off.out" 2>/dev/null
  chk "OVN_AR_NORMALIZE=off keeps the old canonical-only behaviour (0 lines from the xlite reply)" '[ ! -s "$d/off.out" ]'
  rm -rf "${d:?}"
}
ck_normalize_e2e(){   # whole script: the xlite reply no longer fails the pass
  setup "$1" "$2"
  ar_starving xlite:6; modes "reply:$XL"
  ar_run DRY_RUN=1
  chk "xlite pass with the real bold reply is ACCEPTED 4/4, not a failed pass" 'grep -aq "xlite: accepted 4/4" "$T/out.txt" && ! grep -aq "treating as a FAILED pass" "$T/out.txt"'
  chk "the normalisation is logged" 'grep -aq "xlite: normalize: recovered 4 line(s)" "$T/out.txt"'
  chk "the 4 items would be appended (dry-run file) as [ready]" '[ "$(grep -c "^- \[ \] \[P[1-4]\] \[ready\] " "$STATE/dryrun_xlite.md")" = 4 ]'
  chk "a recovered pass leaves no failed-pass marker" '[ ! -e "$STATE/failed_xlite" ]'
  ar_cleanup; T=""
}

# ---- 3. salvage
ck_salvage(){
  setup "$1" "$2"
  echo 99 > "$STATE/count_$(date +%F)"
  ar_run OVN_AR_SALVAGE_REPO=xlite OVN_AR_SALVAGE_FILE="$XL"
  chk "salvage (real, not dry-run) tries to append the accepted items to the box roadmap" 'grep -aq "append.txt" "$BOX/ssh.log"'
  chk "salvage works even though the daily cap (99) is reached" 'grep -aq "SALVAGE xlite: re-validating" "$T/out.txt" && grep -aq "xlite: accepted 4/4" "$T/out.txt"'
  chk "salvage never calls claude" '[ "$(nclaude)" = 0 ] && [ "$(ntimeout)" = 0 ]'
  chk "salvage leaves the daily count and the cooldown markers alone" '[ "$(cat "$STATE/count_$(date +%F)")" = 99 ] && [ ! -e "$STATE/researched_xlite" ] && [ ! -e "$STATE/researched_n_xlite" ]'
  ar_run DRY_RUN=1 OVN_AR_SALVAGE_REPO=xlite OVN_AR_SALVAGE_FILE="$T/nonexistent.txt"
  chk "a missing salvage file is a clear error (exit 1), not a silent run" '[ "$AR_RC" = 1 ] && grep -aq "no reply file" "$T/out.txt"'
  ar_cleanup; T=""
}

# ---- 4. timeout retry + per-pass cost cap
ck_retry(){
  setup "$1" "$2"
  ar_starving xlite:6; tmodes timeout run; modes "reply:$XL"
  ar_run DRY_RUN=1
  chk "attempt 1 gets 1800s, the retry 900s [$(tr '\n' ' ' < "$CAP/timeouts.log" 2>/dev/null)]" '[ "$(tr "\n" " " < "$CAP/timeouts.log")" = "1800 900 " ]'
  chk "a timeout is retried ONCE and the retry is logged" 'grep -aq "xlite: attempt 1 timed out after 1800s (rc=124, no output) - retrying ONCE" "$T/out.txt"'
  chk "the retried pass is accepted 4/4" 'grep -aq "xlite: accepted 4/4" "$T/out.txt"'
  chk "attempt 1 prompt carries the TIME BOX and no RETRY SCOPE" 'grep -aq "TIME BOX" "$CAP/targs_1.txt" && ! grep -aq "RETRY SCOPE" "$CAP/targs_1.txt"'
  chk "retry prompt has RETRY SCOPE (<=4 items) and drops the web tools" 'grep -aq "RETRY SCOPE" "$CAP/targs_2.txt" && grep -aq "AT MOST 4 items" "$CAP/targs_2.txt" && ! grep -aq "WebSearch" "$CAP/targs_2.txt"'
  chk "attempt 1 keeps the web tools" 'grep -aq "^Read Grep Glob WebSearch WebFetch$" "$CAP/targs_1.txt"'
  chk "per-pass cost cap enforced on attempt 1 (--max-budget-usd 4)" '[ "$(awk "/^--max-budget-usd\$/{getline; print}" "$CAP/targs_1.txt")" = 4 ]'
  chk "per-pass cost cap enforced on the retry (--max-budget-usd 2)" '[ "$(awk "/^--max-budget-usd\$/{getline; print}" "$CAP/targs_2.txt")" = 2 ]'
  ar_cleanup; T=""
  setup "$1" "$2"
  ar_starving xlite:6; tmodes timeout run
  ar_run OVN_AR_RETRY=off
  chk "OVN_AR_RETRY=off: one attempt only, then a failed pass" '[ "$(ntimeout)" = 1 ] && [ -f "$STATE/failed_xlite" ]'
  ar_cleanup; T=""
  setup "$1" "$2"
  ar_starving xlite:6; tmodes run; modes fail
  ar_run
  chk "a non-timeout failure (rc=3) is NOT retried, but starts the failed-pass cooldown" '[ "$(ntimeout)" = 1 ] && [ -f "$STATE/failed_xlite" ] && grep -aq "claude exited rc=3" "$T/out.txt"'
  ar_cleanup; T=""
}

# ---- 5. failed-pass cooldown
ck_fail(){
  local t0
  setup "$1" "$2"
  ar_starving xlite:9 iptv_apps:5; tmodes timeout timeout run
  ar_run
  chk "both attempts timed out -> failed marker (1 consecutive) + daily failed counter" '[ "$(awk "{print \$2}" "$STATE/failed_xlite")" = 1 ] && [ "$(cat "$STATE/fails_$(date +%F)")" = 1 ]'
  chk "the failure is logged with its cooldown" 'grep -aq "xlite: failed-pass cooldown started (1h, 1 consecutive failure(s), 1/6 failed passes today)" "$T/out.txt"'
  chk "the failing repo does not hog the run: iptv_apps is served after it" 'grep -aq "iptv_apps: starting research pass" "$T/out.txt"'
  ar_run
  chk "next run: xlite is skipped in its failed-pass cooldown and no claude call is spent on it" 'grep -aq "xlite: in failed-pass cooldown (1h after 1 consecutive failed pass(es))" "$T/out.txt" && [ "$(ntimeout)" = 3 ]'
  t0="$(now)"
  for spec in "5400 1 attempted" "5400 2 skipped" "5400 3 skipped" "15000 5 attempted"; do
    read -r age cnt verdict <<EOS
$spec
EOS
    echo "$((t0 - age)) $cnt" > "$STATE/failed_xlite"; rm -f "$STATE/researched_xlite" "$STATE/researched_n_xlite"
    before="$(ntimeout)"; ar_run
    after="$(ntimeout)"
    if [ "$verdict" = attempted ]; then chk "failed ${cnt}x, last failure ${age}s ago: cooldown expired -> attempted" '[ "$after" -gt "$before" ]'
    else chk "failed ${cnt}x, last failure ${age}s ago: still cooling down (1h doubling per failure) -> skipped" '[ "$after" = "$before" ] && grep -aq "xlite: in failed-pass cooldown" "$T/out.txt"'; fi
  done
  ar_cleanup; T=""
  setup "$1" "$2"
  ar_starving xlite:9; tmodes run; modes boldnone
  echo "$(( $(now) - 7200 )) 2" > "$STATE/failed_xlite"
  ar_run
  chk "a parseable reply (**NONE**) is a valid empty pass, clears the failure streak and sets the normal cooldown" '[ ! -e "$STATE/failed_xlite" ] && [ "$(cat "$STATE/researched_n_xlite")" = 0 ] && ! grep -aq "FAILED pass" "$T/out.txt"'
  ar_cleanup; T=""
  setup "$1" "$2"
  ar_starving xlite:9; tmodes run; modes prose
  ar_run
  chk "a prose-only reply is a FAILED pass and starts the short cooldown (no 18h marker)" 'grep -aq "treating as a FAILED pass" "$T/out.txt" && [ -f "$STATE/failed_xlite" ] && [ ! -e "$STATE/researched_xlite" ]'
  ar_cleanup; T=""
  setup "$1" "$2"
  ar_starving xlite:9; echo 6 > "$STATE/fails_$(date +%F)"
  ar_run
  chk "daily failed-pass cap (6) stops further passes" 'grep -aq "failed-pass cap reached (6/6" "$T/out.txt" && [ "$(nclaude)" = 0 ]'
  ar_cleanup; T=""
}

# ---- 6. cap arithmetic
ck_cap(){
  setup "$1" "$2"
  ar_starving xlite:6
  ar_run DRY_RUN=1
  chk "no history: default 4.5 avg -> ceil(50/4.5)=12 passes, logged with the arithmetic" 'grep -aq "cap arithmetic: burn=100 items/day x claude_share=0.5 = 50 needed/day; avg_accepted_per_pass=4.50 (default 4.5 (only 0 pass(es) logged in 7d)) -> 12 pass(es)/day; clamp\[7 lane repos .. 16\] -> cap=12" "$T/out.txt"'
  ar_cleanup; T=""
  setup "$1" "$2"
  ar_starving xlite:6
  for i in 1 2 3 4; do ar_runlog $((i*3600)) iptv_apps "accepted 10/12"; done
  ar_run DRY_RUN=1
  chk "rich passes (avg 10) -> 5 needed, floored at the 7 lane repos" 'grep -aq "avg_accepted_per_pass=10.00 (measured over 4 pass(es) in 7d) -> 5 pass(es)/day; clamp\[7 lane repos .. 16\] -> cap=7" "$T/out.txt"'
  ar_cleanup; T=""
  setup "$1" "$2"
  ar_starving xlite:6
  for i in 1 2 3 4; do ar_runlog $((i*3600)) iptv_apps "accepted 1/9"; done
  ar_run DRY_RUN=1
  chk "thin passes (avg 1) -> 50 needed, clamped to the ceiling 16" 'grep -aq "avg_accepted_per_pass=1.00 (measured over 4 pass(es) in 7d) -> 50 pass(es)/day; clamp\[7 lane repos .. 16\] -> cap=16" "$T/out.txt"'
  ar_cleanup; T=""
  setup "$1" "$2"
  ar_starving xlite:6; echo 3 > "$STATE/count_$(date +%F)"
  ar_run DRY_RUN=1 OVN_AR_MAX_PER_DAY=3
  chk "explicit OVN_AR_MAX_PER_DAY wins, is logged as an override and still caps" 'grep -aq "cap=3 (OVN_AR_MAX_PER_DAY explicit override)" "$T/out.txt" && grep -aq "daily cap reached (3/3)" "$T/out.txt" && [ "$(nclaude)" = 0 ]'
  ar_cleanup; T=""
}

ALL="ck_default ck_parse ck_normalize_e2e ck_salvage ck_retry ck_fail ck_cap"
nfail(){ printf '%s\n' "$1" | grep -c '^0|'; }
echo "== scenarios (real script + validator) =="
for fn in $ALL; do
  res="$($fn "$SCRIPT" "$VALIDATOR")"
  while IFS='|' read -r v name; do [ -n "$name" ] && ok "$name" "$([ "$v" = 1 ] && echo 1 || echo 0)"; done <<EOT
$res
EOT
done

echo "== mutation checks (scratch copies; each mutant must break at least one check of the named scenario(s)) =="
mut_s(){   # <label> <anchor> <replacement> <scenario fn...>   mutate the SCRIPT
  local label="$1" a="$2" b="$3"; shift 3
  mutate "$SCRIPT" "$MT/s.sh" "$a" "$b" || return
  local r="" fn; for fn in "$@"; do r="$r
$($fn "$MT/s.sh" "$VALIDATOR")"; done; T=""
  ok "script mutant '$label' is caught ($(nfail "$r") check(s) fail)" "$([ "$(nfail "$r")" -ge 1 ] && echo 1 || echo 0)"
}
mut_v(){   # <label> <anchor> <replacement> <scenario fn...>   mutate the VALIDATOR
  local label="$1" a="$2" b="$3"; shift 3
  mutate "$VALIDATOR" "$MT/v.py" "$a" "$b" || return
  local r="" fn; for fn in "$@"; do r="$r
$($fn "$SCRIPT" "$MT/v.py")"; done; T=""
  ok "validator mutant '$label' is caught ($(nfail "$r")) check(s) fail)" "$([ "$(nfail "$r")" -ge 1 ] && echo 1 || echo 0)"
}
mut_s "default allowlist is the old 'iptv_apps xlite'" 'DEFAULT_REPOS="billwatch gitlark iptv_apps xlite test-automation-agent shrike-monitor shrike-notify"' 'DEFAULT_REPOS="iptv_apps xlite"' ck_default
mut_s "no fairness override" 'return (0, -h, 0) if fair > 0 and h >= fair else (1, acc.get(r[0], 0), -h)' 'return (1, acc.get(r[0], 0), -h)' ck_default
mut_s "fairness threshold ignores OVN_AR_FAIR_H=0" 'return (0, -h, 0) if fair > 0 and h >= fair' 'return (0, -h, 0) if h >= fair' ck_default
mut_s "xlite reply parsed with the old grep" 'python3 "$VALIDATE" --normalize "$in/claude_reply.txt" --default-cat "$(ar_default_cat "$repo")" > "$out" 2> "$in/normalize.err" || true' 'grep "^- \[ \]" "$in/claude_reply.txt" > "$out" 2>/dev/null || true' ck_normalize_e2e
mut_s "**NONE** is not recognised as NONE" "grep -qxE '[*\` ]*NONE[.*\` ]*'" "grep -qx 'NONE'" ck_fail
mut_s "salvage still calls claude" 'if [ -n "$SALVAGE_REPO" ]; then cp "$SALVAGE_FILE" "$in/claude_reply.txt"; rc=0' 'if false; then cp "$SALVAGE_FILE" "$in/claude_reply.txt"; rc=0' ck_salvage
mut_s "salvage counts against the daily cap" 'MAX_PER_DAY=999999; MAX_FAILS_PER_DAY=999999' ':' ck_salvage
mut_s "salvage bumps the daily count" 'if [ -z "${DRY_RUN:-}" ] && [ -z "$SALVAGE_REPO" ]; then used=$((used+1))' 'if [ -z "${DRY_RUN:-}" ]; then used=$((used+1))' ck_salvage
mut_s "retry disabled by default" 'RETRY="${OVN_AR_RETRY:-on}"' 'RETRY="${OVN_AR_RETRY:-off}"' ck_retry
mut_s "retry fires on any failure, not only a timeout" 'if [ "$rc" -eq 124 ] && [ "$RETRY" != "off" ]; then' 'if [ "$rc" -ne 0 ] && [ "$RETRY" != "off" ]; then' ck_retry
mut_s "retry reuses the full budget" 'run_claude "$retry_prompt" "$RETRY_TIMEOUT_S" "$RETRY_BUDGET" "Read Grep Glob"' 'run_claude "$retry_prompt" "$RETRY_TIMEOUT_S" "$BUDGET" "Read Grep Glob"' ck_retry
mut_s "retry keeps the web tools" '"$RETRY_BUDGET" "Read Grep Glob"' '"$RETRY_BUDGET" "Read Grep Glob WebSearch WebFetch"' ck_retry
mut_s "--max-budget-usd flag dropped" '--max-budget-usd "$3"' '' ck_retry
mut_s "first-attempt timeout back to 1500s" 'TIMEOUT_S="${OVN_AR_TIMEOUT_S:-1800}"' 'TIMEOUT_S="${OVN_AR_TIMEOUT_S:-1500}"' ck_retry
mut_s "TIME BOX paragraph never added" '[ "${OVN_AR_TIMEBOX:-on}" != "off" ]' '[ "${OVN_AR_TIMEBOX:-on}" = "never" ]' ck_retry
mut_s "retry prompt lost its scope limit" 'propose AT MOST 4 items' 'propose items' ck_retry
mut_s "timeout failure sets no cooldown" 'log "$repo: claude exited rc=$rc: $(tail -c 300 "$in/claude_stderr.txt" "$in/claude_reply.txt" | tr '"'"'\n'"'"' '"'"' '"'"')"; mark_fail; continue' 'log "$repo: claude exited rc=$rc"; continue' ck_fail ck_retry
mut_s "unparseable reply sets no cooldown" 'mark_fail; continue; fi
  rm -f "$fmarker"' 'continue; fi
  rm -f "$fmarker"' ck_fail
mut_s "failure streak never cleared by a success" 'rm -f "$fmarker"   # a parseable reply ends the failure streak' ':' ck_fail
mut_s "cooldown does not double" 'h=$((h*2)); i=$((i+1))' 'i=$((i+1))' ck_fail
mut_s "cooldown cap is 400h" 'FAIL_MAX_H="${OVN_AR_FAIL_COOLDOWN_MAX_H:-4}"' 'FAIL_MAX_H="${OVN_AR_FAIL_COOLDOWN_MAX_H:-400}"' ck_fail
mut_s "failed cooldown never checked" 'if [ -z "$FORCE" ] && [ -f "$fmarker" ]; then' 'if false; then' ck_fail
mut_s "failed-pass daily cap ignored" 'if [ "$fails_today" -ge "$MAX_FAILS_PER_DAY" ]; then' 'if false; then' ck_fail
mut_s "cap arithmetic not logged" 'log "${CAP_LINE#*$'"'"'\t'"'"'}"' ':' ck_cap
mut_s "explicit cap ignored" 'if [ -n "${OVN_AR_MAX_PER_DAY:-}" ]; then MAX_PER_DAY="$OVN_AR_MAX_PER_DAY"; CAP_EXPLICIT=1' 'if false; then MAX_PER_DAY="$OVN_AR_MAX_PER_DAY"; CAP_EXPLICIT=1' ck_cap
mut_v "cap rounds down instead of up" 'want = int(math.ceil(burn * share / avg))' 'want = int(burn * share / avg)' ck_cap
mut_v "cap not floored at the lane count" 'cap = max(nrepos, min(want, ceil_))' 'cap = min(want, ceil_)' ck_cap
mut_v "cap has no ceiling" 'cap = max(nrepos, min(want, ceil_))' 'cap = max(nrepos, want)' ck_cap
mut_v "explicit override lost in the arithmetic" '    if explicit:
        cap = cap_now' '    pass' ck_cap
mut_v "priority range not checked" 'if prio not in "1234" or len(prio) != 1 or prio == "0":' 'if False:' ck_parse
mut_v "no-status/no-checkbox bullets accepted" 'if not status and not re.match(r"^\s*-\s*\[ \]", raw.strip()) and not raw.strip().startswith("[ ]"):' 'if False:' ck_parse
mut_v "bold tags form not recognised" 'if s.startswith("**") and s.count("**") >= 2:' 'if False:' ck_parse ck_normalize_e2e
mut_v "canonical lines rewritten" '    if LINE_RE.match(s):
        return s, None' '    if False:
        return s, None' ck_parse

echo; echo "auto research resilience: $P passed, $F failed"
[ "$F" = 0 ]
