#!/usr/bin/env python3
"""scripts/ovn_work_supply.py frozen-file filter (package K3 item 3, 2026-11-01).

Real case: gitlark had 34 BLOCKED cycles on a work-supply item targeting frozen code_review_agent.py (AGENTS.md: 'Legacy/frozen - do not add features, tests, refactors...').
Fixture fixtures_k3/gitlark_AGENTS_frozen_excerpt.md is the verbatim excerpt of gitlark's AGENTS.md with that list. Every check also runs on a MUTANT of the module
(the source with exactly one piece of logic broken) and must FAIL there."""
import contextlib
import importlib.util
import io
import os
import shutil
import sys
import tempfile

import tmp_track  # noqa: E402
tmp_track.install()

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.path.abspath(os.path.join(HERE, ".."))
SRC = open(os.path.join(SCRIPTS, "ovn_work_supply.py"), encoding="utf-8").read()
AGENTS = open(os.path.join(HERE, "fixtures_k3", "gitlark_AGENTS_frozen_excerpt.md"), encoding="utf-8").read()
P = F = 0
_n = [0]


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:300]) if extra else ""))


def load_module(src, tag):
    _n[0] += 1
    d = os.path.realpath(tempfile.mkdtemp(prefix="supplymod-"))
    p = os.path.join(d, "ovn_work_supply.py")
    with open(p, "w", encoding="utf-8") as f:
        f.write(src)
    shutil.copy(os.path.join(SCRIPTS, "ovn_mission_lint.py"), d)
    spec = importlib.util.spec_from_file_location("ovn_work_supply_fz_%s_%d" % (tag, _n[0]), p)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


REAL = load_module(SRC, "real")


def mut_check(label, chk, old, new):
    good = bool(chk(REAL))
    ok("%s: passes on the real module" % label, good)
    c = SRC.count(old)
    if c != 1:
        ok("mutation anchor exists exactly once: %r" % old[:70], False, "found %d" % c)
        return
    m = load_module(SRC.replace(old, new), "mut")
    crash = ""
    try:
        bad = bool(chk(m))
    except Exception as e:
        bad, crash = False, " [mutant raised %s]" % type(e).__name__
    ok("MUTATION caught (%s): the same check FAILS when the logic is broken%s" % (label, crash), not bad)


def tree(files):
    d = os.path.realpath(tempfile.mkdtemp(prefix="fzroot-"))
    for rp, body in files.items():
        os.makedirs(os.path.dirname(os.path.join(d, rp)) or d, exist_ok=True)
        with open(os.path.join(d, rp), "w") as f:
            f.write(body)
    return d


REAL_FROZEN = ["backend/app/services/code_review_agent.py", "backend/app/routers/code_review.py", "backend/app/services/search.py", "backend/app/services/vector_store.py",
               "backend/app/services/snippet.py", "backend/app/services/review_rule_templates.py", "backend/app/routers/review_rules.py", "web/src/pages/ReviewRulesPage.vue",
               "web/src/stores/reviewRules.ts", "backend/app/services/code_quality_metrics.py", "backend/app/services/ml_code_insights.py",
               "backend/app/services/architecture_analysis_agent.py"]


def chk_parse_real(M):
    root = tree({"AGENTS.md": AGENTS})
    got = M.frozen_paths(root)
    return got == REAL_FROZEN


def chk_dual_purpose_and_prose_excluded(M):
    got = M.frozen_paths(tree({"AGENTS.md": AGENTS}))
    return ("backend/app/routers/pull_requests.py" not in got and "web/src/pages/PullRequestsPage.vue" not in got      # the 'dual-purpose' bullet stays in scope
            and "web/src/components/CodeReviewPanel.vue" not in got                                                     # prose AFTER the list ('Deleted 2026-09-18 ...') is not frozen
            and "code_review_agent" not in got)                                                                          # a bare backticked identifier is not a path


