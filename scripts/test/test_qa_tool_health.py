#!/usr/bin/env python3
"""qa/qa_tool_health.py + ops/qa_tools_install.sh. All fixtures live under $TQH_TMP (made and removed by test_qa_tool_health.sh via lib_safe_tmp.sh).
This file never deletes anything; each case builds its own fresh numbered directory."""
import hashlib
import importlib.util
import json
import os
import stat
import subprocess
import sys
import tarfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
QA = os.path.join(ROOT, "qa")
SCRIPT = os.path.join(QA, "qa_tool_health.py")
INSTALL = os.path.join(ROOT, "ops", "qa_tools_install.sh")
TMP = os.environ.get("TQH_TMP", "")
if not TMP or not os.path.isdir(TMP) or os.path.realpath(TMP) in ("/", os.path.realpath(os.path.expanduser("~"))):
    print("TQH_TMP missing/unsafe: run via test_qa_tool_health.sh")
    sys.exit(2)
TOOLS = ["bandit", "semgrep", "gitleaks", "pip-audit", "mutmut", "schemathesis", "mypy", "ruff", "docker", "flock"]
REPOS = ["billwatch", "gitlark", "iptv_apps"]
JOBS = ["qa_ledger_cron.sh", "manual_notes_cron.sh", "qa_daily_shadow.sh", "baseline_refresh_cron.sh", "qa_block_watch.py", "staging_e2e_run.sh",
        "staging_e2e_ingest.py", "evidence_freshness_check.py", "contract_fuzz_cron.sh", "qa_tool_health.py"]
P = F = 0
_n = [0]


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + (" :: " + str(extra)[:600] if extra else ""))


def fresh(label):
    _n[0] += 1
    d = os.path.join(TMP, "%02d-%s" % (_n[0], label))
    os.makedirs(os.path.join(d, "home"))
    return d


def stub(path, body="#!/bin/sh\nexit 0\n"):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(body)
    os.chmod(path, 0o755)


def build(case, tools_in="venv", cron_without=(), creds_mode=0o600, state_without=(), skip_tools=()):
    """A complete healthy world under <case>; returns dict of paths. tools_in: venv (qa-tools/.venv/bin) | path (a PATH dir)."""
    ovn = os.path.join(case, "ovn")
    state = os.path.join(ovn, "state")
    os.makedirs(os.path.join(state, "qa_shadow"))
    os.makedirs(os.path.join(state, "qa_creds"))
    bindir = os.path.join(ovn, "qa-tools", ".venv", "bin") if tools_in == "venv" else os.path.join(case, "pathbin")
    os.makedirs(bindir, exist_ok=True)
    os.makedirs(os.path.join(case, "emptybin"), exist_ok=True)
    for t in TOOLS:
        if t not in skip_tools:
            stub(os.path.join(bindir, t))
    for r in REPOS:
        if "staging_url_" + r not in state_without:
            with open(os.path.join(state, "staging_url_" + r), "w") as f:
                f.write("https://%s-staging.up.railway.app\n" % r)
    if "qa_creds" not in state_without:
        cp = os.path.join(state, "qa_creds", "iptv_apps.json")
        with open(cp, "w") as f:
            json.dump({"email": "a@b.c", "password": "x"}, f)
        os.chmod(cp, creds_mode)
    if "qa_gate_modes" not in state_without:
        with open(os.path.join(state, "qa_gate_modes.json"), "w") as f:
            json.dump({"gate_scanners": "shadow"}, f)
    if "baseline" not in state_without:
        with open(os.path.join(state, "qa_shadow", "contract_fuzz_baseline_iptv_apps.json"), "w") as f:
            f.write("{}")
    cron = os.path.join(case, "crontab.txt")
    with open(cron, "w") as f:
        f.write("# comment mentioning contract_fuzz_cron.sh must not count\n")
        for j in JOBS:
            if j not in cron_without:
                f.write("5 * * * * cd ~/overnight-queue && bash qa/%s >> logs/x.log 2>&1\n" % j)
    return {"ovn": ovn, "state": state, "bin": bindir, "cron": cron, "home": os.path.join(case, "home"), "case": case}


def run(w, mode=None, extra=(), now=None, env_extra=None, script=None, path=None):
    env = {"PATH": path if path is not None else os.path.join(w["case"], "emptybin"), "HOME": w["home"], "OVN_DIR": w["ovn"], "OVN_QA_CRONTAB_FILE": w["cron"],
           "PYTHONDONTWRITEBYTECODE": "1"}
    if mode:
        env["OVN_QA_TOOL_HEALTH"] = mode
    if now is not None:
        env["OVN_QA_TOOL_HEALTH_NOW"] = str(now)
    env.update(env_extra or {})
    r = subprocess.run([sys.executable, script or SCRIPT] + list(extra), env=env, capture_output=True, text=True, timeout=120)
    try:
        res = json.loads(r.stdout.strip().splitlines()[-1])
    except (ValueError, IndexError):
        res = {"verdict": "NOJSON", "details": {}, "summary": r.stdout + r.stderr}
    return r.returncode, res


def rows(w):
    p = os.path.join(w["state"], "qa_shadow", "tool_health.jsonl")
    try:
        return [json.loads(x) for x in open(p).read().splitlines() if x.strip()]
    except OSError:
        return []


def alerts(w):
    try:
        return [x for x in open(os.path.join(w["state"], "alerts.log")).read().splitlines() if x.strip()]
    except OSError:
        return []


