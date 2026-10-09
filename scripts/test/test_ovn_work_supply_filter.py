#!/usr/bin/env python3
"""scripts/ovn_work_supply.py v2: the per-line filter, the seen policy, --on-exhausted, the template fixes (A1-A5, A3 hook) - every check is also run
against a MUTANT of the module (the source with exactly one piece of logic broken) and must FAIL there, so a green run proves the check bites.

Design: each `chk_*` takes a module object M and returns True/False. The real module is loaded from a temp copy (so a neighbouring
ovn_backlog_eligibility.py or ovn_mission_lint.py never leaks into the result); a mutant is the same source with one `old -> new` substitution
(the anchor must exist exactly once, otherwise the test itself fails: a mutation that no longer applies proves nothing).
No kill -0, no `x | grep -q` under pipefail, no grep on comments, no /private/var dependence (all paths are realpath'ed)."""
import contextlib
import fcntl
import importlib.util
import io
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.path.abspath(os.path.join(HERE, ".."))
SUPPLY = os.path.join(SCRIPTS, "ovn_work_supply.py")
SRC = open(SUPPLY, encoding="utf-8").read()
P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:300]) if extra else ""))


_n = [0]


def load_module(src, tag):
    _n[0] += 1
    d = os.path.realpath(tempfile.mkdtemp(prefix="supplymod-"))
    p = os.path.join(d, "ovn_work_supply.py")
    with open(p, "w", encoding="utf-8") as f:
        f.write(src)
    shutil.copy(os.path.join(SCRIPTS, "ovn_mission_lint.py"), d)
    spec = importlib.util.spec_from_file_location("ovn_work_supply_%s_%d" % (tag, _n[0]), p)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


REAL = load_module(SRC, "real")


def mutant(old, new):
    c = SRC.count(old)
    if c != 1:
        ok("mutation anchor exists exactly once: %r" % old[:70], False, "found %d" % c)
        return None
    return load_module(SRC.replace(old, new), "mut")


def mut_check(label, chk, old, new):
    """The check passes on the real module AND fails on the mutant."""
    good = bool(chk(REAL))
    ok("%s: passes on the real module" % label, good)
    m = mutant(old, new)
    if m is not None:
        crash = ""
        try:
            bad = bool(chk(m))
        except Exception as e:  # a mutant that crashes is also a caught mutant, but say so (the wrong reason would be a weak proof)
            bad = False
            crash = " [mutant raised %s]" % type(e).__name__
        ok("MUTATION caught (%s): the same check FAILS when the logic is broken%s" % (label, crash), not bad)


# ---------------------------------------------------------------- builders
def mk(kind, file, symbols, tier="T2", cat="python"):
    return {"kind": kind, "file": file, "tier": tier, "cat": cat, "text": "do the thing", "verify": "python3 -c \"import sys;sys.exit(1)\"", "symbols": symbols}


def env_dir(files=None, backlog="# backlog\n", progress="# progress\n", done=""):
    """An OVN_DIR with repos/demo holding `files`; the default files produce exactly ONE gap (no-rate-limit on open_router.py)."""
    if files is None:
        files = {"iptv-backend/app/routers/limited.py": "from app.core.limiter import limiter\n@router.get('/a')\n@limiter.limit('5/minute')\ndef a(request):\n    return 1\n",
                 "iptv-backend/app/routers/open_router.py": "@router.get('/x')\ndef x():\n    return 1\n@router.post('/y')\nasync def y(body):\n    return 2\n"}
    d = os.path.realpath(tempfile.mkdtemp(prefix="ovn-"))
    clone = os.path.join(d, "repos", "demo")
    for rp, body in files.items():
        os.makedirs(os.path.dirname(os.path.join(clone, rp)), exist_ok=True)
        with open(os.path.join(clone, rp), "w") as f:
            f.write(body)
    with open(os.path.join(clone, "OVERNIGHT_PROGRESS.md"), "w") as f:
        f.write(progress)
    if done:
        with open(os.path.join(clone, "OVERNIGHT_DONE.md"), "w") as f:
            f.write(done)
    os.makedirs(os.path.join(d, "backlog"))
    os.makedirs(os.path.join(d, "state"))
    with open(os.path.join(d, "backlog", "demo.md"), "w") as f:
        f.write(backlog)
    return d


