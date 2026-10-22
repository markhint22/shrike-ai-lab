#!/usr/bin/env bash
# test_churn_suffix_escalate.sh - P3(b): ovn_churn_guard names_file suffix normalisation + protected-item escalation after K reverts.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"; S="$(cd "$HERE/.." && pwd)"
P=0; F=0
eq(){ if [ "$2" = "$3" ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1 (got [$2] want [$3])"; fi; }
run(){ python3 -c "
import sys; sys.path.insert(0, sys.argv[1]); import ovn_churn_guard as g
exec(sys.stdin.read())
" "$S" 2>&1 | tail -1; }
eq "names_file: churner 'src/x.test.ts' vs item 'iptv-web/src/x.test.ts'" "$(run <<'E2'
print(g.names_file('- [ ] [T4] [EMERGENCY] iptv-web/src/x.test.ts - broken','src/x.test.ts'))
E2
)" "True"
eq "names_file: item 'pkg/src/x.test.ts'" "$(run <<'E2'
print(g.names_file('- [ ] [T4] pkg/src/x.test.ts - y','src/x.test.ts'))
E2
)" "True"
eq "BENIGN names_file: no dir boundary (xsrc/x.test.ts)" "$(run <<'E2'
print(g.names_file('- [ ] [T4] pkg/xsrc/x.test.ts - y','src/x.test.ts'))
E2
)" "False"
eq "BENIGN names_file: different file same dir" "$(run <<'E2'
print(g.names_file('- [ ] [T4] pkg/src/y.test.ts - y','src/x.test.ts'))
E2
)" "False"
esc(){ run <<E2
t='- [ ] [T4] [EMERGENCY] iptv-web/src/x.test.ts - broken\n- [ ] [T2] other.ts - z'.replace('\\\\n','\n')
new,esc=g.plan_escalation(t,[{'file':'src/x.test.ts','n':9,'revert_n':$1}],None,3)
print(len(esc), '[CLAUDE] [churn-escalated' in new, new.count('\n'))
E2
}
eq "escalate: protected item after K=3 reverts is tagged needs-Claude" "$(esc 3)" "1 True 1"
eq "BENIGN escalate: K not reached leaves item untouched" "$(esc 2)" "0 False 1"
eq "escalated line becomes ineligible (not re-picked)" "$(run <<'E2'
t='- [ ] [T4] [EMERGENCY] iptv-web/src/x.test.ts - broken'
new,esc=g.plan_escalation(t,[{'file':'src/x.test.ts','n':9,'revert_n':5}],None,3)
print(len(g.classify_lines(new)))
E2
)" "0"
eq "BENIGN: eligible (non-protected) lines are not touched by escalation" "$(run <<'E2'
t='- [ ] [T4] iptv-web/src/x.test.ts - broken'
new,esc=g.plan_escalation(t,[{'file':'src/x.test.ts','n':9,'revert_n':5}],None,3)
print(len(esc), new==t)
E2
)" "0 True"
eq "default mode is shadow" "$(run <<'E2'
print(g.PROTECTED_ESCALATE)
E2
)" "shadow"
eq "revert_count counts revert-ish subjects touching the file" "$(run <<'E2'
f=('a','b','M')
cs=[{'sha':'a','t':1,'s':'fix: revert foo','f':{'src/x.test.ts':f}},{'sha':'b','t':2,'s':'feat: add','f':{'src/x.test.ts':f}},{'sha':'c','t':3,'s':'drop helper','f':{'src/x.test.ts':f}},{'sha':'d','t':4,'s':'revert other','f':{'o.ts':f}}]
print(g.revert_count(cs,{'file':'src/x.test.ts'},0,10))
E2
)" "2"
eq "post-check only_tags_added accepts the escalation edit and rejects a foreign edit" "$(run <<'E2'
t='- [ ] [T4] [EMERGENCY] iptv-web/src/x.test.ts - broken'
new,esc=g.plan_escalation(t,[{'file':'src/x.test.ts','n':9,'revert_n':5}],None,3)
print(g.only_tags_added(t,new,1), g.only_tags_added(t,new.replace('broken','other'),1))
E2
)" "True False"
# --- review fixes (2026-10-21) ---
AL="$(safe_mktemp_dir)"
eq "names_file: suffix must NOT match a distinct tracked file (admin/src/index.ts vs src/index.ts)" "$(run <<'E2'
amb=g.AmbiguousSet({'index.ts'}); amb.tracked={'src/index.ts','admin/src/index.ts'}
print(g.names_file('- [ ] [T4] admin/src/index.ts - y','src/index.ts',amb), g.names_file('- [ ] [T4] src/index.ts - y','src/index.ts',amb))
E2
)" "False True"
eq "BENIGN names_file: suffix still matches when the prefixed path is NOT tracked" "$(run <<'E2'
amb=g.AmbiguousSet(); amb.tracked={'src/x.test.ts'}
print(g.names_file('- [ ] [T4] iptv-web/src/x.test.ts - y','src/x.test.ts',amb))
E2
)" "True"
eq "plan_escalation does not tag an item for the distinct file" "$(run <<'E2'
amb=g.AmbiguousSet({'index.ts'}); amb.tracked={'src/index.ts','admin/src/index.ts'}
t='- [ ] [T4] [EMERGENCY] admin/src/index.ts - broken'
new,esc=g.plan_escalation(t,[{'file':'src/index.ts','n':9,'revert_n':5}],amb,3)
print(len(esc), new==t)
E2
)" "0 True"
eq "add_tree_aliases returns tracked paths (real git)" "$(T="$AL" && { git init -q "$T/r" && mkdir -p "$T/r/src" "$T/r/admin/src" && : > "$T/r/src/index.ts" && : > "$T/r/admin/src/index.ts" && git -C "$T/r" add -A && git -C "$T/r" -c user.name=t -c user.email=t@t commit -q -m i && git -C "$T/r" update-ref refs/remotes/origin/overnight/feature HEAD && T="$T" run <<'E2'
import os
amb=g.add_tree_aliases(os.environ['T']+'/r',[{'file':'src/index.ts','n':3}])
print(sorted(amb.tracked), sorted(amb))
E2
})" "['admin/src/index.ts', 'src/index.ts'] ['index.ts']"
# enforce-mode end to end: apply_and_push(escalate=True) pushes exactly one OVERNIGHT_PROGRESS.md commit tagging the protected item
E2E="$(safe_mktemp_dir)"
git init -q --bare "$E2E/o.git"; git -C "$E2E/o.git" symbolic-ref HEAD refs/heads/overnight/feature
git clone -q "$E2E/o.git" "$E2E/c" 2>/dev/null; git -C "$E2E/c" checkout -q -b overnight/feature
printf '# P\n- [ ] [T4] [EMERGENCY] iptv-web/src/x.test.ts - broken\n- [ ] [T2] other.ts - z\n' > "$E2E/c/OVERNIGHT_PROGRESS.md"
git -C "$E2E/c" add -A; git -C "$E2E/c" -c user.name=t -c user.email=t@t commit -q -m init; git -C "$E2E/c" push -q origin overnight/feature 2>/dev/null
git -C "$E2E/c" fetch -q origin overnight/feature
BEFORE="$(git -C "$E2E/o.git" rev-list --count overnight/feature)"
eq "enforce apply_and_push(escalate=True) pushes the tag" "$(E2E="$E2E" run <<'E2'
import os
e=os.environ['E2E']
ok,parked=g.apply_and_push('r',e+'/c',[{'file':'src/x.test.ts','n':9,'revert_n':5}],5,None,escalate=True)
print(ok, sum(parked.values()))
E2
)" "True 0"
eq "enforce escalate: exactly one new commit, only the progress file, protected line tagged, other untouched" "$(
 echo "$(( $(git -C "$E2E/o.git" rev-list --count overnight/feature) - BEFORE ))" \
 "$(git -C "$E2E/o.git" diff --name-only overnight/feature~1 overnight/feature | tr '\n' ,)" \
 "$(git -C "$E2E/o.git" show overnight/feature:OVERNIGHT_PROGRESS.md | grep -c 'CLAUDE\] \[churn-escalated')" \
 "$(git -C "$E2E/o.git" show overnight/feature:OVERNIGHT_PROGRESS.md | grep -c '^- \[ \] \[T2\] other.ts')")" "1 OVERNIGHT_PROGRESS.md, 1 1"