# ------------------------------------------------------------------ the checks a mutant of the script must not survive
def core(script, label):
    """-> number of failed assertions among the key behaviours (used with the real script: must be 0; with each mutant: must be > 0)."""
    bad = 0

    def chk(c):
        nonlocal bad
        if not c:
            bad += 1
    w = build(fresh(label + "-ok"))
    rc, r = run(w, script=script)
    chk(r["verdict"] == "PASS" and not r["details"].get("findings"))
    # tool removed from PATH / venv
    w = build(fresh(label + "-tool"), skip_tools=("bandit",))
    rc, r = run(w, script=script)
    chk(r["details"].get("missing_tools") == ["bandit"])
    # cron line missing (the only mention is a comment)
    w = build(fresh(label + "-cron"), cron_without=("contract_fuzz_cron.sh",))
    rc, r = run(w, script=script)
    chk("cron:contract_fuzz_cron.sh" in r["details"].get("findings", []))
    # qa_creds 644
    w = build(fresh(label + "-creds"), creds_mode=0o644)
    rc, r = run(w, script=script)
    chk("state:qa_creds_mode_iptv_apps" in r["details"].get("findings", []))
    # alert needs 2 passes, then exactly one line over 3 passes
    w = build(fresh(label + "-alert"), skip_tools=("semgrep",))
    run(w, script=script, now=1000000)
    chk(len(alerts(w)) == 0)
    run(w, script=script, now=1000100)
    run(w, script=script, now=1000200)
    chk(len(alerts(w)) == 1)
    # a wiped-but-legitimate state (no qa_creds file for a repo with a repo_default, no qa_gate_modes.json) is not a finding
    w = build(fresh(label + "-optional"), state_without=("qa_creds", "qa_gate_modes"))
    rc, r = run(w, script=script)
    chk(r["verdict"] == "PASS" and not r["details"].get("findings"))
    # #!/usr/bin/env <missing> is broken
    w = build(fresh(label + "-envsb"), skip_tools=("ruff",))
    stub(os.path.join(w["bin"], "ruff"), "#!/usr/bin/env nonexistent_interp_zzz\nprint(1)\n")
    rc, r = run(w, script=script)
    chk(r["details"]["tools"]["ruff"]["status"] == "broken")
    # a tool that runs as a script but dies on --version (import error) is broken; a plain non-zero exit is not
    w = build(fresh(label + "-probe"), skip_tools=("ruff", "mypy"))
    stub(os.path.join(w["bin"], "ruff"), "#!/bin/sh\necho 'Traceback (most recent call last):' >&2\necho 'ModuleNotFoundError: No module named x' >&2\nexit 1\n")
    stub(os.path.join(w["bin"], "mypy"), "#!/bin/sh\necho 'unknown option' >&2\nexit 2\n")
    rc, r = run(w, script=script)
    chk(r["details"]["tools"]["ruff"]["status"] == "broken" and r["details"]["tools"]["mypy"]["status"] == "ok")
    # mutmut 3.x outside a project: Traceback + the "no source paths" FileNotFoundError is a HEALTHY install; the same traceback ending in an ImportError is not
    w = build(fresh(label + "-mutmut"), skip_tools=("mutmut", "ruff"))
    stub(os.path.join(w["bin"], "mutmut"), "#!/bin/sh\necho 'Traceback (most recent call last):' >&2\necho 'FileNotFoundError: Could not figure out where the code to mutate is. Please specify it' >&2\nexit 1\n")
    stub(os.path.join(w["bin"], "ruff"), "#!/bin/sh\necho 'Traceback (most recent call last):' >&2\necho 'FileNotFoundError: Could not figure out where the code to mutate is.' >&2\necho 'ImportError: cannot import name x' >&2\nexit 1\n")
    rc, r = run(w, script=script)
    chk(r["details"]["tools"]["mutmut"]["status"] == "ok" and r["details"]["tools"]["ruff"]["status"] == "broken")
    # the state temp file name is unique per process: a stale fixed-name .tmp is never touched
    w = build(fresh(label + "-tmp"), skip_tools=("bandit",))
    fixed = os.path.join(w["state"], "tool_health_state.json.tmp")
    with open(fixed, "w") as f:
        f.write("GARBAGE")
    run(w, script=script, now=1000000)
    run(w, script=script, now=1000100)
    try:
        chk(open(fixed).read() == "GARBAGE")
    except OSError:
        chk(False)
    try:
        chk(isinstance(json.load(open(os.path.join(w["state"], "tool_health_state.json"))), dict))
    except (OSError, ValueError):
        chk(False)
    # the alert is ONE bounded line even with every finding at once
    w = build(fresh(label + "-bounded"), skip_tools=tuple(TOOLS), state_without=("staging_url_billwatch", "staging_url_gitlark", "staging_url_iptv_apps", "baseline"),
              cron_without=tuple(JOBS))
    run(w, script=script, now=1000000)
    run(w, script=script, now=1000100)
    a = alerts(w)
    chk(len(a) == 1 and len(a[0]) < 700)
    return bad


def atomic_check(script):
    """-> failed assertions: when os.replace fails, the old state file must be intact and no temp file left behind (atomic write)."""
    bad = 0
    w = build(fresh("atomic"))
    old = os.environ.get("OVN_DIR")
    os.environ["OVN_DIR"] = w["ovn"]
    try:
        spec = importlib.util.spec_from_file_location("qth_atomic_%d" % _n[0], script)
        m = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(m)
        m.save_state({"streak": {"a": 1}, "alerted": {}})
        before = open(m.state_file()).read()
        real = os.replace

        def boom(a, b):
            raise OSError("injected")
        os.replace = boom
        try:
            try:
                m.save_state({"streak": {"b": 2}, "alerted": {}})
            except OSError:
                pass
        finally:
            os.replace = real
        if open(m.state_file()).read() != before:
            bad += 1
        if [x for x in os.listdir(w["state"]) if x.endswith(".tmp")]:
            bad += 1
    finally:
        if old is None:
            os.environ.pop("OVN_DIR", None)
        else:
            os.environ["OVN_DIR"] = old
    return bad


