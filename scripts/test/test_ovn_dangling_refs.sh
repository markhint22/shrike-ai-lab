#!/usr/bin/env bash
# 2026-10-18 (xlite reverted(build-break) x2): scripts/ovn_dangling_refs.py lists EVERY function a commit deleted that something still calls, with the deleted source.
# Live shape replayed (xlite turn_manager.gd, commit 3b1a3965 / the reverted 'delete dead helpers' cycles): get_phase_name() removed while get_phase_summary() still calls it.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
DR="$HERE/../ovn_dangling_refs.py"; [ -f "$DR" ] || DR="$HERE/ovn_dangling_refs.py"
[ -f "$DR" ] || { echo "  FAIL: ovn_dangling_refs.py not found"; exit 1; }
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
T="$(safe_mktemp_dir)" || exit 1; trap 'rm -rf "$T"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.com GIT_CONFIG_NOSYSTEM=1
R="$T/r"
GD_BASE='class_name TurnManager
extends RefCounted

## Returns a human-readable name for the current phase.
func get_phase_name() -> String:
\tif phase == Phase.PLAYER:
\t\treturn "Player"
\treturn "Enemy"

## Returns the turn state.
func get_phase_summary() -> Dictionary:
\treturn {
\t\t"phase": get_phase_name(),
\t\t"round": 1
\t}

## Returns the count.
func get_phase_count() -> int:
\treturn 2

func is_player_phase() -> bool:
\treturn phase == Phase.PLAYER
'
mkgd(){ rm -rf "$R"; mkdir -p "$R/scripts" "$R/tests"; git -C "$R" init -q -b main; printf "$GD_BASE" > "$R/scripts/tm.gd"; printf 'extends GutTest\nfunc test_x():\n\tassert_eq(TurnManager.new().get_phase_count(), 2)\n' > "$R/tests/test_tm.gd"; git -C "$R" add -A; git -C "$R" commit -q -m base; }
commit(){ git -C "$R" add -A; git -C "$R" commit -q -m c; }
dr(){ python3 -I "${CHECKER:-$DR}" check "$R" HEAD~1 HEAD "$@" 2>&1; }
# delete a function (def line, its doc comment line above, its body, the trailing blank) from tm.gd via python (portable)
delfn(){ python3 -I - "$R/scripts/tm.gd" "$1" <<'PY'
import re,sys
p,name=sys.argv[1],sys.argv[2]
L=open(p).read().split("\n"); out=[]; i=0
while i<len(L):
    if re.match(r"func %s\(" % re.escape(name), L[i]):
        if out and out[-1].startswith("##"): out.pop()
        i+=1
        while i<len(L) and (L[i].startswith("\t") or L[i].startswith(")")): i+=1
        if i<len(L) and L[i]=="": i+=1
        continue
    out.append(L[i]); i+=1
open(p,"w").write("\n".join(out))
PY
}

mkgd; delfn get_phase_name; commit
out="$(dr)"; rc=0; python3 -I "$DR" check "$R" HEAD~1 HEAD >/dev/null 2>&1 || rc=$?
ok "1: deleting get_phase_name while get_phase_summary still calls it => DANGLING get_phase_name (the live incident)" 'grep -qE "^DANGLING.get_phase_name.scripts/tm.gd:[0-9]+.1$" <<< "$out"'
ok "1b: exit code 1 (found)" "[ $rc = 1 ]"
src="$(dr --source)"
ok "2: --source prints the deleted definition verbatim (header + body)" 'grep -qF "### get_phase_name (scripts/tm.gd)" <<< "$src" && grep -qF "func get_phase_name() -> String:" <<< "$src" && grep -qF "return \"Enemy\"" <<< "$src"'
ok "2b: the source stops at the end of the function (does not swallow the next doc comment / func)" '! grep -qF "get_phase_summary" <<< "$(sed -n "/^### get_phase_name/,\$p" <<< "$src")"'

mkgd; delfn get_phase_name; delfn get_phase_summary; commit
ok "3: callee AND its caller deleted together => nothing dangling (rc 0, no output)" '[ -z "$(dr)" ]'

mkgd; delfn get_phase_name; delfn get_phase_count; commit
out="$(dr)"
ok "4: two deleted helpers still called (get_phase_name by the summary, get_phase_count by a test) => BOTH listed (the fix-up used to be told one at a time)" 'grep -qE "^DANGLING.get_phase_name" <<< "$out" && grep -qE "^DANGLING.get_phase_count.tests/test_tm.gd" <<< "$out"'