def red_all(repo, lines):
    return {i: "red" for i in range(len(lines))}


def run_main(M, d, *flags, spec=red_all):
    """Run M.main in-process against OVN_DIR=d with the spec check replaced by `spec`; returns the printed text."""
    M.OVN_DIR = d
    M.spec_check = spec
    M.MIN_BACKLOG = 24
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        M.main(["ovn_work_supply.py", "demo"] + list(flags))
    return buf.getvalue()


def rd(d, *parts):
    try:
        with open(os.path.join(d, *parts)) as f:
            return f.read()
    except OSError:
        return ""


def alerts(d, level):
    return [l for l in rd(d, "state", "alerts.log").split("\n") if "| work-supply:demo |" in l and (" %s |" % level) in l]


GAP = mk("no-rate-limit", "iptv-backend/app/routers/open_router.py", ["x", "y"])


# ---------------------------------------------------------------- (1) the real shape of the v1 bug + open/done/held semantics
def chk_not_cross_line(M):
    """v1: `supply:<kind>` from one line and the file from ANOTHER line suppressed the gap. Here: an [x] line for the same kind on a DIFFERENT file, plus a
    hand-written line that mentions this file - the gap must pass."""
    other = M.render(mk("no-rate-limit", "iptv-backend/app/routers/other.py", ["z"]), "demo").replace("- [ ]", "- [x]", 1)
    hand = "- [ ] [T2] iptv-backend/app/routers/open_router.py — a hand-written item that has no supply marker (cat:python)"
    return M._filter(GAP, [other, hand], {}, {}, now=1000.0) is None


def chk_open_suppresses(M):
    line = M.render(GAP, "demo")
    return M._filter(GAP, ["# header", line], {}, {}, now=1000.0) == "open"


def chk_done_resupplies(M):
    done = M.render(GAP, "demo").replace("- [ ]", "- [x]", 1)
    return M._filter(GAP, [done], {}, {}, now=1000.0) == "resupply"


def chk_held_by_file(M):
    other_kind = M.render(mk("missing-docstring", GAP["file"], ["x"]), "demo")
    return M._filter(GAP, [other_kind], {}, {}, now=1000.0) == "held-by-file"


def chk_exact_tag(M):
    """supply:missing-return-type must not count for kind missing-return-none (the tag is matched with its closing paren)."""
    sib = M.render(mk("missing-return-type", "iptv-backend/app/services/a.py", ["f"]), "demo")
    g = mk("missing-return-none", "iptv-backend/app/services/a.py", ["f"])
    return M._filter(g, [sib.replace("- [ ]", "- [x]", 1)], {}, {}, now=1000.0) is None


def chk_path_boundary(M):
    """app/a.py must not match a line that names iptv-backend/app/a.py or app/a.py.bak."""
    g = mk("missing-docstring", "app/a.py", ["f"])
    l1 = M.render(mk("missing-docstring", "iptv-backend/app/a.py", ["f"]), "demo")
    l2 = M.render(mk("missing-docstring", "app/a.py.bak", ["f"]), "demo")
    return M._filter(g, [l1, l2], {}, {}, now=1000.0) is None


# ---------------------------------------------------------------- (2) cooldown + re-supply cap with an injected clock
def chk_cooldown(M):
    done = M.render(GAP, "demo").replace("- [ ]", "- [x]", 1)
    t0 = 5_000_000.0
    seen = {M.spec_key(GAP): (t0, "supplied")}
    inside = M._filter(GAP, [done], seen, {}, now=t0 + 60) == "done-cooldown"
    after = M._filter(GAP, [done], seen, {}, now=t0 + M.RESUPPLY_COOLDOWN_S + 1) == "resupply"
    return inside and after and M.RESUPPLY_COOLDOWN_S == 7200


