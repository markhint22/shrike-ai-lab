#!/usr/bin/env python3
"""Tests for the GUT refresh path of qa/baseline_verify.py (qa/baseline_verify_gut.py; analysis F6, 2026-10-10).

Runs the REAL CLI (`baseline_verify.py refresh --repo xlite`) against a throwaway git repo that looks like a Godot project, with a FAKE godot binary
(a bash script selected by OVN_GODOT_BIN that prints a canned GUT log and writes a canned junit xml). Covers: ids parsed from the Run Summary and
matching the runner's verify-log ids at compare time (benign control: pre-existing red -> PASS; negative control: a NEW red -> FAIL), growth never
auto-widens, stale (> TTL) red baseline reads as no baseline (UNVERIFIED), truncated log / junit disagreement / unexplained red xml / timeout /
missing binary / non-Godot repo -> nothing written, the live clone is never touched (no worktree, clean status), the scratch dir is removed,
the godot process runs at nice 15 and with XDG dirs inside the scratch dir, and the pytest refresh path is unchanged."""
import json, os, shutil, subprocess, sys, tempfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
QA = os.path.join(ROOT, "qa")
SCRIPT = os.path.join(QA, "baseline_verify.py")

P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + (("  :: " + str(extra)[:400]) if extra else ""))


T = os.path.realpath(tempfile.mkdtemp(prefix="qa-baseline-gut-test-"))
OVN = os.path.join(T, "ovn")
REPOS = os.path.join(OVN, "repos")
TMP = os.path.join(T, "tmp")
os.makedirs(os.path.join(OVN, "state"))
os.makedirs(TMP)
LIVE = os.path.join(REPOS, "xlite")
FAKE = os.path.join(T, "fake_godot.sh")
FLOG = os.path.join(T, "fake_godot.log")

with open(FAKE, "w") as f:
    f.write(r'''#!/bin/bash
# fake godot: records how it was called, prints a canned GUT log, writes a canned junit xml
{ echo "ARGS $*"; echo "CWD $(pwd)"; echo "NICE $(ps -o ni= -p $$ | tr -d ' ')"; echo "XDG $XDG_DATA_HOME"; } >> "$FAKE_LOG"
case " $* " in *" --import "*) [ -n "$FAKE_IMPORT_LINE" ] && echo "$FAKE_IMPORT_LINE"; exit 0;; esac
xml=""; for a in "$@"; do case "$a" in -gjunit_xml_file=*) xml="${a#-gjunit_xml_file=}";; esac; done
[ "$FAKE_MODE" = hang ] && exec sleep 30
cat "$FAKE_GUT_LOG"
[ -n "$FAKE_XML_FILE" ] && [ -n "$xml" ] && cp "$FAKE_XML_FILE" "$xml"
exit 0
''')
os.chmod(FAKE, 0o755)


def wf(name, text):
    p = os.path.join(T, name)
    with open(p, "w") as f:
        f.write(text)
    return p


def gut_log(failing, parse_noise=False):
    """A real-shaped GUT log (ANSI codes included, as in the box's verify logs). failing = [(file, test), ...]."""
    out = ["Godot Engine v4.3.stable.official", "\x1b[33m==============================================", "\x1b[0m\x1b[33m= Run Summary",
           "\x1b[0m\x1b[33m==============================================", "\x1b[0m"]
    last = None
    for fl, t in failing:
        if fl != last:
            out.append("\nres://tests/%s" % fl)
            last = fl
        out += ["\x1b[0m- %s" % t, "\x1b[31m    [Failed]:  \x1b[0m[1] expected to equal [2]:  ", "          at line -1"]
    out += ["", "---- Totals ----", "Warnings          3", "", "Scripts           10", "Tests             %d" % (50 + len(failing)),
            "  Passing         50"]
    if failing:
        out.append("  Failing         %d" % len(failing))
    out += ["Asserts           123", "Time              5.1s", ""]
    out.append("\x1b[31m---- %d failing tests ----" % len(failing) if failing else "\x1b[32m---- All tests passed! ----")
    return "\n".join(out) + "\n"


