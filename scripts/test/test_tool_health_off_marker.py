#!/usr/bin/env python3
"""P6b (2026-10-27): qa/qa_tool_health.py must read a crontab line that the box wrote as `#OFF# <schedule> <cmd>` (preceded by `# id: <name> (off by default; ...)`) as DECLARED OFF
(info / NA), not as a missing live line, and must not demand the contract-fuzz baseline for a gate whose cron is off. Before: 2 permanent findings (cron:contract_fuzz_cron.sh and
state:contract_fuzz_baseline_*), re-flagged by every run. A crontab with NO line for the job (no marker) must still flag it. Fixtures under $TQH_TMP (test_tool_health_off_marker.sh)."""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SCRIPT = os.path.join(ROOT, "qa", "qa_tool_health.py")
TMP = os.environ.get("TQH_TMP", "")
if not TMP or not os.path.isdir(TMP) or os.path.realpath(TMP) in ("/", os.path.realpath(os.path.expanduser("~"))):
    print("TQH_TMP missing/unsafe: run via test_tool_health_off_marker.sh")
    sys.exit(2)
TOOLS = ["bandit", "semgrep", "gitleaks", "pip-audit", "mutmut", "schemathesis", "mypy", "ruff", "docker", "flock"]
REPOS = ["billwatch", "gitlark", "iptv_apps"]
JOBS = ["qa_ledger_cron.sh", "manual_notes_cron.sh", "qa_daily_shadow.sh", "baseline_refresh_cron.sh", "qa_block_watch.py", "staging_e2e_run.sh",
        "staging_e2e_ingest.py", "evidence_freshness_check.py", "contract_fuzz_cron.sh", "qa_tool_health.py"]
FUZZ_LINE = "20 4 * * * cd $HOME/overnight-queue && bash qa/contract_fuzz_cron.sh >> logs/contract_fuzz.log 2>&1"
P = F = 0
_n = [0]


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + (" :: " + str(extra)[:500] if extra else ""))


def build(label, fuzz_block, baseline=True, extra_lines=()):
    _n[0] += 1
    case = os.path.join(TMP, "%02d-%s" % (_n[0], label))
    ovn, home = os.path.join(case, "ovn"), os.path.join(case, "home")
    state = os.path.join(ovn, "state")
    for d in (home, os.path.join(state, "qa_shadow"), os.path.join(state, "qa_creds"), os.path.join(case, "emptybin"), os.path.join(ovn, "qa-tools", ".venv", "bin")):
        os.makedirs(d, exist_ok=True)
    for t in TOOLS:
        p = os.path.join(ovn, "qa-tools", ".venv", "bin", t)
        with open(p, "w") as f:
            f.write("#!/bin/sh\nexit 0\n")
        os.chmod(p, 0o755)
    for r in REPOS:
        with open(os.path.join(state, "staging_url_" + r), "w") as f:
            f.write("https://%s-staging.up.railway.app\n" % r)
    cp = os.path.join(state, "qa_creds", "iptv_apps.json")
    with open(cp, "w") as f:
        json.dump({"email": "a@b.c", "password": "x"}, f)
    os.chmod(cp, 0o600)
    if baseline:
        with open(os.path.join(state, "qa_shadow", "contract_fuzz_baseline_iptv_apps.json"), "w") as f:
            f.write("{}")
    cron = os.path.join(case, "crontab.txt")
    with open(cron, "w") as f:
        for j in JOBS:
            if j != "contract_fuzz_cron.sh":
                f.write("5 * * * * cd ~/overnight-queue && bash qa/%s >> logs/x.log 2>&1\n" % j)
        f.write(fuzz_block)
        for x in extra_lines:
            f.write(x + "\n")
    return {"ovn": ovn, "cron": cron, "home": home, "case": case}


def run(w):
    env = {"PATH": os.path.join(w["case"], "emptybin"), "HOME": w["home"], "OVN_DIR": w["ovn"], "OVN_QA_CRONTAB_FILE": w["cron"], "PYTHONDONTWRITEBYTECODE": "1"}
    r = subprocess.run([sys.executable, SCRIPT], env=env, capture_output=True, text=True, timeout=120)
    try:
        return json.loads(r.stdout.strip().splitlines()[-1])
    except (ValueError, IndexError):
        return {"verdict": "NOJSON", "details": {}, "summary": r.stdout + r.stderr}


def fnd(r):
    return r.get("details", {}).get("findings", [])


HDR = "# id: contract_fuzz (off by default; --enable contract_fuzz to turn on, --disable to turn off)\n"

r = run(build("off-with-header", HDR + "#OFF# " + FUZZ_LINE + "\n", baseline=False))
ok("#OFF# line + header, baseline missing -> no findings, verdict PASS (old: 2 FLAG findings)", fnd(r) == [] and r["verdict"] == "PASS", (r["verdict"], fnd(r)))
ok("declared-off job is reported as INFO in details and the summary", "contract_fuzz_cron.sh" in json.dumps(r["details"].get("declared_off", [])) and "declared off" in r["summary"], (r["details"].get("declared_off"), r["summary"]))

r = run(build("off-no-header", "#OFF# " + FUZZ_LINE + "\n", baseline=False))
ok("a bare #OFF# line (no header) is declared off too", fnd(r) == [], fnd(r))

r = run(build("header-only", HDR + "# nothing else follows\n", baseline=False))
ok("the '# id: contract_fuzz (off by default' header alone declares it off (cron + baseline)", fnd(r) == [], fnd(r))

r = run(build("absent", "", baseline=False))
ok("MUTATION PROOF: no contract_fuzz line at all and no marker -> cron finding still raised", "cron:contract_fuzz_cron.sh" in fnd(r), fnd(r))
ok("MUTATION PROOF: no marker -> the missing baseline is still raised", "state:contract_fuzz_baseline_iptv_apps" in fnd(r), fnd(r))
ok("no marker -> verdict FLAG", r["verdict"] == "FLAG", r["verdict"])

r = run(build("other-off", "", baseline=False, extra_lines=["# id: card_pilot (off by default; --enable card_pilot)", "#OFF# 35 3 * * * cd $HOME/overnight-queue && python3 qa/card_pilot_run.py run >> logs/card_pilot.log 2>&1"]))
ok("an #OFF# line for a DIFFERENT job does not hide the fuzz findings", "cron:contract_fuzz_cron.sh" in fnd(r) and "state:contract_fuzz_baseline_iptv_apps" in fnd(r), fnd(r))

r = run(build("mid-line", "# note: 20 4 * * * bash qa/contract_fuzz_cron.sh #OFF# disabled\n", baseline=False))
ok("#OFF# in the middle of a comment is not a marker", "cron:contract_fuzz_cron.sh" in fnd(r), fnd(r))

r = run(build("live-and-off", FUZZ_LINE + "\n", baseline=False, extra_lines=["#OFF# " + FUZZ_LINE]))
ok("live line wins over a stale #OFF# copy: not off, baseline missing still flagged, no cron finding", "cron:contract_fuzz_cron.sh" not in fnd(r) and "state:contract_fuzz_baseline_iptv_apps" in fnd(r), fnd(r))

r = run(build("live", FUZZ_LINE + "\n", baseline=True))
ok("healthy live cron + baseline -> PASS, nothing declared off", r["verdict"] == "PASS" and not r["details"].get("declared_off"), (r["verdict"], r["details"].get("declared_off")))

r = run(build("off-baseline-present", HDR + "#OFF# " + FUZZ_LINE + "\n", baseline=True))
ok("off cron with a baseline present is still clean", fnd(r) == [], fnd(r))

print("test_tool_health_off_marker: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
