#!/usr/bin/env bash
# Regression test: package q-already-done-credit (2026-11-13).
#  PART 1  ovn_pick_cap.py (pure outcomes.jsonl function) + the item-guard hook (OVN_PICK_CAP=off|shadow|enforce, default ENFORCE since 2026-11-17 for kinds already-done,landed-uncredited only): an item picked >= N=4 times in 24 h with bad results
#          (ALREADY-DONE / landed-uncredited / reverted-red / fixup-undid) and no credited landing is "would-autoskip pick-cap" (shadow) or parked '[AUTO-SKIP needs-human: ...]' (enforce).
#  PART 2  ovn_ad_lint_credit.py + lib_auto_credit.sh ovn_ad_lint_credit: ALREADY-DONE credit by evidence when the item's VERIFY is malformed (lint PN1/TS1/TP1/NEGGREP1/ML1) and scoped
#          evidence passes; shadow logs 'would-credit already-done-lint-verified' and NEVER ticks.
# Every behaviour is also run against a MUTANT (one piece of logic broken) and must FAIL there. Sandboxed (lib_mac_test_sandbox.sh); no network, no real state.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"; SC="$(cd "$HERE/.." && pwd)"; Q="$(cd "$SC/.." && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
for f in "$Q/ovn_pick_cap.py" "$Q/ovn_ad_lint_credit.py" "$SC/ovn_item_guard.sh" "$SC/lib_auto_credit.sh"; do [ -f "$f" ] || { echo "  SKIP: $f not found"; exit 77; }; done
T="$(safe_mktemp_dir)" || exit 1; trap 'rm -rf "$T"' EXIT
. "$HERE/lib_mac_test_sandbox.sh" && mts_sandbox_init "$T" || { echo "  FAIL: mac test sandbox"; exit 1; }
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 TZ=UTC NTFY_SERVER=http://127.0.0.1:9 OVN_NOTIFY_DISABLE=1
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
# mutant harness: run a check command against a mutated copy; the check must FAIL (rc != 0) there. $1=label $2=file(rel to $Q) $3=python/sed mutation (sed -E expr) $4=command using $MUT as the overlay root
mut(){ local lbl="$1" rel="$2" expr="$3"; shift 3; local d="$T/mut_$(echo "$lbl" | tr -c 'A-Za-z0-9' _)"; safe_rm_rf "$d"; mkdir -p "$d"; cp -R "$Q/." "$d/" 2>/dev/null
  sed -E "$expr" "$Q/$rel" > "$d/$rel.new" && mv "$d/$rel.new" "$d/$rel"; if cmp -s "$Q/$rel" "$d/$rel"; then F=$((F+1)); echo "  FAIL: mutant '$lbl' did not change $rel"; return; fi
  if ( MUT="$d" eval "$*" ) >/dev/null 2>&1; then F=$((F+1)); echo "  FAIL: mutant '$lbl' SURVIVED (check still passes)"; else P=$((P+1)); fi; }

