#!/usr/bin/env python3
"""REPAIR 2 (d): the baseline gate said 'no baseline for repo - not guessing' for billwatch / test-automation-agent / gitlark because the box cron's
OVN_BASELINE_REFRESH_REPOS covered only 'iptv_apps xlite'. Pins (1) the PROPOSED cron line in ops/cron.baseline.proposed.txt covers every repo the gate
should have a baseline for, with the slow iptv suite LAST (it hits the 900s per-repo timeout and would eat the 3300s total budget before the others run),
and (2) that qa/baseline_refresh_cron.sh really stores a baseline for each of those repos' LAYOUTS (billwatch-backend/.venv, gitlark backend/.venv,
test-automation-agent backend/.venv next to a decoy backend/venv that exits 9: if it were picked the refresh would not be PASS), run as cron does (relative script path, env -i). Stub pytest, no network, no ntfy."""
import json, os, re, shutil, stat, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
OQ = os.path.abspath(os.path.join(HERE, "..", ".."))
PROPOSAL = os.path.join(OQ, "ops", "cron.baseline.proposed.txt")
P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:600]) if extra else ""))


NEED = ["billwatch", "gitlark", "test-automation-agent", "iptv_apps", "xlite"]
lines = [l for l in open(PROPOSAL).read().splitlines() if l.strip() and not l.lstrip().startswith("#")]
cron = [l for l in lines if "baseline_refresh_cron.sh" in l]
ok("proposal has exactly one active baseline_refresh line", len(cron) == 1, cron)
m = re.search(r'OVN_BASELINE_REFRESH_REPOS="([^"]*)"', cron[0]) if cron else None
repos = m.group(1).split() if m else []
ok("proposal covers billwatch, gitlark, test-automation-agent, iptv_apps and xlite", sorted(repos) == sorted(NEED), repos)
ok("slow iptv_apps suite runs LAST so it cannot starve the others of the shared budget", repos[-1:] == ["iptv_apps"], repos)
ok("proposal is a valid 5-field cron line calling the deployed script path with the relay NTFY_SERVER",
   cron and re.match(r"^11 \*/3 \* \* \* ", cron[0]) and "/home/mhintermeister/overnight-queue/qa/baseline_refresh_cron.sh" in cron[0]
   and "NTFY_SERVER=http://127.0.0.1:8099" in cron[0], cron)
live = open(os.path.join(OQ, "ops", "crontab.box.snapshot.txt")).read()
ok("the live snapshot still has the old 2-repo line (proposal is a delta for the lead to apply, nothing silently changed)",
   'OVN_BASELINE_REFRESH_REPOS="iptv_apps xlite"' in live)

T = os.path.realpath(tempfile.mkdtemp(prefix="qa-blrepos-test-"))
try:
    OVN = os.path.join(T, "ovn")
    for d in ("qa", "state", "logs", "repos"):
        os.makedirs(os.path.join(OVN, d))
    for f in ("qa_common.py", "baseline_verify.py", "qa_timeout.py", "baseline_refresh_cron.sh"):
        shutil.copy(os.path.join(OQ, "qa", f), os.path.join(OVN, "qa", f))
    os.chmod(os.path.join(OVN, "qa", "baseline_refresh_cron.sh"), 0o755)
    env0 = {"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t", "PATH": os.environ["PATH"]}

    def git(d, *a):
        return subprocess.run(["git", "-C", d] + list(a), capture_output=True, text=True, env=env0)

    STUB = "#!/bin/sh\n[ -f red.txt ] && cat red.txt\necho '3 passed in 0.1s'\n"

    def mkclone(name, pkg, red=None, decoy=None):
        d = os.path.join(OVN, "repos", name)
        os.makedirs(os.path.join(d, pkg))
        git(d, "init", "-q", "-b", "develop")
        open(os.path.join(d, pkg, "pyproject.toml"), "w").write("[x]\n")
        if red:
            open(os.path.join(d, pkg, "red.txt"), "w").write(red)
        git(d, "add", "-A"); git(d, "-c", "commit.gpgsign=false", "commit", "-q", "-m", "base")
        git(d, "update-ref", "refs/remotes/origin/develop", "HEAD")
        # venvs are untracked (gitignored in the real clones): the refresh finds the clone's .venv and runs it with cwd = the worktree's package dir
        for v in [".venv"] + ([decoy] if decoy else []):
            b = os.path.join(d, pkg, v, "bin")
            os.makedirs(b)
            if v == ".venv":
                open(os.path.join(b, "pytest"), "w").write(STUB)
                os.chmod(os.path.join(b, "pytest"), 0o755)
            else:
                open(os.path.join(b, "pytest"), "w").write("#!/bin/sh\necho decoy-venv-used; exit 9\n")
                os.chmod(os.path.join(b, "pytest"), 0o755)
        return d

    FAILLINE = "FAILED tests/test_x.py::test_red - AssertionError\n=== 1 failed, 3 passed in 0.1s ===\n"
    mkclone("billwatch", "billwatch-backend")
    mkclone("gitlark", "backend", red=FAILLINE)
    mkclone("test-automation-agent", "backend", decoy="venv")
    env = {"PATH": "/usr/bin:/bin:/usr/local/bin:" + os.path.dirname(shutil.which("git")), "HOME": T, "NTFY_SERVER": "http://127.0.0.1:9", "LANG": "C.UTF-8",
           "OVN_BASELINE_REFRESH_REPOS": "billwatch gitlark test-automation-agent", "OVN_BASELINE_REPO_TIMEOUT": "60"}
    p = subprocess.run(["env", "-i"] + ["%s=%s" % kv for kv in env.items()] + ["bash", "qa/baseline_refresh_cron.sh"],
                       cwd=OVN, capture_output=True, text=True, timeout=300)
    ok("cron script exits 0", p.returncode == 0, p.stderr[-300:])
    log = open(os.path.join(OVN, "logs", "baseline_refresh.log")).read()
    for r, n in (("billwatch", 0), ("gitlark", 1), ("test-automation-agent", 0)):
        ok("%s: refresh logs PASS 'refreshed baseline' with %d red ids" % (r, n), re.search(r"%s: PASS \| refreshed baseline \S+ \(%d red ids\)" % (re.escape(r), n), log) is not None, log)
        path = os.path.join(OVN, "state", "qa_baselines", "verify", r + ".json")
        ok("%s: a baseline file now exists (the gate no longer says 'no baseline for repo')" % r, os.path.isfile(path))
    bl = json.load(open(os.path.join(OVN, "state", "qa_baselines", "verify", "gitlark.json")))
    ok("gitlark: the red id is stored under the package prefix '[backend] '", any(i.startswith("[backend] ") for i in bl.get("failing", [])), bl.get("failing"))
finally:
    shutil.rmtree(T, ignore_errors=True)

print("\nbaseline refresh repos: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
