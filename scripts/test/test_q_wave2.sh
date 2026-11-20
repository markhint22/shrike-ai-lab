#!/usr/bin/env bash
# test_q_wave2.sh - package q-wave2 (2026-11-17). Every behaviour is also run against a MUTANT and must FAIL there.
#  PART 1  pick cap line resolution (ovn_pick_cap.py classify_line / cycle + the item-guard hook): the 17 "no open line" cap trips of 2026-11-16/17 (gitlark 0b20addb, xlite, shrike-monitor, iptv)
#          were all lines ALREADY out of the queue (ticked, or parked by the credit-refusal / no-op block of the same guard run, which retags the line AFTER the row hashed it). The cap now
#          matches the tag/comment-stripped line, reports cap-noop closed|parked ONCE (skip list), and parks by fallback chain (line hash -> text prefix -> unique feat -> oldest staged step).
#  PART 2  GUT ghost tests: `func _test_x` is never run by GUT (ovn_gut_ghost_lint.py + landing gate rule gut-ghost-test, SHADOW ONLY).
#  PART 3  B0d diff-based editor-leak rule (rule editor-leak-diff, SHADOW ONLY) + N=2 wedge-fallback journal row b0-refusal-park (shadow).
# Sandboxed (lib_mac_test_sandbox.sh); no network, no real state.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"; SC="$(cd "$HERE/.." && pwd)"; Q="$(cd "$SC/.." && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
for f in "$Q/ovn_pick_cap.py" "$SC/ovn_item_guard.sh" "$SC/ovn_landing_gates.py" "$SC/lib_landing_gates.sh" "$SC/ovn_gut_ghost_lint.py"; do [ -f "$f" ] || { echo "  SKIP: $f not found"; exit 77; }; done
T="$(safe_mktemp_dir)" || exit 1; trap 'rm -rf "$T"' EXIT
if [ -f "$HERE/lib_mac_test_sandbox.sh" ] && [ "$(uname)" = Darwin ]; then . "$HERE/lib_mac_test_sandbox.sh" && mts_sandbox_init "$T" || { echo "  FAIL: mac test sandbox"; exit 1; }; fi
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 TZ=UTC NTFY_SERVER=http://127.0.0.1:9 OVN_NOTIFY_DISABLE=1 PYTHONDONTWRITEBYTECODE=1
unset OVN_Z3_GUT_GHOST OVN_Z3_B0_DIFF OVN_Z3_B0_PARK_N OVN_PICK_CAP OVN_PICK_CAP_KINDS OVN_Z3_TONE OVN_Z8_TONE
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

# mini tree (what the mutants copy): ovn_pick_cap.py at the root, scripts/ with the gate, lib and guard files
TREE="$T/tree"; mkdir -p "$TREE/scripts"
cp "$Q/ovn_pick_cap.py" "$TREE/"
for f in ovn_item_guard.sh lib_item_select.sh lib_bug_escalate.sh ovn_extract_failure.sh ovn_repeat_ids.py lib_helper_timeout.sh lib_push_bound.sh lib_parked_pattern.sh ovn_landing_gates.py lib_landing_gates.sh ovn_gut_ghost_lint.py; do [ -f "$SC/$f" ] && cp "$SC/$f" "$TREE/scripts/$f"; done
# mut <label> <file rel to the tree> <sed -E expr> <check fn name taking the tree dir>
mut(){ local lbl="$1" rel="$2" expr="$3" chk="$4" d; d="$T/mut_$(echo "$lbl" | tr -c 'A-Za-z0-9' _)"; safe_rm_rf "$d"; mkdir -p "$d"; cp -R "$TREE/." "$d/"
  sed -E "$expr" "$TREE/$rel" > "$d/$rel.new" && mv "$d/$rel.new" "$d/$rel"
  if cmp -s "$TREE/$rel" "$d/$rel"; then F=$((F+1)); echo "  FAIL: mutant '$lbl' did not change $rel"; return; fi
  if "$chk" "$d" >/dev/null 2>&1; then F=$((F+1)); echo "  FAIL: mutant '$lbl' SURVIVED"; else P=$((P+1)); fi; }

# ----------------------------------------------------------------------------- PART 1: pure line resolution ----------------------------------------------------------------------------
cat > "$T/unit_pc.py" <<'PY'
import sys, hashlib, time, os, tempfile
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1]); import ovn_pick_cap as pc
md5 = lambda t: hashlib.md5(t.encode()).hexdigest()
FEAT = "[feat:gitlark-20261115-add-the-plan-history-page-create-web-src]"
def body(n): return "[T1] web/src/pages/P.vue - step %d. VERIFY: `cd web && npx vue-tsc --noEmit`. (cat:vue; multifile:no) %s" % (n, FEAT)
def key(): return pc._item_hash(body(1))
res = {}
def last(n=None, line=None):
    return {"item_hash": key(), "item_line_hash": line if line is not None else (md5(body(n)) if n else "")}