# --- PKG-E: security-path shadow detector ---
eq "security_path_items flags auth/signature/secret paths, skips normal + already-CLAUDE" "$(run <<'E2'
t='\n'.join(['- [ ] [T3] app/services/webhook_signature.py - tidy','- [ ] [T2] app/utils/dates.py - tidy','- [ ] [CLAUDE] [T3] app/auth/jwt_token.py - x','- [x] [T3] app/secret_store.py - done','- [ ] [T3] src/auth.ts - y'])
print([p for _,p in g.security_path_items(t)])
E2
)" "['app/services/webhook_signature.py', 'src/auth.ts']"
eq "BENIGN security_path_items: 'author.py' style words do not match mid-word? (authors.py is flagged: documented over-flag, shadow only)" "$(run <<'E2'
print(len(g.security_path_items('- [ ] [T2] app/dates.py - z')))
E2
)" "0"
eq "SECURITY_PATH_ESCALATE defaults off" "$(run <<'E2'
print(g.SECURITY_PATH_ESCALATE)
E2
)" "off"
# --- review fixes (2026-10-22) ---
eq "revert_count ignores bookkeeping/stub-cleanup subjects (3x 'drop unfilled stub' -> 0)" "$(run <<'E2'
f=('a','b','M')
cs=[{'sha':str(i),'t':i,'s':s,'f':{'src/x.test.ts':f}} for i,s in enumerate(['chore: drop unfilled stub','chore(queue): drop unfilled stub','fix: drop unfilled stub src/x'],1)]
print(g.revert_count(cs,{'file':'src/x.test.ts'},0,10))
E2
)" "0"
eq "BENIGN revert_count still counts a real revert next to bookkeeping" "$(run <<'E2'
f=('a','b','M')
cs=[{'sha':'1','t':1,'s':'chore: drop unfilled stub','f':{'x.ts':f}},{'sha':'2','t':2,'s':'Revert \"feat: x\"','f':{'x.ts':f}}]
print(g.revert_count(cs,{'file':'x.ts'},0,10))
E2
)" "1"
SD="$(safe_mktemp_dir)"
eq "security shadow dedupe: first True, repeat same day False, new day True" "$(OVN_STATE_DIR="$SD" python3 -c "
import sys; sys.path.insert(0, sys.argv[1]); import ovn_churn_guard as g
print(g.security_shadow_new('r','a/auth.ts','d1'), g.security_shadow_new('r','a/auth.ts','d1'), g.security_shadow_new('r','a/auth.ts','d2'), g.security_shadow_new('r','b/auth.ts','d2'))
" "$S")" "True False True True"
safe_rm_rf "$SD" "$E2E" "$AL" /tmp/wt-churnguard-* 2>/dev/null || true
echo "test_churn_suffix_escalate: pass=$P fail=$F"
[ "$F" = 0 ]