def xml_for(failing_tc, errors=0, extra="", asserts=None):
    """A real-shaped GUT junit xml: failing_tc failing TESTCASES (status="fail" + one <failure>, as junit_xml_export.gd writes them). The ROOT failures
    attribute is GUT's totals.failing = failing ASSERTS (default: one per failing test; pass asserts= for multi-assert tests)."""
    root = failing_tc if asserts is None else asserts
    tcs = "".join('<testcase name="test_f%d" assertions="1" status="fail"><failure message="failed"><![CDATA[x]]></failure></testcase>' % i
                  for i in range(failing_tc))
    return ('<?xml version="1.0" encoding="UTF-8"?>\n<testsuites name="GutTests" failures="%d" errors="%d" tests="51" >\n'
            '<testsuite name="tests/a.gd" tests="3" failures="%d"><testcase name="test_ok" assertions="2" status="pass"></testcase>%s%s</testsuite>\n</testsuites>\n'
            % (root, errors, root, tcs, extra))


RED2 = [("test_a.gd", "test_one"), ("test_b.gd", "test_two")]
RED3 = RED2 + [("test_c.gd", "test_three")]
ID2 = ["res://tests/test_a.gd::test_one", "res://tests/test_b.gd::test_two"]


def git(cwd, *a):
    return subprocess.run(["git", "-C", cwd] + list(a), capture_output=True, text=True, timeout=60)


def mk_repo(path, godot=True, gut=True):
    os.makedirs(path)
    git(path, "init", "-q")
    git(path, "config", "user.email", "t@t")
    git(path, "config", "user.name", "t")
    if godot:
        wf_in(path, "project.godot", "config_version=5\n")
    if godot and gut:
        wf_in(path, "addons/gut/gut_cmdln.gd", "extends SceneTree\n")
    wf_in(path, "tests/test_a.gd", "extends GutTest\n")
    git(path, "add", "-A")
    git(path, "commit", "-q", "-m", "init")
    git(path, "update-ref", "refs/remotes/origin/develop", "HEAD")


def wf_in(root, rel, text):
    p = os.path.join(root, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w") as f:
        f.write(text)


mk_repo(LIVE)


def cli(args, env_extra=None, timeout=120):
    env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": T, "OVN_DIR": OVN, "OVN_REPOS_DIR": REPOS, "TMPDIR": TMP, "LANG": "C",
           "OVN_GODOT_BIN": FAKE, "FAKE_LOG": FLOG, "NTFY_SERVER": "http://127.0.0.1:9"}
    env.update(env_extra or {})
    p = subprocess.run(["env", "-i"] + ["%s=%s" % kv for kv in env.items()] + [sys.executable, SCRIPT] + args + ["--no-record"],
                       cwd=T, capture_output=True, text=True, timeout=timeout)
    last = [l for l in p.stdout.splitlines() if l.strip()]
    try:
        js = json.loads(last[-1])
    except Exception:  # noqa: BLE001
        js = {"verdict": "NO-JSON", "summary": p.stdout + p.stderr, "details": {}}
    js.setdefault("details", {})
    return p.returncode, js


BLF = os.path.join(OVN, "state", "qa_baselines", "verify", "xlite.json")


def baseline():
    try:
        with open(BLF) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def flog():
    try:
        with open(FLOG) as f:
            return f.read()
    except OSError:
        return ""


def refresh(failing, xml_failures=None, env=None, args=None, xml=True, xml_asserts=None):
    e = {"FAKE_GUT_LOG": wf("gut.log", gut_log(failing) if isinstance(failing, list) else failing)}
    if xml:
        e["FAKE_XML_FILE"] = wf("gut.xml", xml_for(len(failing) if xml_failures is None else xml_failures, asserts=xml_asserts))
    e.update(env or {})
    try:
        os.unlink(FLOG)
    except OSError:
        pass
    return cli(["refresh", "--repo", "xlite", "--ref", "origin/develop"] + (args or []), e)


def verify_log(failing):
    return wf("verify.log", "-- GUT FULL --\n" + gut_log(failing))


def compare(failing, extra=None):
    return cli(["compare", "--repo", "xlite", "--failing-file", verify_log(failing), "--format", "verify-log", "--runner-failed"] + (extra or []))


