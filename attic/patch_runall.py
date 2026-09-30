#!/usr/bin/env python3
p = "scripts/test/run_all.sh"
s = open(p).read()
if "test_tsc_gate.sh" in s:
    print("already wired"); raise SystemExit
anchor = 'echo; [ $rc -eq 0 ]'
assert s.count(anchor) == 1, f"anchor count={s.count(anchor)}"
add = (
    'echo; echo "===== TS ratchet gate ====="; bash test_tsc_gate.sh || rc=1\n'
    'echo; echo "===== Queue refill ====="; bash test_queue_refill.sh || rc=1\n'
)
open(p, "w").write(s.replace(anchor, add + anchor, 1))
print("wired 2 tests into run_all.sh")
