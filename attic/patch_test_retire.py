#!/usr/bin/env python3
"""Add a <repo>/-prefix-tolerance regression case to test_helpers.py::test_retire."""
p = "scripts/test/test_helpers.py"
s = open(p).read()
if "prefix-tolerant" in s:
    print("already patched"); raise SystemExit
# 1) create a real file reachable only after stripping a leading repo-name component
a1 = 'open(os.path.join(d, "real.py"), "w").write("x = 1\\n")  # a file that exists\n'
a1n = a1 + '        os.makedirs(os.path.join(d, "pkgdir"), exist_ok=True)\n        open(os.path.join(d, "pkgdir", "mod.py"), "w").write("y = 1\\n")\n'
assert s.count(a1) == 1, "anchor1 not found"
s = s.replace(a1, a1n, 1)
# 2) add a prefixed item line to the progress fixture (kept: prefix-tolerant existence)
a2 = '            "- [ ] (human/Claude) do a big multi-file thing.\\n"\n'
a2n = '            "- [ ] [T2] `myrepo/pkgdir/mod.py` — do X. One file.\\n"  # <repo>/ prefix, file exists as pkgdir/mod.py -> KEEP\n' + a2
assert s.count(a2) == 1, "anchor2 not found"
s = s.replace(a2, a2n, 1)
# 3) assert it is kept (prefix-tolerant, not retired as dead-path)
a3 = '        ok("retire keeps valid item", "- [ ] [HIGH] `real.py`" in body)\n'
a3n = a3 + '        ok("retire prefix-tolerant keep", "- [ ] [T2] `myrepo/pkgdir/mod.py`" in body, body)\n'
assert s.count(a3) == 1, "anchor3 not found"
s = s.replace(a3, a3n, 1)
open(p, "w").write(s)
print("patched test_retire with prefix-tolerant case")