print("== refresh --repo xlite (GUT) stores the red set, deterministic")
rc, js = refresh(RED2, xml_asserts=5)  # 2 failing tests, 5 failing asserts (one test fails 3 asserts): the root attribute counts asserts
ok("PASS stored_fresh with 2 red ids even when the junit root counts 5 failing asserts (multi-assert red test)", rc == 0 and js["verdict"] == "PASS" and js["details"].get("status") == "stored_fresh" and js["details"].get("count") == 2, js)

bl = baseline()
ok("baseline holds the file::test ids, source deterministic:refresh-gut, parser gut",
   bl and bl["failing"] == sorted(ID2) and bl["source"] == "deterministic:refresh-gut" and bl["parser"] == "gut", bl)
ok("baseline commit is the ref's commit", bl and bl["commit"] == git(LIVE, "rev-parse", "origin/develop").stdout.strip(), bl)
log = flog()
ok("godot ran: import twice then ONE GUT run with -gdir=res://tests -ginclude_subdirs -gexit -gjunit_xml_file",
   log.count("--import") == 2 and log.count("gut_cmdln.gd") == 1 and "-gdir=res://tests -ginclude_subdirs -gexit -gjunit_xml_file=" in log, log)
# `nice -n 15` is RELATIVE to the ambient niceness (a test started from a niced background job sees 15 + base, capped at 19/20), so compare with this process's own
_base = os.nice(0)
ok("godot ran niced by +15 over the ambient niceness - CPU polite", set(l.split()[1] for l in log.splitlines() if l.startswith("NICE ")) <= {str(min(_base + 15, 19)), str(min(_base + 15, 20))}
   and set(l.split()[1] for l in log.splitlines() if l.startswith("NICE ")) and all(int(l.split()[1]) >= 15 for l in log.splitlines() if l.startswith("NICE ")), (log, _base))
cwds = set(l.split(" ", 1)[1] for l in log.splitlines() if l.startswith("CWD "))
ok("godot ran in a PRIVATE scratch copy (not the live clone) and XDG dirs live in it too",
   len(cwds) == 1 and not list(cwds)[0].startswith(LIVE) and os.path.realpath(list(cwds)[0]).startswith(TMP), log)
ok("XDG_DATA_HOME inside the scratch dir", all(l.split(" ", 1)[1].startswith(TMP) for l in log.splitlines() if l.startswith("XDG ")), log)
ok("scratch dir removed afterwards", not [d for d in os.listdir(TMP) if d.startswith("qa-gut-")], os.listdir(TMP))
ok("live clone untouched: clean status, one worktree, no extra refs written", git(LIVE, "status", "--porcelain").stdout == ""
   and len(git(LIVE, "worktree", "list").stdout.strip().splitlines()) == 1, git(LIVE, "worktree", "list").stdout)

print("== the refreshed ids are the SAME ids the runner's verify-log yields (compare matches them)")
rc, js = compare(RED2, ["--changed-file", "scripts/x.gd"])
ok("benign control: same pre-existing red => PASS, 2 preexisting, 0 new", js["verdict"] == "PASS" and len(js["details"].get("preexisting", [])) == 2
   and not js["details"].get("new_failures"), js)
rc, js = compare(RED3, ["--changed-file", "scripts/x.gd"])
ok("negative control: a NEW red test => FAIL naming it", js["verdict"] == "FAIL" and js["details"].get("new_failures") == ["res://tests/test_c.gd::test_three"], js)

print("== never auto-widen")
h0 = open(BLF).read()
rc, js = refresh(RED3)
ok("refresh with one more red => FLAG growth_pending, baseline NOT widened", js["verdict"] == "FLAG" and js["details"].get("status") == "growth_pending"
   and open(BLF).read().count("test_three") == 1 and baseline()["failing"] == sorted(ID2) and baseline()["pending_growth"], js)
rc, js = refresh(RED3, args=["--accept-growth"])
ok("--accept-growth widens", js["verdict"] == "PASS" and len(baseline()["failing"]) == 3, js)
rc, js = refresh(RED2)
ok("red set shrinking is accepted (stored_shrunk)", js["details"].get("status") == "stored_shrunk" and len(baseline()["failing"]) == 2, js)