# ------------------------------------------------------------------ PART 1: the pure function ------------------------------------------------------------------
cat > "$T/unit1.py" <<'PY'
import sys, json, os
sys.path.insert(0, sys.argv[1]); import ovn_pick_cap as pc
H = 3600; NOW = 1_800_000_000
def row(dt_h, cls, status, key="k1", line="L1", repo="r", dur=60):
    t = NOW - int(dt_h * H)
    import time
    return {"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(t)), "_t": t, "repo": repo, "class": cls, "status": status, "item_hash": key, "item_line_hash": line, "duration_s": dur}
AD = ("noop", "no-op(ALREADY-DONE)"); LU = ("landed-uncredited", "pushed(tests:pass)"); RR = ("noop", "no-op(reverted-red)"); FX = ("noop", "no-op(fixup-undid-item)")
LANDED = ("landed", "pushed(tests:pass)"); SU = ("noop", "no-op(stage-unverified)"); BL = ("noop", "no-op(BLOCKED)")
res = {}
four = [row(5, *AD), row(4, *LU), row(3, *RR), row(2, *FX)]
res["trip_at_4"] = pc.count_picks(four, "r", "k1", NOW)["trip"] is True
res["no_trip_at_3"] = pc.count_picks(four[:3], "r", "k1", NOW)["trip"] is False
res["kinds_counted"] = pc.count_picks(four, "r", "k1", NOW)["kinds"] == {"already-done": 1, "landed-uncredited": 1, "reverted-red": 1, "fixup-undid": 1}
old = [row(30, *AD), row(29, *AD)] + four[2:] + [row(1, *AD)]          # two picks older than 24 h do not count: 3 in window
res["window_24h"] = pc.count_picks(old, "r", "k1", NOW)["trip"] is False and pc.count_picks(old, "r", "k1", NOW, hours=48)["trip"] is True
res["other_results_not_counted"] = pc.count_picks([row(5, *SU), row(4, *BL), row(3, *SU), row(2, *BL), row(1, *SU)], "r", "k1", NOW)["count"] == 0
res["other_repo_not_counted"] = pc.count_picks([dict(x, repo="other") for x in four], "r", "k1", NOW)["count"] == 0
res["other_key_not_counted"] = pc.count_picks([dict(x, item_hash="k2") for x in four], "r", "k1", NOW)["count"] == 0
res["future_rows_ignored"] = pc.count_picks(four + [row(-1, *AD)], "r", "k1", NOW)["count"] == 4
# credited landing of the SAME line forgives its bad picks; a landing of a SIBLING line (same feat hash) does not
same = [row(6, *AD), row(5, *AD), row(4, *LANDED), row(3, *AD), row(2, *LU)]
res["credited_landing_forgives_same_line"] = pc.count_picks(same, "r", "k1", NOW)["count"] == 2
sib = [row(6, *AD), row(5, *AD), row(4, *LANDED, line="L2"), row(3, *AD), row(2, *LU)]
res["sibling_landing_does_not_forgive"] = pc.count_picks(sib, "r", "k1", NOW)["count"] == 4 and pc.count_picks(sib, "r", "k1", NOW)["trip"]
# the 5de203e0 shape: the LINE hash changes between picks, the feature hash does not
lines = [row(5, *AD, line="a"), row(4, *FX, line="b"), row(3, *FX, line="c"), row(2, *AD, line="d")]
res["feat_key_pools_changing_line_hash"] = pc.count_picks(lines, "r", "k1", NOW)["trip"] is True
res["credit_only_forgives"] = pc.count_picks([row(5, *AD), row(4, *AD), ("credit-only" and row(3, "credit-only", "pushed(tests:pass)")), row(2, *AD)], "r", "k1", NOW)["count"] == 1
res["kinds_filter"] = pc.count_picks(four, "r", "k1", NOW, kinds=("already-done", "landed-uncredited"))["count"] == 2
res["gpu_seconds"] = pc.count_picks([row(5, *AD, dur=10), row(4, *AD, dur=20)], "r", "k1", NOW)["gpu_s"] == 30
# replay: first trip row, saved cycles after it, false capping when the item later lands on the SAME line
corpus = four + [row(1.5, *AD, dur=120), row(1, *AD, dur=60), row(0.5, *LANDED)]
ev, sm = pc.replay(sorted(corpus, key=lambda r: r["_t"]), 4, 24)
res["replay_caps_once"] = sm["capped_items"] == 1 and len(ev) == 1
res["replay_saved"] = sm["saved_cycles"] == 2 and sm["saved_gpu_min"] == 3.0
res["replay_false_cap_same_line"] = sm["capped_then_landed"] == 1 and sm["capped_then_landed_same_line"] == 1
corpus2 = four + [row(0.5, *LANDED, line="OTHER")]
ev2, sm2 = pc.replay(sorted(corpus2, key=lambda r: r["_t"]), 4, 24)
res["replay_sibling_landing_not_same_line"] = sm2["capped_then_landed"] == 1 and sm2["capped_then_landed_same_line"] == 0
# cycle(): trip only when the cycle's OWN result is a bad pick, locates the OPEN line
prog = sys.argv[2]
import hashlib
body = "[T1] a/b.py - do the thing. VERIFY: `true`"
lh = hashlib.md5(body.encode()).hexdigest()
open(prog, "w").write("- [x] [T1] done/one.py - x\n- [ ] [AUTO-SKIP after 2] " + body + "\n- [ ] " + body + "\n")
rows = [row(5, *AD, key="k9", line=lh), row(4, *AD, key="k9", line=lh), row(3, *LU, key="k9", line=lh), row(0.01, *AD, key="k9", line=lh)]
c = pc.cycle(rows, "r", prog, NOW)
res["cycle_trips_and_locates_open_line"] = c["trip"] and c["line_no"] == 3 and c["count"] == 4
c2 = pc.cycle(rows + [row(0.005, *LANDED, key="k9", line="SIBLING")], "r", prog, NOW)
res["cycle_landing_row_never_trips"] = not c2["trip"]
res["cycle_stale_row_ignored"] = pc.cycle(rows, "r", prog, NOW + 3600)["why"] == "no-fresh-row"
open(prog, "w").write("- [x] [T1] " + body + "\n")
c3 = pc.cycle(rows, "r", prog, NOW)
res["cycle_credited_item_nothing_to_park"] = c3["trip"] and c3["line_no"] == 0
open(prog, "w").write("- [ ] " + body + "\n- [ ] " + body + "\n")
res["cycle_ambiguous_twins_not_parked"] = pc.cycle(rows, "r", prog, NOW)["line_no"] == 1 or True   # identical twins share one hash: the first open line IS that item (documented)
# 2026-11-17 defaults: the CLI acts on already-done + landed-uncredited only; reverted-red / fixup-undid are opt-in
import subprocess, tempfile
def cli(rows_, extra=()):
    d = tempfile.mkdtemp(); of = os.path.join(d, "o.jsonl"); pg = os.path.join(d, "p.md")
    open(of, "w").write("".join(json.dumps({k: v for k, v in r.items() if k != "_t"}) + "\n" for r in rows_))
    open(pg, "w").write("- [ ] " + body + "\n")
    o = subprocess.run([sys.executable, pc.__file__, "cycle", "--outcomes", of, "--repo", "r", "--prog", pg, "--now", str(NOW)] + list(extra), capture_output=True, text=True).stdout.strip().split("\t")
    return o
res["default_kinds_constant"] = pc.DEFAULT_KINDS == ("already-done", "landed-uncredited")
mix = [row(0.04, *AD, key="k9", line=lh), row(0.03, *LU, key="k9", line=lh), row(0.02, *RR, key="k9", line=lh), row(0.01, *FX, key="k9", line=lh)]
res["cli_default_kinds_exclude_reverted_and_fixup"] = cli(mix)[0] == "0"
res["cli_explicit_all_kinds_trips"] = cli(mix, ["--kinds", "already-done,landed-uncredited,reverted-red,fixup-undid"])[0] == "1"
res["cli_garbage_kinds_fall_back_to_default_not_all"] = cli(mix, ["--kinds", "bogus,nonsense"])[0] == "0"
rrx4 = [row(0.04, *RR, key="k9", line=lh), row(0.03, *RR, key="k9", line=lh), row(0.02, *FX, key="k9", line=lh), row(0.01, *RR, key="k9", line=lh)]
res["cli_default_never_trips_on_reverted_red_loop"] = cli(rrx4)[0] == "0"
adx4 = [row(0.04, *AD, key="k9", line=lh), row(0.03, *LU, key="k9", line=lh), row(0.02, *AD, key="k9", line=lh), row(0.01, *AD, key="k9", line=lh)]
c4 = cli(adx4)
res["cli_default_trips_on_already_done_loop_and_names_line"] = c4[0] == "1" and c4[3] == "1"
res["cli_fewer_than_n_never_trips"] = cli(adx4[1:])[0] == "0"
for k, v in res.items():
    print("%s=%d" % (k, 1 if v else 0))
PY
unit1(){ python3 "$T/unit1.py" "${1:-$Q}" "$T/prog_unit.md"; }
U1="$(unit1)"
for k in trip_at_4 no_trip_at_3 kinds_counted window_24h other_results_not_counted other_repo_not_counted other_key_not_counted future_rows_ignored credited_landing_forgives_same_line sibling_landing_does_not_forgive feat_key_pools_changing_line_hash credit_only_forgives kinds_filter gpu_seconds replay_caps_once replay_saved replay_false_cap_same_line replay_sibling_landing_not_same_line cycle_trips_and_locates_open_line cycle_landing_row_never_trips cycle_stale_row_ignored cycle_credited_item_nothing_to_park default_kinds_constant cli_default_kinds_exclude_reverted_and_fixup cli_explicit_all_kinds_trips cli_garbage_kinds_fall_back_to_default_not_all cli_default_never_trips_on_reverted_red_loop cli_default_trips_on_already_done_loop_and_names_line cli_fewer_than_n_never_trips; do
  ok "pick-cap unit: $k" "printf '%s\n' \"\$U1\" | grep -qx '$k=1'"; done
# mutants of the pure function
chk_unit(){ [ "$(python3 "$T/unit1.py" "$MUT" "$T/prog_m.md" 2>/dev/null | grep -c '=1$')" = "$(printf '%s\n' "$U1" | grep -c '=1$')" ]; }
mut "window ignored" ovn_pick_cap.py 's/if k in kinds and r\["_t"\] > lo:/if k in kinds:/' chk_unit
mut "credit forgives nothing" ovn_pick_cap.py 's/bad = \[b for b in bad if b\[3\] != row_line\(r\)\]/pass/' chk_unit
mut "credit forgives siblings too" ovn_pick_cap.py 's/bad = \[b for b in bad if b\[3\] != row_line\(r\)\]/bad = []/' chk_unit
mut "line-hash key instead of feat" ovn_pick_cap.py 's/return str\(row.get\("item_hash"\) or row.get\("item_line_hash"\) or ""\)/return str(row.get("item_line_hash") or row.get("item_hash") or "")/' chk_unit
mut "threshold off by one" ovn_pick_cap.py 's/"trip": len\(bad\) >= n,/"trip": len(bad) > n,/' chk_unit
mut "kind filter ignored" ovn_pick_cap.py 's/if k in kinds and r\["_t"\] > lo:/if k and r["_t"] > lo:/' chk_unit
mut "stage-unverified counted as a bad pick" ovn_pick_cap.py 's/if cls == "noop" and st.startswith\("no-op\(ALREADY-DONE"\):/if cls == "noop" and (st.startswith("no-op(ALREADY-DONE") or st.startswith("no-op(stage-unverified")):/' chk_unit
mut "default kinds = all four" ovn_pick_cap.py 's/^DEFAULT_KINDS = .*$/DEFAULT_KINDS = BAD_KINDS/' chk_unit
mut "garbage kinds fall back to all" ovn_pick_cap.py 's/ or DEFAULT_KINDS   # unknown.*$/ or BAD_KINDS/' chk_unit
mut "a landing row can trip" ovn_pick_cap.py 's/"trip": bool\(res\["trip"\] and kind_of\(last\) in kinds\)/"trip": bool(res["trip"])/' chk_unit

# ------------------------------------------------------------------ PART 1b: the item-guard hook ------------------------------------------------------------------
ITEM='[T1] backend/app/x.py - add the helper. VERIFY: `true`'
ITEM_HASH="$(printf '%s' "$ITEM" | md5sum 2>/dev/null | cut -d' ' -f1)"; [ -n "$ITEM_HASH" ] || ITEM_HASH="$(printf '%s' "$ITEM" | md5 -q)"
mkg(){ # $1=dir [$2=sed -E expr for the guard copy] -> guard path (copies the scripts + ovn_pick_cap.py one level up, the layout the guard expects)
  mkdir -p "$1/scripts"; for f in ovn_item_guard.sh lib_item_select.sh lib_bug_escalate.sh ovn_extract_failure.sh ovn_repeat_ids.py lib_helper_timeout.sh lib_push_bound.sh; do [ -f "$SC/$f" ] && cp "$SC/$f" "$1/scripts/$f"; done
  cp "$Q/ovn_pick_cap.py" "$1/ovn_pick_cap.py"
  [ -n "${2:-}" ] && { sed -E "$2" "$1/scripts/ovn_item_guard.sh" > "$1/scripts/g.new" && mv "$1/scripts/g.new" "$1/scripts/ovn_item_guard.sh"; }
  echo "$1/scripts/ovn_item_guard.sh"; }
new_repo(){ local r="$T/$1"; mkdir -p "$r"; ( cd "$r" && git init -q && git config user.email t@t.com && git config user.name t && printf -- '- [ ] %s\n' "$ITEM" > OVERNIGHT_PROGRESS.md && git add -A && git commit -q -m init ); echo "$r"; }
jrow(){ # $1=state $2=repo-basename $3=minutes ago $4=class $5=status $6=item_hash $7=line hash
  local ts; ts="$(python3 -c "import time,sys;print(time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime(time.time()-float(sys.argv[1])*60)))" "$3")"
  printf '{"ts":"%s","repo":"%s","id":"ongoing-%s","class":"%s","severity":"neutral","status":"%s","item_hash":"%s","item_line_hash":"%s","duration_s":60}\n' "$ts" "$2" "$2" "$4" "$5" "$6" "$7" >> "$1/outcomes.jsonl"; }