# the gitlark 0b20addb shape: the row hashed the untagged line; by the time the cap runs the credit-refusal block has parked it
parked = "- [ ] [AUTO-SKIP after 2 credit refusals: VERIFY failed] " + body(2)
lines = ["- [ ] " + body(1), parked, "- [ ] " + body(3)]
ln, why = pc.classify_line(lines, last(2), key())
res["parked_line_is_noop_parked"] = (ln, why) == (0, "noop-parked")
res["parked_line_never_parks_a_sibling"] = ln == 0                       # step 1 and 3 are open siblings of the same feat: a guess would park the wrong one
# trailing recovery comment + [x]
sup = "- [x] [AUTO-SKIP after 2 credit refusals: VERIFY failed] " + body(2) + "  <!-- superseded by recovery decomposition below -->"
ln, why = pc.classify_line(["- [ ] " + body(1), sup, "- [ ] " + body(3)], last(2), key())
res["ticked_commented_line_is_noop_closed"] = (ln, why) == (0, "noop-closed")
# the open line itself: exact match
ln, why = pc.classify_line(lines, last(3), key())
res["open_line_hash_parks_that_line"] = (ln, why) == (3, "line-hash")
res["line_hash_beats_oldest"] = ln == 3
# lost line (no hash on the row / text rewritten): unique open feat line
ln, why = pc.classify_line(["- [ ] other thing", "- [x] " + body(1), "- [ ] " + body(2)], last(line=""), key())
res["unique_feat_match"] = (ln, why) == (3, "feat-unique")
# lost line with several open staged steps: OLDEST (first) one
ln, why = pc.classify_line(["- [x] " + body(1), "- [ ] " + body(2), "- [ ] " + body(3), "- [ ] " + body(4)], last(line=""), key())
res["oldest_staged_step"] = (ln, why) == (2, "feat-oldest")
# several open candidates that are NOT staged steps (non-feat items sharing a text key cannot be ordered): park nothing
plain = "[T1] a/b.py - same text twice. VERIFY: `true`"
k2 = pc._item_hash(plain)
ln, why = pc.classify_line(["- [ ] " + plain, "- [ ] " + plain], {"item_hash": k2, "item_line_hash": "x"}, k2)
res["plain_duplicates_park_nothing"] = ln == 0
# a non-feat item ticked with a trailing comment: only the comment-stripped hash form finds it (no feat class to fall back on)
ln, why = pc.classify_line(["- [x] [AUTO-SKIP x] " + plain + "  <!-- closed 2026-11-17 -->"], {"item_hash": k2, "item_line_hash": md5(plain)}, k2)
res["plain_item_comment_closed_noop"] = (ln, why) == (0, "noop-closed")
# a non-feat item retagged after the pick: key = md5 of the untagged text
ln, why = pc.classify_line(["- [ ] [AUTO-SKIP x] " + plain], {"item_hash": k2, "item_line_hash": md5(plain)}, k2)
res["plain_item_retagged_noop_parked"] = (ln, why) == (0, "noop-parked")
t_lines = ["- [ ] [T1] pkg/a.py - add the alpha helper to the registry. VERIFY: `true`", "- [ ] [T1] pkg/b.py - add the beta helper. VERIFY: `true`"]
ln, why = pc.classify_line(t_lines, {"item_hash": "nomatch", "item_line_hash": ""}, "nomatch")
res["no_text_no_match_is_no_open_line"] = (ln, why) == (0, "no-open-line")
# every candidate parked or closed -> the closed verdicts, none of the open-guess ones
ln, why = pc.classify_line(["- [x] " + body(1), "- [x] " + body(2)], last(line="deadbeef"), key())
res["all_closed_feat_is_noop_closed"] = (ln, why) == (0, "noop-closed")
# B1 (reviewer blocker): a park reason holding `]` (pytest id) must still strip whole; the row hash matches, the open sibling is NOT parked
for reason in ("VERIFY failed: test_a[param1] FAILED", "x [nested [deep]] y", "see tests/test_p.py::test_a[1-2][3]"):
    pk = "- [ ] [AUTO-SKIP after 2 credit refusals: %s] %s" % (reason, body(2))
    ln, why = pc.classify_line(["- [ ] " + body(1), pk, "- [ ] " + body(3)], last(2), key())
    res["bracket_reason_noop_parked:" + reason[:14]] = (ln, why) == (0, "noop-parked")
    pk2 = pk + "  <!-- superseded -->"
    ln, why = pc.classify_line(["- [ ] " + body(1), pk2.replace("- [ ]", "- [x]", 1), "- [ ] " + body(3)], last(2), key())
    res["bracket_reason_closed_comment:" + reason[:14]] = (ln, why) == (0, "noop-closed")
res["strip_tags_balanced"] = pc.strip_tags("[AUTO-SKIP a[b] c] text [feat:x]") == "text [feat:x]"
res["strip_tags_unbalanced_reason"] = pc.strip_tags("[AUTO-SKIP a[b c] text") == "text"
# never guess: row has a line hash that cannot be re-derived (reason mangled/truncated), a line of the feat class is parked, an open sibling exists -> noop, not feat-unique
pk = "- [ ] [AUTO-SKIP after 2 credit refusals: something else entirely] " + body(2).replace("step 2", "step 2 reworded")
ln, why = pc.classify_line(["- [ ] " + body(1), pk], last(2), key())
res["lh_present_feat_parked_sibling_open_is_noop"] = ln == 0 and why == "noop-parked"
ln, why = pc.classify_line(["- [x] " + body(1), "- [ ] " + body(3)], last(2), key())
res["lh_present_feat_closed_sibling_open_is_noop"] = ln == 0 and why == "noop-closed"
# no line hash on the row: the feat fallback still works even with a parked sibling around
ln, why = pc.classify_line(["- [ ] " + body(1), pk], last(line=""), key())
res["no_lh_uses_feat_fallback"] = (ln, why) == (1, "feat-unique")
# A2: an unwritable skip list does not make the verdict repeat
dd = tempfile.mkdtemp(); badskip = os.path.join(dd, "nodir", "skip.tsv")
res["unwritable_skiplist_is_seen_not_relogged"] = pc._skip_add(badskip, "r", "k", "l", 1000) is False
# the 17 line=0 replays: closed own line always classifies noop
for j in range(1, 18):
    ln, why = pc.classify_line(["- [ ] " + body(1), "- [x] " + body(j + 10), "- [ ] " + body(2)], last(j + 10), key())
    res["replay_closed_%d" % j] = (ln, why) == (0, "noop-closed")
