#!/usr/bin/env bash
# Package Z3 (2026-11-07): landing gates B0-B6 (scripts/ovn_landing_gates.py + scripts/lib_landing_gates.sh). Runs test_z3_landing_gates.py, then re-runs it against MUTANTS of the
# gates (each mutation removes one gate or one safety property) and requires every mutant to be KILLED (the suite must fail). NTFY pinned to a dead port.
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(type -P python3.12 || type -P python3)"
export NTFY_SERVER=http://127.0.0.1:9 OVN_NOTIFY_DISABLE=1 TZ=UTC
rc=0
"$PY" "$HERE/test_z3_landing_gates.py" || rc=1
echo "test_z3_landing_gates.py rc=$rc"
[ "$rc" -eq 0 ] || exit 1
echo "== Z3 mutation proofs (each mutant must make the suite FAIL)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
MD="$(safe_mktemp_dir)" || exit 1
trap 'safe_rm_rf "$MD"' EXIT
SRC="$HERE/.."
survived=0; n=0
mut() {  # mut <label> <file: py|sh> <old> <new>
  local label="$1" f="$2" old="$3" new="$4" d="$MD/$((n+1))"
  n=$((n+1)); mkdir -p "$d"; cp "$SRC/ovn_landing_gates.py" "$SRC/lib_landing_gates.sh" "$SRC/ovn_item_guard.sh" "$d/"
  case "$f" in py) tf="$d/ovn_landing_gates.py";; guard) tf="$d/ovn_item_guard.sh";; *) tf="$d/lib_landing_gates.sh";; esac
  if ! OLD="$old" NEW="$new" "$PY" - "$tf" <<'PYEOF'
import os, sys
p = sys.argv[1]; s = open(p).read(); old = os.environ["OLD"]; new = os.environ["NEW"]
if old not in s:
    sys.exit(3)
open(p, "w").write(s.replace(old, new, 1))
PYEOF
  then echo "  FAIL mutant '$label' could not be applied (source changed?)"; survived=$((survived+1)); return; fi
  if Z3_MODULE_DIR="$d" "$PY" "$HERE/test_z3_landing_gates.py" >/dev/null 2>&1; then echo "  FAIL mutant SURVIVED: $label"; survived=$((survived+1)); else echo "  ok   mutant killed: $label"; fi
}
mut "B1 gate never fires"                 py 'if len(missing) / float(len(toks)) >= ratio and missing:' 'if False:'
mut "B1 removal steps judged on added lines" py 'if removal:' 'if False:'
mut "B2 Buzz dropped from the token list" py 'DEFAULT_TONE = "Hey|Yo|Buzz|' 'DEFAULT_TONE = "Hey|Yo|'
mut "B2 pre-existing tokens count as new" py 'if prior.get(w, 0) > 0:' 'if False:'
mut "B2 item text no longer suppresses"   py 'if re.search(r"(?<![A-Za-z0-9_])%s(?![A-Za-z0-9_])" % re.escape(w), ctxt):' 'if False:'
mut "B3 repair routes not checked"        py 'check_repair_routes(fds) if kind == "repair" else []' '[]'
mut "B3 fires on every kind"              py 'check_repair_routes(fds) if kind == "repair" else []' 'check_repair_routes(fds)'
mut "B4 test items not checked"           py 'if not is_test_item(item, desc, files):
        return []' 'if True:
        return []'