print("== stale-red control: an expired baseline reads as missing")
b = baseline()
b["ts"] = time.time() - 3 * 86400
with open(BLF, "w") as f:
    json.dump(b, f)
rc, js = compare(RED2)
ok("24h TTL: the same red log against a 3-day-old baseline => UNVERIFIED (no baseline), not PASS", js["verdict"] == "UNVERIFIED", js)
rc, js = refresh(RED3)
ok("refresh over an EXPIRED baseline with a larger red set is logged, not silent (stored_fresh_grown)", js["details"].get("status") == "stored_fresh_grown", js)
ok("... and growth_alerts.jsonl has growth_accepted_after_expiry",
   "growth_accepted_after_expiry" in open(os.path.join(OVN, "state", "qa_baselines", "verify", "growth_alerts.jsonl")).read())
rc, js = refresh(RED2, args=["--accept-growth"])

print("== refusals write nothing")
h0 = open(BLF).read()
trunc = gut_log(RED2).split("---- Totals ----")[0]
rc, js = refresh(trunc)
ok("truncated log (no Totals) => UNVERIFIED, baseline byte-identical", js["verdict"] == "UNVERIFIED" and open(BLF).read() == h0, js)
rc, js = refresh(RED2, xml_failures=0)
ok("junit xml disagrees with the log (0 vs 2) => UNVERIFIED, baseline untouched", js["verdict"] == "UNVERIFIED" and "junit" in js["summary"] and open(BLF).read() == h0, js)
rc, js = refresh([], xml_failures=3)
ok("red junit xml that no failing id explains => UNVERIFIED, baseline untouched", js["verdict"] == "UNVERIFIED" and open(BLF).read() == h0, js)
rc, js = refresh(RED2, xml_failures=2, xml_asserts=0)
ok("junit root failures=0 while 2 testcases fail => UNVERIFIED (inconsistent), baseline untouched", js["verdict"] == "UNVERIFIED" and "inconsistent" in js["summary"] and open(BLF).read() == h0, js)
rc, js = refresh(RED2, xml_failures=2, xml_asserts=1)
ok("junit root counts fewer asserts than failing testcases => UNVERIFIED (inconsistent), baseline untouched", js["verdict"] == "UNVERIFIED" and open(BLF).read() == h0, js)
rc, js = refresh([], xml_failures=0, xml_asserts=3)
ok("junit root red (3 asserts) but no testcase fails and no id => UNVERIFIED (inconsistent), baseline untouched", js["verdict"] == "UNVERIFIED" and "inconsistent" in js["summary"] and open(BLF).read() == h0, js)
rc, js = refresh(RED2, xml=False)
ok("no junit xml written => UNVERIFIED, baseline untouched", js["verdict"] == "UNVERIFIED" and open(BLF).read() == h0, js)
rc, js = refresh([], xml_failures=0, env={"FAKE_XML_FILE": wf("na.xml", xml_for(0, extra='<testcase name="x" status="no asserts"/>'))})
ok('junit xml with status="no asserts" (runner counts it red) and no id => UNVERIFIED, baseline untouched', js["verdict"] == "UNVERIFIED" and open(BLF).read() == h0, js)
rc, js = refresh(RED2, env={"FAKE_IMPORT_LINE": "SCRIPT ERROR: Parse Error: Identifier X not declared"})
ok("a script Parse Error in the import output is a hard-ish red id (godot-parse:), not dropped", js["verdict"] in ("FLAG", "PASS") and
   (any(i.startswith("godot-parse:") for i in (baseline().get("pending_growth") or {}).get("added", [])) or
    any(i.startswith("godot-parse:") for i in baseline()["failing"])), js)
rc, js = refresh(RED2, args=["--accept-growth"])
rc, js = refresh(RED2)
h0 = open(BLF).read()
t0 = time.time()
rc, js = refresh(RED2, env={"FAKE_MODE": "hang"}, args=["--timeout", "3"])
ok("hanging godot => UNVERIFIED 'timed out', bounded, baseline untouched", js["verdict"] == "UNVERIFIED" and "timed out" in js["summary"]
   and time.time() - t0 < 20 and open(BLF).read() == h0, (js, time.time() - t0))