def chk_cap(M):
    done = M.render(GAP, "demo").replace("- [ ]", "- [x]", 1)
    k = M.spec_key(GAP)
    return (M._filter(GAP, [done], {}, {k: M.RESUPPLY_CAP}, now=1000.0) == "done-cooldown"
            and M._filter(GAP, [done], {}, {k: M.RESUPPLY_CAP - 1}, now=1000.0) == "resupply" and M.RESUPPLY_CAP == 2)


def chk_serial(M):
    """A file with more gaps than MAX_SYMBOLS gets serial items: once the first item landed the REMAINING symbols are a different gap and are supplied at once (no cooldown,
    no cap); the same gap still waits out the cooldown."""
    done = M.render(GAP, "demo").replace("- [ ]", "- [x]", 1)
    t0 = 5_000_000.0
    first = mk("no-rate-limit", GAP["file"], ["a", "b", "c", "d", "e", "f"])
    seen = {M.spec_key(first): (t0, "supplied")}
    rest = mk("no-rate-limit", GAP["file"], ["g", "h"])
    return M._filter(rest, [done], seen, {}, now=t0 + 60) is None and M._filter(first, [done], seen, {}, now=t0 + 60) == "done-cooldown"


def chk_swallow_symbols_stable(M):
    """The swallowed-exception gap keeps its key when unrelated edits above it shift the line numbers."""
    a = "def f():\n    try:\n        g()\n    except ValueError:\n        pass\n"
    out = []
    for text in (a, "import os\n\n\n\n" + a):
        d = os.path.realpath(tempfile.mkdtemp(prefix="sw-"))
        os.makedirs(os.path.join(d, "app"))
        with open(os.path.join(d, "app", "svc.py"), "w") as f:
            f.write(text)
        out.append([M.spec_key(s) for s in M.c_swallowed(d)])
    return len(out[0]) == 1 and out[0] == out[1]


def chk_gap_gone(M):
    done = M.render(GAP, "demo").replace("- [ ]", "- [x]", 1)
    return M._filter(GAP, [done], {}, {}, now=1000.0, gap_present=False) == "done-cooldown"


def chk_resupply_e2e(M):
    """End to end with the real main(): an [x] line whose gap persists is re-supplied (count 1, count 2) and then stops (cap); resupplied file is a tab file."""
    d = env_dir()
    old = M.RESUPPLY_COOLDOWN_S
    M.RESUPPLY_COOLDOWN_S = 0
    try:
        bl = os.path.join(d, "backlog", "demo.md")
        added = []
        for _ in range(4):
            out = run_main(M, d)
            added.append("ADDED 1" in out)
            txt = rd(d, "backlog", "demo.md")
            with open(bl, "w") as f:                # the fleet "ticks" every open supply line without fixing anything
                f.write(txt.replace("- [ ]", "- [x]"))
        tab = rd(d, "state", "work_supply_resupplied_demo").strip().split("\n")
        return added == [True, True, True, False] and len(tab) == 1 and tab[0].endswith("\t2") and tab[0].startswith("no-rate-limit|")
    finally:
        M.RESUPPLY_COOLDOWN_S = old


# ---------------------------------------------------------------- (3) infra verdicts never poison seen; alert exactly once at 3
def chk_infra(M):
    d = env_dir()
    seq = [lambda r, l: None, lambda r, l: {0: "no-verify"}, lambda r, l: {0: "bad-spec"}, lambda r, l: {}]
    counters, seen_after, alert_n = [], [], []
    for sp in seq:
        run_main(M, d, spec=sp)
        counters.append(rd(d, "state", "work_supply_infra_fail_demo").strip())
        seen_after.append(rd(d, "state", "work_supply_seen_demo").strip())
        alert_n.append(len(alerts(d, "warn")))
    one_alert = alert_n == [0, 0, 1, 1]            # none after pass 1 and 2, exactly one at pass 3, still one after pass 4 (a threshold of 2 or 4 fails here)
    no_poison = all(s == "" for s in seen_after) and rd(d, "backlog", "demo.md") == "# backlog\n"
    run_main(M, d, spec=red_all)
    reset = rd(d, "state", "work_supply_infra_fail_demo").strip() == "0" and "supply:no-rate-limit" in rd(d, "backlog", "demo.md")
    return counters == ["1", "2", "3", "4"] and one_alert and no_poison and reset