# cycle(): trip + skip list ("once")
H = 3600; NOW = 1_800_000_000
def row(dt_min, cls, status, line):
    t = NOW - dt_min * 60
    return {"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(t)), "_t": t, "repo": "r", "class": cls, "status": status, "item_hash": key(), "item_line_hash": line, "duration_s": 60}
rows = [row(300, "noop", "no-op(ALREADY-DONE)", md5(body(1))), row(200, "noop", "no-op(ALREADY-DONE)", md5(body(1))), row(100, "noop", "no-op(ALREADY-DONE)", md5(body(2))), row(1, "noop", "no-op(ALREADY-DONE)", md5(body(2)))]
d = tempfile.mkdtemp(); prog = os.path.join(d, "P.md"); skip = os.path.join(d, "skip.tsv")
open(prog, "w").write("\n".join(lines) + "\n")
o1 = pc.cycle(rows, "r", prog, NOW, skip_path=skip)
o2 = pc.cycle(rows, "r", prog, NOW + 60, skip_path=skip)
res["cycle_first_noop_reported"] = o1["trip"] and o1["why"] == "noop-parked" and o1["line_no"] == 0
res["cycle_repeat_is_seen"] = o2["why"] == "noop-parked-seen"
res["skip_list_says_skipped"] = pc.skip_check(skip, "r", key(), NOW + 120) == 1 and pc.skip_check(skip, "r", "other", NOW + 120) == 0
res["skip_list_expires"] = pc.skip_check(skip, "r", key(), NOW + pc.SKIP_TTL_S + 120) == 0
o3 = pc.cycle(rows, "r", prog, NOW)    # no skip path: still the verdict, no file
res["cycle_without_skiplist_ok"] = o3["why"] == "noop-parked"
bad = [k for k, v in res.items() if not v]
for k in bad: print("UNIT-FAIL", k)
sys.exit(1 if bad else 0)
PY
chk_pc(){ python3 "$T/unit_pc.py" "$1"; }
ok "pick-cap line resolution (B1 bracket reasons, never-guess, replays)" 'chk_pc "$TREE"'
mut "balanced strip replaced by no-op scan" ovn_pick_cap.py 's/^            for i in range\(m.start\(\), len\(body\)\):$/            for i in range(m.start(), m.start()):/' chk_pc
mut "feat fallback guesses with a line hash" ovn_pick_cap.py 's/^    if lh and len\(live_feat\) != len\(feat\):$/    if False:/' chk_pc
mut "skiplist write failure re-logs" ovn_pick_cap.py 's/^        return False$/        return True/' chk_pc
mut "tag strip off" ovn_pick_cap.py 's/^    forms = \[body\]$/    return [body]/' chk_pc
mut "found-but-closed falls through to a sibling guess" ovn_pick_cap.py 's/^        if hits:$/        if False:/;s/^    if lh and len\(live_feat\) != len\(feat\):$/    if False:/' chk_pc
mut "oldest staged step refuses" ovn_pick_cap.py 's/return live_feat\[0\], "feat-oldest"/return 0, "no-unique-open-line"/' chk_pc
mut "skip list never says seen" ovn_pick_cap.py 's/^    new = \(repo, key, line\) not in cur$/    new = True/' chk_pc
mut "skip ttl ignored" ovn_pick_cap.py 's/int\(p\[3\]\) > now/int(p[3]) > 0/' chk_pc
mut "comment strip off" ovn_pick_cap.py 's/^CMT_RE = .*$/CMT_RE = re.compile(r"(?!x)x")/' chk_pc

# ----------------------------------------------------------------------------- PART 1b: the item-guard hook --------------------------------------------------------------------------
ITEM='[T1] web/src/pages/P.vue - step 2. VERIFY: `true`. (cat:vue) [feat:gl-20261115-plan-history-create-web]'
md5s(){ printf '%s' "$1" | md5sum 2>/dev/null | cut -d' ' -f1 || printf '%s' "$1" | md5 -q; }
IH="$(python3 -c 'import sys;sys.path.insert(0,sys.argv[1]);import ovn_pick_cap as p;print(p._item_hash(sys.argv[2]))' "$Q" "$ITEM")"; LH="$(md5s "$ITEM")"
[ -n "$LH" ] || LH="$(printf '%s' "$ITEM" | md5 -q)"
jrow(){ local ts; ts="$(python3 -c "import time,sys;print(time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime(time.time()-float(sys.argv[1])*60)))" "$2")"
  printf '{"ts":"%s","repo":"r","id":"ongoing-r","class":"noop","severity":"neutral","status":"no-op(ALREADY-DONE)","item_hash":"%s","item_line_hash":"%s","duration_s":60}\n' "$ts" "$IH" "$LH" >> "$1/outcomes.jsonl"; }
guard_chk(){ # $1=tree : parked-line scenario through the real guard, twice
  local d="$1" r st g; r="$T/gr_$$_$RANDOM/r"; mkdir -p "$r"; st="$r/../st"; mkdir -p "$st"
  ( cd "$r" && git init -q && git config user.email t@t.com && git config user.name t && printf -- '- [ ] [AUTO-SKIP after 2 credit refusals: VERIFY failed] %s\n- [ ] [T1] other.py - open sibling. VERIFY: `true`. [feat:gl-20261115-plan-history-create-web]\n' "$ITEM" > OVERNIGHT_PROGRESS.md && git add -A && git commit -q -m init )
  for m in 400 300 200 1; do jrow "$st" "$m"; done
  printf 'Tokens: 1k sent, 1 received.\n' > "$st/l.log"
  g="$d/scripts/ovn_item_guard.sh"
  for _ in 1 2; do env OVN_ITEM_DAY_CAP_MODE=off OVN_REVERT_REPEAT_MODE=off OVN_REPEAT_BREAKER=off OVN_ITEM_NOOP_CAP=99 OVN_ITEM_FAIL_CAP=99 bash "$g" "$r" 'no-op(ALREADY-DONE)' "$st" ongoing-r "$st/l.log" >/dev/null 2>&1; done
  # the parked line stays as it was, the open sibling is NOT parked, exactly one 'cap-noop parked' line, no 'would-autoskip' noise, the item is on the skip list
  [ "$(grep -c 'cap-noop parked' "$st/pick_cap_shadow.log" 2>/dev/null)" = 1 ] && ! grep -q 'would-autoskip' "$st/pick_cap_shadow.log" \
    && [ "$(grep -c 'AUTO-SKIP' "$r/OVERNIGHT_PROGRESS.md")" = 1 ] && [ "$(wc -l < "$st/pick_cap_skip.tsv" | tr -d ' ')" = 1 ]
}
ok "guard: parked-line trip logs cap-noop parked once, parks no sibling, writes the skip list" 'guard_chk "$TREE"'
mut "guard prints would-autoskip for noop verdicts" scripts/ovn_item_guard.sh 's/\[ "\$\{_pc_trip:-0\}" = 1 \] && case "\$\{_pc_why:--\}" in noop-closed\|noop-parked\)/[ "${_pc_trip:-0}" = 1 ] \&\& case "${_pc_why:--}" in noop-never)/' guard_chk
mut "guard skiplist not passed" scripts/ovn_item_guard.sh 's# --skiplist "\$state/pick_cap_skip.tsv"##' guard_chk