mkgd; delfn get_phase_name; printf '\n## Returns a human-readable name for the current phase.\nfunc get_phase_name() -> String:\n\treturn "x"\n' >> "$R/scripts/tm.gd"; commit
ok "5: a function that is moved / re-added elsewhere in the tree is NOT dangling" '[ -z "$(dr)" ]'

mkgd; delfn get_phase_name; sed -i.bak 's/get_phase_name(),/"x",/' "$R/scripts/tm.gd"; rm -f "$R/scripts/tm.gd.bak"; printf '# get_phase_name used to live here\n' >> "$R/scripts/tm.gd"; commit
ok "6: only a comment still mentions the name => not dangling" '[ -z "$(dr)" ]'

# python
rm -rf "$R"; mkdir -p "$R/app"; git -C "$R" init -q -b main
printf 'def helper_a():\n    return 1\n\n\ndef helper_b():\n    return helper_a() + 1\n' > "$R/app/m.py"; printf 'from app.m import helper_b\nprint(helper_b())\n' > "$R/app/use.py"; git -C "$R" add -A; git -C "$R" commit -q -m base
printf 'def helper_b():\n    return 2\n' > "$R/app/m.py"; commit
ok "7: python: helper_a deleted, nothing calls it any more (helper_b was rewritten) => clean" '[ -z "$(dr)" ]'
printf 'def helper_b():\n    return helper_a() + 1\n' > "$R/app/m.py"; commit
printf 'def helper_b():\n    return helper_a() + 1\n' > "$R/app/m.py"
rm -rf "$R"; mkdir -p "$R/app"; git -C "$R" init -q -b main
printf 'def helper_a():\n    return 1\n\n\ndef helper_b():\n    return helper_a() + 1\n' > "$R/app/m.py"; git -C "$R" add -A; git -C "$R" commit -q -m base
printf 'def helper_b():\n    return helper_a() + 1\n' > "$R/app/m.py"; commit
ok "8: python: helper_a deleted but helper_b still calls it => DANGLING helper_a" 'grep -qE "^DANGLING.helper_a.app/m.py:[0-9]+" <<< "$(dr)"'
ok "9: bad ref => rc 2 (fail open)" 'python3 -I "$DR" check "$R" nope HEAD >/dev/null 2>&1; [ $? = 2 ]'

# mutants
mut(){ python3 -I - "$DR" "$T/mut.py" "$1" "$2" <<'PY'
import sys
s=open(sys.argv[1]).read(); assert sys.argv[3] in s, sys.argv[3]
open(sys.argv[2],"w").write(s.replace(sys.argv[3],sys.argv[4],1))
PY
}
mkgd; delfn get_phase_name; commit
mut 'if refs:
            dangling.append((ext, name, path, refs))' 'if False:
            dangling.append((ext, name, path, refs))'
ok "M1 MUTANT (references ignored): the live incident is no longer reported" '[ -z "$(CHECKER="$T/mut.py" dr)" ]'
mkgd; delfn get_phase_name; printf '\n## Returns a human-readable name for the current phase.\nfunc get_phase_name() -> String:\n\treturn "x"\n' >> "$R/scripts/tm.gd"; commit
mut 'if still_defined(repo, after, ext, name):
            continue' 'if False:
            continue'
ok "M2 MUTANT (still-defined check dropped): a moved function is wrongly reported" '[ -n "$(CHECKER="$T/mut.py" dr)" ]'
mkgd; delfn get_phase_name; commit
mut 'if text.lstrip().startswith("#"):
            continue
        refs.append' 'if False:
            continue
        refs.append'
printf '' >/dev/null
mkgd; delfn get_phase_name; sed -i.bak 's/get_phase_name(),/"x",/' "$R/scripts/tm.gd"; rm -f "$R/scripts/tm.gd.bak"; printf '# get_phase_name used to live here\n' >> "$R/scripts/tm.gd"; commit
ok "M3 MUTANT (comment filter dropped): a comment-only mention is wrongly reported" '[ -n "$(CHECKER="$T/mut.py" dr)" ]'

echo "dangling-refs: $P passed, $F failed"
[ "$F" -eq 0 ]