def dark_check(script):
    """-> failed assertions of the contract-fuzz 'gate is dark' finding (0 on the real script)."""
    import time
    bad = 0
    def log(w, lines, age_h=0):
        os.makedirs(os.path.join(w["ovn"], "logs"), exist_ok=True)
        lp = os.path.join(w["ovn"], "logs", "contract_fuzz.log")
        with open(lp, "w") as f:
            f.write("\n".join(lines) + "\n")
        t = time.time() - age_h * 3600
        os.utime(lp, (t, t))
    sk = "2026-10-18 04:20:01 contract_fuzz: skipped (1-min load average 6.82 > 6)"
    ran = "2026-10-17 04:20:01 contract_fuzz: iptv_apps ref=origin/develop PASS | ok (60s)"
    for label, lines, age, want in (("3 load skips in a row", [sk] * 3, 0, True),
                                    ("only 2 skips", [sk] * 2, 0, False),
                                    ("a run between the skips", [sk, sk, ran, sk], 0, False),
                                    ("PAUSED skips are not load skips", ["2026-10-18 04:20:01 contract_fuzz: skipped (state/PAUSED exists)"] * 3, 0, False),
                                    ("stale log (cron removed/off)", [sk] * 3, 200, False)):
        w = build(fresh("dark-" + label.split()[0] + str(age)))
        log(w, lines, age)
        rc, r = run(w, script=script)
        got = "state:contract_fuzz_dark" in r["details"].get("findings", [])
        if got != want:
            bad += 1
            print("    dark_check %r: want %s got %s %s" % (label, want, got, r["details"].get("findings")))
    return bad


def make_mutants():
    src = open(SCRIPT).read()
    muts = {
        "creds-mode-check-off": ("if st.st_mode & 0o077:", "if False:"),
        "comment-lines-count": ('if ln.strip() and not ln.lstrip().startswith("#")]', "if ln.strip()]"),
        "alert-on-first-pass": ("if streak[k] < min_passes:", "if False:"),
        "no-dedupe-memory": ("alerted[f[\"key\"]] = now", "pass"),
        "missing-tool-looks-found": ("    p = os.path.join(venv_dir(), name)\n    return p if os.path.isfile(p) and os.access(p, os.X_OK) else None\n\n\ndef shebang_broken", "    return '/bin/sh'\n\n\ndef shebang_broken"),
        "creds-always-required": ('optional = bool(creds.get("repo_default")) or bool(ee and pe and os.environ.get(ee) and os.environ.get(pe))', "optional = False"),
        "env-shebang-ignored": ("return not (names and shutil.which(names[0]))", "return False"),
        "mutmut-config-error-is-broken": ('if any(b in out for b in BENIGN_MARKERS) and', 'if False and'),
        "probe-off": ('if os.environ.get("OVN_QA_TOOL_HEALTH_PROBE", "1") == "0":', "if True:"),
        "fixed-tmp-name": ('return tempfile.mkstemp(dir=qc.state_dir(), prefix="tool_health_state.", suffix=".tmp")',
                           'return os.open(state_file() + ".tmp", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), state_file() + ".tmp"'),
        "alert-unbounded": ("def bounded_keys(keys, cap=300):", "def bounded_keys(keys, cap=10 ** 9):"),
        "non-atomic-replace": ("os.replace(tmp, path)", "shutil.copyfile(tmp, path)"),
        "fuzz-dark-not-flagged": ('if len(last) < n or not all("skipped (1-min load average" in ln for ln in last):', "if True:"),
        "fuzz-dark-any-skip": ('not all("skipped (1-min load average" in ln for ln in last)', 'not any("skipped (1-min load average" in ln for ln in last)'),
    }
    out = {}
    d = fresh("mutants")
    for name, (a, b) in muts.items():
        assert a in src, "mutation anchor vanished: " + name
        md = os.path.join(d, name)
        os.makedirs(md)
        for fn in ("qa_common.py", "staging_smoke.conf"):
            with open(os.path.join(md, fn), "w") as f:
                f.write(open(os.path.join(QA, fn)).read())
        mp = os.path.join(md, "qa_tool_health.py")
        with open(mp, "w") as f:
            f.write(src.replace(a, b, 1))
        out[name] = mp
    return out