# ----------------------------------------------------------------------------- PART 2: GUT ghost tests ----------------------------------------------------------------------------------
cat > "$T/unit_gg.py" <<'PY'
import sys, os
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(sys.argv[1], "scripts")); import ovn_gut_ghost_lint as gg, ovn_landing_gates as G
res = {}
GHOST = "extends GutTest\n\nfunc _test_walk_scripts_dir():\n\tassert_true(true)\n\nfunc test_real():\n\tassert_true(true)\n"
res["ghost_found"] = [g["name"] for g in gg.scan_text(GHOST, "tests/test_loc_keys_consistent.gd")] == ["_test_walk_scripts_dir"]
res["ghost_line"] = gg.scan_text(GHOST, "tests/test_x.gd")[0]["line"] == 3
res["static_and_typed_ghost"] = len(gg.scan_text("extends GutTest\nstatic func _test_a() -> void:\n\tpass\nfunc _test_b(x := 1) -> void:\n\tpass\n", "tests/test_x.gd")) == 2
res["called_helper_is_not_a_ghost"] = gg.scan_text("extends GutTest\nfunc _test_inner():\n\tpass\nfunc test_outer():\n\t_test_inner()\n", "tests/test_x.gd") == []
res["comment_call_does_not_save_it"] = len(gg.scan_text("extends GutTest\nfunc _test_inner():\n\tpass\n# _test_inner()\n", "tests/test_x.gd")) == 1
res["real_test_names_clean"] = gg.scan_text("extends GutTest\nfunc test_a():\n\tpass\nfunc test_b():\n\tpass\nfunc _helper():\n\tpass\n", "tests/test_x.gd") == []
res["vendored_gut_addon_exempt"] = gg.scan_text("extends GutTest\nfunc _test_running_setup():\n\tpass\n", "addons/gut/test_gut.gd") == []
res["non_gut_script_exempt"] = gg.scan_text("extends Node\nfunc _test_running_setup():\n\tpass\n", "tests/test_x.gd") == []
res["non_test_path_exempt"] = gg.scan_text(GHOST, "scripts/battle.gd") == []
res["is_test_file"] = gg.is_test_file("tests/test_a.gd") and gg.is_test_file("tests/sub/a_test.gd") and not gg.is_test_file("addons/gut/test.gd")
D = "diff --git a/tests/test_loc.gd b/tests/test_loc.gd\n--- a/tests/test_loc.gd\n+++ b/tests/test_loc.gd\n@@ -1,0 +1,3 @@\n+extends GutTest\n+func _test_walk():\n+\tpass\n"
r = G.analyse(D, "add a loc test", "", "step", "")
res["gate_flags_added_ghost"] = [f["token"] for f in r["gut-ghost-test"]] == ["_test_walk"] and r["gut-ghost-test"][0]["sev"] == "FLAG"
D2 = D.replace("_test_walk", "test_walk")
res["gate_clean_on_real_test"] = G.analyse(D2, "add a loc test", "", "step", "")["gut-ghost-test"] == []
D3 = "diff --git a/addons/gut/x.gd b/addons/gut/x.gd\n--- a/addons/gut/x.gd\n+++ b/addons/gut/x.gd\n@@ -1,0 +1,3 @@\n+extends GutTest\n+func _test_walk():\n+\tpass\n"
G1 = lambda t: len(gg.scan_text("extends GutTest\n" + t, "tests/test_x.gd"))
res["callable_string_is_used"] = G1('func _test_a():\n\tpass\nfunc test_b():\n\tvar c = Callable(self, "_test_a")\n') == 0
res["call_string_is_used"] = G1('func _test_a():\n\tpass\nfunc test_b():\n\tcall("_test_a")\n') == 0
res["connect_bare_ref_is_used"] = G1('func _test_a():\n\tpass\nfunc test_b():\n\tsig.connect(_test_a)\n') == 0
res["trailing_comment_mention_is_ghost"] = G1('func _test_a():\n\tpass\nfunc test_b():\n\tpass  # _test_a\n') == 1
res["longer_name_is_not_a_use"] = G1('func _test_a():\n\tpass\nfunc test_b():\n\t_test_a_more()\n') == 1
import time as _t
big = "extends GutTest\n" + "".join("func _test_g%d():\n\tpass\n" % i for i in range(3000)) + "func test_x():\n" + "".join("\tvar v%d = 1\n" % i for i in range(20000))
_s = _t.time(); n_big = len(gg.scan_text(big, "tests/test_x.gd")); res["scan_is_linear"] = n_big == 3000 and _t.time() - _s < 3
res["diff_form_callable_string_clean"] = gg.scan_added("tests/test_x.gd", [(2, "func _test_a():")], "extends GutTest\nfunc _test_a():\n\tpass\nfunc test_b():\n\tcall_deferred(\"_test_a\")\n") == []
res["gate_called_helper_clean"] = G.analyse(D, "add a loc test", "", "step", "", post_text="extends GutTest\nfunc _test_walk():\n\tpass\nfunc test_x():\n\t_test_walk()\n")["gut-ghost-test"] == []
res["gate_ignores_vendored"] = G.analyse(D3, "x", "", "step", "")["gut-ghost-test"] == []
bad = [k for k, v in res.items() if not v]
for k in bad: print("UNIT-FAIL", k)
sys.exit(1 if bad else 0)
PY
chk_gg(){ python3 "$T/unit_gg.py" "$1"; }
ok "GUT ghost lint + gate rule (unit checks)" 'chk_gg "$TREE"'
mut "string refs not counted as use" scripts/ovn_gut_ghost_lint.py 's/_IDENT_RE.findall\(_strip_comment\(ln\)\)/re.findall(r"[A-Za-z_][A-Za-z_0-9]*(?=[ ]*[(])", _strip_comment(ln))/' chk_gg
mut "ghost regex misses underscore names" scripts/ovn_gut_ghost_lint.py 's/\(_test\\w\*\)/(test\\w*)/' chk_gg
mut "called-helper escape off (diff form)" scripts/ovn_gut_ghost_lint.py 's/^            if name in used:$/            if False:/' chk_gg
mut "called-helper escape off (file form)" scripts/ovn_gut_ghost_lint.py 's/if n not in used\]/if True]/' chk_gg
mut "vendored addons not exempt" scripts/ovn_gut_ghost_lint.py 's/p.startswith\("addons\/"\) or "\/addons\/" in p/False/' chk_gg
mut "gate rule not wired" scripts/ovn_landing_gates.py 's/^    res\["gut-ghost-test"\] = .*$/    res["gut-ghost-test"] = []/' chk_gg
mut "non-GUT scripts counted" scripts/ovn_gut_ghost_lint.py 's/^    return bool\(GUT_EXT_RE.search\(text or ""\) or .*$/    return True/' chk_gg