def chk_no_seen_write(M):
    """A single flaky verdict (no-verdict) leaves no seen entry, so the very next pass supplies the gap."""
    d = env_dir()
    run_main(M, d, spec=lambda r, l: {})
    first = rd(d, "state", "work_supply_seen_demo").strip() == ""
    out = run_main(M, d, spec=red_all)
    return first and "ADDED 1" in out


def chk_passes_before_remembered(M):
    d = env_dir()
    run_main(M, d, spec=lambda r, l: {0: "passes-before"})
    rows = rd(d, "state", "work_supply_seen_demo").strip().split("\n")
    out = run_main(M, d, spec=red_all)
    return len(rows) == 1 and len(rows[0].split("\t")) == 3 and rows[0].split("\t")[1] == "passes-before" and "seen=1" in out and "ADDED" not in out


# ---------------------------------------------------------------- (4) key + TTL
def chk_key(M):
    a, b = mk("k", "f.py", ["x", "y"]), mk("k", "f.py", ["y", "x"])
    c = mk("k", "f.py", ["y"])
    ka, kb, kc = M.spec_key(a), M.spec_key(b), M.spec_key(c)
    parts = ka.split("|")
    return ka == kb and ka != kc and len(parts) == 3 and parts[:2] == ["k", "f.py"] and re.fullmatch(r"[0-9a-f]{10}", parts[2]) is not None


def chk_key_requalifies(M):
    d = os.path.join(tempfile.mkdtemp(prefix="seen-"), "seen")
    old = mk("k", "f.py", ["x", "y"])
    M.save_seen(d, {M.spec_key(old): (time.time(), "supplied")})
    seen = M.load_seen(d)
    return (M._filter(old, [], seen, {}) == "seen"
            and M._filter(mk("k", "f.py", ["y"]), [], seen, {}) is None)


def chk_ttl(M):
    NOW = 10_000_000.0
    H = 3600.0
    rows = [("a|f|1\tpasses-before\t%f" % (NOW - 6 * 86400)), ("b|f|1\tpasses-before\t%f" % (NOW - 8 * 86400)),
            ("c|f|1\tsupplied\t%f" % (NOW - 35 * H)), ("d|f|1\tsupplied\t%f" % (NOW - 37 * H)),
            ("e|f|1\tred\t%f" % (NOW - 35 * H)), ("f|f|1\tred\t%f" % (NOW - 37 * H)),
            ("g|f\t%f" % (NOW - 6 * 86400)), ("h|f\t%f" % (NOW - 8 * 86400)), "garbage line", ""]
    p = os.path.join(tempfile.mkdtemp(prefix="ttl-"), "seen")
    with open(p, "w") as f:
        f.write("\n".join(rows) + "\n")
    got = set(M.load_seen(p, now=NOW))
    return got == {"a|f|1", "c|f|1", "e|f|1", "g|f"}


# ---------------------------------------------------------------- (5) log wording
LOGRE = re.compile(r"^demo: (\d+) gaps found, (\d+) filtered \(seen=(\d+) open=(\d+) done-cooldown=(\d+) held-by-file=(\d+)\), (\d+) specs$", re.M)


def chk_log(M):
    d = env_dir()
    out1 = run_main(M, d, "--dry-run")
    m1 = LOGRE.search(out1)
    # a second environment where the only gap is already queued (open line): N=1, filtered 1 (open=1), 0 specs - and it must NOT say 'no new mechanical gaps'
    d2 = env_dir(backlog="# backlog\n" + M.render(GAP, "demo") + "\n")
    out2 = run_main(M, d2)
    m2 = LOGRE.search(out2)
    # nothing to find at all: the only place the phrase is allowed
    d3 = env_dir(files={"iptv-backend/app/services/clean.py": "x = 1\n"})
    out3 = run_main(M, d3)
    return (m1 is not None and m1.groups() == ("1", "0", "0", "0", "0", "0", "1") and m2 is not None and m2.groups() == ("1", "1", "0", "1", "0", "0", "0")
            and "no new mechanical gaps" not in out1 + out2 and "no new mechanical gaps found" in out3)