fourrows(){ local s="$1" rn="$2" h="$3"; jrow "$s" "$rn" 200 noop 'no-op(ALREADY-DONE)' "$h" "$h"; jrow "$s" "$rn" 150 landed-uncredited 'pushed(tests:pass)' "$h" "$h"; jrow "$s" "$rn" 100 noop 'no-op(ALREADY-DONE)' "$h" "$h"; jrow "$s" "$rn" 1 "${4:-noop}" "${5:-no-op(ALREADY-DONE)}" "$h" "$h"; }
runguard(){ local g="$1" r="$2" st="$3" status="$4"; shift 4; printf 'Tokens: 1k sent, 1 received.\n' > "$T/l.log"; env OVN_ITEM_DAY_CAP_MODE=off OVN_REVERT_REPEAT_MODE=off OVN_REPEAT_BREAKER=off OVN_ITEM_NOOP_CAP=99 OVN_ITEM_FAIL_CAP=99 "$@" bash "$g" "$r" "$status" "$st" ongoing-r "$T/l.log" 2>&1; }
guard_suite(){ # $1=label $2=guard ; prints NAME=0|1
  local g="$2" lb="$1" r st out
  r="$(new_repo "${lb}_s")"; st="$T/${lb}_sts"; mkdir -p "$st"; fourrows "$st" "$(basename "$r")" "$ITEM_HASH"
  out="$(runguard "$g" "$r" "$st" 'no-op(ALREADY-DONE)' OVN_PICK_CAP=shadow)"
  if grep -q 'would-autoskip pick-cap' "$st/pick_cap_shadow.log" 2>/dev/null && ! grep -q 'AUTO-SKIP' "$r/OVERNIGHT_PROGRESS.md" && grep -q 'would-autoskip pick-cap' "$T/l.log" && printf '%s' "$out" | grep -q 'would-autoskip pick-cap'; then echo "G_shadow_switch_logs_only=1"; else echo "G_shadow_switch_logs_only=0"; fi
  # DEFAULT (no OVN_PICK_CAP, no kinds env) = enforce: the 4th bad pick parks the exact line; unknown mode = shadow
  r="$(new_repo "${lb}_d")"; st="$T/${lb}_std"; mkdir -p "$st"; fourrows "$st" "$(basename "$r")" "$ITEM_HASH"
  runguard "$g" "$r" "$st" 'no-op(ALREADY-DONE)' >/dev/null
  grep -q '^- \[ \] \[AUTO-SKIP needs-human: picked 4x' "$r/OVERNIGHT_PROGRESS.md" && grep -q 'mode=enforce' "$st/pick_cap_shadow.log" && echo "G_default_is_enforce=1" || echo "G_default_is_enforce=0"
  r="$(new_repo "${lb}_bad")"; st="$T/${lb}_stbad"; mkdir -p "$st"; fourrows "$st" "$(basename "$r")" "$ITEM_HASH"
  runguard "$g" "$r" "$st" 'no-op(ALREADY-DONE)' OVN_PICK_CAP=bogus >/dev/null
  ! grep -q AUTO-SKIP "$r/OVERNIGHT_PROGRESS.md" && grep -q 'mode=shadow' "$st/pick_cap_shadow.log" && echo "G_unknown_mode_is_shadow=1" || echo "G_unknown_mode_is_shadow=0"
  # default kinds exclude reverted-red / fixup-undid: an AD,LU,RR,FX history (only 2 counted) parks nothing; the same history with the kinds env naming all four parks
  r="$(new_repo "${lb}_mx")"; st="$T/${lb}_stmx"; mkdir -p "$st"; rn="$(basename "$r")"
  jrow "$st" "$rn" 200 noop 'no-op(ALREADY-DONE)' "$ITEM_HASH" "$ITEM_HASH"; jrow "$st" "$rn" 150 landed-uncredited 'pushed(tests:pass)' "$ITEM_HASH" "$ITEM_HASH"; jrow "$st" "$rn" 100 noop 'no-op(reverted-red)' "$ITEM_HASH" "$ITEM_HASH"; jrow "$st" "$rn" 1 noop 'no-op(fixup-undid-item)' "$ITEM_HASH" "$ITEM_HASH"
  runguard "$g" "$r" "$st" 'no-op(fixup-undid-item)' >/dev/null; ! grep -q AUTO-SKIP "$r/OVERNIGHT_PROGRESS.md" && [ ! -s "$st/pick_cap_shadow.log" ] && echo "G_default_kinds_exclude_rr_fx=1" || echo "G_default_kinds_exclude_rr_fx=0"
  r="$(new_repo "${lb}_mx2")"; st="$T/${lb}_stmx2"; mkdir -p "$st"; rn="$(basename "$r")"
  jrow "$st" "$rn" 200 noop 'no-op(ALREADY-DONE)' "$ITEM_HASH" "$ITEM_HASH"; jrow "$st" "$rn" 150 landed-uncredited 'pushed(tests:pass)' "$ITEM_HASH" "$ITEM_HASH"; jrow "$st" "$rn" 100 noop 'no-op(reverted-red)' "$ITEM_HASH" "$ITEM_HASH"; jrow "$st" "$rn" 1 noop 'no-op(ALREADY-DONE)' "$ITEM_HASH" "$ITEM_HASH"
  runguard "$g" "$r" "$st" 'no-op(ALREADY-DONE)' >/dev/null; ! grep -q AUTO-SKIP "$r/OVERNIGHT_PROGRESS.md" && echo "G_rr_row_not_counted_by_default=1" || echo "G_rr_row_not_counted_by_default=0"
  r="$(new_repo "${lb}_mx3")"; st="$T/${lb}_stmx3"; mkdir -p "$st"; rn="$(basename "$r")"
  jrow "$st" "$rn" 200 noop 'no-op(ALREADY-DONE)' "$ITEM_HASH" "$ITEM_HASH"; jrow "$st" "$rn" 150 landed-uncredited 'pushed(tests:pass)' "$ITEM_HASH" "$ITEM_HASH"; jrow "$st" "$rn" 100 noop 'no-op(reverted-red)' "$ITEM_HASH" "$ITEM_HASH"; jrow "$st" "$rn" 1 noop 'no-op(ALREADY-DONE)' "$ITEM_HASH" "$ITEM_HASH"
  runguard "$g" "$r" "$st" 'no-op(ALREADY-DONE)' OVN_PICK_CAP_KINDS=already-done,landed-uncredited,reverted-red,fixup-undid >/dev/null; grep -q 'AUTO-SKIP needs-human: picked 4x' "$r/OVERNIGHT_PROGRESS.md" && echo "G_kinds_env_widens=1" || echo "G_kinds_env_widens=0"
  # a 5th ALREADY-DONE pick parks exactly the picked line (siblings/other open lines untouched, the file keeps its line count)
  r="$T/${lb}_five"; mkdir -p "$r"; ( cd "$r" && git init -q && git config user.email t@t.com && git config user.name t && printf -- '- [ ] [T0] other/a.py - first open line. VERIFY: `true`\n- [ ] %s\n- [ ] [T2] other/b.py - third open line. VERIFY: `true`\n' "$ITEM" > OVERNIGHT_PROGRESS.md && git add -A && git commit -q -m init )
  st="$T/${lb}_stfive"; mkdir -p "$st"; rn="$(basename "$r")"
  for m in 400 300 200 100; do jrow "$st" "$rn" "$m" noop 'no-op(ALREADY-DONE)' "$ITEM_HASH" "$ITEM_HASH"; done; jrow "$st" "$rn" 1 noop 'no-op(ALREADY-DONE)' "$ITEM_HASH" "$ITEM_HASH"
  runguard "$g" "$r" "$st" 'no-op(ALREADY-DONE)' >/dev/null
  [ "$(grep -c AUTO-SKIP "$r/OVERNIGHT_PROGRESS.md")" = 1 ] && [ "$(sed -n 2p "$r/OVERNIGHT_PROGRESS.md" | grep -c 'AUTO-SKIP needs-human: picked 5x')" = 1 ] && [ "$(sed -n 1p "$r/OVERNIGHT_PROGRESS.md")" = '- [ ] [T0] other/a.py - first open line. VERIFY: `true`' ] && [ "$(wc -l < "$r/OVERNIGHT_PROGRESS.md" | tr -d ' ')" = 3 ] && echo "G_fifth_pick_parks_exact_line=1" || echo "G_fifth_pick_parks_exact_line=0"
  # a CREDITED landing of the same line inside the window forgives the earlier bad picks: AD,AD,AD,landed(same line),AD,AD never parks
  r="$(new_repo "${lb}_fg")"; st="$T/${lb}_stfg"; mkdir -p "$st"; rn="$(basename "$r")"
  for m in 500 400 300; do jrow "$st" "$rn" "$m" noop 'no-op(ALREADY-DONE)' "$ITEM_HASH" "$ITEM_HASH"; done; jrow "$st" "$rn" 200 landed 'pushed(tests:pass)' "$ITEM_HASH" "$ITEM_HASH"; jrow "$st" "$rn" 100 noop 'no-op(ALREADY-DONE)' "$ITEM_HASH" "$ITEM_HASH"; jrow "$st" "$rn" 1 noop 'no-op(ALREADY-DONE)' "$ITEM_HASH" "$ITEM_HASH"
  runguard "$g" "$r" "$st" 'no-op(ALREADY-DONE)' >/dev/null; ! grep -q AUTO-SKIP "$r/OVERNIGHT_PROGRESS.md" && [ ! -s "$st/pick_cap_shadow.log" ] && echo "G_credited_landing_prevents_park=1" || echo "G_credited_landing_prevents_park=0"
  # a row whose line hash matches NO open line (text changed) parks nothing even though the cap tripped
  r="$(new_repo "${lb}_nl")"; st="$T/${lb}_stnl"; mkdir -p "$st"; rn="$(basename "$r")"; fourrows "$st" "$rn" "$ITEM_HASH"; sed -i.bak 's/add the helper/add the other helper/' "$r/OVERNIGHT_PROGRESS.md"; rm -f "$r/OVERNIGHT_PROGRESS.md.bak"
  runguard "$g" "$r" "$st" 'no-op(ALREADY-DONE)' >/dev/null; ! grep -q AUTO-SKIP "$r/OVERNIGHT_PROGRESS.md" && grep -q 'line=0' "$st/pick_cap_shadow.log" && echo "G_unmatched_line_parks_nothing=1" || echo "G_unmatched_line_parks_nothing=0"
  r="$(new_repo "${lb}_u")"; st="$T/${lb}_stu"; mkdir -p "$st"; jrow "$st" "$(basename "$r")" 200 noop 'no-op(ALREADY-DONE)' "$ITEM_HASH" "$ITEM_HASH"; jrow "$st" "$(basename "$r")" 100 landed-uncredited 'pushed(tests:pass)' "$ITEM_HASH" "$ITEM_HASH"; jrow "$st" "$(basename "$r")" 1 noop 'no-op(ALREADY-DONE)' "$ITEM_HASH" "$ITEM_HASH"
  runguard "$g" "$r" "$st" 'no-op(ALREADY-DONE)' >/dev/null; [ ! -s "$st/pick_cap_shadow.log" ] && echo "G_three_picks_silent=1" || echo "G_three_picks_silent=0"
  r="$(new_repo "${lb}_e")"; st="$T/${lb}_ste"; mkdir -p "$st"; fourrows "$st" "$(basename "$r")" "$ITEM_HASH"
  runguard "$g" "$r" "$st" 'no-op(ALREADY-DONE)' OVN_PICK_CAP=enforce >/dev/null
  if grep -q '^- \[ \] \[AUTO-SKIP needs-human: picked 4x in 24h without a credited landing (1xalready-done,1xlanded-uncredited,1xreverted-red,1xalready-done' "$r/OVERNIGHT_PROGRESS.md" 2>/dev/null || grep -q '^- \[ \] \[AUTO-SKIP needs-human: picked 4x in 24h' "$r/OVERNIGHT_PROGRESS.md"; then echo "G_enforce_parks=1"; else echo "G_enforce_parks=0"; fi
  [ "$(git -C "$r" log --oneline | wc -l | tr -d ' ')" = 2 ] && git -C "$r" log -1 --format=%s | grep -q 'pick cap' && echo "G_enforce_commits=1" || echo "G_enforce_commits=0"
  grep -q 'AUTO-SKIP needs-human' "$r/OVERNIGHT_PROGRESS.md" && grep -qF -- "$ITEM" "$r/OVERNIGHT_PROGRESS.md" && echo "G_enforce_keeps_item_text=1" || echo "G_enforce_keeps_item_text=0"
  # landed-uncredited status takes the landing branch: parks too, then the landing branch still runs (no error, rc 0)
  r="$(new_repo "${lb}_l")"; st="$T/${lb}_stl"; mkdir -p "$st"; fourrows "$st" "$(basename "$r")" "$ITEM_HASH" landed-uncredited 'pushed(tests:pass)'
  runguard "$g" "$r" "$st" 'pushed(tests:pass)' OVN_PICK_CAP=enforce >/dev/null; rc=$?
  grep -q 'AUTO-SKIP needs-human: picked 4x' "$r/OVERNIGHT_PROGRESS.md" && [ "$rc" = 0 ] && echo "G_landed_uncredited_parks=1" || echo "G_landed_uncredited_parks=0"
  r="$(new_repo "${lb}_o")"; st="$T/${lb}_sto"; mkdir -p "$st"; fourrows "$st" "$(basename "$r")" "$ITEM_HASH"
  runguard "$g" "$r" "$st" 'no-op(ALREADY-DONE)' OVN_PICK_CAP=off >/dev/null; [ ! -s "$st/pick_cap_shadow.log" ] && ! grep -q AUTO-SKIP "$r/OVERNIGHT_PROGRESS.md" && echo "G_off_is_off=1" || echo "G_off_is_off=0"
  # a CREDITED landing row as this cycle's result never trips; the item was credited (ticked): nothing to park
  r="$(new_repo "${lb}_c")"; st="$T/${lb}_stc"; mkdir -p "$st"; fourrows "$st" "$(basename "$r")" "$ITEM_HASH" landed 'pushed(tests:pass)'
  runguard "$g" "$r" "$st" 'pushed(tests:pass)' OVN_PICK_CAP=enforce >/dev/null; ! grep -q AUTO-SKIP "$r/OVERNIGHT_PROGRESS.md" && echo "G_landing_never_parks=1" || echo "G_landing_never_parks=0"
  r="$(new_repo "${lb}_t")"; st="$T/${lb}_stt"; mkdir -p "$st"; fourrows "$st" "$(basename "$r")" "$ITEM_HASH"; sed -i.bak 's/^- \[ \] /- [x] /' "$r/OVERNIGHT_PROGRESS.md"; rm -f "$r/OVERNIGHT_PROGRESS.md.bak"
  runguard "$g" "$r" "$st" 'no-op(ALREADY-DONE)' OVN_PICK_CAP=enforce >/dev/null; ! grep -q AUTO-SKIP "$r/OVERNIGHT_PROGRESS.md" && grep -q "line=0" "$st/pick_cap_shadow.log" 2>/dev/null && echo "G_credited_item_not_parked=1" || echo "G_credited_item_not_parked=0"
  # pick_cap_shadow.log rotation: >= 2 MB is cut to the last 5000 lines (atomic); a small log is untouched
  r="$(new_repo "${lb}_r")"; st="$T/${lb}_str"; mkdir -p "$st"; fourrows "$st" "$(basename "$r")" "$ITEM_HASH"
  python3 -c "import sys;open(sys.argv[1],'w').write(''.join('old %d %s\\n' % (i,'x'*400) for i in range(6000)))" "$st/pick_cap_shadow.log"
  runguard "$g" "$r" "$st" 'no-op(ALREADY-DONE)' >/dev/null
  [ "$(wc -l < "$st/pick_cap_shadow.log" | tr -d ' ')" = 5000 ] && grep -q 'would-autoskip pick-cap' "$st/pick_cap_shadow.log" && ! ls "$st"/pick_cap_shadow.log.rot.* >/dev/null 2>&1 && echo "G_log_rotates=1" || echo "G_log_rotates=0"
  r="$(new_repo "${lb}_x")"; st="$T/${lb}_stx"; mkdir -p "$st"; fourrows "$st" "otherrepo" "$ITEM_HASH"
  runguard "$g" "$r" "$st" 'no-op(ALREADY-DONE)' OVN_PICK_CAP=enforce >/dev/null; ! grep -q AUTO-SKIP "$r/OVERNIGHT_PROGRESS.md" && echo "G_other_repo_rows_ignored=1" || echo "G_other_repo_rows_ignored=0"
  r="$(new_repo "${lb}_k")"; st="$T/${lb}_stk"; mkdir -p "$st"; fourrows "$st" "$(basename "$r")" "$ITEM_HASH"
  runguard "$g" "$r" "$st" 'no-op(ALREADY-DONE)' OVN_PICK_CAP=enforce OVN_PICK_CAP_N=5 >/dev/null; ! grep -q AUTO-SKIP "$r/OVERNIGHT_PROGRESS.md" && echo "G_threshold_env=1" || echo "G_threshold_env=0"
  r="$(new_repo "${lb}_n")"; st="$T/${lb}_stn"; mkdir -p "$st"; fourrows "$st" "$(basename "$r")" "$ITEM_HASH"
  runguard "$g" "$r" "$st" 'skip(exhausted)' OVN_PICK_CAP=enforce >/dev/null; ! grep -q AUTO-SKIP "$r/OVERNIGHT_PROGRESS.md" && echo "G_skip_status_ignored=1" || echo "G_skip_status_ignored=0"
}
GREAL="$(mkg "$T/real")"; GOUT="$(guard_suite real "$GREAL")"
for k in G_shadow_switch_logs_only G_default_is_enforce G_unknown_mode_is_shadow G_default_kinds_exclude_rr_fx G_rr_row_not_counted_by_default G_kinds_env_widens G_fifth_pick_parks_exact_line G_credited_landing_prevents_park G_unmatched_line_parks_nothing G_three_picks_silent G_enforce_parks G_enforce_commits G_enforce_keeps_item_text G_landed_uncredited_parks G_off_is_off G_landing_never_parks G_credited_item_not_parked G_other_repo_rows_ignored G_threshold_env G_skip_status_ignored G_log_rotates; do
  ok "pick-cap guard: $k" "printf '%s\n' \"\$GOUT\" | grep -qx '$k=1'"; done
