#!/usr/bin/env python3
"""scripts/ovn_mutation_supply.py scan under `timeout` (qacov B8, 2026-10-10): the scan extracts a `git archive` of the repo into a scratch dir (mutscan-*, ~30 MB for
xlite). The nightly cron wraps it in `timeout`, which sends SIGTERM; Python's default SIGTERM action skips `finally`, so the scratch archive used to be left behind on every
timeout. The scan now turns SIGTERM/SIGHUP into SystemExit so its finally removes the scratch dir.

Handshake, no sleeps for sync: a shim `godot` writes a marker file when the first GUT run starts (the scan is then provably inside scan() with the scratch archive on disk) and
waits on a pipe; the test signals the scan and waits for it to exit. The shim's own process group is killed at the end. A MUTANT of the tool without the signal handlers must
leave the scratch dir behind (proving the check bites). TMPDIR is private to the test so nothing else's mutscan-* dirs are counted."""
import glob
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
TOOL = os.path.join(ROOT, "scripts", "ovn_mutation_supply.py")
P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:300]) if extra else ""))


def sh(*a, cwd=None):
    return subprocess.run(a, cwd=cwd, capture_output=True, text=True)


T = os.path.realpath(tempfile.mkdtemp(prefix="mutterm-"))
try:
    origin = os.path.join(T, "origin.git")
    clone = os.path.join(T, "ovn", "repos", "xlite")
    os.makedirs(os.path.dirname(clone))
    sh("git", "init", "-q", "--bare", origin)
    sh("git", "clone", "-q", origin, clone)
    for rel, txt in (("project.godot", 'config/name="XLite"\n'),
                     ("scripts/units/a.gd", "class_name A\nstatic func f(x, y):\n\tif x < y:\n\t\treturn 1\n\treturn 0\n"),
                     ("tests/test_a.gd", "extends GutTest\nfunc test_f():\n\tassert_eq(A.f(1, 2), 1)\n")):
        p = os.path.join(clone, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, "w").write(txt)
    g = ["git", "-c", "user.name=t", "-c", "user.email=t@t"]
    sh(*g, "add", "-A", cwd=clone)
    sh(*g, "commit", "-q", "-m", "init", cwd=clone)
    started = os.path.join(T, "started")
    pidfile = os.path.join(T, "shim.pid")
    gate = os.path.join(T, "gate.fifo")
    os.mkfifo(gate)
    shim = os.path.join(T, "godot_shim")
    open(shim, "w").write('#!/bin/sh\ncase "$*" in *--import*) exit 0;; esac\necho $$ > "%s"\n: > "%s"\nread _x < "%s"\nexit 0\n' % (pidfile, started, gate))
    os.chmod(shim, 0o755)
    tmpdir = os.path.join(T, "tmp")
    os.makedirs(tmpdir)

    def scratch():
        return sorted(glob.glob(os.path.join(tmpdir, "mutscan-*")))

    def scan_and_signal(tool, sig):
        for f in (started, pidfile):
            if os.path.exists(f):
                os.remove(f)
        env = dict(os.environ, OVN_DIR=os.path.join(T, "ovn"), OVN_GODOT_BIN=shim, TMPDIR=tmpdir, OVN_MUT_TIMEOUT="60")
        env.pop("OVN_MUT_REF", None)
        p = subprocess.Popen([sys.executable, tool, "scan", clone, "--max-mutants", "3"], env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        t0 = time.time()
        while not os.path.exists(started) and p.poll() is None and time.time() - t0 < 60:
            time.sleep(0.05)
        before = scratch()
        alive = p.poll() is None
        if alive:
            os.kill(p.pid, sig)
        try:
            out, _ = p.communicate(timeout=60)
        except subprocess.TimeoutExpired:
            p.kill()
            out, _ = p.communicate()
        # the shim (own session) is still waiting on the fifo: release and reap it
        try:
            pid = int(open(pidfile).read().strip())
            os.killpg(pid, signal.SIGKILL)
        except (OSError, ValueError):
            pass
        return before, alive, p.returncode, out

    before, alive, rc, out = scan_and_signal(TOOL, signal.SIGTERM)
    ok("precondition: the scan was inside scan() with its scratch archive on disk when signalled", alive and len(before) == 1, (alive, before, out))
    ok("SIGTERM: the scan exits with 128+15 (not killed by the default action)", rc == 128 + signal.SIGTERM, (rc, out))
    ok("SIGTERM: the scratch archive (mutscan-*) is removed", scratch() == [], scratch())
    before, alive, rc, out = scan_and_signal(TOOL, signal.SIGHUP)
    ok("SIGHUP: handled the same way (exit 128+1, scratch removed)", alive and rc == 128 + signal.SIGHUP and scratch() == [], (alive, rc, scratch()))

    # mutant: the handler installation is turned into a no-op -> the default SIGTERM action leaves the scratch dir behind
    mut = os.path.join(T, "ovn_mutation_supply_mut.py")
    src = open(TOOL).read()
    anchor = "signal.signal(_sig, lambda n, f: sys.exit(128 + n))"
    ok("mutation anchor exists exactly once in the tool", src.count(anchor) == 1)
    open(mut, "w").write(src.replace(anchor, "pass"))
    before, alive, rc, out = scan_and_signal(mut, signal.SIGTERM)
    ok("MUTANT (no handlers): killed by the default SIGTERM action (rc -15) and the scratch dir is LEFT BEHIND - the checks above bite",
       alive and rc == -signal.SIGTERM and len(scratch()) == 1, (alive, rc, scratch()))
    for d in scratch():
        shutil.rmtree(d, ignore_errors=True)
finally:
    shutil.rmtree(T, ignore_errors=True)
print("  %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