# standalone CLI on a real-shaped tree + lib wiring: z3_step_gate journals the finding in SHADOW and never refuses (even OVN_Z3_GUT_GHOST=enforce)
wt_chk(){ # $1=tree : $2=rule $3=extra-env  (shared by part 2 and 3 through globals RULE/WTFILE/WTBODY/ITEMTXT)
  local d="$1" w st; w="$T/wt_$$_$RANDOM"; mkdir -p "$w/repo/$(dirname "$WTFILE")" "$w/st"; st="$w/st"
  ( cd "$w/repo" && git init -q && git config user.email t@t.com && git config user.name t && printf '%s\n' "$WTOLD" > "$WTFILE" && git add -A && git commit -q -m init && printf '%s\n' "$WTBODY" > "$WTFILE" )
  ( . "$d/scripts/lib_landing_gates.sh"; z3_step_gate "$w/repo" step "$WTDESC" "$ITEMTXT" "$WTFILE" "" "$st" "r:s1"; echo "rc=$?" > "$st/rc"; echo "refuse=${Z3_REFUSE:-}" >> "$st/rc" ) >/dev/null 2>&1
  W_ST="$st"; export W_ST
  [ -f "$st/landing_gates_shadow.log" ]
}
export WTFILE="tests/test_loc.gd" WTOLD="extends GutTest" WTBODY=$'extends GutTest\nfunc _test_walk():\n\tpass' WTDESC="add a loc test" ITEMTXT='[T1] tests/test_loc.gd - add a loc test. [feat:xl-20261115-loc-test]'
gut_wt(){ OVN_Z3_GUT_GHOST="${GGMODE:-}" wt_chk "$1" && grep -q '"rule": "gut-ghost-test"' "$W_ST/landing_gates_shadow.log" && grep -q '"mode": "shadow"' "$W_ST/landing_gates_shadow.log" && grep -q '^rc=0' "$W_ST/rc" && grep -q '^refuse=$' "$W_ST/rc"; }
ok "z3_step_gate journals gut-ghost-test as shadow, no refusal" 'GGMODE= gut_wt "$TREE"'
ok "OVN_Z3_GUT_GHOST=enforce still only shadows" 'GGMODE=enforce gut_wt "$TREE"'
ok "OVN_Z3_GUT_GHOST=off journals nothing" '! GGMODE=off gut_wt "$TREE"'
gut_wt_enf(){ GGMODE=enforce gut_wt "$1"; }
mut "gut-ghost enforce can refuse" scripts/lib_landing_gates.sh '/gut-ghost-test\) mode=/ s/; \[ "\$mode" = enforce \] && mode=shadow//' gut_wt_enf
# CLI over a directory
mkdir -p "$T/cli/tests" "$T/cli/addons/gut"; printf 'extends GutTest\nfunc _test_a():\n\tpass\n' > "$T/cli/tests/test_a.gd"; printf 'extends GutTest\nfunc test_b():\n\tpass\n' > "$T/cli/tests/test_b.gd"; printf 'extends GutTest\nfunc _test_c():\n\tpass\n' > "$T/cli/addons/gut/g.gd"
cli_chk(){ local o; o="$(python3 "$1/scripts/ovn_gut_ghost_lint.py" "$T/cli/tests" "$T/cli/addons")"; local rc=$?; [ "$rc" = 1 ] && [ "$(printf '%s\n' "$o" | grep -c 'ghost GUT test')" = 1 ] && printf '%s' "$o" | grep -q '_test_a'; }
ok "standalone checker: tests/ ghost found, vendored addons skipped, rc 1" 'cli_chk "$TREE"'
mut "cli never fails" scripts/ovn_gut_ghost_lint.py 's/return 1 if found else 0/return 0/' cli_chk

# ----------------------------------------------------------------------------- PART 3: B0d diff-based leak -------------------------------------------------------------------------------
cat > "$T/unit_b0.py" <<'PY'
import sys, os, json, time, tempfile
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(sys.argv[1], "scripts")); import ovn_landing_gates as G
def diff(path, added, removed=()):
    h = "diff --git a/%s b/%s\n--- a/%s\n+++ b/%s\n@@ -10,%d +10,%d @@\n" % (path, path, path, path, len(removed) + 1, len(added) + 1)
    return h + " ctx\n" + "".join("-" + r + "\n" for r in removed) + "".join("+" + a + "\n" for a in added)
def hits(path, added, removed=(), text="", item=""):
    r = G.analyse(diff(path, added, removed), text, item, "step", "")
    return r["editor-leak-diff"] + r["editor-leak-diff-pair"]