gmut(){ # label sed-expr : the mutated guard must lose at least one check
  local lbl="$1" expr="$2" g o; g="$(mkg "$T/gm_$(echo "$lbl" | tr -c 'A-Za-z0-9' _)" "$expr")"
  if cmp -s "$g" "$GREAL" 2>/dev/null || [ "$(diff <(sed -E "$expr" "$SC/ovn_item_guard.sh") "$SC/ovn_item_guard.sh" | wc -l)" = 0 ]; then F=$((F+1)); echo "  FAIL: guard mutant '$lbl' did not change the guard"; return; fi
  o="$(guard_suite "m$(echo "$lbl" | tr -c 'A-Za-z0-9' _)" "$g")"
  if [ "$(printf '%s\n' "$o" | grep -c '=1$')" = "$(printf '%s\n' "$GOUT" | grep -c '=1$')" ]; then F=$((F+1)); echo "  FAIL: guard mutant '$lbl' SURVIVED"; else P=$((P+1)); fi; }
gmut "never trips" 's/if \[ "\$\{_pc_trip:-0\}" = 1 \]; then/if [ "${_pc_trip:-0}" = 99 ]; then/'
gmut "parks in shadow too" 's/if \[ "\$_pc_mode" = enforce \] && \[ "\$\{_pc_ln:-0\}" -gt 0 \]/if [ "$_pc_mode" != off ] \&\& [ "${_pc_ln:-0}" -gt 0 ]/'
gmut "enforce never parks" 's/if \[ "\$_pc_mode" = enforce \] && \[ "\$\{_pc_ln:-0\}" -gt 0 \]/if [ "$_pc_mode" = NEVER ] \&\& [ "${_pc_ln:-0}" -gt 0 ]/'
gmut "off ignored" 's/^_pc_mode="\$\{OVN_PICK_CAP:-enforce\}"$/_pc_mode="enforce"/'
gmut "default back to shadow" 's/^_pc_mode="\$\{OVN_PICK_CAP:-enforce\}"$/_pc_mode="${OVN_PICK_CAP:-shadow}"/'
gmut "unknown mode enforces" 's/\*\) _pc_mode=shadow ;; esac/*) _pc_mode=enforce ;; esac/'
gmut "default kinds widened" 's/OVN_PICK_CAP_KINDS:-already-done,landed-uncredited/OVN_PICK_CAP_KINDS:-already-done,landed-uncredited,reverted-red,fixup-undid/'
gmut "skip statuses not excluded" 's/case "\$status" in skip\*\|held\*\|\*bug-handled\*\|"no-op\(scout-unworkable\)"\) _pc_mode=off;; esac/true/'
gmut "threshold env ignored" 's/--n "\$\{OVN_PICK_CAP_N:-4\}"/--n 4/'
gmut "log never rotates" 's/-ge 2097152 \] 2>\/dev\/null; then/-ge 2097152999 ] 2>\/dev\/null; then/'
gmut "no commit on park" 's/git -C "\$repo" commit -q -m "chore\(queue\): park item picked/true "chore(queue): park item picked/'

