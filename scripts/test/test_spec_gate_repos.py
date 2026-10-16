#!/usr/bin/env python3
"""ovn_spec_gate.py: the scan repo list is configurable (spec-intake-5-lanes, 2026-10-13).

The crontab hard-codes `for r in iptv_apps xlite; do ... scan $r`, so the 5 lanes enabled 10-13 (TAA, shrike-notify, shrike-monitor, billwatch, gitlark) never got a spec verdict.
OVN_SPEC_GATE_REPOS widens what `scan-all` / `scan` (no repo) / `repos` cover; the DEFAULT stays iptv_apps + xlite; `scan <repo>` is unchanged. Runs against a temp OVN_DIR that is PAUSED, so
no git, no worktree and no backlog is touched."""
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
GATE = os.path.join(ROOT, "scripts", "ovn_spec_gate.py")
P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:300]) if extra else ""))


od = tempfile.mkdtemp(prefix="gate-repos-")
os.makedirs(os.path.join(od, "state"))
open(os.path.join(od, "state", "PAUSED"), "w").write("")


def gate(args, **env):
    e = {k: v for k, v in os.environ.items() if not k.startswith("OVN_")}
    e["OVN_DIR"] = od
    e.update(env)
    r = subprocess.run([sys.executable, GATE] + args, capture_output=True, text=True, env=e)
    return r.returncode, r.stdout, r.stderr


def scanned(out):
    return [l.split(":")[0].split()[-1] for l in out.split("\n") if l.startswith("spec_gate scan ")]


print("== default list is UNCHANGED")
rc, out, _ = gate(["repos"])
ok("`repos` default = iptv_apps xlite", rc == 0 and out.split() == ["iptv_apps", "xlite"], out)
rc, out, _ = gate(["scan-all"])
ok("`scan-all` default scans exactly iptv_apps then xlite", rc == 0 and scanned(out) == ["iptv_apps", "xlite"], out)
rc, out, _ = gate(["scan"])
ok("`scan` with no repo = scan-all", rc == 0 and scanned(out) == ["iptv_apps", "xlite"], out)
rc, out, _ = gate(["repos"], OVN_SPEC_GATE_REPOS="")
ok("an empty OVN_SPEC_GATE_REPOS falls back to the default", out.split() == ["iptv_apps", "xlite"], out)

print("== OVN_SPEC_GATE_REPOS widens it")
W = "iptv_apps xlite billwatch gitlark shrike-monitor shrike-notify test-automation-agent"
rc, out, _ = gate(["repos"], OVN_SPEC_GATE_REPOS=W)
ok("`repos` lists the configured repos in order", out.split() == W.split(), out)
rc, out, _ = gate(["scan-all"], OVN_SPEC_GATE_REPOS=W)
ok("`scan-all` scans every configured repo in order", rc == 0 and scanned(out) == W.split(), out)
rc, out, _ = gate(["scan"], OVN_SPEC_GATE_REPOS=W.replace(" ", ","))
ok("comma separated works too", scanned(out) == W.split(), out)
rc, out, _ = gate(["repos"], OVN_SPEC_GATE_REPOS="xlite, xlite ,billwatch")
ok("duplicates are dropped, order kept", out.split() == ["xlite", "billwatch"], out)
rc, out, _ = gate(["repos"], OVN_SPEC_GATE_REPOS="billwatch ../etc /abs a/b ;rm $(id) -x gitlark")
ok("names that are not plain repo names are dropped (no path traversal into backlog/<name>.md)", out.split() == ["billwatch", "gitlark"], out)
rc, out, _ = gate(["repos"], OVN_SPEC_GATE_REPOS="../etc /abs")
ok("nothing valid left -> the default", out.split() == ["iptv_apps", "xlite"], out)
rc, out, _ = gate(["scan", "gitlark"], OVN_SPEC_GATE_REPOS=W)
ok("`scan <repo>` is unchanged: exactly that one repo, whatever the list says", scanned(out) == ["gitlark"], out)

print("== kill switch still applies to every repo")
rc, out, err = gate(["scan-all"], OVN_SPEC_GATE_REPOS="billwatch gitlark", OVN_SPEC_GATE="off")
ok("OVN_SPEC_GATE=off: every repo says so, exit 0", rc == 0 and scanned(out) == ["billwatch", "gitlark"], (out, err))

shutil.rmtree(od, ignore_errors=True)
print("\nspec gate repos: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