res = {}
res["token_in_product_copy"] = len(hits("web/src/pages/N.vue", ['<h1 class="x">Hey! Here are your notifications</h1>'])) == 1
res["pair_hello_to_hiya"] = [h["kind"] for h in hits("web/src/pages/N.vue", ['<h1>Hiya, notifications</h1>'], ['<h1>Hello, notifications</h1>'])] == ["pair"]
res["pair_needs_the_removed_hello"] = hits("web/src/pages/N.vue", ['<h1>Hiya, notifications</h1>'], ['<h1>Notifications</h1>']) == []
res["item_text_asks_for_it"] = hits("web/src/pages/N.vue", ["<h1>Hey! x</h1>"], text="change the heading to say Hey! x") == []
res["test_file_exempt"] = hits("web/src/__tests__/N.spec.ts", ["expect(x).toContain('Hey there')"]) == []
res["docs_exempt"] = hits("docs/guide.md", ["Hey, welcome"]) == [] and hits("web/src/locales/en.ts", ["  greet: 'Hey!'"]) == []
res["comment_line_exempt"] = hits("backend/app/x.py", ["# Hey, this is a note"]) == [] and hits("web/src/a.vue", ["<!-- Hey -->"]) == []
res["moved_line_exempt"] = hits("web/src/pages/N.vue", ["<h1>Hey! x</h1>"], ["<h1>Hey! x</h1>"]) == []
res["identifier_not_token"] = hits("backend/app/x.py", ['name = "HeyCorp"']) == []
res["lowercase_not_token"] = hits("backend/app/x.py", ['s = "hey"']) == []
res["finding_has_item_key"] = hits("web/src/pages/N.vue", ["<h1>Hey!</h1>"], item="[T1] a.vue - x [feat:gl-20261115-x-y]")[0]["item_key"] == G.item_key_of("[T1] a.vue - x [feat:gl-20261116-x-y]")   # date stamp stripped
# A4: the rule uses the SAME token regex as tone-lint, incl. OVN_Z3_TONE_TOKENS
os.environ["OVN_Z3_TONE_TOKENS"] = "Gadzooks|Yippee"
res["custom_tone_token_hits"] = len(hits("web/src/pages/N.vue", ["<h1>Gadzooks! notifications</h1>"])) == 1
res["custom_tone_list_replaces_default"] = hits("web/src/pages/N.vue", ["<h1>Hey! notifications</h1>"]) == []
del os.environ["OVN_Z3_TONE_TOKENS"]
res["default_tokens_back_after_env_cleared"] = len(hits("web/src/pages/N.vue", ["<h1>Hey! notifications</h1>"])) == 1
# wedge fallback: N=2 distinct attempts of one item
d = tempfile.mkdtemp(); j = os.path.join(d, "j.log"); NOW = 1_800_000_000
def ts(dt): return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(NOW - dt))
def put(rule, key, dt, label): open(j, "a").write(json.dumps({"rule": rule, "item_key": key, "ts": ts(dt), "label": label}) + "\n")
put("editor-leak-diff", "K1", 3600, "r:s1"); put("editor-leak-diff", "K1", 3600, "r:s1")      # same attempt twice (two lines) = ONE
res["same_attempt_counts_once"] = G.b0_refusal_count(j, "K1", NOW) == 1
put("editor-leak-diff", "K1", 1800, "r:s2")
res["second_attempt_makes_two"] = G.b0_refusal_count(j, "K1", NOW) == 2
put("editor-leak-diff", "K2", 1800, "r:s3"); put("tone-lint", "K3", 1800, "r:s4"); put("editor-leak-diff", "K3", 30 * 3600, "r:s5"); put("editor-leak-diff-pair", "K4", 600, "r:s6"); put("editor-leak-diff", "K4", 300, "r:s7")
res["pair_rows_count_as_refusals"] = G.b0_refusal_count(j, "K4", NOW) == 2
res["other_item_not_counted"] = G.b0_refusal_count(j, "K2", NOW) == 1 and G.b0_refusal_count(j, "K1", NOW) == 2
res["window_24h"] = G.b0_refusal_count(j, "K3", NOW) == 0
bad = [k for k, v in res.items() if not v]
for k in bad: print("UNIT-FAIL", k)
sys.exit(1 if bad else 0)
PY
chk_b0(){ python3 "$T/unit_b0.py" "$1"; }
ok "B0d diff-based rule + refusal counter (16 unit checks)" 'chk_b0 "$TREE"'
mut "b0d: ignores OVN_Z3_TONE_TOKENS" scripts/ovn_landing_gates.py '/def check_editor_leak_diff/,/^def b0_refusal_count/ s/rx = tone_regex\(\)/rx = tone_regex(DEFAULT_TONE_PRE)/' chk_b0
mut "b0d: comments counted" scripts/ovn_landing_gates.py '/def check_editor_leak_diff/,/^def b0_refusal_count/ s/if _is_comment\(t\) or re\.match\(.*\):$/if False:/' chk_b0
mut "b0d: pair without the removed Hello" scripts/ovn_landing_gates.py 's/if not m and pair_from:/if not m:/' chk_b0
mut "b0d: item text escape off" scripts/ovn_landing_gates.py '/def check_editor_leak_diff/,/^def b0_refusal_count/ s/^            if re.search\(r"\(\?<!\[A-Za-z0-9_\]\)%s\(\?!\[A-Za-z0-9_\]\)" % re.escape\(w\), ctxt\):$/            if False:/' chk_b0
mut "b0d: tests/docs not exempt" scripts/ovn_landing_gates.py '/def check_editor_leak_diff/,/^def b0_refusal_count/ s/if fd.is_deleted or tone_exempt\(fd.path\):/if fd.is_deleted:/' chk_b0
mut "b0d: one attempt counts per line" scripts/ovn_landing_gates.py 's/seen.add\(\(r.get\("ts"\), r.get\("label"\)\)\)/seen.add((r.get("ts"), r.get("label"), id(r)))/' chk_b0
mut "b0d: window ignored" scripts/ovn_landing_gates.py '/def b0_refusal_count/,/return len\(seen\)/ s/if lo < t <= now \+ 60:/if t <= now + 60:/' chk_b0
mut "b0d: item keys mixed" scripts/ovn_landing_gates.py '/def b0_refusal_count/,/return len\(seen\)/ { s/ or item_key not in ln:/:/; s/ or r.get\("item_key"\) != item_key:/:/; }' chk_b0
mut "b0d: pair rule not counted as a refusal" scripts/ovn_landing_gates.py 's/if r.get\("rule"\) not in \("editor-leak-diff", "editor-leak-diff-pair"\)/if r.get("rule") not in ("editor-leak-diff",)/' chk_b0