# ---------------------------------------------------------------- (6) --on-exhausted
def chk_lock(M):
    d = env_dir()
    fd = open(os.path.join(d, "state", "work_supply_demo.lock"), "a+")
    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)      # a held fcntl/flock lock, exactly what a concurrent pass would hold
    try:
        out = run_main(M, d, "--on-exhausted")
        blocked = "holds the lock" in out and rd(d, "backlog", "demo.md") == "# backlog\n"
    finally:
        fcntl.flock(fd, fcntl.LOCK_UN)
        fd.close()
    out2 = run_main(M, d, "--on-exhausted")             # lock released: the same call now works
    return blocked and "ADDED 1" in out2


def chk_interval(M):
    d = env_dir()
    last = os.path.join(d, "state", "work_supply_last_demo")
    open(last, "w").close()                              # a pass finished just now
    out = run_main(M, d, "--on-exhausted")
    fresh_skipped = "skipped" in out and rd(d, "backlog", "demo.md") == "# backlog\n"
    old = time.time() - 400
    os.utime(last, (old, old))
    out2 = run_main(M, d, "--on-exhausted")
    return fresh_skipped and "ADDED 1" in out2 and time.time() - os.path.getmtime(last) < 60


def chk_exhausted_needs_zero_pullable(M):
    prog = "# progress\n" + "\n".join("- [ ] [T2] item %d — y" % i for i in range(3)) + "\n"
    d = env_dir(progress=prog)
    out = run_main(M, d, "--on-exhausted")
    not_run = "not exhausted" in out and rd(d, "backlog", "demo.md") == "# backlog\n"
    # ... and MIN_BACKLOG is ignored when the lane really is empty (normal pass says 'no supply needed' at MIN_BACKLOG 0, on-exhausted does not)
    d2 = env_dir()
    M.OVN_DIR, M.spec_check = d2, red_all
    M.MIN_BACKLOG = 0
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        M.main(["x", "demo"])                          # a normal pass at MIN_BACKLOG 0 is satisfied...
        M.main(["x", "demo", "--on-exhausted"])        # ...the on-exhausted pass is not gated by it
    M.MIN_BACKLOG = 24
    return not_run and "no supply needed" in buf.getvalue() and "ADDED 1" in buf.getvalue()


def chk_kick(M):
    d = env_dir()
    kick = os.path.join(d, "state", "supply_kick")
    run_main(M, d, "--on-exhausted", spec=lambda r, l: {0: "passes-before"})     # a pass that adds nothing
    none_added = not os.path.exists(kick)
    d2 = env_dir()
    run_main(M, d2, "--on-exhausted", spec=red_all)                                 # a pass that adds an item
    return none_added and os.path.exists(os.path.join(d2, "state", "supply_kick"))


def cli_lock_exit(M):
    """The real CLI (subprocess): a held lock makes `--on-exhausted` exit at once with the lock message."""
    d = env_dir()
    fd = open(os.path.join(d, "state", "work_supply_demo.lock"), "a+")
    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    try:
        t0 = time.time()
        r = subprocess.run([sys.executable, SUPPLY, "demo", "--on-exhausted"], env=dict(os.environ, OVN_DIR=d), capture_output=True, text=True, timeout=30)
        return "holds the lock" in r.stdout and r.returncode == 0 and time.time() - t0 < 10 and rd(d, "backlog", "demo.md") == "# backlog\n"
    finally:
        fcntl.flock(fd, fcntl.LOCK_UN)
        fd.close()


# ---------------------------------------------------------------- (7) A5 template fixes
DELETE_FILE_RE = re.compile(r"\b(remove|delete)\b.{0,60}\bfiles?\b", re.I | re.S)