def chk_no_list_no_freeze(M):
    plain = "# Notes\n\nSome text about `app/a.py` and `app/b.py`.\n\n- `app/c.py` - a file\n- `app/d.py` - another\n"
    return M.frozen_paths(tree({"AGENTS.md": plain})) == [] and M.frozen_paths(tree({"README.md": "x"})) == []


def chk_hit_shapes(M):
    root = tree({"backend/app/services/code_review_agent.py": "x"})
    fz = ["backend/app/services/code_review_agent.py", "legacy/", "web/old_*.ts"]
    return (M.frozen_hit("backend/app/services/code_review_agent.py", fz, root) == fz[0] and M.frozen_hit("legacy/deep/a.py", fz, root) == "legacy/"
            and M.frozen_hit("web/old_x.ts", fz, root) == "web/old_*.ts" and M.frozen_hit("backend/app/services/other.py", fz, root) is None
            and M.frozen_hit("legacyx/a.py", fz, root) is None)


def chk_stale_entry_basename(M):
    """a frozen entry whose file was MOVED (no longer at the listed path) still freezes the same basename elsewhere; an entry that exists does not; generic names never."""
    root = tree({"backend/app/agents/code_review_agent.py": "x", "backend/app/services/live.py": "y"})
    stale = ["backend/app/services/code_review_agent.py"]            # listed path is gone
    live = ["backend/app/services/live.py"]                         # listed path exists
    gen = ["old/__init__.py"]
    return (M.frozen_hit("backend/app/agents/code_review_agent.py", stale, root) == stale[0]
            and M.frozen_hit("backend/app/agents/live.py", live, root) is None
            and M.frozen_hit("pkg/__init__.py", gen, root) is None)


def env_dir(agents):
    files = {"iptv-backend/app/core/limiter.py": "from slowapi import Limiter\nlimiter = Limiter(key_func=None)\n",
             "iptv-backend/app/routers/limited.py": "from app.core.limiter import limiter\n@router.get('/a')\n@limiter.limit('5/minute')\ndef a(request):\n    return 1\n",
             "iptv-backend/app/routers/open_router.py": "@router.get('/x')\ndef x():\n    return 1\n",
             "iptv-backend/app/routers/second_router.py": "@router.get('/z')\ndef z():\n    return 1\n"}
    if agents is not None:
        files["AGENTS.md"] = agents
    d = os.path.realpath(tempfile.mkdtemp(prefix="ovn-"))
    clone = os.path.join(d, "repos", "demo")
    for rp, body in files.items():
        os.makedirs(os.path.dirname(os.path.join(clone, rp)), exist_ok=True)
        with open(os.path.join(clone, rp), "w") as f:
            f.write(body)
    with open(os.path.join(clone, "OVERNIGHT_PROGRESS.md"), "w") as f:
        f.write("# progress\n")
    os.makedirs(os.path.join(d, "backlog"))
    os.makedirs(os.path.join(d, "state"))
    with open(os.path.join(d, "backlog", "demo.md"), "w") as f:
        f.write("# backlog\n")
    return d


def run_main(M, d, mode=None, passes=1):
    M.OVN_DIR = d
    M.spec_check = lambda repo, lines: {i: "red" for i in range(len(lines))}
    M.MIN_BACKLOG = 24
    if mode is not None:
        M.FROZEN_MODE = mode
    for _ in range(passes):
        with contextlib.redirect_stdout(io.StringIO()):
            M.main(["ovn_work_supply.py", "demo", "--force"])


def rd(d, *parts):
    try:
        with open(os.path.join(d, *parts)) as f:
            return f.read()
    except OSError:
        return ""


FZ_AGENTS = "# Agents\n\n**Legacy/frozen - do not add features, tests, refactors or helpers to these:**\n- `iptv-backend/app/routers/open_router.py` - frozen.\n"