mut "B4 source = any file"                py 'return p.endswith(SRC_EXT) and not is_test_path(p)' 'return p.endswith(SRC_EXT)'
mut "B5 nothing is ever dropped"          py 'if name in _IGNORE_CALLS or name.startswith("assert") or name in n["stmt_calls"]:' 'if True:'
mut "B5 refactors (rewrites) flagged"     py 'if len(old_lines) >= 4 and common < 0.4 * len(set(l.strip() for l in old_lines)):' 'if False:'
mut "B6 window ignored (nothing counted)" py 'if lo < ts <= now + 60:' 'if False:'
mut "B6 any class counts as a landing"    py 'if not str(r.get("class", "")).startswith("landed"):' 'if False:'
mut "B6 keyed on the feat-level item_hash"  py 'h = r.get("item_line_hash") or r.get("item_hash") or ""' 'h = r.get("item_hash") or ""'
mut "B6 pending landing ignored"          py '+ a.pending' '+ 0'
mut "B0 leak never matches"               py 'm = LEAK_RE.search(log_text or "")' 'm = None'
mut "lib: enforce never refuses"          sh 'then Z3_REFUSE="$rule: $msg"; rc=1; fi' 'then Z3_REFUSE="$rule: $msg"; rc=0; fi'
mut "lib: default mode is enforce"        sh 'eval "v=\${$1:-shadow}"' 'eval "v=\${$1:-enforce}"'
mut "lib: off still journals"             sh '[ "$mode" = off ] && continue' ':'
mut "lib: B5 may enforce"                 sh '[ "$mode" = enforce ] && mode=shadow;;' ':;;'
mut "lib: cap enforce never parks"        sh 'k="$(ovn_hto 60 landing_cap_park python3 "$py" cap-park' 'k="$(echo 0 #'
mut "item_guard: hook removed"           guard 'z3_landing_cap "$state"' 'true "$state"'
mut "lib: cap shadow parks too"           sh 'if [ "$mode" = enforce ] && [ -n "$rd" ]' 'if [ -n "$rd" ]'
mut "D1 item_guard counts the landing twice (pending=1)" guard '"$_z3t" "$id" 0 ||' '"$_z3t" "$id" 1 ||'
mut "D2 park never pushed"                sh 'if git -C "$rd" remote get-url origin >/dev/null 2>&1; then' 'if false; then'
mut "D2 park notice not on stderr"        sh 'echo "z3: landing-cap parked' 'true "z3: landing-cap parked'
mut "D2 item_guard drops the PARKED notice" guard '|| true   # pending=0' '>/dev/null 2>&1 || true   # pending=0'
mut "D3 findings not capped per rule"     py 'return cap_findings(res)' 'return res'
mut "D3 diff bytes not capped in module"  py 'diff_text = (diff_text or "")[:_envint("OVN_Z3_MAX_DIFF_BYTES", 2 * 1024 * 1024)]' 'diff_text = diff_text or ""'
mut "D3 diff bytes not capped in lib"     sh '| head -c "$cap"' '| cat'
mut "D3 journal never rotated"            sh 'tail -c $((max / 2))' 'tail -c 999999999'
mut "index: shadow mutates the real index" sh 'GIT_INDEX_FILE="$ti" git -C "$wt" add -N .' 'git -C "$wt" add -N .'
mut "D4 old side of rename/replace required" py 'if start is not None and any(a < end and start < b for a, b in old_spans):' 'if False:'
mut "B2 non-source file types linted"     py 'if not p.endswith(SRC_EXT):' 'if False:'
mut "B2 tests/fixtures/locale linted"     py 'if is_test_path(p) or TONE_EXEMPT_DIR_RE.search(p) or TONE_EXEMPT_FILE_RE.search(p):' 'if False:'
mut "B4 test-helper dirs unknown"         py 'test_?helpers?|test-helpers?|testhelpers?|test_?utils?|test-utils?|testutils?|test_?support|test-support|testsupport|testing|testlib|test_?lib|snapshots?)/|' 'testing)/|'
mut "B0 paraphrases not matched"          py 'make the greeting (?:more )?casual|greeting\b.{0,60}\bcasual|casual\b.{0,60}\bgreeting|' ''
mut "B0 leak_gate enforce never refuses"  sh 'return 1; fi ;;' 'return 0; fi ;;'
mut "B7 gate never fires"                 py 'res["assert-weaken"] = check_assert_weaken(' 'res["assert-weaken"] = [] and check_assert_weaken('
mut "B7 negative removal ignored"         py 'if rem_neg > add_neg:' 'if False:'
mut "B7 polarity flips flagged"           py 'if _polarity_key(t) in add_pk:' 'if False:'
mut "B7 status flip flagged with source edits" py 'for ln, t in ([] if src_touched else rem):' 'for ln, t in rem:'
mut "B7 status flip needs a success code"  py 'if ac and _status_shape(a) == shape:' 'if _status_shape(a) == shape:'
mut "B7 weak compare ignored"             py 'if strong_rem > strong_add and weak_add' 'if False and weak_add'
mut "B7 duplicate asserts ignored"        py 'if h["add"][i + 1][0] == h["add"][i][0] + 1 and _norm_line' 'if False and _norm_line'
mut "B7 parametrize cases never checked"  py 'if old_test_ok(old_text_fn) and not retired:' 'if False:'
mut "B7 any removed list entry counts"    py 'if any(_PARAM_RE.search(w) for w in window):' 'if True:'
mut "B7 renamed/retired tests flagged"    py 'retired = rem_testdef' 'retired = False'
mut "B7 emptiness replacement flagged"    py 'if add_empty:' 'if False:'
mut "B7 lib: B7 enforce vetoes"           sh 'assert-weaken) mode="$(_z3_mode OVN_Z3_ASSERT_WEAKEN)"; [ "$mode" = enforce ] && mode=shadow;;' 'assert-weaken) mode="$(_z3_mode OVN_Z3_ASSERT_WEAKEN)";;'
mut "B7 lib: off still journals"          sh 'assert-weaken) mode="$(_z3_mode OVN_Z3_ASSERT_WEAKEN)";' 'assert-weaken) mode=shadow; : "$(_z3_mode OVN_Z3_ASSERT_WEAKEN)";'
echo "mutants: $n, survived/unapplied: $survived"
[ "$survived" -eq 0 ] || exit 1
exit 0