def _unused_specs(M, paths):
    M._venv_python = lambda root: "/nonexistent/python"
    M._ruff_json = lambda py, root, args: [{"filename": os.path.join(root, p), "message": "`os` imported but unused", "code": "F401"} for p in paths]
    return list(M.c_unused_imports("/tmp/fake-root"))


def chk_wording(M):
    paths = ["iptv-backend/app/services/a.py", "app/files/x.py", "file.py", "iptv-backend/app/file.py", "x/files/y.py"]
    specs = _unused_specs(M, paths)
    return len(specs) == len(paths) and all(not DELETE_FILE_RE.search(s["text"]) and not DELETE_FILE_RE.search(M.render(s, "demo").split(" — ", 1)[1]) for s in specs) \
        and {s["file"]: s["text"] for s in specs}["iptv-backend/app/services/a.py"].startswith(
            "Delete the unused import(s) from the import statement(s) in iptv-backend/app/services/a.py (ruff F401): `os`")


def chk_wording_regex_selftest(M):
    """The regex itself: the OLD wording matches (so the check can fail), the new one does not."""
    return bool(DELETE_FILE_RE.search("Remove the unused import(s) in this file: `os`")) and not DELETE_FILE_RE.search("Delete the unused import(s) from the import statement(s) in a/b.py")


def _verify_rc(M, annotation):
    d = tempfile.mkdtemp(prefix="anyv-")
    with open(os.path.join(d, "m.py"), "w") as f:
        f.write("from typing import Any, Optional\nimport typing\ndef f(x):\n    return x\n".replace("def f(x):", "def f(x) -> %s:" % annotation) if annotation else "def f(x):\n    return x\n")
    cmd = M.verify_return_types("m.py", ["f"])
    return subprocess.run(["bash", "-c", cmd], cwd=d, capture_output=True, text=True).returncode


def chk_any(M):
    bad = ["Any", "Optional[Any]", "typing.Any", "typing.Optional[typing.Any]", "Any | None", "None | Any", ""]
    good = ["int", "dict[str, Any]", "list[Any]", "Optional[int]", "int | None", "Optional[dict[str, Any]]"]
    return all(_verify_rc(M, a) == 1 for a in bad) and all(_verify_rc(M, a) == 0 for a in good) and ">" not in M.verify_return_types("m.py", ["f"])


def chk_gd_off(M):
    d = tempfile.mkdtemp(prefix="gd-")
    os.makedirs(os.path.join(d, "scripts"))
    with open(os.path.join(d, "scripts", "a.gd"), "w") as f:
        f.write("extends Node\nfunc do_it(x):\n\tvar a = 1\n\tvar b = 2\n\tvar c = 3\n\tvar e = 4\n\treturn a\n")
    keep = os.environ.pop("OVN_SUPPLY_GD_DOCS", None)
    try:
        off = list(M.c_gd_docs(d))
        os.environ["OVN_SUPPLY_GD_DOCS"] = "on"
        on = list(M.c_gd_docs(d))
    finally:
        os.environ.pop("OVN_SUPPLY_GD_DOCS", None)
        if keep is not None:
            os.environ["OVN_SUPPLY_GD_DOCS"] = keep
    return off == [] and len(on) == 1 and on[0]["kind"] == "gd-missing-doc"


# ---------------------------------------------------------------- (A3) pullable_count hook
def chk_blocked(M):
    return M._local_pullable_count("- [ ] [T2] a BLOCKED by x\n- [ ] [T2] b is unblocked now\n- [ ] [T2] c — y\n", "") == 2