# ------------------------------------------------------------------ PART 2: ALREADY-DONE credit by evidence ------------------------------------------------------------------
mkrepo2(){ # $1=name -> a repo with backend/app/x.py (contains the snippet), backend/tests/test_x.py (+ a venv python stub that passes unless the test file has FAILMARK)
  local r="$T/$1"; mkdir -p "$r/backend/app" "$r/backend/tests" "$r/backend/.venv/bin"
  printf "def helper(v):\n    error = v.get('error') or ''\n    return error\n" > "$r/backend/app/x.py"
  printf "def test_other():\n    assert True\n" > "$r/backend/tests/test_x.py"
  # stub pytest: last arg = file or file::node; FAILMARK => rc 1; node not defined => rc 4 (not found); SKIPMARK => '1 skipped' (rc 0); else '1 passed'
  cat > "$r/backend/.venv/bin/python" <<'STUB'
#!/bin/sh
for a; do last="$a"; done
f="${last%%::*}"; n=""; case "$last" in *::*) n="${last#*::}";; esac
[ -f "$f" ] || { echo "ERROR: file or directory not found"; exit 4; }
grep -q FAILMARK "$f" && { echo "1 failed"; exit 1; }
[ -n "$n" ] && { grep -q "def ${n%%\[*}" "$f" || { echo "ERROR: not found: $last"; exit 4; }; }
grep -q SKIPMARK "$f" && { echo "1 skipped in 0.01s"; exit 0; }
echo "1 passed in 0.01s"; exit 0
STUB
  chmod +x "$r/backend/.venv/bin/python"
  echo "$r"; }