# lib: shadow journal rows + the b0-refusal-park shadow row on the 2nd attempt; enforce never refuses; off drops both
b0_wt(){ # $1=tree ; two attempts of the same item
  local d="$1" w st; w="$T/b0_$$_$RANDOM"; mkdir -p "$w/repo/web/src" "$w/st"; st="$w/st"
  ( cd "$w/repo" && git init -q && git config user.email t@t.com && git config user.name t && printf '<h1>Hello</h1>\n' > web/src/N.vue && git add -A && git commit -q -m init && printf '<h1>Hey! hi</h1>\n' > web/src/N.vue )
  local it='[T1] web/src/N.vue - rename the heading to Notifications. [feat:gl-20261115-n-vue]'
  ( . "$d/scripts/lib_landing_gates.sh"; z3_step_gate "$w/repo" step "rename the heading" "$it" web/src/N.vue "" "$st" "r:s1"; r1=$?; z3_step_gate "$w/repo" step "rename the heading" "$it" web/src/N.vue "" "$st" "r:s2"; echo "rc=$r1,$?" > "$st/rc"; echo "refuse=${Z3_REFUSE:-}" >> "$st/rc" ) >/dev/null 2>&1
  W_ST="$st"; export W_ST; sleep 1; true
}
b0_lib_chk(){ b0_wt "$1"; local j="$W_ST/landing_gates_shadow.log"   # SHADOW semantics (the caller exports OVN_Z3_B0_DIFF=shadow OVN_Z3_TONE=shadow so nothing else refuses)
  [ "$(grep -c '"rule": "editor-leak-diff"' "$j")" = 2 ] && grep '"rule": "editor-leak-diff"' "$j" | grep -q '"mode": "shadow"' && ! grep '"rule": "editor-leak-diff"' "$j" | grep -q '"mode": "enforce"' && [ "$(grep -c '"rule":"b0-refusal-park"' "$j")" -ge 1 ] && grep -q '"mode":"shadow"' "$j" \
    && grep -q '^refuse=$' "$W_ST/rc"; }