def chk_main_skips_frozen(M):
    d = env_dir(FZ_AGENTS)
    run_main(M, d, passes=2)
    bl = rd(d, "backlog", "demo.md")
    log = rd(d, "state", "work_supply_frozen.log")
    al = rd(d, "state", "alerts.log")
    return ("second_router.py" in bl and "open_router.py" not in bl and log.count("\n") == 1 and "skipped iptv-backend/app/routers/open_router.py" in log
            and al.count("] info | work-supply:demo | skipped 1 gap(s)") == 1 and "frozen file(s): iptv-backend/app/routers/open_router.py" in al)


def chk_main_without_agents_unchanged(M):
    d = env_dir(None)
    run_main(M, d)
    bl = rd(d, "backlog", "demo.md")
    return "second_router.py" in bl and "open_router.py" in bl and rd(d, "state", "work_supply_frozen.log") == ""


def chk_shadow_supplies_but_logs(M):
    d = env_dir(FZ_AGENTS)
    run_main(M, d, mode="shadow")
    bl = rd(d, "backlog", "demo.md")
    return "open_router.py" in bl and "second_router.py" in bl and "SHADOW would-skip iptv-backend/app/routers/open_router.py" in rd(d, "state", "work_supply_frozen.log")


def chk_off_ignores(M):
    d = env_dir(FZ_AGENTS)
    run_main(M, d, mode="off")
    return "open_router.py" in rd(d, "backlog", "demo.md") and rd(d, "state", "work_supply_frozen.log") == ""


print("== work supply: AGENTS.md frozen list (real gitlark excerpt) ==")
mut_check("parse: the real gitlark list yields exactly its 12 frozen paths", chk_parse_real, '''state, prose_left = "armed", 6
            continue''', '''state, prose_left = "idle", 6
            continue''')
mut_check("parse: dual-purpose bullet, prose after the list and bare identifiers are not frozen", chk_dual_purpose_and_prose_excluded,
          'if re.search(r"dual-purpose", body, re.I):', 'if False:')
mut_check("parse: an AGENTS.md without a frozen lead-in freezes nothing", chk_no_list_no_freeze, '''if not is_bullet and _FROZEN_LEAD.search(ln) and (re.search(r"do not", ln, re.I) or ln.lstrip().startswith("#")):
                state, prose_left = "armed", 6
            continue''', '''if is_bullet:
                state, prose_left = "armed", 6
            continue''')
mut_check("match: exact path, directory prefix, glob; near-miss paths do not match", chk_hit_shapes, 'elif fz.endswith("/"):\n            if path.startswith(fz):', 'elif fz.endswith("/"):\n            if path.startswith(fz.rstrip("/")):')
mut_check("match: a stale entry (file moved) freezes the same basename; a live entry and generic names do not", chk_stale_entry_basename,
          'if not os.path.exists(os.path.join(root, fz)):', 'if True:')
print("== work supply: end to end (default on / shadow / off / no AGENTS.md) ==")
mut_check("default 'on': the frozen gap is NOT supplied, the other is; one log line + one info alert per file per day", chk_main_skips_frozen,
          '            if FROZEN_MODE == "on":\n                stat["frozen"] += 1\n                continue', '            if False:\n                stat["frozen"] += 1\n                continue')
mut_check("a repo without a frozen list supplies everything and logs nothing", chk_main_without_agents_unchanged,
          'frozen = frozen_paths(root) if FROZEN_MODE != "off" else []', 'frozen = ["iptv-backend/app/routers/open_router.py"] if FROZEN_MODE != "off" else []')
mut_check("shadow mode logs but still supplies", chk_shadow_supplies_but_logs, 'if FROZEN_MODE == "on":', 'if FROZEN_MODE != "off":')
mut_check("off mode neither skips nor logs", chk_off_ignores, 'frozen = frozen_paths(root) if FROZEN_MODE != "off" else []', 'frozen = frozen_paths(root)')
print("\n%d passed, %d failed" % (P, F))
tmp_track.sweep()
sys.exit(1 if F else 0)