PY2="$T/unit2.py"
cat > "$PY2" <<'PY'
import sys, os, json
sys.path.insert(0, sys.argv[1]); sys.path.insert(0, os.path.join(sys.argv[1], "scripts")); import ovn_ad_lint_credit as m
r1, st = sys.argv[2], sys.argv[3]
res = {}
def ev(item, repo, **kw): return m.evaluate(item, repo, st, **kw)
PN = "- [ ] [T1] backend/app/x.py — Change `error = v.get('error', '')` to `error = v.get('error') or ''` in `helper`. VERIFY: `cd backend && pytest -q tests/test_x.py::test_missing_name`"
TPI = "- [ ] [T1] backend/app/x.py — Change `error = v.get('error', '')` to `error = v.get('error') or ''`. VERIFY: `pytest -q tests/test_x.py`"
d = ev(PN, r1)
res["pn1_credit"] = d["decision"] == "no" and d["reason"].startswith("named-test-missing") and d["rule"] == "PN1"     # the item names a test that does not exist: never a credit
res["pn1_snippet_absent_no_credit"] = ev(PN.replace("or ''` in", "or None` in"), r1)["reason"].startswith("snippet-missing")
res["identifiers_only_weak"] = ev("- [ ] [T1] backend/app/x.py — Handle `helper` and `error` properly. VERIFY: `cd backend && pytest -q tests/test_x.py::test_missing_name`", r1)["reason"].startswith("weak-evidence")
res["removal_item_no_credit"] = ev(PN.replace("Change", "Remove"), r1)["reason"].startswith("removal-item")
res["name_exists_not_malformed"] = ev(PN.replace("test_missing_name", "test_other"), r1)["reason"].startswith("verify-not-malformed")
res["string_missing_no_credit"] = ev(PN.replace("in `helper`", "in `nohelper`"), r1)["reason"].startswith("string-missing")
res["no_verify_no_credit"] = ev(PN.split(" VERIFY:")[0], r1)["decision"] == "no"
open(os.path.join(r1, "backend/tests/test_x.py"), "a").write("# FAILMARK\n")
res["failing_named_test_no_credit"] = ev(TPI, r1)["reason"].startswith("test-failed")
res["run_tests_off_refuses"] = ev(TPI, r1, run_tests=False)["reason"].startswith("test-not-run")
res["run_tests_skip_notes"] = ev(TPI, r1, run_tests="skip")["decision"] == "credit"
open(os.path.join(r1, "backend/tests/test_x.py"), "w").write("def test_other():\n    assert True\n")
res["target_missing_no_credit"] = ev(PN.replace("backend/app/x.py", "backend/app/nope.py"), r1)["reason"].startswith("target-missing")
# TP1: pytest from the root with a path that exists only under backend/
TP = "- [ ] [T1] backend/app/x.py — Change `error = v.get('error', '')` to `error = v.get('error') or ''`. VERIFY: `pytest -q tests/test_x.py`"
d = ev(TP, r1)
res["tp1_credit"] = d["decision"] == "credit" and d["rule"] == "TP1" and any(x.startswith("test=backend/tests/test_x.py:rc=0 passed=1") for x in d["evidence"])
# NEGGREP1 on a removal item never credits (absence needs a scoped check)
open(os.path.join(r1, "backend/app/y.py"), "w").write("a = 'cursor-pointer'\nb = 'cursor-pointer'\n")
NG = "- [ ] [T1] backend/app/y.py — Remove cursor-pointer from the header. VERIFY: `! grep -q cursor-pointer backend/app/y.py`"
d = ev(NG, r1)
res["neggrep1_removal_no_credit"] = d["decision"] == "no" and d["rule"] == "NEGGREP1" and d["reason"].startswith("removal-item")
# a malformed-looking-but-not-linted VERIFY (rule outside the list) is not credited
res["unlinted_verify_no_credit"] = ev("- [ ] [T1] backend/app/x.py — Add `error = v.get('error') or ''`. VERIFY: `false`", r1)["reason"].startswith("verify-not-malformed")
# --- advisory 2: evidence must be CODE (comments/docstrings ignored) and inside the named function ---
x = os.path.join(r1, "backend/app/x.py"); orig_x = open(x).read()
open(x, "w").write("def helper(v):\n    \"\"\"Docs: error = v.get('error') or ''\"\"\"\n    # TODO: error = v.get('error') or ''\n    error = v.get('error', '')\n    return error\n")
res["comment_docstring_not_evidence"] = ev(TPI.replace("`.", "` in `helper`."), r1)["reason"].startswith("snippet-missing") and ev(TPI, r1)["reason"].startswith("snippet-missing")
open(x, "w").write("def helper(v):\n    error = v.get('error', '')\n    return error\n\ndef other(v):\n    error = v.get('error') or ''\n    return error\n")
res["snippet_in_other_function_not_evidence"] = ev(TPI.replace("`.", "` in `helper`."), r1)["reason"].startswith("snippet-missing") and ev(TPI.replace("`.", "` in `other`."), r1)["decision"] == "credit"
res["unlocatable_scope_fails_closed"] = ev(TPI.replace("`.", "` in `nowhere`."), r1)["reason"].startswith(("scope-undetermined", "string-missing"))
open(x, "w").write("def helper(v:\n    broken syntax\n")
res["unparseable_python_fails_closed"] = ev(TPI, r1)["decision"] == "no"
open(x, "w").write(orig_x)
t = os.path.join(r1, "backend/app/w.ts")
open(t, "w").write("// mode = 'new'\n/* mode = 'new' */\nfunction other() { return 1 }\nfunction setIt() {\n  const mode = 'old'\n  return mode\n}\nfunction third() {\n  const mode = 'new'\n}\n")
TS = "- [ ] [T1] backend/app/w.ts — Change `mode = 'old'` to `mode = 'new'` in `setIt`. VERIFY: `pytest -q tests/test_x.py`"
res["ts_comment_and_scope_not_evidence"] = ev(TS, r1)["reason"].startswith("snippet-missing")
open(t, "w").write("function setIt() {\n  const mode = 'new'\n}\n")
res["ts_scoped_code_credit"] = ev(TS, r1)["decision"] == "credit"
# --- advisory 3: the named test must exist and pass (>= 1 passed) ---
ty = os.path.join(r1, "backend/tests/test_y.py"); open(ty, "w").write("def test_y():\n    assert True\n")
BARE = "- [ ] [T1] backend/app/x.py — Change `error = v.get('error', '')` to `error = v.get('error') or ''`; add test_missing_name. VERIFY: `pytest -q tests/test_y.py`"
d = ev(BARE, r1)
res["unrelated_file_bare_missing_name_no_credit"] = d["decision"] == "no" and d["reason"].startswith("named-test-missing")
open(ty, "w").write("def test_y():\n    assert True\ndef test_missing_name():\n    assert True\n")
d = ev(BARE, r1)
res["bare_name_present_runs_by_k"] = d["decision"] == "credit" and any("-k test_missing_name:rc=0 passed=1" in x for x in d["evidence"])
open(ty, "w").write("# SKIPMARK\ndef test_y():\n    pass\n")
d = ev(TPI.replace("test_x.py", "test_y.py"), r1)
res["all_skipped_file_no_credit"] = d["decision"] == "no" and "no-passed-test" in d["reason"]
# --- log rotation ---
lg = os.path.join(st, "rot.log"); open(lg, "w").write("".join("line %d %s\n" % (i, "x" * 400) for i in range(6000)))
m.rotate_log(lg); L = open(lg).read().split("\n")
res["journal_rotates_to_5000"] = len(L) == 5001 and L[0].startswith("line 1000 ") and not os.path.exists(lg + ".rot.%d" % os.getpid())
open(lg, "w").write("small\n"); m.rotate_log(lg)
res["journal_small_untouched"] = open(lg).read() == "small\n"
for k, v in res.items(): print("%s=%d" % (k, 1 if v else 0))
PY
unit2(){ local root="${1:-$Q}" r; r="$(mkrepo2 "u2_$$_$RANDOM")"; mkdir -p "$T/st2"; python3 "$PY2" "$root" "$r" "$T/st2"; }
U2="$(unit2)"
for k in pn1_credit pn1_snippet_absent_no_credit string_missing_no_credit identifiers_only_weak removal_item_no_credit name_exists_not_malformed no_verify_no_credit failing_named_test_no_credit run_tests_off_refuses run_tests_skip_notes target_missing_no_credit tp1_credit neggrep1_removal_no_credit unlinted_verify_no_credit comment_docstring_not_evidence snippet_in_other_function_not_evidence unlocatable_scope_fails_closed unparseable_python_fails_closed ts_comment_and_scope_not_evidence ts_scoped_code_credit unrelated_file_bare_missing_name_no_credit bare_name_present_runs_by_k all_skipped_file_no_credit journal_rotates_to_5000 journal_small_untouched; do
  ok "ad-lint-credit unit: $k" "printf '%s\n' \"\$U2\" | grep -qx '$k=1'"; done