b0_shadow(){ OVN_Z3_B0_DIFF=shadow OVN_Z3_TONE=shadow b0_lib_chk "$1"; }
ok "lib: B0d with OVN_Z3_B0_DIFF=shadow journals shadow rows; the 2nd attempt of one item adds the b0-refusal-park shadow row; refuses nothing" 'b0_shadow "$TREE"'
# FLIP (separate commit): token kind ENFORCE by default (it follows the tone-lint mode, which is enforce by default)
b0_def(){ b0_wt "$1"; local j="$W_ST/landing_gates_shadow.log"; grep '"rule": "editor-leak-diff"' "$j" | grep -q '"mode": "enforce"' && grep -q '^rc=1,1' "$W_ST/rc"; }
ok "FLIP: default = enforce: the journal row says mode=enforce and the attempt is refused" 'b0_def "$TREE"'
mut "flip: default falls back to shadow" scripts/lib_landing_gates.sh 's/\*\) v="\$\(_z3_tone_mode\)";; esac; fi/*) v=shadow;; esac; fi/' b0_def
b0_own(){ OVN_Z3_B0_DIFF=enforce OVN_Z3_TONE=shadow b0_wt "$1"; grep -q '^rc=1,1' "$W_ST/rc" && grep -q '^refuse=editor-leak-diff:' "$W_ST/rc"; }
ok "FLIP: with tone-lint reverted, the B0d rule on its own refuses (Z3_REFUSE names editor-leak-diff)" 'b0_own "$TREE"'
mut "flip: B0d clamped to shadow" scripts/lib_landing_gates.sh '/editor-leak-diff\) mode=/ s/mode="\$\(_z3_b0d_mode\)";;/mode="shadow";;/' b0_own
b0_rev_leak(){ OVN_Z3_EDITOR_LEAK=shadow b0_wt "$1"; local j="$W_ST/landing_gates_shadow.log"; grep '"rule": "editor-leak-diff"' "$j" | grep -q '"mode": "shadow"' && ! grep '"rule": "editor-leak-diff"' "$j" | grep -q '"mode": "enforce"'; }
ok "FLIP: OVN_Z3_EDITOR_LEAK=shadow reverts the rule to shadow" 'b0_rev_leak "$TREE"'
mut "flip: OVN_Z3_EDITOR_LEAK=shadow ignored" scripts/lib_landing_gates.sh 's/shadow\|off\) v="\$OVN_Z3_EDITOR_LEAK";;/never) v="$OVN_Z3_EDITOR_LEAK";;/' b0_rev_leak
b0_rev_tone(){ OVN_Z3_TONE=shadow b0_wt "$1"; local j="$W_ST/landing_gates_shadow.log"; grep '"rule": "editor-leak-diff"' "$j" | grep -q '"mode": "shadow"' && ! grep '"rule": "editor-leak-diff"' "$j" | grep -q '"mode": "enforce"' && grep -q '^refuse=$' "$W_ST/rc"; }
ok "FLIP: OVN_Z3_TONE=shadow (the existing tone revert) reverts B0d too: journal-only, nothing refused" 'b0_rev_tone "$TREE"'
mut "flip: B0d ignores the tone revert" scripts/lib_landing_gates.sh 's/\*\) v="\$\(_z3_tone_mode\)";; esac; fi/*) v=enforce;; esac; fi/' b0_rev_tone
b0_rev_alias(){ OVN_Z3_TONE_LINT=shadow b0_wt "$1"; ! grep '"rule": "editor-leak-diff"' "$W_ST/landing_gates_shadow.log" | grep -q '"mode": "enforce"' && grep -q '^refuse=$' "$W_ST/rc"; }
ok "FLIP: the alias OVN_Z3_TONE_LINT=shadow reverts B0d too" 'b0_rev_alias "$TREE"'
b0_rev_bogus(){ OVN_Z3_B0_DIFF=bogus OVN_Z3_TONE=shadow b0_lib_chk "$1"; }
ok "FLIP: an invalid OVN_Z3_B0_DIFF is shadow, never a silent enforce" 'b0_rev_bogus "$TREE"'
mut "flip: invalid value enforces" scripts/lib_landing_gates.sh 's/\*\) printf .shadow.;; esac$/*) printf enforce;; esac/' b0_rev_bogus
b0_explicit_over_leak(){ OVN_Z3_B0_DIFF=enforce OVN_Z3_EDITOR_LEAK=shadow OVN_Z3_TONE=shadow b0_wt "$1"; grep -q '^refuse=editor-leak-diff:' "$W_ST/rc"; }
ok "FLIP: explicit OVN_Z3_B0_DIFF=enforce beats OVN_Z3_EDITOR_LEAK=shadow" 'b0_explicit_over_leak "$TREE"'
b0_leak_enforce_irrelevant(){ OVN_Z3_EDITOR_LEAK=enforce b0_def "$1"; }
ok "FLIP: OVN_Z3_EDITOR_LEAK=enforce is the log-sentence gate's flag; the token rule stays enforce either way" 'b0_leak_enforce_irrelevant "$TREE"'
b0_off(){ OVN_Z3_B0_DIFF=off b0_wt "$1"; ! grep -q 'editor-leak-diff\|b0-refusal-park' "$W_ST/landing_gates_shadow.log" 2>/dev/null; }
ok "OVN_Z3_B0_DIFF=off journals nothing" 'b0_off "$TREE"'
b0_off2(){ OVN_Z3_EDITOR_LEAK=off b0_wt "$1"; ! grep -q 'editor-leak-diff\|b0-refusal-park' "$W_ST/landing_gates_shadow.log" 2>/dev/null; }
ok "OVN_Z3_EDITOR_LEAK=off journals nothing" 'b0_off2 "$TREE"'
b0_off3(){ OVN_Z3_TONE_LINT=off b0_wt "$1"; ! grep -q 'editor-leak-diff\|b0-refusal-park' "$W_ST/landing_gates_shadow.log" 2>/dev/null; }
ok "OVN_Z3_TONE_LINT=off silences B0d too" 'b0_off3 "$TREE"'
# the word-pair kind never enforces, even with the token rule on enforce
b0_pair(){ local d="$1" w st; w="$T/b0p_$$_$RANDOM"; mkdir -p "$w/repo/web/src" "$w/st"; st="$w/st"
  ( cd "$w/repo" && git init -q && git config user.email t@t.com && git config user.name t && printf '<h1>Hello there</h1>\n' > web/src/N.vue && git add -A && git commit -q -m init && printf '<h1>Hiya there</h1>\n' > web/src/N.vue )
  ( . "$d/scripts/lib_landing_gates.sh"; z3_step_gate "$w/repo" step "rename the heading" '[T1] web/src/N.vue - rename. [feat:gl-20261115-n-vue]' web/src/N.vue "" "$st" "r:s1"; echo "rc=$?" > "$st/rc"; echo "refuse=${Z3_REFUSE:-}" >> "$st/rc" ) >/dev/null 2>&1
  grep -q '"rule": "editor-leak-diff-pair"' "$st/landing_gates_shadow.log" && grep '"rule": "editor-leak-diff-pair"' "$st/landing_gates_shadow.log" | grep -q '"mode": "shadow"' && grep -q '^rc=0' "$st/rc" && grep -q '^refuse=$' "$st/rc"; }
ok "FLIP: the Hello->Hiya pair is journaled shadow and never refuses under the enforce default" 'b0_pair "$TREE"'
b0_pair_enf(){ OVN_Z3_B0_DIFF=enforce b0_pair "$1"; }
mut "flip: pair kind enforces" scripts/lib_landing_gates.sh '/editor-leak-diff-pair\) mode=/ s/; \[ "\$mode" = enforce \] && mode=shadow//' b0_pair_enf
mut "b0d: park row never written" scripts/lib_landing_gates.sh '/_b0o" in/ s/"over": true/"over": never/' b0_shadow
# the park row must not appear after a SINGLE attempt
b0_single(){ local d="$1" w st; w="$T/b0s_$$_$RANDOM"; mkdir -p "$w/repo/web/src" "$w/st"; st="$w/st"
  ( cd "$w/repo" && git init -q && git config user.email t@t.com && git config user.name t && printf '<h1>Hello</h1>\n' > web/src/N.vue && git add -A && git commit -q -m init && printf '<h1>Hey! hi</h1>\n' > web/src/N.vue )
  ( . "$d/scripts/lib_landing_gates.sh"; z3_step_gate "$w/repo" step "rename the heading" '[T1] web/src/N.vue - rename. [feat:gl-20261115-n-vue]' web/src/N.vue "" "$st" "r:s1" ) >/dev/null 2>&1
  grep -q '"rule": "editor-leak-diff"' "$st/landing_gates_shadow.log" && ! grep -q 'b0-refusal-park' "$st/landing_gates_shadow.log"; }
ok "one attempt journals the leak row but no park row" 'b0_single "$TREE"'
mut "b0d: park after one attempt" scripts/lib_landing_gates.sh 's/_b0n="\$\{OVN_Z3_B0_PARK_N:-2\}"/_b0n=1/' b0_single

echo
echo "q-wave2: $P passed, $F failed"
[ "$F" = 0 ]
