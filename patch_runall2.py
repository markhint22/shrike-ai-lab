#!/usr/bin/env python3
p = "scripts/test/run_all.sh"
s = open(p).read()
if "test_retire_prefix.sh" in s:
    print("already wired"); raise SystemExit
anchor = 'echo; [ $rc -eq 0 ]'
assert s.count(anchor) == 1, f"anchor count={s.count(anchor)}"
add = 'echo; echo "===== Retire prefix-tolerance ====="; bash test_retire_prefix.sh || rc=1\n'
open(p, "w").write(s.replace(anchor, add + anchor, 1))
print("wired test_retire_prefix into run_all.sh")