ok("scratch dir removed after a timeout too", not [d for d in os.listdir(TMP) if d.startswith("qa-gut-")], os.listdir(TMP))
rc, js = refresh(RED2, env={"OVN_GODOT_BIN": os.path.join(T, "no-such-godot")})
ok("missing godot binary => NA (repo type unsupported HERE), baseline untouched", js["verdict"] == "NA" and open(BLF).read() == h0, js)
rc, js = refresh(RED2, env={"OVN_BASELINE_GUT": "off"})
ok("OVN_BASELINE_GUT=off => NA (old behaviour)", js["verdict"] == "NA" and open(BLF).read() == h0, js)
rc, js = cli(["refresh", "--repo", "xlite", "--ref", "origin/nope"], {"FAKE_GUT_LOG": wf("g.log", gut_log([]))})
ok("unknown ref => NA/UNVERIFIED (never PASS), nothing written", js["verdict"] in ("NA", "UNVERIFIED"), js)
ok("baseline still byte-identical after all refusals", open(BLF).read() == h0)

print("== repo type checks")
NOGUT = os.path.join(REPOS, "nogut")
mk_repo(NOGUT, godot=True, gut=False)
rc, js = cli(["refresh", "--repo", "nogut", "--ref", "origin/develop"], {"FAKE_GUT_LOG": wf("g.log", gut_log([]))})
ok("project.godot without vendored GUT => NA", js["verdict"] == "NA", js)
PLAIN = os.path.join(REPOS, "plainrepo")
mk_repo(PLAIN, godot=False)
rc, js = cli(["refresh", "--repo", "plainrepo", "--ref", "origin/develop"], {"FAKE_GUT_LOG": wf("g.log", gut_log([]))})
ok("no project.godot and no pytest => NA naming the repo types supported", js["verdict"] == "NA" and "no project.godot" in js["summary"], js)
ok("neither wrote a baseline", not os.path.exists(os.path.join(OVN, "state", "qa_baselines", "verify", "nogut.json"))
   and not os.path.exists(os.path.join(OVN, "state", "qa_baselines", "verify", "plainrepo.json")))

print("== OVN_GUT_SUBDIRS=off drops -ginclude_subdirs like the other callers")
rc, js = refresh(RED2, env={"OVN_GUT_SUBDIRS": "off"})
ok("flag removed", "-ginclude_subdirs" not in flog() and "-gdir=res://tests -gexit" in flog(), flog())

print("== pytest refresh path is unchanged (venv repo still uses pytest, never godot)")
PY = os.path.join(REPOS, "pyrepo")
mk_repo(PY, godot=False)
os.makedirs(os.path.join(PY, ".venv", "bin"))
wf_in(PY, ".venv/bin/pytest", "#!/bin/sh\necho 'FAILED tests/test_x.py::test_a - boom'\necho '1 failed, 3 passed in 0.10s'\n")
os.chmod(os.path.join(PY, ".venv", "bin", "pytest"), 0o755)
try:
    os.unlink(FLOG)
except OSError:
    pass
rc, js = cli(["refresh", "--repo", "pyrepo", "--ref", "origin/develop"], {"FAKE_GUT_LOG": wf("g.log", gut_log([]))})
ok("pyrepo refresh uses pytest (PASS stored_fresh 1 id) and never ran godot", js["verdict"] == "PASS" and js["details"].get("count") == 1 and not os.path.exists(FLOG), js)

print("== GUT module missing next to baseline_verify.py (partial deploy) degrades to the old NA, never a crash")
D = os.path.join(T, "partial")
os.makedirs(D)
for fn in ("baseline_verify.py", "qa_common.py"):
    shutil.copy(os.path.join(QA, fn), D)
p = subprocess.run(["env", "-i", "PATH=" + os.environ.get("PATH", ""), "HOME=" + T, "OVN_DIR=" + OVN, "OVN_REPOS_DIR=" + REPOS, sys.executable,
                    os.path.join(D, "baseline_verify.py"), "refresh", "--repo", "xlite", "--ref", "origin/develop", "--no-record"],
                   capture_output=True, text=True, timeout=60, cwd=T)
