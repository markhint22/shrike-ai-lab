#!/usr/bin/env python3
p = "scripts/test/run_all.sh"
s = open(p).read()
if "test_reconcile_branches.sh" in s:
    print("already wired"); raise SystemExit
anchor = 'echo; [ $rc -eq 0 ]'
assert s.count(anchor) == 1, f"anchor count={s.count(anchor)}"
add = 'echo; echo "===== Branch reconcile guard ====="; bash test_reconcile_branches.sh || rc=1\n'
open(p, "w").write(s.replace(anchor, add + anchor, 1))
print("wired test_reconcile_branches into run_all.sh")