def chk_external_pullable(M):
    d = tempfile.mkdtemp(prefix="elig-")
    os.makedirs(os.path.join(d, "scripts"))
    mod = os.path.join(d, "scripts", "ovn_backlog_eligibility.py")
    M.OVN_DIR = d
    local = M._local_pullable_count("- [ ] [T2] c — y\n", "")
    res = []
    for body, want in (("def pullable(b, p, d=''):\n    return 7\n", 7),
                       ("def pullable(b, p, d=''):\n    raise RuntimeError('boom')\n", local),
                       ("def pullable(b, p, d=''):\n    return 'many'\n", local),
                       ("def pullable(b, p, d=''):\n    return True\n", local),
                       ("def other():\n    return 3\n", local)):
        with open(mod, "w") as f:
            f.write(body)
        with contextlib.redirect_stderr(io.StringIO()):
            res.append(M.pullable_count("- [ ] [T2] c — y\n", "") == want)
    os.unlink(mod)
    res.append(M.pullable_count("- [ ] [T2] c — y\n", "") == local == 1)
    return all(res)


# ---------------------------------------------------------------- run
print("== (1) per-line filter")
mut_check("(1a) an unrelated [x] line + a marker-less line mentioning the file do not suppress", chk_not_cross_line,
          'on_file = [l for l in lines if "supply:" in l and pat.search(l)]',
          'on_file = (["\\n".join(lines)] if ("supply:" in "\\n".join(lines) and pat.search("\\n".join(lines))) else [])')
mut_check("(1b) an open line naming kind and file suppresses", chk_open_suppresses, '        return "open"', '        pass')
mut_check("(1c) a done line with the gap still present is re-supplied", chk_done_resupplies, '        return "resupply"', '        return "done-cooldown"')
mut_check("(1d) another open supply item on the same file holds the gap", chk_held_by_file, '        return "held-by-file"', '        pass')
mut_check("(1e) the tag is matched exactly (return-type vs return-none)", chk_exact_tag, 'tag = "supply:%s)" % spec["kind"]', 'tag = "supply:%s" % spec["kind"][:12]')
mut_check("(1f) the file name is matched on path boundaries", chk_path_boundary, r'(?<![\w./-])%s(?![\w./-])', r'%s')
print("== (2) cooldown and re-supply cap (injected clock)")
mut_check("(2a) cooldown 7200 s from the supply time", chk_cooldown, 'if ts is not None and now - ts < RESUPPLY_COOLDOWN_S:', 'if False:')
mut_check("(2b) at most 2 re-supplies", chk_cap, 'if resupplied.get(key, 0) >= RESUPPLY_CAP:', 'if False:')
mut_check("(2c0) serial items: the remaining symbols of a file are supplied at once, the same gap still cools down", chk_serial, 'if prior and key not in prior:', 'if False:')
mut_check("(2c1) the swallowed-exception key survives line shifts (symbols are not line numbers)", chk_swallow_symbols_stable,
          '"symbols": sym or ["L%d" % h.lineno for h in hs]', '"symbols": ["L%d" % h.lineno for h in hs]')
ok("(2c) a gap that is gone is never re-supplied", chk_gap_gone(REAL))
mut_check("(2d) end to end: [x] with the gap persisting -> supplied, supplied, supplied(2nd resupply), then stops; tab file counts 2", chk_resupply_e2e,
          'if resupplied.get(key, 0) >= RESUPPLY_CAP:', 'if False:')
print("== (3) infra verdicts")
mut_check("(3a) no-verdict/no-verify/bad-spec never write seen; counter 1,2,3,4; ONE warn alert at 3; a clean pass resets", chk_infra,
          '            dropped[v] = dropped.get(v, 0) + 1\n            infra += 1', '            dropped[v] = dropped.get(v, 0) + 1\n            seen[spec_key(s)] = (now, v)\n            infra += 1')