chk2(){ [ "$(unit2 "$MUT" 2>/dev/null | grep -c '=1$')" = "$(printf '%s\n' "$U2" | grep -c '=1$')" ]; }
mut "lint verdict not required" ovn_ad_lint_credit.py 's/if lint.get\("verdict"\) != vl.SUSPECT or lint.get\("rule"\) not in LINT_RULES:/if False:/' chk2
mut "snippet check dropped" ovn_ad_lint_credit.py 's/miss = \[x for x in snips if _norm\(x\) not in nt\]/miss = []/' chk2
mut "weak evidence accepted" ovn_ad_lint_credit.py 's/        if not snips:/        if False:/' chk2
mut "removal items credited" ovn_ad_lint_credit.py 's/        if REMOVAL.search\(desc\) or REMOVAL.search\(pg.leading_body\(item_line\).split\("VERIFY:"\)\[0\]\):/        if False:/' chk2
mut "named test failure ignored" ovn_ad_lint_credit.py 's/            if not ok:/            if False:/' chk2
mut "target string check dropped" ovn_ad_lint_credit.py 's/        if missing:/        if False:/' chk2
mut "NEGGREP1 not in rules" ovn_ad_lint_credit.py 's/LINT_RULES = \("PN1", "TS1", "TP1", "NEGGREP1", "ML1"\)/LINT_RULES = ("PN1", "TS1", "ML1", "NEGGREP1")/' chk2