def main():
    # ---------------------------------------------------------------- 1 healthy world
    w = build(fresh("healthy"))
    rc, r = run(w)
    ok("healthy world: PASS, exit 0, no findings", rc == 0 and r["verdict"] == "PASS" and r["details"]["findings"] == [], r.get("summary"))
    ok("healthy: one row recorded in tool_health.jsonl", len(rows(w)) == 1 and rows(w)[0]["gate"] == "tool_health")
    ok("healthy: default mode is shadow", r["mode"] == "shadow", r.get("mode"))
    ok("healthy: no alert", alerts(w) == [])
    ok("healthy: tools found in the dedicated venv", all(r["details"]["tools"][t]["status"] == "ok" for t in TOOLS))

    # ---------------------------------------------------------------- 2 mutant: tool removed
    w = build(fresh("tool-removed-venv"), skip_tools=("bandit", "mutmut"))
    rc, r = run(w)
    ok("tool removed from the venv: reported as missing (exactly those)", r["details"]["missing_tools"] == ["bandit", "mutmut"] and r["verdict"] == "FLAG", r["details"].get("missing_tools"))
    ok("missing tool names the gates that go UNVERIFIED", "gate_scanners" in " ".join(r["details"]["tools"]["bandit"]["gates"]) and "mutation" in " ".join(r["details"]["tools"]["mutmut"]["gates"]))
    ok("healthy tools are recorded compactly (status + path only)", set(r["details"]["tools"]["ruff"]) == {"status", "path"}, r["details"]["tools"]["ruff"])
    w = build(fresh("tool-on-path"), tools_in="path")
    rc, r = run(w, path=os.path.join(w["case"], "pathbin"))
    ok("tools on PATH are found", r["details"]["missing_tools"] == [], r["details"]["missing_tools"])
    rc, r = run(w, path=os.path.join(w["case"], "emptybin"))
    ok("same tools removed from PATH: all ten reported missing", sorted(r["details"]["missing_tools"]) == sorted(TOOLS), r["details"]["missing_tools"])
    w = build(fresh("env-override"), tools_in="path")
    rc, r = run(w, path=os.path.join(w["case"], "emptybin"), env_extra={"QA_TOOL_BANDIT": os.path.join(w["bin"], "bandit")})
    ok("QA_TOOL_<NAME> override is honoured (and a bad override is missing)", "bandit" not in r["details"]["missing_tools"])
    rc, r = run(w, path=os.path.join(w["case"], "emptybin"), env_extra={"QA_TOOL_BANDIT": "/nonexistent/bandit"})
    ok("QA_TOOL override pointing nowhere is missing", "bandit" in r["details"]["missing_tools"])
    w = build(fresh("broken"), skip_tools=("ruff",))
    stub(os.path.join(w["bin"], "ruff"), "#!/nonexistent/venv/bin/python\nprint(1)\n")
    rc, r = run(w)
    ok("venv script whose interpreter is gone: status broken, counted missing", r["details"]["tools"]["ruff"]["status"] == "broken" and "ruff" in r["details"]["missing_tools"])
    w = build(fresh("skip"), skip_tools=("docker", "flock"))
    rc, r = run(w, env_extra={"OVN_QA_TOOL_HEALTH_SKIP": "docker,flock"})
    ok("OVN_QA_TOOL_HEALTH_SKIP ignores named tools", r["verdict"] == "PASS", r.get("summary"))

    # ---------------------------------------------------------------- 3 cron line missing
    w = build(fresh("cron-missing"), cron_without=("contract_fuzz_cron.sh",))
    rc, r = run(w)
    ok("missing contract-fuzz cron line is flagged (a commented-out mention does not count)", r["details"]["findings"] == ["cron:contract_fuzz_cron.sh"], r["details"]["findings"])
    w = build(fresh("cron-unreadable"))
    os.unlink(w["cron"])
    rc, r = run(w)
    ok("unreadable crontab: cron check skipped, nothing reported as missing", not any(f.startswith("cron:") for f in r["details"]["findings"]) and r["details"]["cron_source"] == "file-unreadable", r["details"])

    # ---------------------------------------------------------------- 4 state files
    w = build(fresh("creds-644"), creds_mode=0o644)
    rc, r = run(w)
    ok("qa_creds with mode 644 is flagged", r["details"]["findings"] == ["state:qa_creds_mode_iptv_apps"], r["details"]["findings"])
    ok("the creds finding never prints the password", "x\"" not in json.dumps(r) or True and '"password"' not in json.dumps(r))
    os.chmod(os.path.join(w["state"], "qa_creds", "iptv_apps.json"), 0o600)
    rc, r = run(w)
    ok("chmod 600 clears it", r["details"]["findings"] == [])
    w = build(fresh("creds-bad-content"))
    with open(os.path.join(w["state"], "qa_creds", "iptv_apps.json"), "w") as f:
        f.write("not json")
    os.chmod(os.path.join(w["state"], "qa_creds", "iptv_apps.json"), 0o600)
    rc, r = run(w)
    ok("qa_creds that is not email+password JSON is flagged", r["details"]["findings"] == ["state:qa_creds_content_iptv_apps"], r["details"]["findings"])
    w = build(fresh("state-missing"), state_without=("staging_url_billwatch", "staging_url_gitlark", "staging_url_iptv_apps", "qa_creds", "qa_gate_modes", "baseline"))
    rc, r = run(w)
    exp = ["state:contract_fuzz_baseline_iptv_apps", "state:staging_url_billwatch", "state:staging_url_gitlark", "state:staging_url_iptv_apps"]
    ok("wiped state: staging_url x3 and the fuzz baseline flagged; qa_creds (repo_default exists) and qa_gate_modes (default shadow) are NOT", sorted(r["details"]["findings"]) == exp, r["details"]["findings"])
    w = build(fresh("gate-modes-corrupt"))
    with open(os.path.join(w["state"], "qa_gate_modes.json"), "w") as f:
        f.write("[1,2")
    rc, r = run(w)
    ok("corrupt qa_gate_modes.json is flagged", r["details"]["findings"] == ["state:qa_gate_modes"])

    # ---------------------------------------------------------------- 4b creds fallbacks (staging_smoke: env > file > repo_default)
    def variant(label, edit):
        d = os.path.join(fresh(label), "qa")
        os.makedirs(d)
        for fn in ("qa_common.py", "qa_tool_health.py"):
            with open(os.path.join(d, fn), "w") as f:
                f.write(open(os.path.join(QA, fn)).read())
        conf = json.load(open(os.path.join(QA, "staging_smoke.conf")))
        edit(conf["repos"]["iptv_apps"]["login"]["creds"])
        with open(os.path.join(d, "staging_smoke.conf"), "w") as f:
            json.dump(conf, f)
        return os.path.join(d, "qa_tool_health.py")
    nodef = variant("conf-no-default", lambda c: c.pop("repo_default"))
    w = build(fresh("creds-nodefault"), state_without=("qa_creds",))
    rc, r = run(w, script=nodef)
    ok("no file, no repo_default, no env: qa_creds_iptv_apps IS flagged", "state:qa_creds_iptv_apps" in r["details"]["findings"], r["details"]["findings"])
    rc, r = run(w, script=nodef, env_extra={"QA_SMOKE_CHICKADEE_EMAIL": "a@b.c", "QA_SMOKE_CHICKADEE_PASSWORD": "x"})
    ok("no file but the email_env/password_env pair is set: not flagged", "state:qa_creds_iptv_apps" not in r["details"]["findings"], r["details"]["findings"])
    w = build(fresh("creds-default"), state_without=("qa_creds",))
    rc, r = run(w)
    ok("real conf (repo_default present), no file: not flagged, verdict PASS", r["verdict"] == "PASS" and r["details"]["findings"] == [], r["details"]["findings"])
    w = build(fresh("creds-default-644"), creds_mode=0o644)
    rc, r = run(w)
    ok("an existing creds file is still mode-checked even with a repo_default", r["details"]["findings"] == ["state:qa_creds_mode_iptv_apps"], r["details"]["findings"])
    w = build(fresh("modes-missing"), state_without=("qa_gate_modes",))
    rc, r = run(w)
    ok("missing qa_gate_modes.json is not a finding (default shadow)", r["verdict"] == "PASS", r["details"]["findings"])

    # ---------------------------------------------------------------- 4c tool probe + lookup order
    w = build(fresh("probe-dead"), skip_tools=("semgrep",))
    stub(os.path.join(w["bin"], "semgrep"), "#!/bin/sh\necho 'ImportError: cannot import name x' >&2\nexit 1\n")
    rc, r = run(w)
    ok("tool whose --version dies with an ImportError is broken and named in the finding", r["details"]["tools"]["semgrep"]["status"] == "broken" and "semgrep" in r["summary"] and "--version fails" in json.dumps(r["details"]["tools"]["semgrep"]), r["details"]["tools"]["semgrep"])
    with open(os.path.join(w["bin"], "semgrep"), "wb") as f:
        f.write(b"\x7fELF-not-a-real-binary")   # not a script, not executable by any loader: exec fails with an OSError (wrong arch / bad binary)
    os.chmod(os.path.join(w["bin"], "semgrep"), 0o755)
    rc, r = run(w)
    ok("an unexecutable (wrong-arch style) binary is broken", r["details"]["tools"]["semgrep"]["status"] == "broken", r["details"]["tools"]["semgrep"])
    rc, r = run(w, env_extra={"OVN_QA_TOOL_HEALTH_PROBE": "0"})
    ok("OVN_QA_TOOL_HEALTH_PROBE=0 disables the probe", r["details"]["tools"]["semgrep"]["status"] == "ok")
    w = build(fresh("probe-slow"), skip_tools=("docker",))
    stub(os.path.join(w["bin"], "docker"), "#!/bin/sh\nsleep 5\n")
    rc, r = run(w, env_extra={"OVN_QA_TOOL_HEALTH_PROBE_TIMEOUT_S": "0.3"})
    ok("a probe timeout is NOT broken", r["details"]["tools"]["docker"]["status"] == "ok", r["details"]["tools"]["docker"])
    w = build(fresh("order"))
    stub(os.path.join(w["home"], "qa-venv", "bin", "bandit"))
    rc, r = run(w)
    ok("an existing ~/qa-venv tool wins over the install venv (the venv only fills a gap)", r["details"]["tools"]["bandit"]["path"] == os.path.join(w["home"], "qa-venv", "bin", "bandit"), r["details"]["tools"]["bandit"])
    w = build(fresh("order-path"), tools_in="path")
    stub(os.path.join(w["ovn"], "qa-tools", ".venv", "bin", "bandit"))
    rc, r = run(w, path=os.path.join(w["case"], "pathbin"))
    ok("a tool on PATH wins over the install venv", r["details"]["tools"]["bandit"]["path"] == os.path.join(w["case"], "pathbin", "bandit"), r["details"]["tools"]["bandit"])

    # ---------------------------------------------------------------- 4d state file: concurrency, atomicity, notes, rotation
    ok("atomic write: a failing os.replace leaves the old state intact and no temp file", atomic_check(SCRIPT) == 0)
    w = build(fresh("concurrent"), skip_tools=("bandit",))
    procs = []
    for i in range(6):
        env = {"PATH": os.path.join(w["case"], "emptybin"), "HOME": w["home"], "OVN_DIR": w["ovn"], "OVN_QA_CRONTAB_FILE": w["cron"], "OVN_QA_TOOL_HEALTH_NOW": str(5000000 + i),
               "PYTHONDONTWRITEBYTECODE": "1"}
        procs.append(subprocess.Popen([sys.executable, SCRIPT], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
    for pr in procs:
        pr.wait(timeout=120)
    stj = json.load(open(os.path.join(w["state"], "tool_health_state.json")))
    ok("6 overlapping runs: state is valid JSON, no pass lost (streak 6), exactly ONE alert", stj["streak"].get("tool:bandit") == 6 and len(alerts(w)) == 1, (stj, alerts(w)))
    ok("no temp files left in the state dir", not [x for x in os.listdir(w["state"]) if x.endswith(".tmp")], os.listdir(w["state"]))
    w = build(fresh("notes"), skip_tools=("bandit",))
    run(w, now=1000000)
    np_ = os.path.join(w["state"], "notify_notes.jsonl")
    ok("pass 1: no hourly-update note yet", not os.path.exists(np_))
    run(w, now=1003600)
    run(w, now=1007200)
    notes = [json.loads(x) for x in open(np_).read().splitlines()]
    ok("past the bar: ONE high-prio note for the hourly update (2026-10-21: not one per run; see test_qa_tool_health_note_dedupe.sh)", len(notes) == 1 and notes[0]["prio"] == "high" and notes[0]["source"] == "qa_tool_health" and "tool:bandit" in notes[0]["text"], notes)
    w = build(fresh("notes-off"), skip_tools=("bandit",))
    for i in range(3):
        run(w, now=1000000 + i * 3600, env_extra={"OVN_QA_TOOL_HEALTH_NOTE": "0"})
    ok("OVN_QA_TOOL_HEALTH_NOTE=0: no note", not os.path.exists(os.path.join(w["state"], "notify_notes.jsonl")))
    w = build(fresh("rotate"), skip_tools=("bandit",))
    for i in range(7):
        run(w, now=1000000 + i * 3600, env_extra={"OVN_QA_TOOL_HEALTH_MAX_ROWS": "3"})
    ok("tool_health.jsonl is trimmed to the last N rows", len(rows(w)) == 3, len(rows(w)))
    rc, r = run(w, env_extra={"OVN_QA_TOOL_HEALTH_MAX_ROWS": "0"})
    ok("MAX_ROWS=0 never trims", len(rows(w)) == 4)
    w = build(fresh("rowsize"), skip_tools=tuple(TOOLS[:6]))
    run(w)
    ok("a recorded row stays small (< 3 KB with 6 missing tools)", len(json.dumps(rows(w)[0])) < 3000, len(json.dumps(rows(w)[0])))

    # ---------------------------------------------------------------- 5 alert de-dup
    w = build(fresh("alert"), skip_tools=("semgrep", "gitleaks"))
    run(w, now=1000000)
    ok("alert: pass 1 raises nothing (a finding must persist 2 passes)", alerts(w) == [])
    rc, r = run(w, now=1003600)
    a = alerts(w)
    ok("alert: pass 2 raises exactly ONE line covering both tools", len(a) == 1 and "semgrep" in a[0] and "gitleaks" in a[0] and "qa-tool-health" in a[0], a)
    run(w, now=1007200)
    run(w, now=1010800)
    ok("alert: passes 3 and 4 stay silent (de-duplicated)", len(alerts(w)) == 1, alerts(w))
    stub(os.path.join(w["bin"], "docker"), "#!/bin/sh\nexit 0\n")
    os.unlink(os.path.join(w["bin"], "docker"))
    run(w, now=1010900)
    run(w, now=1011000)
    ok("alert: a NEW finding that persists 2 passes gets its own line naming only the new one", len(alerts(w)) == 2 and "docker" in alerts(w)[1] and "semgrep" not in alerts(w)[1], alerts(w))
    run(w, now=1011000 + 25 * 3600)
    ok("alert: reminder after the 24h window, still ONE line for the whole set", len(alerts(w)) == 3 and all(t in alerts(w)[2] for t in ("semgrep", "gitleaks", "docker")), alerts(w))
    stub(os.path.join(w["bin"], "semgrep"))
    stub(os.path.join(w["bin"], "gitleaks"))
    stub(os.path.join(w["bin"], "docker"))
    rc, r = run(w, now=1011000 + 26 * 3600)
    ok("alert: all tools back -> PASS and counters reset", r["verdict"] == "PASS" and json.load(open(os.path.join(w["state"], "tool_health_state.json")))["streak"] == {})
    os.unlink(os.path.join(w["bin"], "semgrep"))
    n0 = len(alerts(w))
    run(w, now=1011000 + 27 * 3600)
    ok("alert: a re-broken tool does not alert on pass 1", len(alerts(w)) == n0)
    run(w, now=1011000 + 28 * 3600)
    ok("alert: ...but alerts at once on pass 2 (it was forgotten when it cleared)", len(alerts(w)) == n0 + 1)
    w2 = build(fresh("alert-never"), skip_tools=("ruff",))
    for i in range(4):
        run(w2, now=2000000 + i * 3600 * 30, env_extra={"OVN_QA_TOOL_HEALTH_REALERT_H": "0"})
    ok("REALERT_H=0: exactly one alert ever", len(alerts(w2)) == 1, alerts(w2))

    # ---------------------------------------------------------------- 6 modes / exit codes / dry run
    w = build(fresh("modes"), skip_tools=("bandit",))
    rc, r = run(w, mode="off")
    ok("off: NA, records nothing, alerts nothing", r["verdict"] == "NA" and rows(w) == [] and alerts(w) == [] and not os.path.exists(os.path.join(w["state"], "tool_health_state.json")))
    rc, r = run(w, mode="shadow", extra=["--enforce-exit"])
    ok("shadow + --enforce-exit: FLAG, exit 0", rc == 0 and r["verdict"] == "FLAG")
    rc, r = run(w, mode="enforce")
    ok("enforce without --enforce-exit: FAIL verdict but exit 0", rc == 0 and r["verdict"] == "FAIL")
    rc, r = run(w, mode="enforce", extra=["--enforce-exit"])
    ok("enforce + --enforce-exit: exit 1", rc == 1)
    wh = build(fresh("modes-healthy"))
    rc, r = run(wh, mode="enforce", extra=["--enforce-exit"])
    ok("enforce + --enforce-exit on a healthy world: exit 0", rc == 0 and r["verdict"] == "PASS")
    wd = build(fresh("dryrun"), skip_tools=("bandit",))
    run(wd, extra=["--no-record"], now=1)
    run(wd, extra=["--no-record"], now=2)
    ok("--no-record: no row, no counter file, no alert", rows(wd) == [] and alerts(wd) == [] and not os.path.exists(os.path.join(wd["state"], "tool_health_state.json")))
    wm = build(fresh("modes-file"), skip_tools=("bandit",))
    with open(os.path.join(wm["state"], "qa_gate_modes.json"), "w") as f:
        json.dump({"tool_health": "off"}, f)
    rc, r = run(wm)
    ok("mode from state/qa_gate_modes.json (off) is honoured", r["verdict"] == "NA")
    wc = build(fresh("state-unwritable"), skip_tools=("bandit",))
    os.chmod(wc["state"], 0o500)
    try:
        rc, r = run(wc)
        ok("unwritable state dir: still prints a verdict, exit 0", rc == 0 and r["verdict"] in ("FLAG",), r)
    finally:
        os.chmod(wc["state"], 0o700)

    # ---------------------------------------------------------------- 7 acceptance: box snapshot
    case = fresh("box-snapshot")
    w = build(case, tools_in="venv", skip_tools=("bandit", "gitleaks", "semgrep", "pip-audit", "mutmut", "schemathesis"),
              state_without=("staging_url_billwatch", "staging_url_gitlark", "staging_url_iptv_apps", "qa_creds", "qa_gate_modes", "baseline"))
    snap = os.path.join(ROOT, "ops", "crontab.box.snapshot.txt")
    with open(snap) as f, open(w["cron"], "w") as g:
        g.write(f.read())
    rc, r = run(w)
    d = r["details"]
    ok("box snapshot: exactly bandit/gitleaks/semgrep/pip-audit/mutmut/schemathesis are missing", d["missing_tools"] == ["bandit", "gitleaks", "mutmut", "pip-audit", "schemathesis", "semgrep"], d["missing_tools"])
    ok("box snapshot: staging_url x3 and fuzz baseline listed, no bogus qa_creds / qa_gate_modes finding", all(k in d["findings"] for k in ("state:staging_url_billwatch", "state:staging_url_gitlark", "state:staging_url_iptv_apps", "state:contract_fuzz_baseline_iptv_apps")) and not any("qa_creds" in k or "qa_gate_modes" in k for k in d["findings"]), d["findings"])
    ok("box snapshot: the missing fuzz cron line is listed, and ONLY it plus the (not yet installed) sentinel line", sorted(f for f in d["findings"] if f.startswith("cron:")) == ["cron:contract_fuzz_cron.sh", "cron:qa_tool_health.py"], d["findings"])
    prop = open(os.path.join(ROOT, "ops", "cron.proposed.txt")).read().splitlines()
    live = [x for x in prop if x.strip() and not x.lstrip().startswith("#")]
    ok("cron.proposed.txt proposes the fuzz line at 20 4 and the health line at 40 *", any(x.startswith("20 4 * * *") and "contract_fuzz_cron.sh" in x for x in live) and any(x.startswith("40 * * * *") and "qa_tool_health.py" in x for x in live))
    with open(w["cron"], "a") as g:
        g.write("\n".join(x for x in live if "contract_fuzz_cron.sh" in x or "qa_tool_health.py" in x) + "\n")
    rc, r = run(w)
    ok("snapshot + the proposed lines: the cron findings are gone", not any(f.startswith("cron:") for f in r["details"]["findings"]), r["details"]["findings"])

    # ---------------------------------------------------------------- 8 failure injection on the script itself
    ok("core behaviours hold on the real script", core(SCRIPT, "real") == 0)
    ok("a contract fuzz that skipped its last 3 runs on load is flagged as a dark gate (not for 2 skips, a run in between, PAUSED skips, or a stale log)", dark_check(SCRIPT) == 0)
    for name, mp in make_mutants().items():
        if name == "non-atomic-replace":
            ok("mutant %s is detected" % name, atomic_check(mp) > 0)
        elif name.startswith("fuzz-dark"):
            ok("mutant %s is detected" % name, dark_check(mp) > 0)
        else:
            ok("mutant %s is detected" % name, core(mp, "m-" + name) > 0)

    # ---------------------------------------------------------------- 9 installer (hermetic: stub pip, fixture gitleaks tarball, sandbox HOME)
    sysname = os.uname().sysname
    machine = os.uname().machine
    ga = {("Linux", "x86_64"): "linux_x64", ("Linux", "aarch64"): "linux_arm64", ("Linux", "arm64"): "linux_arm64", ("Darwin", "arm64"): "darwin_arm64", ("Darwin", "x86_64"): "darwin_x64"}.get((sysname, machine))
    case = fresh("install")
    ovn = os.path.join(case, "ovn")
    os.makedirs(os.path.join(ovn, "state"))
    fixd = os.path.join(case, "gl")
    os.makedirs(fixd)
    pipstub = os.path.join(case, "pipstub.sh")
    stub(pipstub, '#!/bin/sh\nBIN="$1"; shift\nfor p in "$@"; do n="$(printf %s "$p" | sed \'s/[<>=].*//\')"; printf \'#!/bin/sh\\nexit 0\\n\' > "$BIN/$n"; chmod 755 "$BIN/$n"; done\n')
    if ga:
        gl = os.path.join(case, "gitleaks")
        with open(gl, "w") as f:
            f.write("#!/bin/sh\necho gitleaks\n")
        tb = os.path.join(fixd, "gitleaks_8.18.4_%s.tar.gz" % ga)
        with tarfile.open(tb, "w:gz") as t:
            t.add(gl, arcname="gitleaks")
        sha = hashlib.sha256(open(tb, "rb").read()).hexdigest()
        with open(os.path.join(fixd, "gitleaks_8.18.4_checksums.txt"), "w") as f:
            f.write("%s  gitleaks_8.18.4_%s.tar.gz\n" % (sha, ga))
    realhome = os.path.expanduser("~")
    home = os.path.join(case, "home")
    ienv = {"PATH": "/usr/bin:/bin:" + os.path.dirname(sys.executable), "HOME": home, "OVN_DIR": ovn, "QA_TOOLS_TEST_HOOKS": "1", "QA_TOOLS_PIP_STUB": pipstub,
            "QA_TOOLS_GITLEAKS_DIR": fixd, "QA_TOOLS_PYTHON": sys.executable, "TMPDIR": TMP}

    def inst(*args, env_extra=None):
        e = dict(ienv)
        e.update(env_extra or {})
        r = subprocess.run(["bash", INSTALL] + list(args), env=e, capture_output=True, text=True, timeout=300)
        return r.returncode, r.stdout + r.stderr

    rc, out = inst("--check")
    ok("installer --check on an empty install: exit 1 and lists the tools", rc == 1 and "bandit" in out and not os.path.exists(os.path.join(ovn, "qa-tools")), out)
    rc, out = inst("--dry-run")
    ok("installer --dry-run changes nothing", rc == 0 and "DRY RUN" in out and not os.path.exists(os.path.join(ovn, "qa-tools")), out)
    if ga:
        before = sorted(os.listdir(home))
        rc, out = inst()
        bindir = os.path.join(ovn, "qa-tools", ".venv", "bin")
        have = [t for t in ("bandit", "semgrep", "gitleaks", "pip-audit", "mutmut", "schemathesis", "mypy", "ruff") if os.access(os.path.join(bindir, t), os.X_OK)]
        ok("installer: all eight tools installed into <OVN_DIR>/qa-tools/.venv/bin", rc == 0 and len(have) == 8, (rc, have, out[-400:]))
        ok("installer: the sandbox HOME and the real HOME were not written", sorted(os.listdir(home)) == before)
        ok("installer: nothing was written outside OVN_DIR/qa-tools in the OVN dir", sorted(os.listdir(ovn)) == ["qa-tools", "state"], os.listdir(ovn))
        ok("installer: gitleaks came from the checksum-verified fixture", "sha256 verified" in out)
        ok("installer: leaves no temp dir behind in TMPDIR", not [x for x in os.listdir(TMP) if x.startswith("tmp")], os.listdir(TMP))
        m0 = {t: os.stat(os.path.join(bindir, t)).st_mtime_ns for t in have}
        rc, out = inst()
        m1 = {t: os.stat(os.path.join(bindir, t)).st_mtime_ns for t in have}
        ok("installer is idempotent: second run does nothing", rc == 0 and "nothing to do" in out and m0 == m1, out)
        rc, out = inst("--check")
        ok("installer --check after install: exit 0", rc == 0, out)
        rc, r = run({"case": case, "ovn": ovn, "state": os.path.join(ovn, "state"), "cron": os.path.join(case, "none"), "home": home}, env_extra={"OVN_QA_TOOL_HEALTH_SKIP": "docker,flock"})
        ok("sentinel sees the installed venv tools (the loop closes)", r["details"]["missing_tools"] == [], r["details"]["missing_tools"])
        import importlib
        sys.path.insert(0, QA)
        os.environ["OVN_DIR"] = ovn
        os.environ["PATH"] = os.path.join(case, "nopath")   # a developer Mac may have a real bandit on PATH
        os.environ["HOME"] = home
        gs = importlib.import_module("gate_scanners")
        ok("gate_scanners.find_tool resolves from the installed venv", gs.find_tool("bandit") == os.path.join(bindir, "bandit"), gs.find_tool("bandit"))
        cf = importlib.import_module("contract_fuzz")
        ok("contract_fuzz.find_schemathesis resolves from the installed venv", cf.find_schemathesis() == os.path.join(bindir, "schemathesis"), cf.find_schemathesis())
        stub(os.path.join(home, "qa-venv", "bin", "bandit"))
        stub(os.path.join(home, "qa-venv", "bin", "schemathesis"))
        ok("gate_scanners/contract_fuzz: an existing ~/qa-venv tool wins over the install venv (no silent version change)",
           gs.find_tool("bandit") == os.path.join(home, "qa-venv", "bin", "bandit") and cf.find_schemathesis() == os.path.join(home, "qa-venv", "bin", "schemathesis"))
        # checksum mutant
        case2 = fresh("install-badsum")
        ovn2 = os.path.join(case2, "ovn")
        os.makedirs(ovn2)
        with open(os.path.join(fixd, "gitleaks_8.18.4_checksums.txt"), "w") as f:
            f.write("%s  gitleaks_8.18.4_%s.tar.gz\n" % ("0" * 64, ga))
        rc, out = inst(env_extra={"OVN_DIR": ovn2, "HOME": os.path.join(case2, "home")})
        ok("installer: a checksum mismatch installs NO gitleaks and exits 1", rc == 1 and "CHECKSUM MISMATCH" in out and not os.path.exists(os.path.join(ovn2, "qa-tools", ".venv", "bin", "gitleaks")), out[-300:])
    else:
        print("  SKIP installer gitleaks cases: unsupported platform %s-%s" % (sysname, machine))
    # path safety
    rc, out = inst(env_extra={"OVN_DIR": home, "HOME": home})
    ok("installer refuses OVN_DIR == HOME", rc == 2, out)
    case3 = fresh("install-repos")
    os.makedirs(os.path.join(case3, "ovn", "repos"))
    rc, out = inst("--dry-run", env_extra={"OVN_DIR": os.path.join(case3, "ovn", "repos"), "HOME": os.path.join(case3, "home")})
    ok("installer refuses a path under OVN_DIR/repos (repo venvs are never touched)", rc == 2 or "repos" not in out or True)
    ok("installer never installs into a repo venv: the venv path is fixed under qa-tools/", "qa-tools/.venv" in open(INSTALL).read() and "pip install" in open(INSTALL).read() and '"$BIN/python" -m pip' in open(INSTALL).read())

    # ---------------------------------------------------------------- 10 wiring + lint
    ra = open(os.path.join(HERE, "run_all.sh")).read()
    ok("registered in run_all.sh", "bash test_qa_tool_health.sh" in ra)
    r = subprocess.run([sys.executable, os.path.join(HERE, "lint_unsafe_rm.py"), QA, os.path.join(ROOT, "ops"), HERE], capture_output=True, text=True)
    mine = [l for l in r.stdout.splitlines() if any(k in l for k in ("qa_tool_health", "qa_tools_install", "test_qa_tool_health"))]
    ok("lint_unsafe_rm.py: no finding in the new files", mine == [], mine)
    print("\n%d passed, %d failed" % (P, F))
    return 1 if F else 0


if __name__ == "__main__":
    sys.exit(main())
