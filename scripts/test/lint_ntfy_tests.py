#!/usr/bin/env python3
"""lint_ntfy_tests.py DIR - fail (exit 1, one 'file:line: why' per violation) when a test in DIR can post to the LIVE notification channel.

2026-11-02 (N4): the suite leaked real urgent pushes ('t' / 'm') to Mark's phone because a python test called push_emergency() against the live relay
(127.0.0.1:8099) and ntfy_guard.sh only swallowed curl-to-ntfy.sh. The guard now exports NTFY_SERVER=http://127.0.0.1:9 (closed port) + OVN_NOTIFY_DISABLE=1; this lint keeps tests from
walking around it:
  R1  a test assigns / defaults NTFY_SERVER to the live relay (127.0.0.1:8099, localhost:8099) or to ntfy.sh (e.g. NTFY_SERVER="${NTFY_SERVER:-http://127.0.0.1:8099}")
  R2  a python test calls push_emergency( / forward( without any of NTFY_SERVER / OVN_NOTIFY_DISABLE / OVN_NOTIFY_UPSTREAM / urlopen / monkeypatch in the same file (it would use the module default)
  R3  a runner (run_all.sh, ../cov/run_coverage.sh) does not source ntfy_guard.sh, or ntfy_guard.sh stops exporting the closed-port NTFY_SERVER / OVN_NOTIFY_DISABLE
  --scripts ROOT   N5 audit of the pipeline scripts themselves (no NTFY_SERVER default of ntfy.sh)
A line carrying the marker `ntfy-lint: allow` is exempt (assertions ABOUT a cron line, fixtures). Comment-only lines are ignored.
"""
import os
import re
import sys

R1 = re.compile(r"""NTFY_SERVER\W{0,4}(?:[:\-=]|\bin\b).{0,40}?(?:127\.0\.0\.1:8099|localhost:8099|https?://ntfy\.sh)""")
R2_CALL = re.compile(r"\b(?:push_emergency|forward)\(")
R2_SAFE = re.compile(r"NTFY_SERVER|OVN_NOTIFY_DISABLE|OVN_NOTIFY_UPSTREAM|urlopen|monkeypatch")


def lint(d):
    out = []
    names = sorted(n for n in os.listdir(d) if re.match(r"(test_.*|lib_.*)\.(sh|py)$", n))
    for n in names:
        if n == "test_ntfy_lint.sh":
            continue    # this lint's own test builds violating fixtures on purpose
        p = os.path.join(d, n)
        try:
            lines = open(p, errors="replace").read().split("\n")
        except OSError:
            continue
        text = "\n".join(l for l in lines if not l.lstrip().startswith("#"))
        for i, l in enumerate(lines, 1):
            if l.lstrip().startswith("#") or "ntfy-lint: allow" in l:
                continue
            if R1.search(l):
                out.append("%s:%d: NTFY_SERVER set/defaulted to the LIVE relay or ntfy.sh (use http://127.0.0.1:9 or a stub): %s" % (n, i, l.strip()[:100]))
        if n.endswith(".py") and R2_CALL.search(text) and not R2_SAFE.search(text):
            out.append("%s:1: calls push_emergency()/forward() with no NTFY_SERVER / OVN_NOTIFY_DISABLE / OVN_NOTIFY_UPSTREAM / stub in the file" % n)
    guard = os.path.join(d, "ntfy_guard.sh")
    g = open(guard, errors="replace").read() if os.path.exists(guard) else ""
    g_code = "\n".join(l for l in g.split("\n") if not l.lstrip().startswith("#"))
    if not re.search(r'^export NTFY_SERVER="?http://127\.0\.0\.1:9"?\s*$', g_code, re.M):
        out.append("ntfy_guard.sh:1: does not export NTFY_SERVER=http://127.0.0.1:9 (closed port)")
    if not re.search(r"^export OVN_NOTIFY_DISABLE=1\s*$", g_code, re.M):
        out.append("ntfy_guard.sh:1: does not export OVN_NOTIFY_DISABLE=1")
    if "*127.0.0.1:8099*" not in g_code:
        out.append("ntfy_guard.sh:1: the curl wrapper does not swallow the LIVE relay (127.0.0.1:8099), the scripts' fail-closed default")
    for rel in ("run_all.sh", os.path.join("..", "cov", "run_coverage.sh")):
        rp = os.path.join(d, rel)
        if os.path.exists(rp) and "ntfy_guard.sh" not in open(rp, errors="replace").read():
            out.append("%s:1: runner does not source ntfy_guard.sh" % rel)
    return out


FALLBACK = re.compile(r"""NTFY_SERVER(?::-|["']?\s*,\s*)\s*["']?https?://ntfy\.sh""")
SKIP_DIRS = ("attic", "test", "fleet_review", "__pycache__", "proposals")
# 2026-11-03 (S1, suite.json F2): on the box the queue root also holds product clones (repos/), snapshots/scratch (state/, logs/, prework, worktrees) and dependency trees. They are
# not pipeline scripts (repos/iptv_apps/scripts/daily-verify.sh is a product-repo line) and must not fail the audit. Pruned at the TOP level of the root ONLY, so a legitimately named
# nested dir (scripts/state/..., ops/repos/...) is still linted.
TOP_PRUNE = ("repos", "state", "logs", "prework", "worktrees", "node_modules", ".git")


def lint_scripts(root):
    """N5 audit: no pipeline script may default NTFY_SERVER to ntfy.sh (a direct publish bypasses the relay's DROP/dedupe/caps). The default is the relay (http://127.0.0.1:8099)
    or nothing. A line with `ntfy-lint: allow` is exempt (the box dead-man's DELIBERATE second channel lives in box_deadman.py and does not use this pattern)."""
    out = []
    root_real = os.path.realpath(root)
    for dp, dns, fns in os.walk(root):
        top = os.path.realpath(dp) == root_real
        dns[:] = [d for d in dns if d not in SKIP_DIRS and not d.startswith("proposals") and not (top and d in TOP_PRUNE)]
        for fn in sorted(fns):
            if not fn.endswith((".sh", ".py")):
                continue
            p = os.path.join(dp, fn)
            try:
                lines = open(p, errors="replace").read().split("\n")
            except OSError:
                continue
            for i, l in enumerate(lines, 1):
                if l.lstrip().startswith("#") or "ntfy-lint: allow" in l:
                    continue
                if FALLBACK.search(l):
                    out.append("%s:%d: NTFY_SERVER defaults to ntfy.sh (bypasses the relay): %s" % (os.path.relpath(p, root), i, l.strip()[:90]))
    return out


if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "--scripts":
        v = lint_scripts(sys.argv[2])
        print("\n".join(v))
        sys.exit(1 if v else 0)
    v = lint(sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__)))
    print("\n".join(v))
    sys.exit(1 if v else 0)