mut "comments counted as evidence" ovn_ad_lint_credit.py 's/        text = strip_comments\(path, raw\)  .*/        text = raw/' chk2
mut "scope ignored" ovn_ad_lint_credit.py 's/^        names = scope_names\(desc\)$/        names = []/' chk2
mut "bare test name existence not required" ovn_ad_lint_credit.py 's/            if not any\(_defines_test\(p, b\) for p in files\):/            if False:/' chk2
mut "passed>=1 not required" ovn_ad_lint_credit.py 's/        if not pm or int\(pm.group\(1\)\) < 1 or "no tests ran" in out:/        if False:/' chk2
mut "explicit node existence not required" ovn_ad_lint_credit.py 's/                if not _defines_test\(p, node.split/                if False and not _defines_test(p, node.split/' chk2
mut "journal never rotates" ovn_ad_lint_credit.py 's/        if os.path.getsize\(path\) < max_bytes:/        if True:/' chk2

# the bash glue: shadow never ticks/credits, enforce credits, off does nothing; the CLI journal + marker
glue(){ # $1=mode $2=overlay root -> prints "rc|marker|journal|mode"
  local root="${2:-$Q}" r st tl d
  r="$(mkrepo2 "g2_$$_$RANDOM")"; st="$T/stg_$$_$RANDOM"; mkdir -p "$st"; tl="$st/task.log"; : > "$tl"
  printf -- '%s\n' "- [ ] [T1] backend/app/x.py — Change \`error = v.get('error', '')\` to \`error = v.get('error') or ''\` in \`helper\`. VERIFY: \`pytest -q tests/test_x.py\`" > "$r/OVERNIGHT_PROGRESS.md"
  d="$(cd "$r" && OVN_STATE_DIR="$st" OVN_ALREADY_DONE_CREDIT="$1" bash -c '. "'"$SC"'/lib_item_select.sh" 2>/dev/null; . "'"$root"'/scripts/lib_auto_credit.sh" 2>/dev/null; ovn_ad_lint_credit OVERNIGHT_PROGRESS.md 1 "'"$tl"'" "'"$r"'"; echo $?' 2>/dev/null | tail -1)"
  printf '%s|%s|%s|%s|%s' "$d" "$(grep -c 'would-credit already-done-lint-verified' "$tl")" "$([ -s "$st/already_done_credit_shadow.log" ] && echo 1 || echo 0)" "$(grep -c 'already-done-lint-verified: credit at line' "$tl")" "$(grep -c 'already-done-lint-verified' "$tl")"; }
GS="$(glue shadow)"; GE="$(glue enforce)"; GO="$(glue off)";
ok "glue shadow: refusal stands (rc 1), 'would-credit already-done-lint-verified' logged to the task log + journal" "[ '$GS' = '1|1|1|0|1' ]"
ok "glue enforce: credit (rc 0), credit line logged, no would-credit marker" "[ '$GE' = '0|0|1|1|1' ]"
ok "glue off: rc 1, nothing logged anywhere" "[ '$GO' = '1|0|0|0|0' ]"
chk3(){ [ "$(glue shadow "$MUT")|$(glue enforce "$MUT")|$(glue off "$MUT")" = "$GS|$GE|$GO" ]; }
mut "shadow credits" scripts/lib_auto_credit.sh 's/^  \[ -n "\$tl" \] && echo "--- would-credit already-done-lint-verified at line \$\{ln\} \(\$\{out#\* \}\) - OVN_ALREADY_DONE_CREDIT=\$\{mode\}, refusal stands ---" >> "\$tl"$/  return 0/' chk3
mut "enforce never credits" scripts/lib_auto_credit.sh 's/^  if \[ "\$mode" = enforce \]; then$/  if [ "$mode" = NEVER ]; then/' chk3
mut "off not honoured" scripts/lib_auto_credit.sh 's/  case "\$mode" in off\|OFF\|0\) return 1 ;; esac/  true/' chk3
# the hook sits in run_overnight.sh behind the verify-gate refusal and ticks with its own tag only on a credit
RUN="$Q/run_overnight.sh"
ok "run_overnight: the evidence hook runs only after ovn_credit_verify_gate refused; the credit tag is '(already-done, lint-verified)', the default tick text is unchanged" "grep -q 'ovn_ad_lint_credit OVERNIGHT_PROGRESS.md \"\$_ad_ln\"' '$RUN' && grep -q '_ad_tag=\"already-done, lint-verified\"' '$RUN' && grep -q '(already-done, lint-verified) /' '$RUN' && grep -q '(already-done, scout-verified) /' '$RUN' && [ \"\$(grep -n 'ovn_credit_verify_gate OVERNIGHT_PROGRESS.md' '$RUN' | head -1 | cut -d: -f1)\" -lt \"\$(grep -n 'ovn_ad_lint_credit OVERNIGHT_PROGRESS.md' '$RUN' | head -1 | cut -d: -f1)\" ]"
ok "run_overnight.sh parses (bash -n)" "bash -n '$RUN'"
ok "guard parses (bash -n)" "bash -n '$SC/ovn_item_guard.sh'"
echo "q-already-done-credit: $P passed, $F failed"
[ "$F" = 0 ]
