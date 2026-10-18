#!/usr/bin/env python3
"""lint_bypass_check.py <lint_unsafe_rm.py> <scratch dir> : runs the lint (as a separate process, like a real run) on every sample of lint_bypass_cases.py.
FLAG samples must exit 1, PASS samples must exit 0. Prints one line per failure and 'bypass cases: N passed, M failed'; exit 1 when any failed. Writes only under <scratch dir>."""
import os, subprocess, sys
here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, here)
import lint_bypass_cases as C
lint, scratch = sys.argv[1], sys.argv[2]
if not os.path.isdir(scratch):
    sys.exit("scratch dir missing")
p = f = 0
for kind, cases in (("FLAG", C.FLAG), ("PASS", C.PASS)):
    for n, (name, fname, content) in enumerate(cases):
        d = os.path.join(scratch, "%s_%03d" % (kind.lower(), n))
        os.makedirs(d)
        body = ("#!/usr/bin/env bash\n" + content + "\n") if fname.endswith(".sh") else content
        with open(os.path.join(d, fname), "w") as fh:
            fh.write(body)
        r = subprocess.run([sys.executable, "-I", lint, d], capture_output=True, text=True)
        want = 1 if kind == "FLAG" else 0
        if r.returncode == want:
            p += 1
        else:
            f += 1
            print("  FAIL %s %s: lint rc=%d (wanted %d)  %s" % (kind, name, r.returncode, want, r.stdout.strip().split("\n")[0][:160]))
print("bypass cases: %d passed, %d failed" % (p, f))
sys.exit(1 if f else 0)