js = json.loads(p.stdout.strip().splitlines()[-1])
ok("partial deploy => NA with the pytest-only message, exit 0", p.returncode == 0 and js["verdict"] == "NA" and "no .venv/bin/pytest" in js["summary"], p.stdout + p.stderr)

print("== junit_counts: failing TESTCASES, not the root asserts attribute")
sys.path.insert(0, QA)
import baseline_verify_gut as _bvg
def _jc(text):
    return _bvg.junit_counts(wf("jc.xml", text))
ok("multi-assert: root failures=3 over 2 failing testcases => 2 failing testcases", _jc(xml_for(2, asserts=3))[3] == 2 and _jc(xml_for(2, asserts=3))[0] == 3)
ok("status=fail without a <failure> child still counts", _jc('<testsuites failures="1"><testsuite><testcase name="t" status="fail"/></testsuite></testsuites>')[3] == 1)
ok("<error> child counts", _jc('<testsuites errors="1"><testsuite><testcase name="t"><error message="x"/></testcase></testsuite></testsuites>')[3] == 1)
ok("pending / no-asserts testcases are not failing testcases", _jc('<testsuites failures="0"><testsuite><testcase name="t" status="pending"/><testcase name="u" status="no asserts"/></testsuite></testsuites>')[3] == 0)
big = xml_for(0, extra='<testcase name="pad" status="pass"><system-out>' + "x" * 300000 + '</system-out></testcase>' + '<testcase name="late" status="fail"><failure message="f"/></testcase>', asserts=1)
ok("a failing testcase beyond the first 200 kB is still counted", _jc(big)[3] == 1)
ok("a '>' inside a quoted attribute does not break the testcase match", _jc('<testsuites failures="1"><testsuite><testcase name="a>b" status="fail"/></testsuite></testsuites>')[3] == 1)

print("== a scratch dir leaked by an outer-timeout kill is swept by the next refresh (only old, own, real dirs named qa-gut-*)")
def _mkd(name, age_s):
    d = os.path.join(TMP, name)
    os.makedirs(os.path.join(d, "src"))
    with open(os.path.join(d, "src", "f"), "w") as f:
        f.write("x")
    t = time.time() - age_s
    os.utime(d, (t, t))
    return d
_old = _mkd("qa-gut-leaked-old", 7200)
_new = _mkd("qa-gut-running-fresh", 60)
_other = _mkd("keep-me-old", 7200)
_tgt = _mkd("symlink-target-old", 7200)
os.symlink(_tgt, os.path.join(TMP, "qa-gut-link"))
rc, js = refresh(RED2)
ok("the old qa-gut-* dir is gone after a refresh", not os.path.exists(_old), os.listdir(TMP))
ok("a fresh qa-gut-* dir (a concurrent refresh) is untouched", os.path.isdir(_new))
ok("an old dir without the qa-gut- prefix is untouched", os.path.isdir(_other))
ok("a qa-gut-* symlink is never followed or removed", os.path.islink(os.path.join(TMP, "qa-gut-link")) and os.path.isdir(_tgt))
ok("the refresh itself still worked and its own scratch dir is gone", js["verdict"] in ("PASS", "FLAG") and sorted(d for d in os.listdir(TMP) if d.startswith("qa-gut-")) == ["qa-gut-link", "qa-gut-running-fresh"], os.listdir(TMP))
tempfile.tempdir = TMP   # sweep_stale looks in tempfile.gettempdir()
ok("sweep_stale honours max(1h, 2 x timeout): a 2 h old dir survives --timeout 5000, goes at --timeout 900",
   (_mkd("qa-gut-t5000", 7200) and _bvg.sweep_stale(5000) == 0 and os.path.isdir(os.path.join(TMP, "qa-gut-t5000")) and _bvg.sweep_stale(900) == 1
    and not os.path.exists(os.path.join(TMP, "qa-gut-t5000"))))
shutil.rmtree(_new, ignore_errors=True)
os.unlink(os.path.join(TMP, "qa-gut-link"))
tempfile.tempdir = None

shutil.rmtree(T, ignore_errors=True)
print("\nqa_baseline_gut: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