mut_check("(3b) the alert fires exactly once per streak (== not >=)", chk_infra, 'n == INFRA_ALERT_AFTER', 'n >= INFRA_ALERT_AFTER')
mut_check("(3b2) the alert threshold is 3 consecutive passes, not 2", chk_infra, 'INFRA_ALERT_AFTER = 3', 'INFRA_ALERT_AFTER = 2')
mut_check("(3b3) the alert threshold is 3 consecutive passes, not 4", chk_infra, 'INFRA_ALERT_AFTER = 3', 'INFRA_ALERT_AFTER = 4')
mut_check("(3c) one flaky verdict does not block the next pass", chk_no_seen_write, '            infra += 1', '            seen[spec_key(s)] = (now, "supplied"); infra += 1')
mut_check("(3d) passes-before IS remembered (7 d) and shows up as seen=1", chk_passes_before_remembered, 'seen[spec_key(s)] = (now, v)  # already satisfied', 'pass  # already satisfied')
print("== (4) key and TTL")
mut_check("(4a) the key hashes the sorted gap symbols", chk_key, '"\\n".join(syms)', '""')
mut_check("(4b) a changed symbol set re-qualifies, the same set stays seen", chk_key_requalifies, '"\\n".join(syms)', '""')
mut_check("(4c) TTL: passes-before 7 d, supplied/red 36 h, old two-column rows read as passes-before", chk_ttl,
          '"supplied": 36 * 3600', '"supplied": 7 * 86400')
mut_check("(4d) TTL: passes-before is 7 d, not 36 h", chk_ttl, '"passes-before": 7 * 86400, "red"', '"passes-before": 36 * 3600, "red"')
mut_check("(4e) TTL: red is 36 h", chk_ttl, '"red": 36 * 3600, "supplied"', '"red": 90 * 86400, "supplied"')
print("== (5) log wording")
mut_check("(5) 'N gaps found, M filtered (...), K specs'; 'no new mechanical gaps' only when N == 0", chk_log,
          '"%s: %d gaps found, %d filtered (seen=%d open=%d done-cooldown=%d held-by-file=%d), %d specs"',
          '"%s: no new mechanical gaps found (%d %d %d %d %d %d %d)"')
print("== (6) --on-exhausted")
mut_check("(6a) a held fcntl lock makes a concurrent call exit immediately", chk_lock, '    except OSError:\n        fd.close()\n        return None', '    except OSError:\n        pass')
ok("(6a2) the same through the real CLI (subprocess, held lock)", cli_lock_exit(REAL))
mut_check("(6b) min interval 300 s since work_supply_last", chk_interval, '< ON_EXHAUSTED_MIN_INTERVAL_S:\n', '< -1:\n')
mut_check("(6c) runs only when pullable == 0, ignoring MIN_BACKLOG", chk_exhausted_needs_zero_pullable, '        if have != 0:', '        if False:')
mut_check("(6d) supply_kick is touched only when items were added", chk_kick,
          '    save_seen(seen_path, seen)\n    _touch(last_path)', '    save_seen(seen_path, seen)\n    _touch(last_path)\n    _touch(_state("supply_kick"))')
print("== (7) template fixes")
ok("(7a0) the delete-file regex matches the OLD wording and not the new one", chk_wording_regex_selftest(REAL))
mut_check("(7a) unused-import text never matches \\b(remove|delete)\\b.{0,60}\\bfiles?\\b (also for paths named file/files)", chk_wording,
          '"Delete the unused import(s) from the import statement(s) in %s (ruff F401): %s. Delete only these names from their import lines "',
          '"Remove the unused import(s) in this file%.0s: %s. Delete only these names from their import lines "')
mut_check("(7b) the guard drops the path when it would trip the regex", chk_wording, '    if DELETE_FILE_RE.search(text):', '    if False:') if "DELETE_FILE_RE" in SRC else ok("(7b) guard present in the module", False)
mut_check("(7c) a bare Any / Optional[Any] / Any | None return type fails the return-type VERIFY; real types pass", chk_any,
          '(n.returns is None or bad_r(n.returns))', '(n.returns is None)')
mut_check("(8) the gd-doc family is OFF by default", chk_gd_off, 'os.environ.get("OVN_SUPPLY_GD_DOCS", "off")', 'os.environ.get("OVN_SUPPLY_GD_DOCS", "on")')
print("== (A3) pullable_count")
mut_check("(A3a) BLOCKED (case-sensitive) holds a line; 'unblocked' does not", chk_blocked, r'|BLOCKED|', r'|')
mut_check("(A3b) ovn_backlog_eligibility.pullable is used when present; errors / non-int results fall back to the local count", chk_external_pullable,
          '    fn = _external_pullable()\n', '    fn = None\n')

print("\n%d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
